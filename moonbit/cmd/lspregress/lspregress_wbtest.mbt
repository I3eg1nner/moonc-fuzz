///|
/// Pure tests for the inverted-oracle matcher and the path helpers.
///
/// No server is started here: every case feeds a synthetic `Wire` to
/// `evaluate`, so the tests stay deterministic and never hang.
fn mk_wire(
  ids : Array[Int32],
  bodies : Array[String],
  alive : Bool,
  timed_out : Bool,
  eof : Bool,
  bad_header : String,
) -> Wire {
  { ids, bodies, alive, timed_out, eof, bad_header, }
}

///|
test "hang matcher: silence+alive passes, any response fails" {
  let quiet = mk_wire([], [], true, true, false, "")
  let v = evaluate(Hang, quiet)
  assert_true(v.ok)
  assert_eq(v.observed, "HANG")

  let answered = mk_wire(
    [2],
    ["{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}"],
    true,
    false,
    false,
    "",
  )
  let v2 = evaluate(Hang, answered)
  assert_false(v2.ok)
  assert_eq(v2.observed, "OK")

  let error_answered = mk_wire(
    [2],
    [
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"x\"}}",
    ],
    true,
    false,
    false,
    "",
  )
  let v3 = evaluate(Hang, error_answered)
  assert_false(v3.ok)
  assert_eq(v3.observed, "ERROR -32602")

  let dead = mk_wire([], [], false, false, true, "")
  let v4 = evaluate(Hang, dead)
  assert_false(v4.ok)
  assert_eq(v4.observed, "EXITED")

  let zombie = mk_wire([], [], false, true, false, "")
  let v5 = evaluate(Hang, zombie)
  assert_false(v5.ok)
  assert_eq(v5.observed, "DEAD")
}

///|
test "response matcher: needle, missing id, wrong body" {
  let rows : Array[(Expected, Wire, Bool)] = [
    (
      ResponseContains(2, "newText"),
      mk_wire(
        [2],
        [
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"newText\":\"fn f() {}\"}}",
        ],
        true,
        false,
        false,
        "",
      ),
      true,
    ),
    // Missing id is distinct from a body that simply lacks the needle.
    (
      ResponseContains(3, "newText"),
      mk_wire(
        [2],
        [
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"newText\":\"fn f() {}\"}}",
        ],
        true,
        false,
        false,
        "",
      ),
      false,
    ),
    (
      ResponseContains(2, "newText"),
      mk_wire(
        [2],
        ["{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}"],
        true,
        false,
        false,
        "",
      ),
      false,
    ),
    // An error body is not a control response even if it mentions the needle.
    (
      ResponseContains(2, "newText"),
      mk_wire(
        [2],
        [
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32601,\"message\":\"newText\"}}",
        ],
        true,
        false,
        false,
        "",
      ),
      false,
    ),
  ]
  for row in rows {
    let (expect, wire, want) = row
    assert_eq(evaluate(expect, wire).ok, want)
  }
  let missing = evaluate(
    ResponseContains(3, "newText"),
    mk_wire([2], ["{\"id\":2,\"result\":null}"], true, false, false, ""),
  )
  assert_true(missing.observed.contains("MISSING_ID"))
  assert_true(missing.detail.contains("[2]"))
}

///|
test "error-code matcher and control mismatch" {
  let ok_error = mk_wire(
    [2],
    [
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"bad params\"}}",
    ],
    true,
    false,
    false,
    "",
  )
  assert_true(evaluate(ErrorCode(2, -32602), ok_error).ok)
  assert_false(evaluate(ErrorCode(2, -32601), ok_error).ok)

  let result_instead = mk_wire(
    [2],
    ["{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}"],
    true,
    false,
    false,
    "",
  )
  let v = evaluate(ErrorCode(2, -32602), result_instead)
  assert_false(v.ok)
  assert_eq(v.observed, "OK")

  // F12 control: id 2 answered but id 3 was swallowed by the wedge.
  let half = mk_wire([2], ["{\"id\":2,\"result\":null}"], true, true, false, "")
  let c = evaluate(AllAnswered([2, 3]), half)
  assert_false(c.ok)
  assert_eq(c.observed, "MISSING_IDS [3]")
  let both = mk_wire(
    [2, 3],
    ["{\"id\":2,\"result\":null}", "{\"id\":3,\"result\":null}"],
    true,
    false,
    false,
    "",
  )
  assert_true(evaluate(AllAnswered([2, 3]), both).ok)
  let both_errors = mk_wire(
    [2, 3],
    [
      "{\"id\":2,\"error\":{\"code\":-32601,\"message\":\"x\"}}", "{\"id\":3,\"error\":{\"code\":-32601,\"message\":\"x\"}}",
    ],
    true,
    false,
    false,
    "",
  )
  assert_false(evaluate(AllAnswered([2, 3]), both_errors).ok)
}

///|
test "missing binary is an operational error, not a pass" {
  let missing = check_server("/no/such/moon-lsp", fn(_) { false })
  match missing {
    None => assert_true(false)
    Some(msg) => {
      assert_true(msg.contains("moon-lsp not found"))
      assert_true(msg.contains("/no/such/moon-lsp"))
    }
  }
  assert_true(check_server("/bin/true", fn(_) { true }) is None)
}

///|
test "path helpers expand home and parse --only" {
  assert_eq(
    expand_home("~/.moon/bin/moon-lsp", "/home/u"),
    "/home/u/.moon/bin/moon-lsp",
  )
  assert_eq(expand_home("~", "/home/u"), "/home/u")
  assert_eq(expand_home("/opt/moon-lsp", "/home/u"), "/opt/moon-lsp")
  let only = parse_only(" F10-hang, , F12-control ,")
  assert_eq(only.length(), 2)
  assert_eq(only[0], "F10-hang")
  assert_eq(only[1], "F12-control")
}
