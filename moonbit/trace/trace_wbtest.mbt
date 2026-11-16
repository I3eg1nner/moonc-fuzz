///|
fn trace_test_run(
  rc : Int32,
  stderr : String,
  timed_out : Bool,
) -> @exec.RunResult {
  {
    rc,
    stdout: "",
    stderr,
    ms: 1L,
    timed_out,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
}

///|
test "collector rejects shell exits even when a PC was written" {
  let (outcome, failure) = classify_collection(
    trace_test_run(127, "", false),
    1L,
    1024L,
  )
  assert_true(outcome == CollectorFailed)
  assert_true(failure.contains("127"))
}

///|
test "collector distinguishes diagnostics from unclassified exits" {
  let (diag, diag_failure) = classify_collection(
    trace_test_run(2, "in.mbt:1:1 [E3002] Parse error", false),
    1L,
    1024L,
  )
  assert_true(diag == Rejected)
  assert_eq(diag_failure, "")
  let (unknown, unknown_failure) = classify_collection(
    trace_test_run(2, "something went wrong", false),
    1L,
    1024L,
  )
  assert_true(unknown == CollectorFailed)
  assert_true(unknown_failure.contains("unclassified_exit=2"))
}

///|
test "collector keeps signals and resource failures out of rejections" {
  let (signal, _) = classify_collection(
    trace_test_run(-11, "", false),
    1L,
    1024L,
  )
  assert_true(signal == CompilerAbort)
  let (timeout, reason) = classify_collection(
    trace_test_run(0, "", true),
    1L,
    1024L,
  )
  assert_true(timeout == CollectorFailed)
  assert_eq(reason, "timeout")
  let (large, large_reason) = classify_collection(
    trace_test_run(0, "", false),
    2048L,
    1024L,
  )
  assert_true(large == CollectorFailed)
  assert_eq(large_reason, "trace_too_large")
}

///|
test "collector accepts a clean exit and rejects an empty trace" {
  let (ok, failure) = classify_collection(
    trace_test_run(0, "", false),
    1L,
    1024L,
  )
  assert_true(ok == Accepted)
  assert_eq(failure, "")
  let (empty, reason) = classify_collection(
    trace_test_run(0, "", false),
    0L,
    1024L,
  )
  assert_true(empty == CollectorFailed)
  assert_eq(reason, "empty_trace")
}
