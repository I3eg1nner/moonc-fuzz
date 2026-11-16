///|
/// Structured result of one background coverage collection.  `complete=false`
/// means the result must not enter a coverage union: QEMU failed, the log was
/// truncated, or the timeout fired.
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
  stage : String
  outcome : TraceOutcome
  complete : Bool
  functions : Array[String]
  elapsed_ms : Int64
  trace_bytes : Int64
  detail : String
}

///|
fn is_compiler_abort(kind : String) -> Bool {
  kind == "ICE" ||
  kind == "OOM" ||
  kind == "OCAML_EXN" ||
  kind == "STACK" ||
  kind == "ASSERT"
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
  stage : String,
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
  let kind = @exec.classify(r)
  let outcome = if r.timed_out || trace_bytes == 0L {
    CollectorFailed
  } else if trace_bytes > max_trace_bytes {
    CollectorFailed
  } else if r.rc == 0 {
    Accepted
  } else if is_compiler_abort(kind) {
    CompilerAbort
  } else {
    Rejected
  }
  let complete = outcome != CollectorFailed
  {
    input_hash,
    config_hash,
    stage,
    outcome,
    complete,
    functions,
    elapsed_ms: r.ms,
    trace_bytes,
    detail: @exec.ice_detail(r),
  }
}
