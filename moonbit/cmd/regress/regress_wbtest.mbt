///|
test "p1_source emits one interpolation segment per index" {
  assert_eq(p1_source(2), "fn f() -> String { \"\\{0}\\{1}\" }\n")
  assert_eq(p1_source(0), "fn f() -> String { \"\" }\n")
}

///|
test "basename keeps the last path component" {
  assert_eq(basename("/a/b/c.mbt"), "c.mbt")
  assert_eq(basename("c.mbt"), "c.mbt")
  assert_eq(basename("/a/b/"), "")
}
