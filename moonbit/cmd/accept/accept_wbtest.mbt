///|
test "count_lines ignores blank and whitespace-only lines" {
  assert_eq(count_lines("a\nb\n"), 2)
  assert_eq(count_lines("a\n\n   \nb\n"), 2)
  assert_eq(count_lines(""), 0)
}

///|
test "basename keeps the last path component" {
  assert_eq(basename("/a/b/c.json"), "c.json")
  assert_eq(basename("c.json"), "c.json")
}
