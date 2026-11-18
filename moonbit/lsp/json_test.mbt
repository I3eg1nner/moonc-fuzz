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
