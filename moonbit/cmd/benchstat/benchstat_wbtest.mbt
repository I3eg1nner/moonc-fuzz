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
    "{\"elapsed_ms\":0,\"coverage_adds\":0,\"new_edges\":0}",
    "{\"elapsed_ms\":60000,\"coverage_adds\":3,\"new_edges\":1}",
    "{\"elapsed_ms\":120000,\"coverage_adds\":5,\"new_edges\":4}",
  ]
  ignore(@stager.write_text(path, lines.join("\n") + "\n"))
  let (w, fields, time) = window_deltas(path)
  assert_true(fields)
  assert_true(time)
  assert_eq(w.length(), 2)
  assert_eq(w[0], 4L)
  assert_eq(w[1], 5L)
  ignore(@stager.rm_rf(path))
}

///|
test "missing elapsed_ms makes window metrics invalid, not zero" {
  let path = "/tmp/benchstat_no_time.jsonl"
  ignore(
    @stager.write_text(
      path,
      "{\"coverage_adds\":1,\"new_edges\":2}\n{\"coverage_adds\":3,\"new_edges\":4}\n",
    ),
  )
  let (w, fields, time) = window_deltas(path)
  assert_true(fields)
  assert_false(time)
  assert_eq(w.length(), 0)
  ignore(@stager.rm_rf(path))
}

///|
test "saturated metrics are detected from elapsed time" {
  let path = "/tmp/benchstat_sat.jsonl"
  let lines : Array[String] = []
  let mut i = 0
  while i < 10 {
    let adds = if i < 3 { i * 10 } else { 20 }
    let ms = i * 60000
    lines.push(
      "{\"elapsed_ms\":" + ms.to_string() + ",\"coverage_adds\":" +
      adds.to_string() + ",\"new_edges\":0}",
    )
    i += 1
  }
  ignore(@stager.write_text(path, lines.join("\n") + "\n"))
  let (adds_sat, _, has) = saturation_ms(path)
  assert_true(has)
  // Plateau reached at sample 2 (120 s), long before the 540 s end.
  assert_eq(adds_sat, 120000L)
  ignore(@stager.rm_rf(path))
}
