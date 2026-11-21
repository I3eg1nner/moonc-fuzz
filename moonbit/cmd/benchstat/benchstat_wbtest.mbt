///|
test "GNU time decimals parse without a /10 loss" {
  assert_eq(parse_x100("814.39"), 81439L)
  assert_eq(parse_x100("0.5"), 50L)
  assert_eq(parse_x100("2"), 200L)
  assert_eq(parse_x100("0.00"), 0L)
  assert_eq(parse_x100("garbage"), 0L)
  assert_eq(parse_x100("1.234"), 123L)
}

///|
test "window deltas read the coverage fields monitor emits" {
  let path = "/tmp/benchstat_window_test.jsonl"
  let lines = [
    "{\"coverage_adds\":0,\"new_edges\":0}",
    "{\"coverage_adds\":3,\"new_edges\":1}",
    "{\"coverage_adds\":5,\"new_edges\":4}",
  ]
  ignore(@stager.write_text(path, lines.join("\n") + "\n"))
  let w = window_deltas(path)
  // one window: (3+1-0) + (5+4-3-1) = 9
  assert_eq(w.length(), 1)
  assert_eq(w[0], 9L)
  ignore(@stager.rm_rf(path))
}
