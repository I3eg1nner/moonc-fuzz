///|
/// Result of one child-process invocation.  `rc` uses the Python harness
/// convention: negative signal number for a killed child, `-999` for a spawn
/// error.  `timed_out` is set only when the wall-clock guard fired.
pub(all) struct RunResult {
  rc : Int32
  stdout : String
  stderr : String
  ms : Int64
  timed_out : Bool
}

///|
fn text_of(b : Bytes) -> String {
  // Child output is treated as UTF-8 with replacement, exactly like the
  // Python harness's `.decode("utf-8", "replace")`.
  b.to_string()
}

///|
/// Run `cmd args...` with a hard wall-clock timeout.  On timeout the child is
/// killed by the async cancellation handler, so a parser OOM/hang cannot leak
/// into the next test.
pub async fn run(
  cmd : String,
  args : Array[String],
  cwd : StringView,
  timeout_ms : Int32,
) -> RunResult {
  let t0 = @async.now()
  let maybe = @async.with_timeout_opt(timeout_ms, async fn() {
    @process.run(
      cmd,
      args,
      cwd~,
      stdout=@process.ProcessOutput::Collect,
      stderr=@process.ProcessOutput::Collect,
      cancel_handler=@process.hard_cancel(),
    )
  })
  let ms = @async.now() - t0
  match maybe {
    None => { rc: -999, stdout: "", stderr: "", ms, timed_out: true, }
    Some(res) => {
      let out = res.stdout_text() catch { _ => text_of(res.stdout_binary()) }
      let err = res.stderr_text() catch { _ => text_of(res.stderr_binary()) }
      { rc: res.exit_code, stdout: out, stderr: err, ms, timed_out: false, }
    }
  }
}

///|
/// Convenience wrapper for `cmd` that has no arguments.
pub async fn run1(
  cmd : String,
  cwd : StringView,
  timeout_ms : Int32,
) -> RunResult {
  run(cmd, [], cwd, timeout_ms)
}

///|
pub fn stdout(r : RunResult) -> String {
  r.stdout
}

///|
pub fn stderr(r : RunResult) -> String {
  r.stderr
}

///|
/// Classify a result using the same markers as harness/mbtfuzz.py.
/// Returned strings are stable identifiers, not prose.
pub fn classify(r : RunResult) -> String {
  if r.timed_out {
    return "HANG"
  }
  // Compiler markers are written to stderr.  Scanning stdout here lets a
  // fuzzed program that prints "Oops..." masquerade as a compiler ICE.
  let t = r.stderr
  if t.contains("Oops, the compiler has encountered") {
    return "ICE"
  }
  if t.contains("out of memory") ||
    t.contains("Out_of_memory") ||
    t.contains("Cannot allocate memory") ||
    t.contains("Memprof") {
    return "OOM"
  }
  if t.contains("Fatal error: exception") {
    return "OCAML_EXN"
  }
  if t.contains("Stack overflow") || t.contains("Stack_overflow") {
    return "STACK"
  }
  if t.contains("Assert_failure") {
    return "ASSERT"
  }
  if r.rc < 0 {
    return "SIG"
  }
  if r.rc == 0 {
    return "OK"
  }
  "ERR"
}

///|
/// Extract the first `Error: ...` line from an ICE report, trimmed to 200
/// bytes.  This is the low-cardinality part of a defect signature.
pub fn ice_detail(r : RunResult) -> String {
  let t = r.stderr + r.stdout
  for line in t.split("\n") {
    let s = line.trim()
    if s.has_prefix("Error: ") {
      let v = s.exact_view(start=7)
      return if v.char_length() > 200 {
        v.exact_view(start=0, end=200).to_owned()
      } else {
        v.to_owned()
      }
    }
  }
  ""
}
