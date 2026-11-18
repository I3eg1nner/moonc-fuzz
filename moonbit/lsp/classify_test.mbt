///|
test "classify maps synthetic outcomes" {
  assert_eq(classify(Response(true)), Ok)
  assert_eq(classify(Response(false)), ErrorResponse)
  assert_eq(classify(TimeoutAlive), Hang)
  assert_eq(classify(TimeoutDead(-11)), Crash)
  assert_eq(classify(TimeoutDead(139)), Crash)
  assert_eq(classify(Exited(0)), Ok)
  assert_eq(classify(Exited(3)), Crash)
}

///|
test "classify_stage separates initialize hangs" {
  assert_eq(classify_stage(TimeoutAlive, true), InitHang)
  assert_eq(classify_stage(TimeoutAlive, false), Hang)
  assert_eq(classify_stage(Response(false), true), ErrorResponse)
}

///|
test "signatures are normalized" {
  assert_eq(
    signature(Hang, "moonbit-lsp/format-nth", 0),
    "hang:moonbit-lsp/format-nth",
  )
  assert_eq(signature(FlakyHang, "shutdown", 0), "hang:shutdown")
  assert_eq(signature(Crash, "textDocument/hover", -11), "crash:signal:11")
  assert_eq(signature(Crash, "textDocument/hover", 139), "crash:exit:139")
  assert_eq(signature(Ok, "initialize", 0), "")
}

///|
test "confirm applies the 3/3 rule" {
  assert_eq(confirm(Hang, 3, 3), Hang)
  assert_eq(confirm(Hang, 3, 2), FlakyHang)
  assert_eq(confirm(Hang, 1, 1), FlakyHang)
  assert_eq(confirm(Crash, 3, 3), Crash)
  assert_eq(confirm(Crash, 3, 1), FlakyCrash)
  assert_eq(confirm(Ok, 1, 1), Ok)
}
