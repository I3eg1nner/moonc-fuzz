///|
/// Tests for the two pieces of judgement inside the differential: what counts
/// as "did not build", and which pair of targets a mismatch hint describes.
/// Both are places where a wrong answer hides a real difference.

///|
fn obs(t : String, built : Bool, rc : Int32, out : String) -> Obs {
  { target: t, built, rc, out, err: "", ms: 0L, }
}

///|
test "build-failure detection: compile diagnostics only" {
  assert_true(looks_like_build_failure("Error: [4021]\n  Parse error"))
  assert_true(looks_like_build_failure("failed to build x (native)"))
  assert_false(looks_like_build_failure("panic: division by zero"))
  assert_false(
    looks_like_build_failure(
      "Error: Machine_error(kind=unsupported; who=\"lower_array_make\")",
    ),
  )
}

///|
test "compare: needs two live targets, then stdout and rc must agree" {
  assert_eq(
    compare([obs("wasm-gc", true, 0, "a\n"), obs("native", true, 0, "a\n")]),
    "ALL_EQUAL",
  )
  assert_eq(
    compare([obs("wasm-gc", true, 0, "a\n"), obs("native", true, 1, "a\n")]),
    "MISMATCH",
  )
  assert_eq(
    compare([obs("wasm-gc", true, 0, "a\n"), obs("native", true, 0, "b\n")]),
    "MISMATCH",
  )
  assert_eq(
    compare([obs("wasm-gc", true, 0, "a\n"), obs("native", false, 1, "")]),
    "SKIP",
  )
}

///|
test "hint: names the first differing pair and line" {
  let o = [
    obs("wasm-gc", true, 0, "x=1\ny=2\n"),
    obs("js", true, 0, "x=1\ny=3\n"),
    obs("native", true, 0, "x=1\ny=2\n"),
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
    obs("wasm-gc", true, 0, "same\n"),
    obs("native", true, 134, "same\n"),
  ])
  assert_true(h.contains("rc wasm-gc=0 vs native=134"))
}

///|
test "first_diff_line: a missing line shows up as an empty line" {
  // "a\nb\n" splits to ["a","b",""], so the divergence is at line 2, not a
  // length-only difference.
  assert_eq(first_diff_line("a\nb\n", "a\n"), "line 2: `b` vs ``")
  assert_eq(first_diff_line("a\nb", "a\nc"), "line 2: `b` vs `c`")
}
