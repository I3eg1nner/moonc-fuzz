///|
/// Structured result of one background coverage collection.  `complete=false`
/// means the result must not enter a coverage union: QEMU failed, the log was
/// truncated, or the outcome could not be attributed to the compiler.
pub(all) enum TraceOutcome {
  Accepted
  Rejected
  CompilerAbort
  CollectorFailed
}

///|
pub impl Eq for TraceOutcome with fn equal(a, b) {
  match (a, b) {
    (Accepted, Accepted)
    | (Rejected, Rejected)
    | (CompilerAbort, CompilerAbort)
    | (CollectorFailed, CollectorFailed) => true
    _ => false
  }
}

///|
pub extend TraceOutcome with Eq::{not_equal, equal}

///|
/// The three compiler entry points are a closed set.  Scheduling, command
/// construction, and report keys all switch on this type instead of silently
/// treating an unknown string as T1 or T3.
pub(all) enum TraceStage {
  T1
  T2
  T3
}

///|
pub impl Eq for TraceStage with fn equal(a, b) {
  match (a, b) {
    (T1, T1) | (T2, T2) | (T3, T3) => true
    _ => false
  }
}

///|
pub extend TraceStage with Eq::{not_equal, equal}

///|
pub fn trace_stage_name(stage : TraceStage) -> String {
  match stage {
    T1 => "t1"
    T2 => "t2"
    T3 => "t3"
  }
}

///|
pub fn trace_outcome_name(o : TraceOutcome) -> String {
  match o {
    Accepted => "accepted"
    Rejected => "rejected"
    CompilerAbort => "compiler_abort"
    CollectorFailed => "collector_failed"
  }
}

///|
pub(all) struct TraceResult {
  input_hash : String
  config_hash : String
  stage : TraceStage
  outcome : TraceOutcome
  complete : Bool
  functions : Array[String]
  elapsed_ms : Int64
  trace_bytes : Int64
  /// Exit status of the traced command.  Negative values are signals.
  rc : Int32
  /// Machine-readable failure category; empty for a usable result.
  failure : String
  detail : String
}

///|
fn is_compiler_abort(kind : String) -> Bool {
  kind == "ICE" ||
  kind == "OOM" ||
  kind == "OCAML_EXN" ||
  kind == "STACK" ||
  kind == "ASSERT" ||
  kind == "SIG"
}

///|
/// Exit statuses reserved by the GNU timeout wrapper, not by moonc.  A
/// valid-looking PC written before such an exit is not evidence that this run
/// exercised the requested compiler path.  Do not extend this to arbitrary
/// >=128 statuses: moonc itself uses 199 for real ICEs.
fn is_collector_exit(rc : Int32) -> Bool {
  rc == 124 || rc == 125 || rc == 126 || rc == 127
}

///|
/// A normal compiler rejection must carry a diagnostic.  Without one, a
/// non-zero exit is indistinguishable from a broken collector and is kept out
/// of the coverage union.
fn has_compiler_diagnostic(r : @exec.RunResult) -> Bool {
  let text = r.stderr + "\n" + r.stdout
  text.contains("[E") ||
  text.contains("Error:") ||
  text.contains("\"level\":\"error\"")
}

///|
fn clipped(text : String, limit : Int32) -> String {
  let s = text.trim()
  if s.char_length() <= limit {
    s.to_owned()
  } else {
    s.exact_view(start=0, end=limit).to_owned() + "..."
  }
}

///|
/// Pure decision function, kept separate so fault-injection tests can exercise
/// exit 127, signals, empty traces, and unclassified failures without running
/// QEMU.
fn classify_collection(
  r : @exec.RunResult,
  trace_bytes : Int64,
  max_trace_bytes : Int64,
) -> (TraceOutcome, String) {
  if r.timed_out {
    (CollectorFailed, "timeout")
  } else if trace_bytes == 0L {
    (CollectorFailed, "empty_trace")
  } else if trace_bytes > max_trace_bytes {
    (CollectorFailed, "trace_too_large")
  } else if r.rc == 0 {
    (Accepted, "")
  } else if is_collector_exit(r.rc) {
    // Wrapper status wins even if the command wrote OOM/ICE-looking text
    // before the wrapper failed.
    (CollectorFailed, "collector_exit=" + r.rc.to_string())
  } else if is_compiler_abort(@exec.classify(r)) {
    (CompilerAbort, "")
  } else if has_compiler_diagnostic(r) {
    (Rejected, "")
  } else {
    (CollectorFailed, "unclassified_exit=" + r.rc.to_string())
  }
}

///|
fn parse_i64(s : StringView) -> Int64 {
  let mut v = 0L
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
    } else if c == '\n' || c == '\r' || c == ' ' || c == '\t' {
      return v
    } else {
      return 0L
    }
  }
  v
}

///|
/// `stat` before reading lets an oversized log fail without allocating it.
async fn log_size(path : String) -> Int64 {
  let r = @exec.run("/usr/bin/stat", ["-c", "%s", path], "/tmp", 5000)
  if r.rc == 0 {
    parse_i64(r.stdout.trim())
  } else {
    -1L
  }
}

///|
/// Run one command under QEMU and symbolize its executed PCs.  The caller
/// supplies the exact argv used by the fast path; nothing here reconstructs a
/// "close enough" invocation.
pub async fn collect(
  qemu : String,
  cmd : String,
  args : Array[String],
  cwd : String,
  tag : String,
  sym : SymTab,
  input_hash : String,
  config_hash : String,
  stage : TraceStage,
  timeout_ms : Int32,
  max_trace_bytes : Int64,
) -> TraceResult {
  let trace_path = if cwd.has_suffix("/") {
    cwd + "trace_" + tag + ".log"
  } else {
    cwd + "/trace_" + tag + ".log"
  }
  @fs.remove_file(trace_path) catch {
    _ => ()
  }
  let qargs = ["-d", "exec", "-D", trace_path, "--", cmd]
  for a in args {
    qargs.push(a)
  }
  let r = @exec.run_isolated(qemu, qargs, cwd, timeout_ms, mem_mb=4096)
  let pre_size = log_size(trace_path)
  let trace = if pre_size > max_trace_bytes {
    ""
  } else {
    @fs.read_file_to_string(trace_path) catch {
      _ => ""
    }
  }
  let trace_bytes = if pre_size >= 0L {
    pre_size
  } else {
    trace.length().to_int64()
  }
  @fs.remove_file(trace_path) catch {
    _ => ()
  }
  let functions = if trace == "" {
    []
  } else {
    let all = summarize_trace(trace, sym).funcs
    let out : Array[String] = []
    for f in all {
      if f.has_prefix("camlMoonc") {
        out.push(f)
      }
    }
    out
  }
  let (outcome, failure) = classify_collection(r, trace_bytes, max_trace_bytes)
  let complete = outcome != CollectorFailed
  let detail = if complete {
    @exec.ice_detail(r)
  } else {
    let stderr = clipped(r.stderr, 240)
    if stderr == "" {
      failure
    } else {
      failure + "; stderr=" + stderr
    }
  }
  {
    input_hash,
    config_hash,
    stage,
    outcome,
    complete,
    functions,
    elapsed_ms: r.ms,
    trace_bytes,
    rc: r.rc,
    failure,
    detail,
  }
}
