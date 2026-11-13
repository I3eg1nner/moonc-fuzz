///|
test "render emits the documented JSON shape" {
  let nm = "0000000000000010 T a\n0000000000000020 T b\n"
  let trace = "[0/0000000000000018/0]\n[0/0000000000000020/0]\n[0/0000000000000099/0]\n"
  assert_eq(
    render(nm, trace),
    "{\"tool\":\"qemu-exec-trace+nm-moonbit\",\"text_lo\":16,\"text_hi\":32,\"symbols\":2,\"total_tb\":3,\"mapped_tb\":2,\"func_count\":2,\"funcs\":[\"a\",\"b\"]}",
  )
}

///|
test "render handles an empty symbol table" {
  assert_eq(
    render("", "[0/0000000000000010/0]\n"),
    "{\"tool\":\"qemu-exec-trace+nm-moonbit\",\"text_lo\":0,\"text_hi\":0,\"symbols\":0,\"total_tb\":1,\"mapped_tb\":0,\"func_count\":0,\"funcs\":[]}",
  )
}
