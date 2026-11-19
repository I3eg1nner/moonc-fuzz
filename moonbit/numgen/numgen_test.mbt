///|
/// The generator is only trustworthy if its programs are well formed and the
/// differential can tell cases apart, so these are the invariants a broken
/// template would break.

///|
fn braces_balanced(s : String) -> Bool {
  let mut d = 0
  for c in s {
    if c == '{' {
      d += 1
    } else if c == '}' {
      d -= 1
      if d < 0 {
        return false
      }
    }
  }
  d == 0
}

///|
test "cases: unique ids, every program has a main, braces balance" {
  let cs = cases()
  assert_true(cs.length() >= 20)
  let seen : Map[String, Unit] = Map([])
  for c in cs {
    assert_false(seen.contains(c.id))
    seen.set(c.id, ())
    assert_true(c.src.contains("fn main"))
    assert_true(braces_balanced(c.src))
    assert_true(c.id.char_length() > 3)
    assert_true(c.family != "")
  }
}

///|
test "cases: every program defines the helpers it calls" {
  for c in cases() {
    if c.src.contains("b(") {
      assert_true(c.src.contains("fn b(x : Bool)"))
    }
    if c.src.contains("u(") {
      assert_true(c.src.contains("fn u(x : UInt64)"))
    }
  }
}

///|
test "select: family filter is exact and empty means all" {
  assert_eq(select("").length(), cases().length())
  let f64 = select("f64")
  assert_true(f64.length() >= 5)
  for c in f64 {
    assert_eq(c.family, "f64")
  }
  assert_eq(select("nope").length(), 0)
}

///|
test "nan case: prints folded and runtime NaN separately" {
  let mut found = false
  for c in cases() {
    if c.id == "nan-array-bits" {
      found = true
      assert_true(c.src.contains("folded_div00"))
      assert_true(c.src.contains("runtime_div00"))
      // The runtime one must defeat constant folding, or the case would only
      // test the folder.
      assert_true(c.src.contains("d(0.0) / d(0.0)"))
    }
  }
  assert_true(found)
}

///|
test "grid cases: iterate arrays rather than repeating literals" {
  for c in cases() {
    if c.id == "f64-opgrid" {
      assert_true(c.src.contains("for i, x in xs"))
      assert_true(c.src.contains("for j, y in ys_values()"))
    }
    if c.id == "int-opgrid" {
      assert_true(c.src.contains("for a, x in xs"))
      assert_true(c.src.contains("for b, y in ys_values()"))
    }
    if c.id == "str-rep" {
      assert_true(c.src.contains("for i, x in ss"))
      assert_true(c.src.contains("for j, y in ss"))
    }
  }
}
