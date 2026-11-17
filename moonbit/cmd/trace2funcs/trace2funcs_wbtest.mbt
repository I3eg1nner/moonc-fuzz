///|
test "render emits the documented JSON shape" {
  let nm = "0000000000000010 T a\n0000000000000020 T b\n"
  let trace = "[0/0000000000000018/0]\n[0/0000000000000020/0]\n[0/0000000000000099/0]\n"
  assert_eq(
    render(nm, trace),
    "{\"tool\":\"qemu-exec-trace+nm-moonbit\",\"text_lo\":16,\"text_hi\":32,\"symbols\":2,\"total_tb\":3,\"mapped_tb\":2,\"func_count\":2,\"funcs\":[\"a\",\"b\"],\"unique_pc\":3,\"mapped_unique_pc\":2,\"edges\":2,\"mapped_edges\":1,\"func_depth\":[{\"func\":\"a\",\"blocks\":1,\"edges\":0},{\"func\":\"b\",\"blocks\":1,\"edges\":0}]}",
  )
}

///|
test "render handles an empty symbol table" {
  assert_eq(
    render("", "[0/0000000000000010/0]\n"),
    "{\"tool\":\"qemu-exec-trace+nm-moonbit\",\"text_lo\":0,\"text_hi\":0,\"symbols\":0,\"total_tb\":1,\"mapped_tb\":0,\"func_count\":0,\"funcs\":[],\"unique_pc\":1,\"mapped_unique_pc\":0,\"edges\":0,\"mapped_edges\":0,\"func_depth\":[]}",
  )
}
