///|
test "json_quote escapes controls but keeps unicode" {
  assert_eq(json_quote("a\"b\\c\n\t"), "\"a\\\"b\\\\c\\n\\t\"")
  assert_eq(json_quote("é😀"), "\"é😀\"")
}

///|
test "inspect_response finds id and result" {
  let info = inspect_response("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":null}")
  assert_eq(info.id, Some(7))
  assert_false(info.has_error)
  assert_true(info.has_result)
}

///|
test "inspect_response finds an error and negative id" {
  let info = inspect_response(
    "{\"id\":-2,\"error\":{\"code\":-32603,\"message\":\"Request not supported yet!\"}}",
  )
  assert_eq(info.id, Some(-2))
  assert_true(info.has_error)
  assert_false(info.has_result)
}

///|
test "inspect_response ignores nested error strings and notifications" {
  let info = inspect_response(
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"text\":\"\\\"error\\\": 1\"}}",
  )
  assert_eq(info.id, None)
  assert_false(info.has_error)
}

///|
test "inspect_response survives ids with surrounding whitespace" {
  let info = inspect_response("{ \"id\" : 12 , \"result\" : [] }")
  assert_eq(info.id, Some(12))
  assert_true(info.has_result)
}

///|
test "inspect_response extracts the error code" {
  let info = inspect_response(
    "{\"id\":2,\"error\":{\"code\":-32602,\"message\":\"bad params\"}}",
  )
  assert_eq(info.error_code, Some(-32602))
  let ok = inspect_response("{\"id\":2,\"result\":null}")
  assert_eq(ok.error_code, None)
}

///|
test "response detection is independent of id type" {
  let int_result = inspect_response("{\"id\":2,\"result\":null}")
  assert_true(int_result.is_response())
  assert_eq(int_result.id_kind.text(), "2")

  let null_error = inspect_response(
    "{\"id\":null,\"error\":{\"code\":-32600,\"message\":\"invalid request\"}}",
  )
  assert_true(null_error.is_response())
  assert_true(null_error.has_id())
  assert_eq(null_error.id_kind.text(), "null")
  assert_eq(null_error.error_code, Some(-32600))

  let string_error = inspect_response(
    "{\"id\":\"2\",\"error\":{\"code\":-32600,\"message\":\"invalid request\"}}",
  )
  assert_true(string_error.is_response())
  assert_true(string_error.has_id())
  assert_eq(string_error.id, None)
  assert_eq(string_error.id_kind.text(), "\"2\"")

  // A notification has no id member at all, even though it may carry params.
  let notification = inspect_response("{\"method\":\"x\",\"params\":{}}")
  assert_false(notification.is_response())
  assert_false(notification.has_id())
  assert_eq(notification.id_kind.text(), "missing")

  // Malformed JSON must not crash; a truncated frame with only an id is not
  // a response yet, and garbage is not a response at all.
  let truncated = inspect_response("{\"id\":2")
  assert_true(truncated.has_id())
  assert_false(truncated.is_response())
  let not_json = inspect_response("not json at all")
  assert_false(not_json.is_response())
  assert_eq(not_json.id_kind.text(), "missing")
}
