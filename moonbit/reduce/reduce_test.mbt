///|
/// Tests for the reducer.  The interesting properties are not "it got
/// smaller": any line-dropper does that.  They are that it never returns a
/// case that fails the predicate, never reorders lines, and stops when told.

///|
fn src_of(lines : Array[String]) -> String {
  let b = StringBuilder()
  for i, l in lines {
    if i > 0 {
      b.write_string("\n")
    }
    b.write_string(l)
  }
  b.to_string()
}

///|
fn is_subsequence(small : Array[String], big : Array[String]) -> Bool {
  let mut j = 0
  for line in big {
    if j < small.length() && small[j] == line {
      j += 1
    }
  }
  j == small.length()
}

///|
test "reduces to the single line the predicate needs" {
  let src = src_of([
    "// header comment", "", "fn helper() -> Int { 1 }", "", "fn boom() -> Int { 1 / 0 }",
    "", "fn main { println(boom()) }", "",
  ])
  let out = reduce_with(src, 2000, fn(t) { t.contains("boom") })
  // Either one-line form is a valid answer; the harness must not assume which.
  assert_eq(out.split("\n").count(), 1)
  assert_true(out.contains("boom"))
}

///|
test "keeps both lines when the predicate needs both" {
  let src = src_of(["alpha", "beta", "gamma", "delta", "epsilon"])
  let out = reduce_with(src, 2000, fn(t) {
    t.contains("beta") && t.contains("delta")
  })
  assert_eq(out, "beta\ndelta")
}

///|
test "removes a whole unrelated block before touching lines" {
  let src = src_of([
    "fn unrelated() -> Unit {", "  let a = 1", "  let b = 2", "  println(a + b)",
    "}", "", "fn boom() -> Unit {", "  println(1)", "}",
  ])
  let out = reduce_with(src, 2000, fn(t) { t.contains("boom") })
  assert_false(out.contains("unrelated"))
  assert_true(out.contains("fn boom"))
}

///|
test "result is always a subsequence of the input" {
  let src = src_of(["a", "b", "c", "d", "e", "f", "g", "h"])
  let out = reduce_with(src, 2000, fn(t) { t.contains("c") && t.contains("f") })
  let small : Array[String] = []
  for l in out.split("\n") {
    small.push(l.to_owned())
  }
  let big : Array[String] = []
  for l in src.split("\n") {
    big.push(l.to_owned())
  }
  assert_true(is_subsequence(small, big))
  assert_eq(out, "c\nf")
}

///|
test "respects a predicate that also caps the size" {
  let src = src_of(["x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8"])
  let out = reduce_with(src, 2000, fn(t) {
    t.contains("x4") && t.split("\n").count() <= 4
  })
  assert_true(out.contains("x4"))
  assert_true(out.split("\n").count() <= 4)
}

///|
test "fuel bounds the number of runs" {
  let src = src_of(["a", "b", "c", "d", "e", "f"])
  let r = start(src, 1)
  let mut n = 0
  let mut go = true
  while go {
    match next_text(r) {
      Some(_) => {
        n += 1
        verdict(r, false)
      }
      None => go = false
    }
  }
  assert_eq(n, 1)
  assert_true(was_exhausted(r))
  assert_eq(test_calls(r), 1)
}

///|
test "candidate is idempotent until a verdict arrives" {
  let src = src_of(["a", "b", "c", "d"])
  let r = start(src, 100)
  let first = next_text(r)
  let again = next_text(r)
  assert_true(first == again)
  assert_eq(test_calls(r), 1)
  verdict(r, false)
  assert_true(next_text(r) != first)
}

///|
test "already-minimal input costs no runs" {
  let r = start("only line", 100)
  assert_true(next_text(r) is None)
  assert_eq(test_calls(r), 0)
  assert_eq(result(r), "only line")
}

///|
test "trailing newlines do not become removable empty lines" {
  let out = reduce_with("a\nb\n\n\n", 100, fn(t) { t.contains("b") })
  assert_eq(out, "b")
}

///|
test "top_blocks: only top-level spans, largest first" {
  let lines : Array[String] = [
    "fn a() {", "  if x {", "    y()", "  }", "}", "fn b() { z() }",
  ]
  let spans = top_blocks(lines)
  assert_eq(spans.length(), 2)
  assert_eq(spans[0], (0, 5))
  assert_eq(spans[1], (5, 6))
}

///|
test "top_blocks: unbalanced braces do not panic or invent spans" {
  let lines : Array[String] = ["fn a() {", "  let s = \"}\"", "  {"]
  // The string literal brace closes early; the engine will test whatever it
  // derived and the predicate decides.  The only requirement is no crash.
  let spans = top_blocks(lines)
  assert_true(spans.length() <= 2)
}
