///|
/// The sweep is only as good as its renderer: a case that fails to compile for
/// a syntax reason would be counted as a defect, so the templates are checked
/// structurally here.

///|
fn balanced(s : String) -> Bool {
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
fn count_occur(hay : String, needle : String) -> Int32 {
  let mut n = 0
  let mut rest = hay
  while rest.find(needle) is Some(i) {
    n += 1
    rest = rest[i + needle.length():].to_owned()
  }
  n
}

///|
test "cases: 36 unique ids, four shapes, one control each" {
  let cs = cases()
  assert_eq(cs.length(), 36)
  let seen : Map[String, Unit] = Map([])
  let mut plain = 0
  for c in cs {
    assert_false(seen.contains(c.id))
    seen.set(c.id, ())
    if !c.valtype {
      plain += 1
      assert_eq(c.fields, 2)
    }
  }
  assert_eq(plain, 4)
}

///|
test "lib: valtype marker appears exactly when requested" {
  for c in cases() {
    let src = lib_source(c)
    assert_eq(src.contains("#valtype"), c.valtype)
    assert_true(balanced(src))
    assert_true(src.contains("pub fn make() -> Array[E]"))
    assert_true(
      src.contains("let xs : Array[E] = []") ||
      src.contains("let row : Array[E] = []"),
    )
  }
}

///|
test "lib: field count is rendered exactly" {
  for c in cases() {
    let src = lib_source(c)
    if c.shape is Shape::Record ||
      c.shape is Shape::Arr2 ||
      c.shape is Shape::ManyVar {
      assert_eq(count_occur(src, " : Int\n"), c.fields)
    }
  }
}

///|
test "lib: nested shape puts the enum behind a struct" {
  for c in cases() {
    if c.shape is Shape::Nested {
      let src = lib_source(c)
      assert_true(src.contains("struct Inner {"))
      assert_true(src.contains("inner: { k:"))
    }
  }
}

///|
test "lib: manyvar has 64 variants and no nullary variant" {
  for c in cases() {
    if c.shape is Shape::ManyVar {
      let src = lib_source(c)
      assert_eq(count_occur(src, "(Int)\n"), 64)
      assert_false(src.contains("  A\n"))
    }
  }
}
