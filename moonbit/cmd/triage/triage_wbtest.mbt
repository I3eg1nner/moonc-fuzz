///|
/// Promotion rules.  The classifier is pure so the flaky branch can be tested
/// without a nondeterministic candidate.
test "triage classifier" {
  // 3/3, control silent, not known -> confirmed
  assert_eq(
    triage_status(true, false, 3, true, false, false, false),
    "confirmed",
  )
  // 2/3 -> flaky
  assert_eq(triage_status(true, false, 2, true, false, false, false), "flaky")
  // known witness wins over confirmed
  assert_eq(triage_status(true, false, 3, true, true, false, false), "known")
  // a control that also fails voids the case
  assert_eq(
    triage_status(true, false, 3, false, false, false, false),
    "inconclusive",
  )
  // minimise requested but not published -> flaky, never confirmed
  assert_eq(triage_status(true, false, 3, true, false, true, false), "flaky")
  assert_eq(triage_status(true, false, 3, true, false, true, true), "confirmed")
  // timeouts are not defect-class
  assert_eq(
    triage_status(false, true, 3, true, false, false, false),
    "timeout-only",
  )
  assert_eq(
    triage_status(false, false, 0, true, false, false, false),
    "inconclusive",
  )
}
