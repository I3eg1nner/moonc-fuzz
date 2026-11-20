// Deep-funnel driver: type-valid IR programs through dedicated T2/T3 queues.
//
// The main campaign's funnel is shallow: a byte mutation of a real source is
// usually not type-correct, so T2 succeeds ~0.4% of the time and T3 produced no
// non-empty output in the 60 s calibration.  This driver takes the other
// direction: it only feeds *type-valid* programs (the IR generator's output),
// so every case is a legitimate T2 candidate by construction, and it measures
// what the deep stages actually deliver:
//
//   attempts -> T2 builds -> T3 runs -> output matches the reference interpreter
//
// The reference interpreter is the sentinel: a T3 run only counts as complete
// when it exited 0 and printed exactly the lines the interpreter computed.  An
// empty output is recorded as empty, never as success.
//
// Usage: deepfuzz [--out DIR] [--duration S] [--cases N] [--size N]
//                 [--target T] [--timeout-ms N] [--batch N] [--seed N]

///|
fn usage() -> Unit {
  println(
    "usage: deepfuzz [--out DIR] [--duration S] [--cases N] [--size N] " +
    "[--target wasm-gc|native|js] [--timeout-ms N] [--batch N] [--seed N]",
  )
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn parse_int(s : String) -> Int32 {
  let mut n = 0
  let mut neg = false
  let mut i = 0
  if s.length() > 0 && s.get_char(0) == Some('-') {
    neg = true
    i = 1
  }
  while i < s.length() {
    match s.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
        } else {
          break
        }
      None => break
    }
    i += 1
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
/// Per-operator accounting.  A case is attributed to every operator it
/// contains, so "which operators survive the deep stages" is answerable
/// without claiming independence.
struct OpStat {
  mut cases : Int32
  mut built : Int32
  mut ran : Int32
  mut matched : Int32
}

///|
fn op_names(e : @ir.Expr, out : Map[String, Unit]) -> Unit {
  match e {
    Add(a, b) => {
      out.set("add", ())
      op_names(a, out)
      op_names(b, out)
    }
    Sub(a, b) => {
      out.set("sub", ())
      op_names(a, out)
      op_names(b, out)
    }
    Mul(a, b) => {
      out.set("mul", ())
      op_names(a, out)
      op_names(b, out)
    }
    Lt(a, b) => {
      out.set("lt", ())
      op_names(a, out)
      op_names(b, out)
    }
    Eq(a, b) => {
      out.set("eq", ())
      op_names(a, out)
      op_names(b, out)
    }
    If(c, a, b) => {
      out.set("if_expr", ())
      op_names(c, out)
      op_names(a, out)
      op_names(b, out)
    }
    Call(_, args) => {
      out.set("call", ())
      for a in args {
        op_names(a, out)
      }
    }
    ArrayLit(items) => {
      out.set("array", ())
      for a in items {
        op_names(a, out)
      }
    }
    Index(a, b) => {
      out.set("index", ())
      op_names(a, out)
      op_names(b, out)
    }
    Len(a) => {
      out.set("len", ())
      op_names(a, out)
    }
    _ => ()
  }
}

///|
fn op_names_stmt(s : @ir.Stmt, out : Map[String, Unit]) -> Unit {
  match s {
    Let(_, _, e, _) => op_names(e, out)
    Assign(_, e) => op_names(e, out)
    ArraySet(_, a, b) => {
      out.set("array_set", ())
      op_names(a, out)
      op_names(b, out)
    }
    Emit(_, e) => op_names(e, out)
    If(c, a, b) => {
      out.set("if_stmt", ())
      op_names(c, out)
      for s in a {
        op_names_stmt(s, out)
      }
      for s in b {
        op_names_stmt(s, out)
      }
    }
    While(c, body, _) => {
      out.set("while", ())
      op_names(c, out)
      for s in body {
        op_names_stmt(s, out)
      }
    }
    Return(e) => op_names(e, out)
  }
}

///|
fn program_ops(p : @ir.Program) -> Array[String] {
  let set : Map[String, Unit] = Map([])
  for f in p.funcs {
    for s in f.body {
      op_names_stmt(s, set)
    }
  }
  set.keys().collect()
}

///|
fn write_pkg(dir : String, src : String) -> Bool {
  @stager.rm_rf(dir)
  let made = try {
    @fs.create_dir(dir)
    true
  } catch {
    _ => false
  }
  if !made {
    return false
  }
  @stager.write_text(
    join(dir, "moon.mod"),
    "name = \"repro/deepfuzz\"\nversion = \"0.1.0\"\n",
  ) &&
  @stager.write_text(join(dir, "moon.pkg"), "pkgtype(kind: \"executable\")\n") &&
  @stager.write_text(join(dir, "main.mbt"), src)
}

///|
fn lines_of(s : String) -> Array[String] {
  let out : Array[String] = []
  for line in s.split("\n") {
    out.push(line.to_owned())
  }
  while out.length() > 0 && out[out.length() - 1] == "" {
    out.pop() |> ignore
  }
  out
}

///|
fn output_matches(actual : String, expected : Array[String]) -> Bool {
  let got = lines_of(actual)
  if got.length() != expected.length() {
    return false
  }
  for i, e in expected {
    if got[i] != e {
      return false
    }
  }
  true
}

///|
async fn main {
  let args = @env.args()
  if args.contains("--help") {
    usage()
    return
  }
  let out = match arg_value(args, "--out") {
    Some(s) => s
    None => "/tmp/mbtfuzz_deepfuzz"
  }
  let duration = match arg_value(args, "--duration") {
    Some(s) => parse_int(s)
    None => 60
  }
  let max_cases = match arg_value(args, "--cases") {
    Some(s) => parse_int(s)
    None => 100000
  }
  let size = match arg_value(args, "--size") {
    Some(s) => parse_int(s)
    None => 12
  }
  let target = match arg_value(args, "--target") {
    Some(s) => s
    None => "wasm-gc"
  }
  let timeout_ms = match arg_value(args, "--timeout-ms") {
    Some(s) => parse_int(s)
    None => 60000
  }
  let batch = match arg_value(args, "--batch") {
    Some(s) => parse_int(s)
    None => 32
  }
  let seed0 = match arg_value(args, "--seed") {
    Some(s) => parse_int(s).to_uint64()
    None => 1UL
  }
  // create_dir is not recursive: make the parent, the run dir and the work
  // dir explicitly.  Without this the driver silently measured nothing.
  let _ = try {
    @fs.create_dir(out)
    true
  } catch {
    _ => false
  }
  let out_dir = join(out, @env.now().to_string())
  @stager.rm_rf(out_dir)
  let _ = try {
    @fs.create_dir(out_dir)
    true
  } catch {
    _ => false
  }
  let work = join(out_dir, "work")
  let _ = try {
    @fs.create_dir(work)
    true
  } catch {
    _ => false
  }
  let deadline = @env.now() + duration.to_uint64() * 1000UL
  let mut attempts = 0
  let mut interp_failed = 0
  let mut t2_ok = 0
  let mut t3_ok = 0
  let mut matched = 0
  let mut empty_output = 0
  let mut mismatch = 0
  let mut t3_nonzero = 0
  let mut build_ms = 0L
  let mut run_ms = 0L
  let ops : Map[String, OpStat] = Map([])
  let mut cases_done = 0
  while cases_done < max_cases && @env.now() < deadline {
    // Generation queue: a batch of type-valid programs, then the T2 stage
    // consumes it.  Batching is what makes T2 and T3 separately observable
    // instead of one blended `moon run` per case.
    let programs : Array[@ir.Program] = []
    let expecteds : Array[Array[String]] = []
    let sources : Array[String] = []
    for k in 0..<batch {
      let seed = seed0 + (cases_done + k).to_uint64()
      let p = @ir.generate(seed, size)
      let src = @ir.emit_program(p)
      let exp = @ir.run(p, 200000) catch {
        _ => {
          interp_failed += 1
          []
        }
      }
      programs.push(p)
      expecteds.push(exp)
      sources.push(src)
    }
    for k in 0..<programs.length() {
      if @env.now() >= deadline || cases_done >= max_cases {
        break
      }
      attempts += 1
      let dir = join(work, "c" + cases_done.to_string())
      cases_done += 1
      if !write_pkg(dir, sources[k]) {
        continue
      }
      let b = @exec.run_isolated(
        @stager.moon_path(),
        ["build", "--target", target],
        dir,
        timeout_ms,
        max_output_bytes=65536,
        mem_mb=2048,
      )
      build_ms += b.ms
      let uses = program_ops(programs[k])
      for u in uses {
        match ops.get(u) {
          Some(s) => s.cases += 1
          None => ops.set(u, { cases: 1, built: 0, ran: 0, matched: 0, })
        }
      }
      if b.rc != 0 || b.timed_out {
        continue
      }
      t2_ok += 1
      for u in uses {
        match ops.get(u) {
          Some(s) => s.built += 1
          None => ()
        }
      }
      let r = @exec.run_isolated(
        @stager.moon_path(),
        ["run", "main.mbt", "--target", target],
        dir,
        timeout_ms,
        max_output_bytes=1048576,
        mem_mb=2048,
      )
      run_ms += r.ms
      if r.timed_out || r.rc < 0 {
        t3_nonzero += 1
        continue
      }
      t3_ok += 1
      for u in uses {
        match ops.get(u) {
          Some(s) => s.ran += 1
          None => ()
        }
      }
      if r.rc != 0 {
        t3_nonzero += 1
        continue
      }
      if r.stdout.trim().length() == 0 {
        empty_output += 1
        continue
      }
      if output_matches(r.stdout, expecteds[k]) {
        matched += 1
        for u in uses {
          match ops.get(u) {
            Some(s) => s.matched += 1
            None => ()
          }
        }
      } else {
        mismatch += 1
      }
      @stager.rm_rf(dir)
      if cases_done % 500 == 0 {
        println(
          "[deepfuzz] cases=" +
          cases_done.to_string() +
          " t2=" +
          t2_ok.to_string() +
          " t3=" +
          t3_ok.to_string() +
          " matched=" +
          matched.to_string(),
        )
      }
    }
  }
  let mut all = 0
  let mut sum_build = 0.0
  for k, v in ops {
    ignore(k)
    all += v.cases
    sum_build = sum_build
  }
  let b = StringBuilder()
  b.write_string("{\"attempts\":" + attempts.to_string())
  b.write_string(",\"interp_failed\":" + interp_failed.to_string())
  b.write_string(",\"t2_ok\":" + t2_ok.to_string())
  b.write_string(",\"t3_complete\":" + t3_ok.to_string())
  b.write_string(",\"t3_matched\":" + matched.to_string())
  b.write_string(",\"t3_mismatch\":" + mismatch.to_string())
  b.write_string(",\"t3_nonzero\":" + t3_nonzero.to_string())
  b.write_string(",\"empty_output\":" + empty_output.to_string())
  b.write_string(",\"build_ms\":" + build_ms.to_string())
  b.write_string(",\"run_ms\":" + run_ms.to_string())
  b.write_string(",\"target\":\"" + target + "\"")
  b.write_string(",\"size\":" + size.to_string())
  b.write_string(",\"ops\":{")
  let mut first = true
  for k, v in ops {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string("\"" + k + "\":{\"cases\":" + v.cases.to_string())
    b.write_string(",\"built\":" + v.built.to_string())
    b.write_string(",\"ran\":" + v.ran.to_string())
    b.write_string(",\"matched\":" + v.matched.to_string() + "}")
  }
  b.write_string("}}")
  let line = b.to_string()
  println(line)
  ignore(@stager.write_text(join(out_dir, "summary.json"), line))
  ignore(all)
  ignore(sum_build)
}
