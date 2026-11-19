///|
/// Compiler-driven reducer.
///
/// The division of labour matters: `reduce/` decides *what to try next* and is
/// covered by pure tests; this file only answers "does this candidate still
/// reproduce the same defect signature".  Keeping the process-spawning part
/// thin is what makes the engine testable at all.
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
fn write_text(path : String, text : String) -> Bool {
  let ok = try {
    @fs.write_string_to_file(path, text)
    true
  } catch {
    _ => false
  }
  ok
}

///|
fn try_read_dir(path : String) -> Array[String] {
  let out : Array[String] = []
  let names = @fs.read_dir(path) catch { _ => return out }
  for n in names {
    out.push(n)
  }
  out
}

///|
fn copy_tree(src : String, dst : String) -> Bool {
  let made = try {
    @fs.create_dir(dst)
    true
  } catch {
    _ => false
  }
  if !made && !@fs.path_exists(dst) {
    return false
  }
  let mut ok = true
  for name in try_read_dir(src) {
    if ok {
      let sp = join(src, name)
      let dp = join(dst, name)
      let is_dir_here = @fs.is_dir(sp) catch { _ => false }
      if is_dir_here {
        if !copy_tree(sp, dp) {
          ok = false
        }
      } else {
        let read_ok = try {
          let bytes = @fs.read_file_to_bytes(sp)
          @fs.write_bytes_to_file(dp, bytes)
          true
        } catch {
          _ => false
        }
        if !read_ok {
          ok = false
        }
      }
    }
  }
  ok
}

///|
fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let is_dir_here = @fs.is_dir(path) catch { _ => false }
  if is_dir_here {
    for name in try_read_dir(path) {
      rm_rf(join(path, name))
    }
    let _ = try {
      @fs.remove_dir(path)
      true
    } catch {
      _ => false
    }
  } else {
    let _ = try {
      @fs.remove_file(path)
      true
    } catch {
      _ => false
    }
  }
}

///|
fn moon_path() -> String {
  match @env.get_env_var("MOON") {
    Some(p) => p
    None => {
      let home = match @env.get_env_var("HOME") {
        Some(h) => h
        None => "/home/user"
      }
      home + "/.moon/bin/moon"
    }
  }
}

///|
fn stage_args(stage : String, target : String) -> Array[String] {
  let args : Array[String] = [stage, "--target", target]
  if stage == "test" {
    args.push("--build-only")
  }
  args
}

///|
/// Collapse runs of digits and whitespace.  Link-time ICE text embeds temp
/// paths, symbol hashes and byte counts, so an exact compare would reject
/// every candidate and silently reduce nothing.
fn normalize(s : String) -> String {
  let b = StringBuilder()
  let mut in_digits = false
  let mut in_space = false
  for c in s {
    let is_digit = c >= '0' && c <= '9'
    let is_space = c == ' ' || c == '\t'
    if is_digit {
      if !in_digits {
        b.write_char('#')
      }
      in_digits = true
      in_space = false
    } else if is_space {
      if !in_space {
        b.write_char(' ')
      }
      in_space = true
      in_digits = false
    } else {
      b.write_char(c)
      in_digits = false
      in_space = false
    }
  }
  let t = b.to_string().trim().to_owned()
  if t.char_length() > 180 {
    t[0:180].to_owned()
  } else {
    t
  }
}

///|
/// Defect signature of one staged run, built from the shared oracle layer so
/// the reducer and the campaign agree on what "the same defect" means.
fn signature(stage : String, r : @exec.RunResult) -> String {
  let obs = @judge.observation(
    stage,
    r.rc,
    r.timed_out,
    r.ms,
    r.ms,
    0,
    false,
    false,
    r.stdout,
    r.stderr,
  )
  let parts : Array[String] = []
  for f in @judge.check_all(@judge.registry(), obs) {
    parts.push(f.signature)
  }
  let raw = if parts.length() > 0 {
    let b = StringBuilder()
    for i, p in parts {
      if i > 0 {
        b.write_string(";")
      }
      b.write_string(p)
    }
    b.to_string()
  } else if r.timed_out {
    "timeout"
  } else if r.rc != 0 {
    "fail/rc=" + r.rc.to_string()
  } else {
    "ok"
  }
  normalize(raw)
}

///|
fn escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '"' {
      b.write_string("\\\"")
    } else if c == '\\' {
      b.write_string("\\\\")
    } else if c == '\n' {
      b.write_string("\\n")
    } else if c == '\r' {
      b.write_string("\\r")
    } else if c == '\t' {
      b.write_string("\\t")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn usage() -> Unit {
  println(
    "usage: reduce --dir PATH [--file lib.mbt] [--stage build|check|test] " +
    "[--timeout-ms N] [--fuel N] [--out PATH] [--target native] [--keep-workdir]",
  )
}

///|
/// Write one candidate and run one stage in the disposable work directory.
async fn run_once(
  target_path : String,
  stage : String,
  target : String,
  workdir : String,
  timeout_ms : Int,
  text : String
) -> String {
  if !write_text(target_path, text) {
    return "write-error"
  }
  let r = @exec.run_isolated(
    moon_path(),
    stage_args(stage, target),
    workdir,
    timeout_ms,
    max_output_bytes=65536,
  )
  signature(stage, r)
}

///|
async fn main {
  let args = @env.args()
  let mut dir = ""
  let mut file = "lib.mbt"
  let mut stage = "build"
  let mut timeout_ms = 120000
  let mut fuel = 300
  let mut out = ""
  let mut target = "native"
  let mut keep_workdir = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--dir" && i + 1 < args.length() {
      dir = args[i + 1]
    } else if a == "--file" && i + 1 < args.length() {
      file = args[i + 1]
    } else if a == "--stage" && i + 1 < args.length() {
      stage = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = parse_int(args[i + 1], timeout_ms)
    } else if a == "--fuel" && i + 1 < args.length() {
      fuel = parse_int(args[i + 1], fuel)
    } else if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--target" && i + 1 < args.length() {
      target = args[i + 1]
    } else if a == "--keep-workdir" {
      keep_workdir = true
    }
  }
  if dir == "" || !@fs.path_exists(join(dir, file)) {
    usage()
    @env.exit(2)
  }
  if stage != "check" && stage != "build" && stage != "test" {
    usage()
    @env.exit(2)
  }

  let start_ms = @env.now()
  let workdir = "/tmp/mbtfuzz_reduce_" + start_ms.to_string()
  rm_rf(workdir)
  if !copy_tree(dir, workdir) {
    println("{\"ok\":false,\"error\":\"copy failed\"}")
    @env.exit(2)
  }
  let target_path = join(workdir, file)
  let original = read_text(target_path)
  let before_lines = count_lines(original)

  let baseline = run_once(
    target_path,
    stage,
    target,
    workdir,
    timeout_ms,
    original,
  )
  if baseline == "ok" {
    println(
      "{\"ok\":false,\"error\":\"baseline passes; nothing to reduce\"," +
      "\"stage\":\"" +
      stage +
      "\"}",
    )
    @env.exit(1)
  }

  let r = @reduce.start(original, fuel)
  let mut go = true
  while go {
    match @reduce.next_text(r) {
      Some(cand) => {
        let sig = run_once(
          target_path,
          stage,
          target,
          workdir,
          timeout_ms,
          cand,
        )
        @reduce.verdict(r, sig == baseline)
      }
      None => go = false
    }
  }
  let reduced = @reduce.result(r)
  // Never trust an unverified reduction: re-run the final text once.
  let final_sig = run_once(
    target_path,
    stage,
    target,
    workdir,
    timeout_ms,
    reduced,
  )
  let verified = final_sig == baseline
  if !verified {
    // Fall back to the baseline text rather than shipping a broken witness.
    let _ = write_text(target_path, original)
  }
  if out != "" {
    let _ = write_text(out, reduced)
  }
  let after_lines = count_lines(reduced)
  let ms = @env.now() - start_ms
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  b.write_string(if verified { "true" } else { "false" })
  b.write_string(",\"stage\":\"")
  b.write_string(stage)
  b.write_string("\",\"baseline\":\"")
  b.write_string(escape(baseline))
  b.write_string("\",\"before_lines\":")
  b.write_string(before_lines.to_string())
  b.write_string(",\"after_lines\":")
  b.write_string(after_lines.to_string())
  b.write_string(",\"calls\":")
  b.write_string(@reduce.test_calls(r).to_string())
  b.write_string(",\"exhausted\":")
  b.write_string(if @reduce.was_exhausted(r) { "true" } else { "false" })
  b.write_string(",\"verified\":")
  b.write_string(if verified { "true" } else { "false" })
  b.write_string(",\"ms\":")
  b.write_string(ms.to_string())
  b.write_string(",\"workdir\":\"")
  b.write_string(escape(if keep_workdir { workdir } else { "" }))
  b.write_string("\",\"out\":\"")
  b.write_string(escape(out))
  b.write_string("\"}")
  println(b.to_string())
  if !keep_workdir {
    rm_rf(workdir)
  }
  if !verified {
    @env.exit(1)
  }
}

///|
fn count_lines(text : String) -> Int {
  let mut n = 0
  for line in text.split("\n") {
    if line.char_length() > 0 {
      n += 1
    }
  }
  n
}

///|
fn parse_int(s : String, dflt : Int) -> Int {
  let mut v = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - 48)
      any = true
    } else {
      return dflt
    }
  }
  if any { v } else { dflt }
}
