///|
test "first write into a nested witness directory is durable" {
  let base = "/tmp/sem3_durable_test"
  @stager.rm_rf(base)
  ensure_dir(base + "/a/b/c")
  assert_true(@fs.path_exists(base + "/a/b/c"))
  assert_true(@stager.write_text(base + "/a/b/c/main.mbt", "fn main {}"))
  assert_true(@fs.path_exists(base + "/a/b/c/main.mbt"))
  @stager.rm_rf(base)
}
