///|
/// The publication rule is the whole point of the tool: a reduction that does
/// not re-verify must not appear at `--out`, no matter what the caller checks.

///|
test "unverified reduction has no publish path" {
  assert_eq(publish_path("/tmp/reduced.mbt", true), "/tmp/reduced.mbt")
  assert_eq(publish_path("/tmp/reduced.mbt", false), "")
}

///|
test "empty out stays empty either way" {
  assert_eq(publish_path("", true), "")
  assert_eq(publish_path("", false), "")
}
