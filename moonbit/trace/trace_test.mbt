///|
test "parse_hex_u64 accepts lower/upper hex and rejects junk" {
  assert_eq(@trace.parse_hex_u64("0"), Some(0UL))
  assert_eq(@trace.parse_hex_u64("1aF"), Some(431UL))
  assert_eq(@trace.parse_hex_u64(""), None)
  assert_eq(@trace.parse_hex_u64("12g"), None)
}

///|
test "SymTab filters undefined symbols and maps nearest preceding" {
  let tab = @trace.SymTab::parse(
    "0000000000000010 T a\n0000000000000020 t b\n0000000000000030 W c\n0000000000000040 U d\n",
  )
  assert_eq(tab.len(), 3)
  assert_eq(tab.text_range(), (16UL, 48UL))
  assert_eq(tab.func_of(16UL), Some("a"))
  assert_eq(tab.func_of(31UL), Some("a"))
  assert_eq(tab.func_of(32UL), Some("b"))
  assert_eq(tab.func_of(48UL), Some("c"))
  assert_eq(tab.func_of(15UL), None)
  assert_eq(tab.func_of(49UL), None)
}

///|
test "short_name mirrors the Python helper" {
  assert_eq(
    @trace.short_name("camlMoonc__Lex_literal__foo_123"),
    "Lex_literal__foo_123",
  )
  assert_eq(
    @trace.short_name("camlStdlib__array__length_1"),
    "Stdlib.array__length_1",
  )
  assert_eq(@trace.short_name("main"), "main")
}

///|
test "parse_trace_pc handles both QEMU address spaces" {
  let high = "Trace 0: 0x7ced4c000100 [0000000000000000/0000004000821290/0x40c0b3] "
  let low = "Trace 0: 0x7ced4c000240 [0000000000000000/000000000060fce0/0x40c0b3] "
  assert_eq(@trace.parse_trace_pc(high), Some(0x4000821290UL))
  assert_eq(@trace.parse_trace_pc(low), Some(0x60fce0UL))
  assert_eq(@trace.parse_trace_pc("no brackets here"), None)
  assert_eq(@trace.parse_trace_pc("[1/zz/3]"), None)
}

///|
test "summarize_trace dedups, sorts, and counts mapped Tbs" {
  let tab = @trace.SymTab::parse(
    "0000000000000010 T a\n0000000000000020 t b\n0000000000000030 W c\n",
  )
  let trace = "[0/0000000000000010/0]\n[0/0000000000000018/0]\n" +
    "[0/0000000000000020/0]\n[0/0000000000000099/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.funcs, ["a", "b"])
  assert_eq(s.total_tb, 4)
  assert_eq(s.mapped_tb, 3)
}

///|
test "json_string_array escapes quotes and backslashes" {
  assert_eq(@trace.json_string_array([]), "[]")
  assert_eq(
    @trace.json_string_array(["a", "b\"c", "d\\e", "f\ng"]),
    "[\"a\",\"b\\\"c\",\"d\\\\e\",\"f\\ng\"]",
  )
}
