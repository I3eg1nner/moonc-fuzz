///|
/// Empty corpus: Python's `aggregate([])` returns an empty union and two empty
/// lists; `minimize_corpus` selects nothing.
test "empty input" {
  let (union, per_new, cumulative) = @cov.aggregate([])
  @test.assert_eq(union, [])
  @test.assert_eq(per_new, [])
  @test.assert_eq(cumulative, [])
  @test.assert_eq(@cov.minimize_sets([]), [])
  @test.assert_eq(
    @cov.union_stats([]),
    "{\"func_count\":0,\"per_input_new\":[],\"cumulative\":[]}",
  )
}

///|
/// Python wraps every per-input list in `set(r)`, so duplicates are counted
/// once both inside an input and across inputs.
test "duplicate function names" {
  let parsed = @cov.parse_json("{\"funcs\":[\"a\",\"b\",\"a\",\"b\"]}")
  @test.assert_eq(parsed.len(), 2)
  @test.assert_eq(parsed.sorted(), ["a", "b"])
  let (union, per_new, cumulative) = @cov.aggregate([
    ["a", "a", "b"],
    ["a", "b"],
  ])
  @test.assert_eq(union, ["a", "b"])
  @test.assert_eq(per_new, [2, 0])
  @test.assert_eq(cumulative, [2, 2])
}

///|
/// Basic set algebra, including duplicates on the left/right operands.
test "union intersection difference" {
  let left = @cov.parse_json("{\"funcs\":[\"b\",\"a\",\"a\"]}")
  let right = @cov.parse_json("{\"funcs\":[\"c\",\"b\",\"c\"]}")
  @test.assert_eq(left.union(right).sorted(), ["a", "b", "c"])
  @test.assert_eq(left.intersection(right).sorted(), ["b"])
  @test.assert_eq(left.difference(right).sorted(), ["a"])
  @test.assert_eq(right.difference(left).sorted(), ["c"])
  @test.assert_eq(left.union(right).len(), 3)
  @test.assert_eq(left.intersection(right).len(), 1)
  @test.assert_eq(left.difference(right).len(), 1)
}

///|
/// `per_input_new` follows Python's iteration order: first-seen names per
/// input, and `cumulative` is the running union size (not a running sum).
test "aggregate order" {
  let (union, per_new, cumulative) = @cov.aggregate([
    ["b", "a"],
    ["c", "a"],
    ["d"],
    [],
  ])
  @test.assert_eq(union, ["a", "b", "c", "d"])
  @test.assert_eq(per_new, [2, 1, 1, 0])
  @test.assert_eq(cumulative, [2, 3, 4, 4])
}

///|
/// `union_stats` is the compact JSON boundary used by the MoonBit report; the
/// three keys and their aggregation order are fixed.
test "union stats shape" {
  @test.assert_eq(
    @cov.union_stats([["b", "a"], ["c", "a"], ["d"], []]),
    "{\"func_count\":4,\"per_input_new\":[2,1,1,0],\"cumulative\":[2,3,4,4]}",
  )
}

///|
/// Greedy selection: largest marginal gain wins, strict `>` keeps the lowest
/// index on ties, chosen inputs are skipped, and selection stops at no gain.
test "greedy minimize tie-breaking" {
  // Round 1 is a tie between indices 1 and 2 after index 0 wins with gain 2.
  @test.assert_eq(@cov.minimize_sets([["a", "b"], ["c"], ["c"], ["d"]]), [
    0, 1, 3,
  ])
  // All gains tie at 1, so the lowest index is taken every round.
  @test.assert_eq(@cov.minimize_sets([["a"], ["b"], ["c"]]), [0, 1, 2])
  // Empty sets never make progress; a later input still covers the universe.
  @test.assert_eq(@cov.minimize_sets([[], ["a"], []]), [1])
  @test.assert_eq(@cov.minimize_sets([[], []]), [])
  // Duplicates inside an input must not inflate its gain.
  @test.assert_eq(@cov.minimize_sets([["a", "a"], ["b"]]), [0, 1])
}

///|
/// Parse a real-looking snapshot: the `{"funcs":[...]}` field is read while
/// `tool`, `corpus`, `n`, `per_input_new`, and `cumulative` are ignored.
test "json parse real snippet" {
  let text = "{\"tool\":\"qemu-exec-trace+nm\",\"corpus\":\"seeds_real\"," +
    "\"n\":624,\"funcs\":[\"Ppx_fold_blob\",\"_start\",\"Ppx_fold_blob\"]," +
    "\"per_input_new\":[861,1],\"cumulative\":[861,862],\"modules\":{\"Ppx\":3}}"
  let parsed = @cov.parse_json(text)
  @test.assert_eq(parsed.len(), 2)
  @test.assert_eq(parsed.sorted(), ["Ppx_fold_blob", "_start"])
  // A missing/null `funcs` mirrors Python's `d.get("funcs") or []`.
  @test.assert_eq(@cov.parse_json("{\"tool\":\"x\"}").len(), 0)
  @test.assert_eq(@cov.parse_json("{\"funcs\":null}").len(), 0)
}

///|
/// `to_json_string` emits the canonical sorted shape and `parse_json` accepts
/// it back with identical set contents.
test "json round trip" {
  let original = @cov.parse_json("{\"funcs\":[\"z\",\"a\",\"z\"],\"extra\":1}")
  let encoded = original.to_json_string()
  @test.assert_eq(encoded, "{\"funcs\":[\"a\",\"z\"]}")
  let decoded = @cov.parse_json(encoded)
  @test.assert_eq(decoded.sorted(), original.sorted())
  @test.assert_eq(decoded.len(), original.len())
}

///|
/// Fixed-width row: 34/5/7/6/7/9 columns, `-` placeholders for zero edges,
/// zero funcs and an empty `per_input_new`, and `.3f`/`.2f` formatting.
test "report row" {
  @test.assert_eq(
    @cov.report_row("snap", 10, 5, 3, [2, 0, 1]),
    "snap                                  10       5  0.000       3      0.30",
  )
  @test.assert_eq(
    @cov.report_row("snap", 10, 0, 0, []),
    "snap                                  10       -      -       -         -",
  )
  @test.assert_eq(
    @cov.report_row("snap", 10, 65536, 4, [10]),
    "snap                                  10   65536  1.000       4      1.00",
  )
  @test.assert_eq(
    @cov.report_row("a-very-long-snapshot-name-that-exceeds-34", 3, 100, 2, [
      1, 2,
    ]),
    "a-very-long-snapshot-name-that-exceeds-34     3     100  0.002       2      1.00",
  )
}

///|
/// The seven-column variant matches `cov.py report` byte-for-byte.
test "report row with tool" {
  @test.assert_eq(
    @cov.report_row_with_tool("snap", "qemu-exec-trace+nm", 10, 5, 3, [2, 0, 1]),
    "snap                               qemu-exec-trace+nm        10       5  0.000       3      0.30",
  )
  @test.assert_eq(
    @cov.report_header(),
    "snapshot                           tool                       n   edges   dens   funcs  new/exec",
  )
}
