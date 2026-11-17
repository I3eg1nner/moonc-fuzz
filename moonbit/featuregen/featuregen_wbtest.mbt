///|
test "deterministic enumeration and exact matrix size" {
  let a = layout_cases()
  let b = layout_cases()
  assert_eq(a.length(), 160)
  assert_eq(matrix_size(), 160)
  assert_eq(a.length(), b.length())
  for i in 0..<a.length() {
    assert_eq(a[i].id, b[i].id)
    assert_eq(a[i].index, i)
  }
}

///|
test "ids are unique and stable" {
  let cases = layout_cases()
  let seen : Array[String] = []
  for c in cases {
    for prev in seen {
      assert_true(c.id != prev)
    }
    seen.push(c.id)
  }
  assert_eq(cases[0].id, "L0000-vt-push-none")
  assert_eq(cases[1].id, "L0001-vt-makei-none")
  assert_eq(cases[4].id, "L0004-vt-slice-none")
  assert_eq(cases[5].id, "L0005-plain-push-none")
  assert_eq(cases[159].id, "L0159-plain-slice-int_bool_enum_array_int_string")
}

///|
test "F7 seed and its plain control are built in" {
  let seed = f7_seed()
  let control = f7_control()
  assert_true(seed.valtype)
  assert_eq(op_tag(seed.op), "push")
  assert_eq(seed.fields.length(), 2)
  assert_eq(field_tag(seed.fields[0].ty), "int")
  assert_eq(field_tag(seed.fields[1].ty), "enum_string")
  assert_eq(seed.id, "L0080-vt-push-int_enum_string")
  assert_false(control.valtype)
  assert_eq(op_tag(control.op), "push")
  assert_eq(control.fields.length(), 2)
  assert_eq(control.id, "L0085-plain-push-int_enum_string")
}

///|
test "F7 renderer emits valtype, enum payload and a checksum" {
  let pkg = render_package(f7_seed())
  assert_true(pkg.lib_mbt.contains("#valtype\nstruct Entry"))
  assert_true(pkg.lib_mbt.contains("enum Kind {\n  Ref(String)\n}"))
  assert_true(pkg.lib_mbt.contains("pub fn checksum() -> Int64"))
  assert_true(pkg.lib_mbt.contains("xs.push(entry(i))"))
  assert_true(pkg.main_mbt.contains("println(checksum())"))
  assert_true(pkg.main_test_mbt.contains("@generated.checksum()"))
  assert_true(pkg.moon_pkg.contains("pkgtype(kind: \"executable\")"))
}

///|
test "plain control renderer omits #valtype but keeps the payload" {
  let pkg = render_package(f7_control())
  assert_false(pkg.lib_mbt.contains("#valtype"))
  assert_true(pkg.lib_mbt.contains("Ref(String)"))
}

///|
test "remove-enum-payload control keeps valtype but uses a bare Int field" {
  let c = layout_cases()[10]
  assert_true(c.valtype)
  assert_eq(c.fields.length(), 1)
  assert_eq(field_tag(c.fields[0].ty), "int")
  let pkg = render_package(c)
  assert_true(pkg.lib_mbt.contains("#valtype"))
  assert_false(pkg.lib_mbt.contains("enum Kind"))
}

///|
test "zero-field struct uses explicit Entry construction" {
  let c = layout_cases()[0]
  assert_eq(c.fields.length(), 0)
  let pkg = render_package(c)
  assert_true(pkg.lib_mbt.contains("Entry::{ }"))
  assert_true(pkg.lib_mbt.contains("struct Entry {\n}"))
}

///|
test "renderer is deterministic" {
  for c in [f7_seed(), f7_control(), layout_cases()[159]] {
    let a = render_package(c)
    let b = render_package(c)
    assert_eq(a.moon_mod, b.moon_mod)
    assert_eq(a.lib_mbt, b.lib_mbt)
    assert_eq(a.main_mbt, b.main_mbt)
    assert_eq(a.main_test_mbt, b.main_test_mbt)
  }
}

///|
test "expected checksum for zero-field push is 7*131^4" {
  let c = layout_cases()[0]
  let want = 7L * 131L * 131L * 131L * 131L
  assert_eq(expected_checksum(c), want)
}

///|
test "expected checksum follows filter/slice cardinality" {
  let zero_push = layout_cases()[0]
  let zero_filter = layout_cases()[3]
  let zero_slice = layout_cases()[4]
  assert_eq(
    expected_checksum(zero_filter),
    7L * 131L * 131L * 131L * 131L * 131L,
  )
  assert_eq(expected_checksum(zero_slice), 7L * 131L * 131L * 131L * 131L)
  assert_eq(expected_checksum(zero_push), 7L * 131L * 131L * 131L * 131L)
}

///|
test "every matrix case renders a complete package" {
  for c in layout_cases() {
    let pkg = render_package(c)
    assert_true(pkg.moon_mod.contains("featfuzz/generated"))
    assert_true(pkg.lib_mbt.contains("pub fn checksum() -> Int64"))
    assert_true(pkg.main_test_mbt.contains("assert_eq(a, b)"))
  }
}

///|
test "features JSON names all axes" {
  let s = features_json(f7_seed())
  assert_true(s.contains("\"valtype\":true"))
  assert_true(s.contains("\"op\":\"push\""))
  assert_true(s.contains("enum_string"))
}
