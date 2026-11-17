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

///|
test "wrapper status wins over OOM-looking command output" {
  let (outcome, failure) = classify_collection(
    trace_test_run(127, "Cannot allocate memory", false),
    1L,
    1024L,
  )
  assert_true(outcome == CollectorFailed)
  assert_eq(failure, "collector_exit=127")
}

///|
test "moonc ICE status 199 is not mistaken for a wrapper failure" {
  let (ice, _) = classify_collection(
    trace_test_run(
      199, "Oops, the compiler has encountered an unexpected situation.", false,
    ),
    1L,
    1024L,
  )
  assert_true(ice == CompilerAbort)
  let (unknown, reason) = classify_collection(
    trace_test_run(199, "", false),
    1L,
    1024L,
  )
  assert_true(unknown == CollectorFailed)
  assert_eq(reason, "unclassified_exit=199")
}

///|
test "coverage_fields returns exact counters from one trace scan" {
  let tab = SymTab::parse(
    "0000000000000010 T camlMoonc__A\n0000000000000020 T camlMoonc__B\n" +
    "0000000000000030 T main\n",
  )
  // Repeated PC 0x10 and repeated pair (0x30,0x30); one unmapped PC at the end.
  let trace = "[0/0000000000000010/0]\n[0/0000000000000010/0]\n" +
    "[0/0000000000000020/0]\n[0/0000000000000030/0]\n" +
    "[0/0000000000000030/0]\n[0/0000000000000099/0]\n"
  let (functions, unique_pc, mapped_unique_pc, edges, mapped_edges) = coverage_fields(
    trace, tab,
  )
  // The historic `camlMoonc*` filter still drops `main`.
  assert_eq(functions, ["camlMoonc__A", "camlMoonc__B"])
  assert_eq(unique_pc, 4)
  assert_eq(mapped_unique_pc, 3)
  // Pairs: (10,10) (10,20) (20,30) (30,30) (30,99).
  assert_eq(edges, 5)
  // (30,99) is the only pair with an unmapped endpoint.
  assert_eq(mapped_edges, 4)
  // `main` is mapped, so edge_keys includes transitions it participates in:
  // the edge set is wider than the function set.
  assert_eq(edge_keys(trace, tab).length(), 4)
  assert_true(edge_keys(trace, tab).contains("32,48"))
}

///|
test "coverage_fields on an empty trace is all zeros" {
  let tab = SymTab::parse("0000000000000010 T camlMoonc__A\n")
  let (functions, unique_pc, mapped_unique_pc, edges, mapped_edges) = coverage_fields(
    "", tab,
  )
  assert_eq(functions, [])
  assert_eq(unique_pc, 0)
  assert_eq(mapped_unique_pc, 0)
  assert_eq(edges, 0)
  assert_eq(mapped_edges, 0)
}
