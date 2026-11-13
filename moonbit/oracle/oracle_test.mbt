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
