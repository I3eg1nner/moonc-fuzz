// Semantic differential: generate small programs per operator family, compute
// the expected output with an in-process reference evaluator, run the same
// program on js / wasm-gc / native and compare stdout+rc.
//
// Known backend artefacts (float formatting) are a separate family that is
// reported as excluded, never as a mismatch.
fn usage() -> Unit {
  println("usage: sem3 --out DIR [--duration S] [--inject TARGET] [--limit N]")
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") { a + b } else { a + "/" + b }
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name { return Some(args[i + 1]) }
    i += 1
  }
  None
}

///|
fn num_arg(args : Array[String], name : String, d : Int32) -> Int32 {
  match arg_value(args, name) {
    Some(s) => {
      let mut n = 0
      let mut any = false
      for c in s {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
          any = true
        } else { return d }
      }
      if any { n } else { d }
    }
    None => d
  }
}

///|
struct Case {
  family : String
  src : String
  expected : Array[String]
  /// Independent node reference source; empty = use the MoonBit reference.
  js : String
  excluded : Bool
}

///|
fn i32_expr(a : Int, b : Int, op : Int) -> Int {
  match op {
    0 => a + b
    1 => a - b
    2 => a * b
    3 => a & b
    4 => a | b
    5 => a ^ b
    6 => a << (b & 7)
    7 => a >> (b & 7)
    _ => a
  }
}

///|
fn gen_i32(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(2000) - 1000
  let b = rng.int(31) + 1
  let op = rng.int(8)
  let e = i32_expr(a, b, op)
  let opname = ["+", "-", "*", "&", "|", "^", "<<", ">>"][op]
  let rhs = if op >= 6 { "(b & 7)" } else { "b" }
  let src = "fn main {\n  let a : Int = " + a.to_string() + "\n  let b : Int = " +
    b.to_string() + "\n  println((a " + opname + " " + rhs + ").to_string())\n}\n"
  let jrhs = if op >= 6 { "(b&7)" } else { "b" }
  let js = "const a=" + a.to_string() + "; const b=" + b.to_string() +
    "; console.log(((a " + opname + " " + jrhs + ")|0).toString());\n"
  { family: "i32", src, expected: [e.to_string()], js, excluded: false }
}

///|
fn gen_i64(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(1 << 30).to_int64() % 1000000007L
  let b = rng.int(1 << 30).to_int64() % 1000000007L
  let op = rng.int(3)
  let e = if op == 0 { a + b } else if op == 1 { a - b } else { a * b }
  let opname = ["+", "-", "*"][op]
  let src = "fn main {\n  let a : Int64 = " + a.to_string() + "L\n  let b : Int64 = " +
    b.to_string() + "L\n  println((a " + opname + " b).to_string())\n}\n"
  let js = "const a=" + a.to_string() + "n; const b=" + b.to_string() +
    "n; console.log(BigInt.asIntN(64, a " + opname + " b).toString());\n"
  { family: "i64", src, expected: [e.to_string()], js, excluded: false }
}

///|
fn gen_str(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let n = rng.int(5) + 1
  let m = rng.int(5) + 1
  let sa : Array[String] = []
  let sb : Array[String] = []
  let mut i = 0
  let letters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
  while i < n { sa.push(letters[rng.int(26)]); i += 1 }
  i = 0
  while i < m { sb.push(letters[rng.int(26)]); i += 1 }
  let a = sa.join("")
  let b = sb.join("")
  let src = "fn main {\n  let a = \"" + a + "\"\n  let b = \"" + b +
    "\"\n  println(a + b)\n  println((a + b).length().to_string())\n  println((a == b).to_string())\n}\n"
  let eq = if a == b { "true" } else { "false" }
  let js = "const a=\"" + a + "\"; const b=\"" + b +
    "\"; console.log(a+b); console.log((a+b).length); console.log(String(a===b));\n"
  { family: "string_ascii", src, expected: [a + b, (a.length() + b.length()).to_string(), eq], js, excluded: false }
}

///|
fn gen_array(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let vals = [rng.int(10), rng.int(10), rng.int(10), rng.int(10)]
  let w = rng.int(50)
  let src = "fn main {\n  let xs : Array[Int] = [" + vals[0].to_string() + ", " +
    vals[1].to_string() + ", " + vals[2].to_string() + ", " + vals[3].to_string() +
    "]\n  xs[2] = " + w.to_string() + "\n  println(xs[1].to_string())\n  println(xs[2].to_string())\n  println(xs.length().to_string())\n}\n"
  let js = "const xs=[" + vals[0].to_string() + "," + vals[1].to_string() + "," +
    vals[2].to_string() + "," + vals[3].to_string() + "]; xs[2]=" + w.to_string() +
    "; console.log(xs[1]); console.log(xs[2]); console.log(xs.length);\n"
  { family: "array_inbounds", src, expected: [vals[1].to_string(), w.to_string(), "4"], js, excluded: false }
}

///|
fn gen_loop(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let n = rng.int(30)
  let src = "fn main {\n  let mut i = 0\n  let mut s = 0\n  while i <= " +
    n.to_string() + " {\n    s = s + i\n    i = i + 1\n  }\n  println(s.to_string())\n}\n"
  let js = "let s=0; for(let i=0;i<=" + n.to_string() + ";i++){s+=i;} console.log(s);\n"
  { family: "loop_counter", src, expected: [((n * (n + 1)) / 2).to_string()], js, excluded: false }
}

///|
fn gen_oob(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let src = "fn main {\n  let xs : Array[Int] = [1, 2, 3]\n  let i = " +
    (rng.int(5) + 5).to_string() + "\n  println(xs[i].to_string())\n}\n"
  let js = "const xs=[1,2,3]; const i=" + (rng.int(5) + 5).to_string() +
    "; if(i>=xs.length) throw new Error('oob'); console.log(xs[i]);\n"
  { family: "array_oob", src, expected: ["<trap>"], js, excluded: false }
}

///|
fn gen_float(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let x = rng.int(10).to_double() / 3.0
  let src = "fn main {\n  println((" + x.to_string() + ").to_string())\n}\n"
  { family: "float_format", src, expected: [], js: "", excluded: true }
}

///|
fn next_case(family : String, seed : UInt64) -> Case {
  if family == "i32" { gen_i32(seed) } else if family == "i64" { gen_i64(seed) } else if family == "string_ascii" {
    gen_str(seed)
  } else if family == "array_inbounds" {
    gen_array(seed)
  } else if family == "loop_counter" {
    gen_loop(seed)
  } else if family == "array_oob" {
    gen_oob(seed)
  } else if family == "expr_i32" {
    gen_expr(seed, 32)
  } else if family == "expr_i64" {
    gen_expr(seed, 64)
  } else if family == "boundary_i32" {
    gen_boundary(seed)
  } else if family == "boundary_i64" {
    gen_boundary64(seed)
  } else if family == "array_alias" {
    gen_alias(seed)
  } else if family == "utf8_string" {
    gen_utf8(seed)
  } else if family == "var_use" {
    gen_var(seed)
  } else if family == "if_else" {
    gen_if(seed)
  } else if family == "func_call" {
    gen_func(seed)
  } else if family == "array_nested" {
    gen_nested_array(seed)
  } else if family == "struct_fields" {
    gen_struct(seed)
  } else if family == "struct_nested" {
    gen_nested_struct(seed)
  } else if family == "enum_match" {
    gen_enum(seed)
  } else if family == "generic_box" {
    gen_box(seed)
  } else if family == "closure_capture" {
    gen_closure(seed)
  } else if family == "typed_nested" {
    gen_typed_nested(seed)
  } else if family == "typed_deep" {
    gen_typed_deep(seed)
  } else if family == "float_bits" {
    gen_float_bits(seed)
  } else if family == "float_cmp" {
    gen_float_cmp(seed)
  } else {
    gen_float(seed)
  }
}

///|
fn ensure_dir(p : String) -> Unit {
  if p == "" || p == "." || p == "/" || @fs.path_exists(p) {
    return
  }
  let parent = @corpus.dirname(p)
  if parent != p {
    ensure_dir(parent)
  }
  ignore(try { @fs.create_dir(p); true } catch { _ => false })
}

///|
fn write_pkg(dir : String, src : String) -> Bool {
  ensure_dir(dir)
  @stager.write_text(join(dir, "moon.mod"), "name = \"sem3\"\nversion = \"0.1.0\"\n") &&
  @stager.write_text(join(dir, "moon.pkg"), "pkgtype(kind: \"executable\")\n") &&
  @stager.write_text(join(dir, "main.mbt"), src)
}

///|
fn lines_of(s : String) -> Array[String] {
  let out : Array[String] = []
  for l in s.split("\n") { if l != "" { out.push(l.to_owned()) } }
  out
}

///|
async fn node_reference(js : String) -> (Array[String], Int32) {
  let r = @exec.run("/usr/bin/env", ["node", "-e", js], "/tmp", 10000, max_output_bytes=65536)
  (lines_of(r.stdout), r.rc)
}

///|
struct Obs {
  target : String
  class : String
  stage : String
  out : String
  rc : Int32
  timed_out : Bool
  truncated : Bool
  ice : Bool
  bytes : Int
}

///|
fn target_class(rc : Int32, timed_out : Bool, truncated : Bool, err : String) -> String {
  if timed_out {
    "timeout"
  } else if truncated {
    "truncated"
  } else if rc == 0 {
    "ok"
  } else if err.contains("RuntimeError") || err.contains("panic") ||
    err.contains("trap") || err.contains("abort") || err.contains("Abort") ||
    err.contains("PanicError") ||
    err.contains("SIGABRT") || err.contains("core dumped") ||
    err.contains("Segmentation") || err.contains("Illegal instruction") {
    "trap"
  } else if err.contains("Oops, the compiler") ||
    err.contains("Machine_error") || err.contains("Assertion failed") {
    "ice"
  } else if err.contains("Error:") || err.contains("failed to build") ||
    err.contains("error[") || err.contains("unknown method") {
    "compile_error"
  } else {
    "runtime_error"
  }
}

///|
fn observations_complete(classes : Array[String]) -> Bool {
  if classes.length() != 3 {
    return false
  }
  for c in classes {
    if c != "ok" && c != "trap" {
      return false
    }
  }
  true
}

///|
fn save_case(
  ev : String,
  kind : String,
  src : String,
  expected : Array[String],
  actual : String,
  argv : String,
) -> Bool {
  ensure_dir(ev)
  let ok = @stager.write_text(join(ev, "main.mbt"), src) &&
    @stager.write_text(join(ev, "expected.txt"), expected.join("\n")) &&
    @stager.write_text(join(ev, "actual.txt"), actual) &&
    @stager.write_text(join(ev, "kind.txt"), kind) &&
    @stager.write_text(join(ev, "argv.txt"), argv)
  ok && @fs.path_exists(join(ev, "main.mbt")) &&
  @fs.path_exists(join(ev, "actual.txt"))
}

///|
async fn main {
  let args = @env.args()
  let out = match arg_value(args, "--out") { Some(s) => s; None => "/tmp/sem3" }
  let duration = num_arg(args, "--duration", 300)
  let limit = num_arg(args, "--limit", 100000)
  let seed_off = num_arg(args, "--seed", 1)
  let inject = match arg_value(args, "--inject") { Some(s) => s; None => "" }
  let inject_node = args.contains("--inject-node")
  let inject_moon = args.contains("--inject-moon")
  let forced_family = match arg_value(args, "--family") { Some(s) => s; None => "" }
  let expected_override = match arg_value(args, "--expected") { Some(s) => s; None => "" }
  let backend_timeout = num_arg(args, "--backend-timeout-ms", 30000)
  let no_node = args.contains("--no-node")
  let backend_cmds : Map[String, String] = Map([])
  let mut bi = 0
  while bi < args.length() {
    if args[bi] == "--backend-cmd" && bi + 1 < args.length() {
      let spec = args[bi + 1]
      match spec.find("=") {
        Some(eq) => backend_cmds.set(spec[0:eq].to_owned(), spec[eq + 1:].to_owned())
        None => ()
      }
      bi += 2
    } else { bi += 1 }
  }
  let families = if forced_family != "" {
    [forced_family]
  } else {
    ["i32", "i64", "string_ascii", "array_inbounds", "loop_counter", "array_oob", "expr_i32", "expr_i64", "boundary_i32", "boundary_i64", "array_alias", "utf8_string", "var_use", "if_else", "func_call", "array_nested", "struct_fields", "struct_nested", "enum_match", "generic_box", "closure_capture", "typed_nested", "typed_deep", "float_bits", "float_cmp", "float_format"]
  }
  @stager.rm_rf(out)
  ensure_dir(out)
  let deadline = @env.now() + duration.to_uint64() * 1000UL
  let targets = ["js", "wasm-gc", "native"]
  let backend_stats : Map[String, (Int32, Int32, Int32, Int32, Int32)] = Map([])
  for t in targets { backend_stats.set(t, (0, 0, 0, 0, 0)) }
  let counts : Map[String, (Int32, Int32, Int32, Int32)] = Map([]) // attempts,witness,excluded,inconclusive
  for f in families { counts.set(f, (0, 0, 0, 0)) }
  let mut cases = 0
  let mut unique_programs = 0
  let mut oracle_candidates = 0
  let witness_hashes : Map[String, Unit] = Map([])
  let seen : Map[String, Unit] = Map([])
  while @env.now() < deadline && cases < limit {
    cases += 1
    let family = families[cases % families.length()]
    let c0 = next_case(
      family,
      0x9e3779b97f4a7c15UL * cases.to_uint64() + seed_off.to_uint64() * 131UL,
    )
    let c = if expected_override != "" {
      { family: c0.family, src: c0.src, expected: [expected_override], js: c0.js, excluded: c0.excluded }
    } else {
      c0
    }
    // MoonBit core documents min/-1 (either operator) as having no portable
    // result ("may abort or get an arbitrary value"); backend divergence here
    // is allowed, so it is excluded_domain rather than a witness.
    let excluded = c.excluded ||
      ((family == "boundary_i32" || family == "boundary_i64") &&
        (c.src.contains("/ -1") || c.src.contains("% -1")))
    let (at, wi, ex, inc) = counts.get(family).unwrap()
    counts.set(family, (at + 1, wi, ex, inc))
    let h = @corpus.sha1_hex(c.src)
    if !seen.contains(h) { seen.set(h, ()); unique_programs += 1 }
    if excluded {
      // Float formatting: policy-excluded, only counted.
      counts.set(family, (at + 1, wi, ex + 1, inc))
      continue
    }
    let wd = join(out, "work")
    if !write_pkg(wd, c.src) { continue }
    let moon_ref = if inject_moon {
      let sh : Array[String] = []
      for x in c.expected { sh.push(x + "9") }
      sh
    } else {
      c.expected
    }
    let mut continue_ok = false
    let mut ref_expected = moon_ref
    if c.js != "" && !no_node {
      let (ne, nrc) = node_reference(c.js)
      if nrc != 0 && c.expected.length() == 1 && c.expected[0] == "<trap>" {
        ref_expected = ["<trap>"]
        continue_ok = true
      }
      if (nrc != 0 || ne.length() == 0) && !continue_ok {
        let ev = join(join(out, "inconclusive"), cases.to_string())
        ensure_dir(ev)
        ignore(@stager.write_text(join(ev, "node.js"), c.js))
        ignore(save_case(ev, "node_reference_failed", c.src, c.expected, c.js, "node -e ..."))
        counts.set(family, (at + 1, wi, ex, inc + 1))
        continue
      }
      if !continue_ok {
        let placeholder = c.expected.length() == 1 && c.expected[0] == "<node>"
        if !placeholder {
        // Two independent references disagree: this is the most valuable
        // oracle candidate, not a backend witness.
        let mut same = ne.length() == moon_ref.length()
        if same {
          for i, x in moon_ref { if ne[i] != x { same = false } }
        }
        if !same &&
          !(c.expected.length() == 1 && c.expected[0] == "<node>") {
          let ev = join(join(out, "reference_disagree"), cases.to_string())
          let saved = save_case(
            ev,
            "reference_disagree",
            c.src,
            c.expected,
            "moon_ref=" + moon_ref.join("|") + "\nnode_ref=" + ne.join("|"),
            "node -e ...",
          )
          if !saved { println("{\"ok\":false,\"error\":\"ref evidence save failed\"}"); @env.exit(2) }
          oracle_candidates += 1
          counts.set(family, (at + 1, wi, ex, inc))
          continue
        }
        }
        ref_expected = ne
        if inject_node {
          let shifted : Array[String] = []
          for x in ne { shifted.push(x + "9") }
          ref_expected = shifted
        }
      }
    }
    let obs : Array[Obs] = []
    for t in targets {
      let cmd = backend_cmds.get(t)
      let r = match cmd {
        Some(c) => @exec.run_isolated(
          c, [t, join(wd, "main.mbt")], wd,
          backend_timeout, max_output_bytes=1048576, mem_mb=2048,
        )
        None => @exec.run_isolated(
          @stager.moon_path(), ["run", "main.mbt", "--target", t], wd,
          backend_timeout, max_output_bytes=1048576, mem_mb=2048,
        )
      }
      let cls = target_class(r.rc, r.timed_out, r.stdout_truncated, r.stderr)
      obs.push({
        target: t,
        class: cls,
        stage: if cls == "compile_error" || cls == "ice" { "compile" } else { "run" },
        out: r.stdout.trim_end().to_owned(),
        rc: r.rc,
        timed_out: r.timed_out,
        truncated: r.stdout_truncated,
        ice: cls == "ice",
        bytes: r.stdout.length(),
      })
    }
    let mut classes = ""
    for o in obs {
      classes = classes + o.target + "=" + o.class + " "
      let (okc, trapc, other, to, tr) = backend_stats.get(o.target).unwrap()
      let no = if o.class == "ok" { okc + 1 } else { okc }
      let nt = if o.class == "trap" { trapc + 1 } else { trapc }
      let no2 = if o.class != "ok" && o.class != "trap" { other + 1 } else { other }
      let nto = if o.timed_out { to + 1 } else { to }
      let ntr = if o.truncated { tr + 1 } else { tr }
      backend_stats.set(o.target, (no, nt, no2, nto, ntr))
    }
    let actual = obs.map(fn(o) {
      o.target + "[" + o.class + "] stage=" + o.stage + " rc=" + o.rc.to_string() +
      " timed_out=" + o.timed_out.to_string() + " truncated=" + o.truncated.to_string() +
      " ice=" + o.ice.to_string() + " bytes=" + o.bytes.to_string() + "\n" + o.out
    }).join("\n---\n")
    let argv = @stager.moon_path() + " run main.mbt --target js|wasm-gc|native\n"
    let mut verdict = "pass"
    let class_arr = obs.map(fn(o) { o.class })
    if !observations_complete(class_arr) {
      // A timeout/compile_error/truncated/ICE/runtime_error backend means the
      // three-backend observation is incomplete; never call it a witness.
      verdict = "inconclusive"
    } else if family == "array_oob" {
      // Every backend must have actually executed and trapped; a compile
      // error/timeout is not a trap and must not be reported as pass.
      let mut all_trap = true
      for o in obs { if o.class != "trap" { all_trap = false } }
      if all_trap { verdict = "witness" } else { verdict = "inconclusive" }
    } else {
      let mut any_ok = false
      let mut any_trap = false
      for o in obs {
        if o.class == "ok" { any_ok = true }
        if o.class == "trap" { any_trap = true }
      }
      if any_ok && any_trap {
        // One backend produced a value while another trapped: this IS a
        // cross-backend divergence, not an inconclusive run.
        verdict = "witness"
      } else {
        for o in obs { if o.class != "ok" { verdict = "inconclusive" } }
      }
      if verdict == "pass" {
        let outs : Array[String] = []
        for o in obs { outs.push(o.out) }
        let mut same_out = true
        for i in 1..<outs.length() { if outs[i] != outs[0] { same_out = false } }
        let mut matched_count = 0
        for i, o in obs {
          let want : Array[String] = []
          for x in ref_expected {
            want.push(
              if inject == "all" || (inject != "" && targets[i] == inject) {
                x + "9"
              } else {
                x
              },
            )
          }
          let got : Array[String] = []
          for l in o.out.split("\n") { if l != "" { got.push(l.to_owned()) } }
          let mut matches = got.length() == want.length()
          if matches {
            for j, w in want { if got[j] != w { matches = false } }
          }
          if matches { matched_count += 1 }
        }
        if matched_count == obs.length() {
          verdict = "pass"
        } else if same_out && matched_count == 0 {
          // With the node reference, three backends agreeing but differing
          // from an independent oracle is a compiler/reference divergence.
          // With the MoonBit reference it is only an oracle candidate.
          verdict = if c.js != "" { "witness" } else { "oracle" }
        } else {
          verdict = "witness"
        }
      }
    }
    if verdict == "oracle" {
      oracle_candidates += 1
      let ev = join(join(out, "oracle_candidate"), cases.to_string())
      let saved = save_case(ev, verdict, c.src, c.expected, actual + "\n" + classes, argv)
      if !saved {
        println("{\"ok\":false,\"error\":\"oracle save failed\"}")
        @env.exit(2)
      }
    } else if verdict != "pass" {
      let ev = join(join(out, if verdict == "witness" { "witness" } else { "inconclusive" }), cases.to_string())
      let saved = save_case(ev, verdict, c.src, c.expected, actual + "\n" + classes, argv)
      if !saved {
        println("{\"ok\":false,\"error\":\"witness save failed at " + ev + "\"}")
        @env.exit(2)
      }
      // Count only after the evidence is durable.
      if verdict == "witness" {
        counts.set(family, (at + 1, wi + 1, ex, inc))
        witness_hashes.set(h, ())
      } else {
        counts.set(family, (at + 1, wi, ex, inc + 1))
      }
    }
  }
  let b = StringBuilder()
  b.write_string("{\"cases\":" + cases.to_string())
  b.write_string(",\"unique_programs\":" + unique_programs.to_string())
  b.write_string(",\"unique_witness\":" + witness_hashes.length().to_string())
  b.write_string(",\"oracle_candidates\":" + oracle_candidates.to_string())
  b.write_string(",\"backend_obs\":{")
  let mut bfirst = true
  for t in targets {
    if !bfirst { b.write_string(",") }
    bfirst = false
    let (okc, trapc, other, to, tr) = backend_stats.get(t).unwrap()
    b.write_string("\"" + t + "\":{\"ok\":" + okc.to_string() + ",\"trap\":" + trapc.to_string() +
      ",\"other\":" + other.to_string() + ",\"timeout\":" + to.to_string() +
      ",\"truncated\":" + tr.to_string() + "}")
  }
  b.write_string("}")
  b.write_string(",\"families\":{")
  let mut first = true
  for f in families {
    let (a, w, e, inc) = counts.get(f).unwrap()
    if !first { b.write_string(",") }
    first = false
    b.write_string("\"" + f + "\":{\"attempts\":" + a.to_string() + ",\"witness\":" +
      w.to_string() + ",\"excluded\":" + e.to_string() +
      ",\"inconclusive\":" + inc.to_string() + "}")
  }
  b.write_string("}}")
  println(b.to_string())
  ignore(@stager.write_text(join(out, "summary.json"), b.to_string()))
}

///|
#derive(Eq)
enum TE {
  C(Int64)
  Add(TE, TE)
  Sub(TE, TE)
  Mul(TE, TE)
  Div(TE, TE)
  Mod(TE, TE)
  BAnd(TE, TE)
  BOr(TE, TE)
  BXor(TE, TE)
  Shl(TE, TE)
  Shr(TE, TE)
}

///|
fn te_u64(v : Int64) -> UInt64 { v.reinterpret_as_uint64() }

///|
fn te_i64(u : UInt64) -> Int64 { u.reinterpret_as_int64() }

///|
fn te_wrap32(v : Int64) -> Int64 {
  let x = v & 0xFFFFFFFFL
  if x >= 0x80000000L { x - 0x100000000L } else { x }
}

///|
fn te_eval(t : TE, bits : Int32) -> Int64 {
  match t {
    C(v) => if bits == 32 { te_wrap32(v) } else { v }
    Add(a, b) => {
      if bits == 64 {
        te_i64(te_u64(te_eval(a, 64)) + te_u64(te_eval(b, 64)))
      } else {
        te_wrap32(te_eval(a, 32) + te_eval(b, 32))
      }
    }
    Sub(a, b) => {
      if bits == 64 {
        te_i64(te_u64(te_eval(a, 64)) - te_u64(te_eval(b, 64)))
      } else {
        te_wrap32(te_eval(a, 32) - te_eval(b, 32))
      }
    }
    Mul(a, b) => {
      if bits == 64 {
        te_i64(te_u64(te_eval(a, 64)) * te_u64(te_eval(b, 64)))
      } else {
        te_wrap32(te_eval(a, 32) * te_eval(b, 32))
      }
    }
    Div(a, b) => {
      let d = te_eval(b, bits)
      if d == 0L {
        0L
      } else {
        let v = te_eval(a, bits) / d
        if bits == 32 { te_wrap32(v) } else { v }
      }
    }
    Mod(a, b) => {
      let d = te_eval(b, bits)
      if d == 0L {
        0L
      } else {
        let v = te_eval(a, bits) % d
        if bits == 32 { te_wrap32(v) } else { v }
      }
    }
    BAnd(a, b) => te_eval(a, bits) & te_eval(b, bits)
    BOr(a, b) => te_eval(a, bits) | te_eval(b, bits)
    BXor(a, b) => te_eval(a, bits) ^ te_eval(b, bits)
    Shl(a, b) => {
      // Shift counts are Int (32-bit) at the source level even for Int64.
      let sh = te_eval(b, 32) & (if bits == 32 { 31L } else { 63L })
      let v = te_eval(a, bits) << sh.to_int()
      if bits == 32 { te_wrap32(v) } else { v }
    }
    Shr(a, b) => {
      let sh = te_eval(b, 32) & (if bits == 32 { 31L } else { 63L })
      te_eval(a, bits) >> sh.to_int()
    }
  }
}

///|
fn te_render(t : TE) -> String {
  match t {
    C(v) => v.to_string()
    Add(a, b) => "(" + te_render(a) + " + " + te_render(b) + ")"
    Sub(a, b) => "(" + te_render(a) + " - " + te_render(b) + ")"
    Mul(a, b) => "(" + te_render(a) + " * " + te_render(b) + ")"
    Div(a, b) => "(" + te_render(a) + " / " + te_render(b) + ")"
    Mod(a, b) => "(" + te_render(a) + " % " + te_render(b) + ")"
    BAnd(a, b) => "(" + te_render(a) + " & " + te_render(b) + ")"
    BOr(a, b) => "(" + te_render(a) + " | " + te_render(b) + ")"
    BXor(a, b) => "(" + te_render(a) + " ^ " + te_render(b) + ")"
    Shl(a, b) => "(" + te_render(a) + " << " + te_render(b) + ")"
    Shr(a, b) => "(" + te_render(a) + " >> " + te_render(b) + ")"
  }
}

///|
fn te_render64(t : TE) -> String {
  match t {
    C(v) => v.to_string() + "L"
    Add(a, b) => "(" + te_render64(a) + " + " + te_render64(b) + ")"
    Sub(a, b) => "(" + te_render64(a) + " - " + te_render64(b) + ")"
    Mul(a, b) => "(" + te_render64(a) + " * " + te_render64(b) + ")"
    Div(a, b) => "(" + te_render64(a) + " / " + te_render64(b) + ")"
    Mod(a, b) => "(" + te_render64(a) + " % " + te_render64(b) + ")"
    BAnd(a, b) => "(" + te_render64(a) + " & " + te_render64(b) + ")"
    BOr(a, b) => "(" + te_render64(a) + " | " + te_render64(b) + ")"
    BXor(a, b) => "(" + te_render64(a) + " ^ " + te_render64(b) + ")"
    Shl(a, b) => "(" + te_render64(a) + " << (" + te_render(b) + "))"
    Shr(a, b) => "(" + te_render64(a) + " >> (" + te_render(b) + "))"
  }
}

///|
fn te_gen(rng : @mutate.Rng, depth : Int32, bits : Int32) -> TE {
  if depth <= 0 {
    let v = rng.int(2000).to_int64() - 1000L
    C(if bits == 32 { te_wrap32(v) } else { v })
  } else {
    let op = rng.int(11)
    let a = te_gen(rng, depth - 1, bits)
    let b = if op == 3 || op == 4 {
      // Keep divisors non-zero in-tree to avoid trap cases here.
      C(if rng.int(2) == 0 { 1L } else { -1L })
    } else if op == 8 || op == 9 {
      // Shift counts are small non-negative values; negative/huge counts make
      // the expected value depend on masking details and produced oracle noise.
      C(rng.int(8).to_int64())
    } else {
      te_gen(rng, depth - 1, bits)
    }
    match op {
      0 => Add(a, b)
      1 => Sub(a, b)
      2 => Mul(a, b)
      3 => Div(a, b)
      4 => Mod(a, b)
      5 => BAnd(a, b)
      6 => BOr(a, b)
      7 => BXor(a, b)
      8 => Shl(a, b)
      9 => Shr(a, b)
      _ => Add(a, b)
    }
  }
}

///|
fn gen_expr(seed : UInt64, bits : Int32) -> Case {
  let rng = @mutate.Rng::new(seed)
  let depth = rng.int(3) + 2
  let t = te_gen(rng, depth, bits)
  let e = te_eval(t, bits)
  let ty = if bits == 32 { "Int" } else { "Int64" }
  let lit = if bits == 32 { te_render(t) } else { te_render(t) + "L" }
  // For 64-bit, every literal in the tree needs the L suffix; render with a
  // cast instead: Int64 conversion of the rendered Int expression.
  let expr = if bits == 32 { lit } else { te_render64(t) }
  let src = "fn main {\n  println((" + expr + ").to_string())\n}\n"
  let js = if bits == 32 {
    "const d32=(a,b)=>b===0?0:(a/b)|0;const m32=(a,b)=>b===0?0:(a%b)|0; console.log(((" +
    te_js32(t) + ")|0).toString());\n"
  } else {
    "console.log((" + te_js64(t) + ").toString());\n"
  }
  { family: if bits == 32 { "expr_i32" } else { "expr_i64" }, src, expected: [e.to_string()], js, excluded: false }
}

///|
fn gen_boundary(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let cases : Array[(String, String)] = [
    ("2147483647 + 1", "-2147483648"),
    ("-2147483648 - 1", "2147483647"),
    ("2147483647 * 2", "-2"),
    ("-2147483648 / -1", "-2147483648"),
    ("-7 / 2", "-3"),
    ("-7 % 2", "-1"),
    ("7 % -2", "1"),
    ("1 << 31", "-2147483648"),
    ("1 << 32", "1"),
    ("-1 >> 1", "-1"),
    ("1 << -1", "-2147483648"),
  ]
  let i = rng.int(cases.length())
  let (expr, exp) = cases[i]
  let src = "fn main {\n  println((" + expr + ").to_string())\n}\n"
  { family: "boundary_i32", src, expected: [exp], js: "", excluded: false }
}

///|
fn gen_boundary64(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let cases : Array[(String, String)] = [
    ("9223372036854775807L + 1L", "-9223372036854775808"),
    ("-9223372036854775808L - 1L", "9223372036854775807"),
    ("9223372036854775807L * 2L", "-2"),
    ("-9223372036854775808L / -1L", "-9223372036854775808"),
    ("-7L / 2L", "-3"),
    ("-7L % 2L", "-1"),
    ("1L << 63", "-9223372036854775808"),
    ("1L << 64", "1"),
    ("-1L >> 1", "-1"),
    ("1L << -1", "-9223372036854775808"),
  ]
  let i = rng.int(cases.length())
  let (expr, exp) = cases[i]
  let src = "fn main {\n  println((" + expr + ").to_string())\n}\n"
  { family: "boundary_i64", src, expected: [exp], js: "", excluded: false }
}

///|
fn gen_alias(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let v = rng.int(20)
  let src = "fn main {\n  let xs : Array[Int] = [" + v.to_string() +
    "]\n  let ys = xs\n  ys[0] = " + (v + 1).to_string() +
    "\n  println(xs[0].to_string())\n}\n"
  let js = "const xs=[" + v.to_string() + "]; const ys=xs; ys[0]=" + (v + 1).to_string() +
    "; console.log(xs[0]);\n"
  { family: "array_alias", src, expected: [(v + 1).to_string()], js, excluded: false }
}

///|
fn gen_utf8(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let strs = ["é", "éa", "🙂", "aé🙂", "日本語"]
  let s = strs[rng.int(strs.length())]
  let src = "fn main {\n  let s = \"" + s +
    "\"\n  println(s.length().to_string())\n  println(s.char_length().to_string())\n}\n"
  // Probe (all three backends agree): length() counts UTF-16 code units,
  // char_length() counts Unicode scalar values.  "é"=1/1, "🙂"=2/1,
  // "aé🙂"=4/3, "日本語"=3/3.
  let units = if s == "🙂" { 2 } else if s == "aé🙂" { 4 } else if s == "éa" { 2 } else if s == "日本語" { 3 } else { 1 }
  let chars = if s == "🙂" { 1 } else if s == "aé🙂" { 3 } else if s == "éa" { 2 } else if s == "日本語" { 3 } else { 1 }
  let js = "const s=\"" + s + "\"; console.log(s.length); console.log([...s].length);\n"
  { family: "utf8_string", src, expected: [units.to_string(), chars.to_string()], js, excluded: false }
}

///|
fn gen_var(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let t = te_gen(rng, 3, 32)
  let v = te_eval(t, 32)
  let src = "fn main {\n  let x = " + te_render(t) +
    "\n  let y = x + x\n  println(y.to_string())\n}\n"
  let js = "const d32=(a,b)=>b===0?0:(a/b)|0;const m32=(a,b)=>b===0?0:(a%b)|0; const x=" +
    te_js32(t) + "; console.log(((x+x)|0).toString());\n"
  { family: "var_use", src, expected: [te_wrap32(v + v).to_string()], js, excluded: false }
}

///|
fn gen_if(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = te_gen(rng, 2, 32)
  let b = te_gen(rng, 2, 32)
  let va = te_eval(a, 32)
  let vb = te_eval(b, 32)
  let take_a = va < vb
  let v = if take_a { va } else { vb }
  let src = "fn main {\n  let x = if (" + te_render(a) + " < " + te_render(b) +
    ") { " + te_render(a) + " } else { " + te_render(b) +
    " }\n  println(x.to_string())\n}\n"
  let js = "const d32=(a,b)=>b===0?0:(a/b)|0;const m32=(a,b)=>b===0?0:(a%b)|0; const a=" +
    te_js32(a) + "; const b=" + te_js32(b) + "; console.log((((a<b)?a:b)|0).toString());\n"
  { family: "if_else", src, expected: [v.to_string()], js, excluded: false }
}

///|
fn gen_func(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(200).to_int64() - 100L
  let b = rng.int(200).to_int64() - 100L
  let v = a + b
  let src = "fn add(a : Int, b : Int) -> Int { a + b }\nfn main {\n  let x = " +
    a.to_string() + "\n  let y = " + b.to_string() +
    "\n  println(add(x, y).to_string())\n}\n"
  let js = "const a=" + a.to_string() + "; const b=" + b.to_string() +
    "; console.log(((a+b)|0).toString());\n"
  { family: "func_call", src, expected: [v.to_string()], js, excluded: false }
}

///|
fn gen_nested_array(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(10)
  let b = rng.int(10)
  let src = "fn main {\n  let xs : Array[Array[Int]] = [[" + a.to_string() +
    ", " + b.to_string() + "], [3, 4]]\n  println(xs[0][1].to_string())\n}\n"
  let js = "const xs=[[" + a.to_string() + "," + b.to_string() +
    "],[3,4]]; console.log(xs[0][1]);\n"
  { family: "array_nested", src, expected: [b.to_string()], js, excluded: false }
}

///|
fn gen_struct(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(100)
  let b = rng.int(100)
  let src = "struct P { x : Int; y : Int }\nfn sum(p : P) -> Int { p.x + p.y }\nfn main {\n  let p : P = { x: " +
    a.to_string() + ", y: " + b.to_string() +
    " }\n  println(p.x.to_string())\n  println(p.y.to_string())\n  println(sum(p).to_string())\n}\n"
  let js = "const p={x:" + a.to_string() + ",y:" + b.to_string() +
    "}; console.log(p.x); console.log(p.y); console.log((p.x+p.y)|0);\n"
  { family: "struct_fields", src, expected: [a.to_string(), b.to_string(), (a + b).to_string()], js, excluded: false }
}

///|
fn gen_nested_struct(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(50)
  let b = rng.int(50)
  let src = "struct Inner { v : Int }\nstruct Outer { a : Inner; b : Int }\nfn main {\n  let o : Outer = { a: { v: " +
    a.to_string() + " }, b: " + b.to_string() +
    " }\n  println(o.a.v.to_string())\n  println(o.b.to_string())\n}\n"
  let js = "const i={v:" + a.to_string() + "}; const o={a:i,b:" + b.to_string() +
    "}; console.log(o.a.v); console.log(o.b);\n"
  { family: "struct_nested", src, expected: [a.to_string(), b.to_string()], js, excluded: false }
}

///|
fn gen_enum(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let tag = rng.int(3)
  let x = rng.int(30)
  let y = rng.int(30)
  if tag == 0 {
    let src = "enum E { A; B(Int); C(Int, Int) }\nfn main {\n  let e : E = A\n  let r = match e {\n    A => 0\n    B(n) => n\n    C(a, b) => a + b\n  }\n  println(r.to_string())\n}\n"
    { family: "enum_match", src, expected: ["0"], js: "console.log(0);\n", excluded: false }
  } else if tag == 1 {
    let src = "enum E { A; B(Int); C(Int, Int) }\nfn main {\n  let e : E = B(" + x.to_string() +
      ")\n  let r = match e {\n    A => 0\n    B(n) => n\n    C(a, b) => a + b\n  }\n  println(r.to_string())\n}\n"
    { family: "enum_match", src, expected: [x.to_string()], js: "console.log(" + x.to_string() + ");\n", excluded: false }
  } else {
    let src = "enum E { A; B(Int); C(Int, Int) }\nfn main {\n  let e : E = C(" + x.to_string() +
      ", " + y.to_string() +
      ")\n  let r = match e {\n    A => 0\n    B(n) => n\n    C(a, b) => a + b\n  }\n  println(r.to_string())\n}\n"
    { family: "enum_match", src, expected: [(x + y).to_string()], js: "console.log(" + (x + y).to_string() + ");\n", excluded: false }
  }
}

///|
fn gen_box(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let v = rng.int(100)
  let src = "enum Box[T] { Val(T) }\nfn main {\n  let b : Box[Int] = Box::Val(" +
    v.to_string() +
    ")\n  match b { Box::Val(x) => println(x.to_string()) }\n}\n"
  { family: "generic_box", src, expected: [v.to_string()], js: "console.log(" + v.to_string() + ");\n", excluded: false }
}

///|
fn gen_closure(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let k = rng.int(50)
  let x = rng.int(50)
  let src = "fn main {\n  let k = " + k.to_string() +
    "\n  let f = fn(x : Int) -> Int { x + k }\n  println(f(" + x.to_string() +
    ").to_string())\n}\n"
  let js = "const k=" + k.to_string() + "; const f=(x)=>x+k; console.log(f(" +
    x.to_string() + "));\n"
  { family: "closure_capture", src, expected: [(k + x).to_string()], js, excluded: false }
}

///|
fn gen_typed_nested(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(30)
  let b = rng.int(30)
  let src = "struct Inner { v : Int }\nenum Box[T] { Val(T) }\nenum E { A; B(Box[Inner]) }\nstruct Outer { e : E; k : Int }\nfn main {\n  let o : Outer = { e: B(Box::Val({ v: " +
    a.to_string() + " })), k: " + b.to_string() +
    " }\n  let r = match o.e {\n    A => 0\n    B(bx) => match bx {\n      Box::Val(i) => i.v + o.k\n    }\n  }\n  println(r.to_string())\n}\n"
  let js = "const i={v:" + a.to_string() + "}; const bx={tag:'Val',v:i}; const o={e:{tag:'B',p:bx},k:" +
    b.to_string() + "}; console.log((o.k+i.v)|0);\n"
  { family: "typed_nested", src, expected: [(a + b).to_string()], js, excluded: false }
}

///|
fn te_js32(t : TE) -> String {
  let p = "const d32=(a,b)=>b===0?0:(a/b)|0;const m32=(a,b)=>b===0?0:(a%b)|0;"
  ignore(p)
  match t {
    C(v) => v.to_string()
    Add(a, b) => "(" + te_js32(a) + " + " + te_js32(b) + ")"
    Sub(a, b) => "(" + te_js32(a) + " - " + te_js32(b) + ")"
    Mul(a, b) => "(" + te_js32(a) + " * " + te_js32(b) + ")"
    Div(a, b) => "d32(" + te_js32(a) + "," + te_js32(b) + ")"
    Mod(a, b) => "m32(" + te_js32(a) + "," + te_js32(b) + ")"
    BAnd(a, b) => "(" + te_js32(a) + " & " + te_js32(b) + ")"
    BOr(a, b) => "(" + te_js32(a) + " | " + te_js32(b) + ")"
    BXor(a, b) => "(" + te_js32(a) + " ^ " + te_js32(b) + ")"
    Shl(a, b) => "(" + te_js32(a) + "<< (" + te_js32(b) + " & 31))"
    Shr(a, b) => "(" + te_js32(a) + ">> (" + te_js32(b) + " & 31))"
  }
}

///|
fn te_js64(t : TE) -> String {
  match t {
    C(v) => "BigInt.asIntN(64,BigInt(" + v.to_string() + "))"
    Add(a, b) => "BigInt.asIntN(64," + te_js64(a) + " + " + te_js64(b) + ")"
    Sub(a, b) => "BigInt.asIntN(64," + te_js64(a) + " - " + te_js64(b) + ")"
    Mul(a, b) => "BigInt.asIntN(64," + te_js64(a) + " * " + te_js64(b) + ")"
    Div(a, b) => "BigInt.asIntN(64," + te_js64(a) + "/" + "(" + te_js64(b) + "||1n))"
    Mod(a, b) => "BigInt.asIntN(64," + te_js64(a) + "%" + "(" + te_js64(b) + "||1n))"
    BAnd(a, b) => "BigInt.asIntN(64," + te_js64(a) + " & " + te_js64(b) + ")"
    BOr(a, b) => "BigInt.asIntN(64," + te_js64(a) + " | " + te_js64(b) + ")"
    BXor(a, b) => "BigInt.asIntN(64," + te_js64(a) + " ^ " + te_js64(b) + ")"
    Shl(a, b) => "BigInt.asIntN(64," + te_js64(a) + "<< (" + te_js64(b) + " & 63n))"
    Shr(a, b) => "BigInt.asIntN(64," + te_js64(a) + ">> (" + te_js64(b) + " & 63n))"
  }
}

///|
fn gen_typed_deep(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(20)
  let b = rng.int(20)
  let c = rng.int(20)
  let d = rng.int(20)
  let src = "struct Leaf { v : Int }\nstruct Bucket { xs : Array[Leaf]; k : Int }\nenum Box[T] { Val(T) }\nenum Holder { Empty; Has(Box[Bucket]) }\nstruct Root { h : Holder; n : Int }\nfn main {\n  let r : Root = { h: Has(Box::Val({ xs: [{ v: " +
    a.to_string() + " }, { v: " + b.to_string() + " }], k: " + c.to_string() +
    " })), n: " + d.to_string() +
    " }\n  let out = match r.h {\n    Empty => 0\n    Has(bx) => match bx {\n      Box::Val(bk) => bk.xs[1].v + bk.k + r.n\n    }\n  }\n  println(out.to_string())\n}\n"
  let js = "const leafs=[{v:" + a.to_string() + "},{v:" + b.to_string() +
    "}]; const bk={xs:leafs,k:" + c.to_string() +
    "}; const r={h:{tag:'Has',p:{tag:'Val',v:bk}},n:" + d.to_string() +
    "}; console.log((bk.xs[1].v+bk.k+r.n)|0);\n"
  { family: "typed_deep", src, expected: [(b + c + d).to_string()], js, excluded: false }
}

///|
fn gen_float_bits(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(1000).to_double() / 8.0
  let b = (rng.int(1000).to_double() / 8.0) + 0.5
  let op = rng.int(11)
  let (mexpr, jexpr, is_nan) = if op == 0 {
    ("a + b", "a + b", false)
  } else if op == 1 {
    ("a - b", "a - b", false)
  } else if op == 2 {
    ("a * b", "a * b", false)
  } else if op == 3 {
    ("a / b", "a / b", false)
  } else if op == 4 {
    ("a.sqrt()", "Math.sqrt(a)", false)
  } else if op == 5 {
    ("a.floor()", "Math.floor(a)", false)
  } else if op == 6 {
    ("a.ceil()", "Math.ceil(a)", false)
  } else if op == 7 {
    ("a.round()", "Math.round(a)", false)
  } else if op == 8 {
    ("a.trunc()", "Math.trunc(a)", false)
  } else if op == 9 {
    ("a.min(b)", "Math.min(a, b)", false)
  } else {
    ("a.max(b)", "Math.max(a, b)", false)
  }
  // Negative sqrt would be NaN; the inputs are positive, but keep the guard.
  let src = "fn main {\n  let a : Double = " + a.to_string() + "\n  let b : Double = " +
    b.to_string() + "\n  let r : Double = " + mexpr +
    "\n  println(r.reinterpret_as_uint64().to_string())\n}\n"
  let js = "const a=" + a.to_string() + "; const b=" + b.to_string() +
    "; const f=(x)=>{const dv=new DataView(new ArrayBuffer(8));dv.setFloat64(0,x);return dv.getBigUint64(0).toString()}; console.log(f(" +
    jexpr + "));\n"
  { family: "float_bits", src, expected: ["<node>"], js, excluded: is_nan }
}

///|
fn gen_float_cmp(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(100).to_double() / 4.0
  let b = rng.int(100).to_double() / 4.0
  let op = rng.int(3)
  let mexpr = if op == 0 { "a < b" } else if op == 1 { "a == b" } else { "a > b" }
  let jexpr = if op == 0 { "a < b" } else if op == 1 { "a === b" } else { "a > b" }
  let src = "fn main {\n  let a : Double = " + a.to_string() + "\n  let b : Double = " +
    b.to_string() + "\n  println((" + mexpr + ").to_string())\n}\n"
  let js = "const a=" + a.to_string() + "; const b=" + b.to_string() +
    "; console.log(String(" + jexpr + "));\n"
  { family: "float_cmp", src, expected: ["<node>"], js, excluded: false }
}
