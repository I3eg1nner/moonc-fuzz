///|
test "capsule summary stays valid JSON when triage is appended" {
  let plain = capsule_summary(3, 1, 2, 0, 0, 0, 0, 10UL, 2, "")
  assert_true(plain.has_prefix("{"))
  assert_true(plain.has_suffix("}"))
  let with_triage = capsule_summary(
    3, 1, 2, 0, 0, 0, 0, 10UL, 2, "{\"triaged\":2,\"known\":1}",
  )
  // Exactly one closing brace at the end, and the triage object is a field.
  assert_true(with_triage.contains(",\"triage\":{\"triaged\":2"))
  assert_true(with_triage.has_suffix("}"))
  let mut closes = 0
  for c in with_triage {
    if c == '}' {
      closes += 1
    }
  }
  assert_eq(closes, 2)
}
