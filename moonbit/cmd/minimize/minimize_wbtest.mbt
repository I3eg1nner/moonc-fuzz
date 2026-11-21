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

///|
test "publishing requires a successful write" {
  let file = "/tmp/min_publish_ok.mbt"
  ignore(@fs.remove_file(file) catch { _ => () })
  assert_eq(publish_reduction(file, true, "fn f() {}\n"), file)
  assert_eq(@stager.read_text(file), "fn f() {}\n")
  // A directory path cannot be written as a file: publishing must fail closed.
  let dir = "/tmp/min_publish_dir"
  ignore(@stager.rm_rf(dir))
  ignore(@fs.create_dir(dir) catch { _ => () })
  assert_eq(publish_reduction(dir, true, "x"), "")
  assert_eq(publish_reduction("/tmp/min_publish_unverified.mbt", false, "x"), "")
  @stager.rm_rf(dir)
}
