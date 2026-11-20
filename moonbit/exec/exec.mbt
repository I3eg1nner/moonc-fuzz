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
  /// SHA-1 of the full stdout after trimming, computed before truncation.
  /// Empty when no cap was requested; then `stdout` is already complete.
  stdout_digest : String
  /// Full stdout length in bytes before truncation.
  stdout_full_len : Int64
  stdout_truncated : Bool
}

///|
priv struct CappedText {
  text : String
  digest : String
  full_len : Int64
  truncated : Bool
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
  max_output_bytes~ : Int32 = 0,
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
    None =>
      {
        rc: -999,
        stdout: "",
        stderr: "",
        ms,
        timed_out: true,
        stdout_digest: "",
        stdout_full_len: 0L,
        stdout_truncated: false,
      }
    Some(res) => {
      let out = res.stdout_text() catch { _ => text_of(res.stdout_binary()) }
      let err = res.stderr_text() catch { _ => text_of(res.stderr_binary()) }
      let capped = cap_text(out, max_output_bytes)
      let err = cap_text(err, max_output_bytes)
      {
        rc: res.exit_code,
        stdout: capped.text,
        stderr: err.text,
        ms,
        timed_out: false,
        stdout_digest: capped.digest,
        stdout_full_len: capped.full_len,
        stdout_truncated: capped.truncated,
      }
    }
  }
}

///|
/// Bound collected output before it reaches classification or evidence files.
/// This happens after the child exits, so it limits retention, not the child's
/// peak memory; the wall-clock guard is still the primary defence.
fn cap_text(s : String, max_bytes : Int32) -> CappedText {
  if max_bytes <= 0 || s.length() <= max_bytes {
    return {
      text: s,
      digest: "",
      full_len: s.length().to_int64(),
      truncated: false,
    }
  }
  let digest = @crypto.bytes_to_hex_string(@crypto.sha1(@utf8.encode(s.trim())))
  let full_len = s.length().to_int64()
  let b = StringBuilder()
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    let w = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    if n + w > max_bytes {
      break
    }
    n = n + w
    b.write_char(c)
  }
  b.write_string("\n[output truncated]")
  { text: b.to_string(), digest, full_len, truncated: true, }
}

///|
/// Run with an external process-group timeout and an optional address-space
/// limit.  GNU `timeout` puts the child in its own group and kills descendants,
/// so a `moon run` native build cannot leave a C compiler behind.  `prlimit`
/// applies the memory cap to the whole group.
pub async fn run_isolated(
  cmd : String,
  args : Array[String],
  cwd : StringView,
  timeout_ms : Int32,
  max_output_bytes~ : Int32 = 0,
  mem_mb~ : Int32 = 0,
  fsize_mb~ : Int32 = 0,
) -> RunResult {
  let secs = ((timeout_ms + 999) / 1000).to_string() + "s"
  let targs : Array[String] = ["-v", "-k", "1s", secs, cmd]
  for a in args {
    targs.push(a)
  }
  let limits : Array[String] = []
  if mem_mb > 0 {
    limits.push("--as=" + (mem_mb.to_int64() * 1048576L).to_string())
  }
  // A file-size limit is a hard write cap for a child whose only output is one
  // file (the QEMU trace log).  It must not be used for compilers, which write
  // legitimate build artefacts.
  if fsize_mb > 0 {
    limits.push("--fsize=" + (fsize_mb.to_int64() * 1048576L).to_string())
  }
  let (outer, oargs) = if limits.length() > 0 {
    limits.push("--")
    limits.push("/usr/bin/timeout")
    for a in targs {
      limits.push(a)
    }
    ("/usr/bin/prlimit", limits)
  } else {
    ("/usr/bin/timeout", targs)
  }
  // Do not cap inside run: the timeout controller writes its marker to stderr
  // at the very end, so a pre-detection cap could hide it.
  let raw = run(outer, oargs, cwd, timeout_ms + 5000)
  let controller_fired = raw.stderr.contains("timeout: sending signal")
  let clean_err = if controller_fired {
    strip_timeout_messages(raw.stderr)
  } else {
    raw.stderr
  }
  let capped_out = cap_text(raw.stdout, max_output_bytes)
  let capped_err = cap_text(clean_err, max_output_bytes)
  let r = {
    rc: raw.rc,
    stdout: capped_out.text,
    stderr: capped_err.text,
    ms: raw.ms,
    timed_out: false,
    stdout_digest: capped_out.digest,
    stdout_full_len: capped_out.full_len,
    stdout_truncated: capped_out.truncated,
  }
  if raw.timed_out || r.rc == 124 || controller_fired {
    { ..r, rc: -999, timed_out: true, }
  } else {
    r
  }
}

///|
fn strip_timeout_messages(stderr : String) -> String {
  let b = StringBuilder()
  for line in stderr.split("\n") {
    if !line.contains("timeout: sending signal") {
      b.write_string(line.to_owned())
      b.write_string("\n")
    }
  }
  b.to_string()
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

///|
/// Append one line with O_APPEND through the shell.  `x/fs` exposes no append
/// handle, and read-then-rewrite made every stats tick and every failure log
/// O(file size).  The payload travels as a positional argument, so nothing is
/// shell-quoted or interpolated.
pub async fn append_line(path : String, line : String) -> Unit {
  let _ = run(
    "/bin/sh",
    ["-c", "printf '%s\\n' \"$1\" >> \"$2\"", "sh", line, path],
    "/tmp",
    5000,
  )
}
