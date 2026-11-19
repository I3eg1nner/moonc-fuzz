///|
/// Tests for the script-mode variant generator.  The grid is only meaningful
/// if the renderer is correct, so the invariants asserted here are exactly the
/// ones a broken template would violate: duplicate ids, a missing `#valtype`
/// marker, unbalanced braces, or a "control" that is not actually a control.

///|
fn brace_delta(s : String) -> Int32 {
  let mut d = 0
  for c in s {
    if c == '{' {
      d += 1
    } else if c == '}' {
      d -= 1
    }
  }
  d
}

///|
test "cases: 36 unique ids, 18 valtype and 18 plain" {
  let cs = cases()
  assert_eq(cs.length(), 36)
  let ids : Map[String, Unit] = Map([])
  let mut vt = 0
  for c in cs {
    assert_false(ids.contains(c.id))
    ids.set(c.id, ())
    if c.valtype {
      vt += 1
    }
  }
  assert_eq(vt, 18)
}

///|
test "render: valtype marker appears exactly when requested" {
  for c in cases() {
    let src = render(c)
    assert_eq(src.contains("#valtype"), c.valtype)
    assert_eq(brace_delta(src), 0)
    assert_true(src.contains("fn main {"))
    assert_true(src.contains("println("))
  }
}

///|
test "render: the field container declares the wrapper struct" {
  for c in cases() {
    let src = render(c)
    if c.container is Container::CField {
      assert_true(src.contains("struct Wrapper"))
      assert_true(src.contains("items : Array[Entry]"))
    } else {
      assert_false(src.contains("struct Wrapper"))
    }
  }
}

///|
test "render: payload spelling reaches the source" {
  let i = Payload::PInt
  assert_eq(payload_type(i), "Int")
  assert_eq(payload_value(i), "0")
  for c in cases() {
    if c.payload is Payload::PArrayInt {
      assert_true(render(c).contains("Ref(Array[Int])"))
    }
    if c.payload is Payload::PString {
      assert_true(render(c).contains("Ref(String)"))
    }
  }
}

///|
test "boundary: 12 unique probes, four expected to fail" {
  let bs = boundary_cases()
  assert_eq(bs.length(), 12)
  let ids : Map[String, Unit] = Map([])
  let mut failing = 0
  for b in bs {
    assert_false(ids.contains(b.id))
    ids.set(b.id, ())
    if b.expect_defect {
      failing += 1
    }
    assert_eq(brace_delta(b.src), 0)
    assert_true(b.src.contains("fn main {"))
    assert_true(b.why.char_length() > 10)
  }
  assert_eq(failing, 4)
}

///|
test "boundary: the minimal witness is the shortest failing probe" {
  let mut min_len = 100000
  for b in boundary_cases() {
    if b.expect_defect && b.src.char_length() < min_len {
      min_len = b.src.char_length()
    }
  }
  // b04 is the minimal one; if a new probe is shorter the table should say so.
  for b in boundary_cases() {
    if b.expect_defect && b.id == "b04-int-plus-enum-int-payload" {
      assert_eq(b.src.char_length(), min_len)
    }
  }
}
