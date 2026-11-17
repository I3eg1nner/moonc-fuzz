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
  assert_eq(s.unique_pc, 4)
  assert_eq(s.mapped_unique_pc, 3)
  assert_eq(s.edges, 3)
  assert_eq(s.mapped_edges, 2)
  assert_eq(s.func_depth.length(), 2)
  assert_eq(s.func_depth[0].name, "a")
  assert_eq(s.func_depth[0].blocks, 2)
  assert_eq(s.func_depth[0].edges, 1)
  assert_eq(s.func_depth[1].name, "b")
  assert_eq(s.func_depth[1].blocks, 1)
  assert_eq(s.func_depth[1].edges, 0)
}

///|
test "repeated PCs dedup to one block" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n0000000000000020 T b\n")
  // PC 0x10 executes twice but is one distinct block for function a.
  let trace = "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.total_tb, 3)
  assert_eq(s.unique_pc, 2)
  assert_eq(s.mapped_unique_pc, 2)
  assert_eq(s.func_depth[0].name, "a")
  assert_eq(s.func_depth[0].blocks, 1)
  assert_eq(s.func_depth[1].name, "b")
  assert_eq(s.func_depth[1].blocks, 1)
}

///|
test "repeated same pair dedups to one edge" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n0000000000000020 T b\n")
  // Five transitions, but only two distinct pairs: a->b and b->a.
  let trace = "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000020/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.total_tb, 6)
  assert_eq(s.unique_pc, 2)
  assert_eq(s.edges, 2)
  assert_eq(s.mapped_edges, 2)
  // Repeating one self-pair three times is still one distinct edge.
  let same = "[0/0000000000000010/0]\n[0/0000000000000010/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000010/0]\n"
  let t = @trace.summarize_trace(same, tab)
  assert_eq(t.total_tb, 4)
  assert_eq(t.unique_pc, 1)
  assert_eq(t.edges, 1)
  assert_eq(t.mapped_edges, 1)
  assert_eq(t.func_depth[0].blocks, 1)
  assert_eq(t.func_depth[0].edges, 1)
}

///|
test "unmapped PCs count in total and unique but not mapped" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n")
  let trace = "[0/0000000000000099/0]\n[0/0000000000000099/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000099/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.total_tb, 4)
  assert_eq(s.mapped_tb, 1)
  assert_eq(s.unique_pc, 2)
  assert_eq(s.mapped_unique_pc, 1)
  assert_eq(s.funcs, ["a"])
  // (0x99,0x99), (0x99,0x10), (0x10,0x99) are all distinct TB transitions,
  // but none has both endpoints mapped.
  assert_eq(s.edges, 3)
  assert_eq(s.mapped_edges, 0)
  assert_eq(s.func_depth[0].blocks, 1)
  assert_eq(s.func_depth[0].edges, 0)
}

///|
test "cross-function edges are global but not per-function intra edges" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n0000000000000020 T b\n")
  let cross = @trace.summarize_trace(
    "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000020/0]\n",
    tab,
  )
  assert_eq(cross.edges, 2)
  assert_eq(cross.mapped_edges, 2)
  assert_eq(cross.func_depth[0].edges, 0)
  assert_eq(cross.func_depth[1].edges, 0)
  // 0x18 maps to a, so a->a is intra; a->b and b->a are not.
  let mixed = @trace.summarize_trace(
    "[0/0000000000000010/0]\n[0/0000000000000018/0]\n" +
    "[0/0000000000000020/0]\n",
    tab,
  )
  assert_eq(mixed.edges, 2)
  assert_eq(mixed.mapped_edges, 2)
  assert_eq(mixed.func_depth[0].name, "a")
  assert_eq(mixed.func_depth[0].blocks, 2)
  assert_eq(mixed.func_depth[0].edges, 1)
  assert_eq(mixed.func_depth[1].name, "b")
  assert_eq(mixed.func_depth[1].blocks, 1)
  assert_eq(mixed.func_depth[1].edges, 0)
}

///|
test "malformed lines are ignored and do not break adjacency" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n0000000000000020 T b\n")
  let trace = "garbage\nTrace 0: no brackets here\n[1/zz/3]\n" +
    "[0/0000000000000010/0]\n\n[0/0000000000000020/0]\nnot a trace\n" +
    "[0/0000000000000018/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.total_tb, 3)
  assert_eq(s.unique_pc, 3)
  assert_eq(s.funcs, ["a", "b"])
  // The malformed lines between parsed entries are invisible: the sequence is
  // 0x10 -> 0x20 -> 0x18, so both transitions are retained.
  assert_eq(s.edges, 2)
  assert_eq(s.mapped_edges, 2)
  assert_eq(s.func_depth[0].name, "a")
  assert_eq(s.func_depth[0].blocks, 2)
  assert_eq(s.func_depth[0].edges, 0)
  assert_eq(s.func_depth[1].name, "b")
  assert_eq(s.func_depth[1].blocks, 1)
  assert_eq(s.func_depth[1].edges, 0)
}

///|
test "per-function depth is sorted deterministically by name" {
  // nm output intentionally out of address order; symbol parse sorts by addr.
  // Both names have the same length so MoonBit's shortlex String order is also
  // the obvious alphabetical order (existing `funcs.sort()` semantics).
  let tab = @trace.SymTab::parse(
    "0000000000000020 T bravo\n0000000000000010 T alpha\n",
  )
  // Trace order is bravo, alpha, bravo; the reported order must still be sorted.
  let trace = "[0/0000000000000020/0]\n[0/0000000000000010/0]\n" +
    "[0/0000000000000020/0]\n"
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.funcs, ["alpha", "bravo"])
  assert_eq(s.func_depth[0].name, "alpha")
  assert_eq(s.func_depth[0].blocks, 1)
  assert_eq(s.func_depth[0].edges, 0)
  assert_eq(s.func_depth[1].name, "bravo")
  assert_eq(s.func_depth[1].blocks, 1)
  assert_eq(s.func_depth[1].edges, 0)
  // A second run over the same input renders the same depth array.
  let again = @trace.summarize_trace(trace, tab)
  assert_eq(
    @trace.json_func_depth_array(s.func_depth),
    @trace.json_func_depth_array(again.func_depth),
  )
}

///|
test "json_string_array escapes quotes and backslashes" {
  assert_eq(@trace.json_string_array([]), "[]")
  assert_eq(
    @trace.json_string_array(["a", "b\"c", "d\\e", "f\ng"]),
    "[\"a\",\"b\\\"c\",\"d\\\\e\",\"f\\ng\"]",
  )
}

///|
test "range_of covers each symbol and ends the last at +4096" {
  let tab = @trace.SymTab::parse(
    "0000000000000010 T a\n0000000000000020 t b\n0000000000000030 W c\n",
  )
  assert_eq(tab.range_of("b"), Some((32UL, 48UL)))
  assert_eq(tab.range_of("c"), Some((48UL, 4144UL)))
  assert_eq(tab.range_of("missing"), None)
}

///|
test "empty symbol table maps nothing" {
  let tab = @trace.SymTab::parse("")
  assert_eq(tab.len(), 0)
  assert_eq(tab.text_range(), (0UL, 0UL))
  assert_eq(tab.func_of(0UL), None)
  assert_eq(tab.range_of("a"), None)
}

///|
test "edge_keys are exact, deduped, sorted, and mapped-only" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n0000000000000020 T b\n")
  // Parsed pairs: (10,20) (20,10) (10,10) then (10,99) (99,20).
  // The pair with an unmapped endpoint is excluded; repeated pairs collapse.
  let trace = "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000010/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000020/0]\n" +
    "[0/0000000000000010/0]\n[0/0000000000000099/0]\n" +
    "[0/0000000000000020/0]\n"
  // Exact keys keep both endpoints in decimal, so the result is injective.
  assert_eq(@trace.edge_keys(trace, tab), ["16,16", "16,32", "32,16"])
  let s = @trace.summarize_trace(trace, tab)
  assert_eq(s.mapped_edges, 3)
  // The key set and the counter are the same set by construction.
  assert_eq(@trace.edge_keys(trace, tab).length(), s.mapped_edges)
}

///|
test "edge_keys ignores all-unmapped transitions and the empty trace" {
  let tab = @trace.SymTab::parse("0000000000000010 T a\n")
  assert_eq(@trace.edge_keys("", tab), [])
  let trace = "[0/0000000000000010/0]\n[0/0000000000000099/0]\n" +
    "[0/0000000000000099/0]\n"
  // (10,99) and (99,99) each have an unmapped endpoint.
  assert_eq(@trace.edge_keys(trace, tab), [])
  assert_eq(@trace.summarize_trace(trace, tab).edges, 2)
  assert_eq(@trace.summarize_trace(trace, tab).mapped_edges, 0)
}
