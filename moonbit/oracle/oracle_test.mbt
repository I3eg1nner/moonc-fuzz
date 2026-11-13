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
test "oracle treats two failure classes as agreement, not miscompile" {
  assert_true(@oracle.outcomes_agree("SIG", -11, "", "SIG", -11, ""))
  assert_true(!@oracle.outcomes_agree("SIG", -11, "", "ICE", 199, ""))
}

///|
test "outcomes_agree trims both sides before comparing stdout" {
  assert_true(@oracle.outcomes_agree("OK", 0, "a\n", "OK", 0, " a "))
  assert_true(!@oracle.outcomes_agree("OK", 0, "a b", "OK", 0, "ab"))
}

///|
test "outcomes_agree compares failure class, not exit code" {
  // wasm trap vs native abort with different rc is not a miscompile.
  assert_true(@oracle.outcomes_agree("SIG", -11, "", "SIG", -6, ""))
  assert_true(@oracle.outcomes_agree("ICE", 199, "", "ICE", 2, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "OOM", 199, ""))
}
