///|
test "oracle sensitivity: injected stdout mismatch" {
  assert_true(!@oracle.outcomes_agree("OK", 0, "a", "OK", 0, "b"))
  assert_true(@oracle.outcomes_agree("OK", 0, "a", "OK", 0, "a"))
}

///|
test "oracle sensitivity: injected rc mismatch and success/failure split" {
  assert_true(!@oracle.outcomes_agree("OK", 0, "", "OK", 1, ""))
  assert_true(!@oracle.outcomes_agree("OK", 0, "", "ERR", 1, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "OK", 0, ""))
}

///|
test "run-stage traps compare rc and output" {
  assert_true(@oracle.outcomes_agree("SIG", -11, "", "SIG", -11, ""))
  assert_true(!@oracle.outcomes_agree("SIG", -11, "", "ICE", 199, ""))
}

///|
test "outcomes_agree trims both sides before comparing stdout" {
  assert_true(@oracle.outcomes_agree("OK", 0, "a\n", "OK", 0, " a "))
  assert_true(!@oracle.outcomes_agree("OK", 0, "a b", "OK", 0, "ab"))
}

///|
test "outcomes_agree does not equate unrelated failures" {
  assert_true(!@oracle.outcomes_agree("SIG", -11, "", "SIG", -6, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "ICE", 2, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "OOM", 199, ""))
}

///|
test "link failure vs build failure is inconclusive, not same" {
  assert_true(
    @oracle.classify_diff("ERR", 2, "", "link", "ERR", 2, "", "build") ==
    @oracle.Inconclusive,
  )
}

///|
test "one backend runs while the other is rejected is an acceptance diff" {
  assert_true(
    @oracle.classify_diff("OK", 0, "x", "run", "ERR", 2, "", "build") ==
    @oracle.AcceptDiff,
  )
}

///|
test "compiler abort is never folded into same" {
  assert_true(
    @oracle.classify_diff("ICE", 199, "", "link", "ERR", 2, "", "build") ==
    @oracle.CompilerAbort,
  )
  assert_true(
    @oracle.classify_diff("ICE", 199, "", "build", "ICE", 199, "", "build") ==
    @oracle.CompilerAbort,
  )
}

///|
test "both sides execute and agree only when rc and stdout match" {
  assert_true(
    @oracle.classify_diff("OK", 0, "x\n", "run", "OK", 0, " x ", "run") ==
    @oracle.Same,
  )
  assert_true(
    @oracle.classify_diff("OK", 0, "x", "run", "OK", 0, "y", "run") ==
    @oracle.SemanticDiff,
  )
  assert_true(
    @oracle.classify_diff("OK", 0, "x", "run", "OK", 1, "x", "run") ==
    @oracle.SemanticDiff,
  )
}

///|
test "both sides fail before execution is inconclusive" {
  assert_true(
    @oracle.classify_diff("ERR", 2, "", "link", "ERR", 2, "", "build") ==
    @oracle.Inconclusive,
  )
}
