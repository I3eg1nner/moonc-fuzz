///|
/// Tests for the two pieces of judgement inside the differential: the terminal
/// state of one target, and whether a set of states proves agreement.  Both
/// are places where a wrong answer hides either a real difference or a failed
/// experiment.

///|
fn obs(t : String, status : String, rc : Int32, out : String) -> Obs {
  {
    target: t,
    status,
    rc,
    out,
    err: "",
    ms: 0L,
    truncated: false,
    digest: "",
    full_len: 0L,
  }
}

///|
fn obs_full(
  t : String,
  out : String,
  truncated : Bool,
  digest : String,
  full_len : Int64,
) -> Obs {
  {
    target: t,
    status: ST_COMPLETE,
    rc: 0,
    out,
    err: "",
    ms: 0L,
    truncated,
    digest,
    full_len,
  }
}

///|
/// The false pass this suite exists for: two targets that both timed out used
/// to look identical because neither produced output.
test "compare: two timeouts are not agreement" {
  assert_eq(
    compare([
      obs("wasm-gc", ST_TIMEOUT, -999, ""),
      obs("native", ST_TIMEOUT, -999, ""),
    ]),
    "INCONCLUSIVE",
  )
}

///|
test "compare: identical crashes are not agreement" {
  assert_eq(
    compare([
      obs("wasm-gc", ST_RUN_FAIL, -11, ""),
      obs("native", ST_RUN_FAIL, -11, ""),
    ]),
    "INCONCLUSIVE",
  )
  assert_eq(
    compare([
      obs("wasm-gc", ST_BUILD_FAIL, 1, ""),
      obs("native", ST_BUILD_FAIL, 1, ""),
    ]),
    "INCONCLUSIVE",
  )
  assert_eq(
    compare([
      obs("wasm-gc", ST_LINK_FAIL, 1, ""),
      obs("native", ST_LINK_FAIL, 1, ""),
    ]),
    "INCONCLUSIVE",
  )
}

///|
test "compare: one failed target voids the case" {
  assert_eq(
    compare([
      obs("wasm-gc", ST_COMPLETE, 0, "a\n"),
      obs("native", ST_BUILD_FAIL, 1, ""),
    ]),
    "INCONCLUSIVE",
  )
  assert_eq(compare([obs("wasm-gc", ST_COMPLETE, 0, "a\n")]), "ALL_EQUAL")
}

///|
test "compare: only all-complete equal output is ALL_EQUAL" {
  assert_eq(
    compare([
      obs("wasm-gc", ST_COMPLETE, 0, "a\n"),
      obs("native", ST_COMPLETE, 0, "a\n"),
    ]),
    "ALL_EQUAL",
  )
  assert_eq(
    compare([
      obs("wasm-gc", ST_COMPLETE, 0, "a\n"),
      obs("native", ST_COMPLETE, 0, "b\n"),
    ]),
    "MISMATCH",
  )
  assert_eq(
    compare([
      obs("wasm-gc", ST_COMPLETE, 0, "a\n"),
      obs("js", ST_COMPLETE, 0, "a\n"),
      obs("native", ST_COMPLETE, 0, "a\n"),
    ]),
    "ALL_EQUAL",
  )
  assert_eq(compare([]), "NO_CASES")
}

///|
test "link failure is separated from a plain build failure" {
  assert_true(link_failure("Error: failed to link repro/v128surface"))
  assert_true(link_failure("Machine_error(kind=unsupported; who=\"x\")"))
  assert_false(link_failure("Error: [4021] Value x not found in package y"))
  assert_false(link_failure("Error: Parse error at line 3"))
}

///|
test "self-test covers every counterexample" {
  assert_true(self_test(false))
}

///|
test "hint: names the first differing pair and line" {
  let o = [
    obs("wasm-gc", ST_COMPLETE, 0, "x=1\ny=2\n"),
    obs("js", ST_COMPLETE, 0, "x=1\ny=3\n"),
    obs("native", ST_COMPLETE, 0, "x=1\ny=2\n"),
  ]
  let h = mismatch_hint(o)
  assert_true(h.has_prefix("wasm-gc vs js"))
  assert_true(h.contains("line 2"))
  assert_true(h.contains("y=2"))
  assert_true(h.contains("y=3"))
}

///|
test "hint: reports an rc difference instead of an empty line diff" {
  let h = mismatch_hint([
    obs("wasm-gc", ST_COMPLETE, 0, "same\n"),
    obs("native", ST_COMPLETE, 134, "same\n"),
  ])
  assert_true(h.contains("rc wasm-gc=0 vs native=134"))
}

///|
test "first_diff_line: a missing line shows up as an empty line" {
  assert_eq(first_diff_line("a\nb\n", "a\n"), "line 2: `b` vs ``")
  assert_eq(first_diff_line("a\nb", "a\nc"), "line 2: `b` vs `c`")
}

///|
/// The truncation false pass: two outputs that share the first 64 KiB but
/// differ afterwards used to compare equal because only the prefix was kept.
test "truncated output is never ALL_EQUAL" {
  let a = obs_full("wasm-gc", "prefix", true, "digest-a", 70000L)
  let b = obs_full("native", "prefix", true, "digest-b", 70000L)
  assert_eq(compare([a, b]), "INCONCLUSIVE")
  // Even with the same digest, a capped observation is not a complete one.
  let a2 = obs_full("wasm-gc", "prefix", true, "same", 70000L)
  let b2 = obs_full("native", "prefix", true, "same", 70000L)
  assert_eq(compare([a2, b2]), "INCONCLUSIVE")
}

///|
test "full digests decide equality when nothing is truncated" {
  let a = obs_full("wasm-gc", "prefix", false, "d1", 70000L)
  let b = obs_full("native", "prefix", false, "d1", 70000L)
  assert_eq(compare([a, b]), "ALL_EQUAL")
  let c = obs_full("native", "prefix", false, "d2", 70000L)
  assert_eq(compare([a, c]), "MISMATCH")
  let d = obs_full("native", "prefix", false, "d1", 70001L)
  assert_eq(compare([a, d]), "MISMATCH")
}
