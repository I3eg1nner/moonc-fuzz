///|
test "matrix is curated, unique and covers every axis value" {
  let cases = @asyncgen.matrix()
  assert_true(cases.length() >= 40 && cases.length() <= 100)
  let ids : Map[String, Unit] = Map([])
  for c in cases {
    assert_false(ids.contains(c.id))
    ids.set(c.id, ())
  }
  assert_eq(ids.length(), cases.length())
  let shapes : Map[String, Unit] = Map([])
  let susps : Map[String, Unit] = Map([])
  let ctrls : Map[String, Unit] = Map([])
  let tys : Map[String, Unit] = Map([])
  let entries : Map[String, Unit] = Map([])
  for c in cases {
    shapes.set(@asyncgen.shape_slug(c.shape), ())
    susps.set(@asyncgen.suspension_slug(c.suspension), ())
    ctrls.set(@asyncgen.control_slug(c.control), ())
    tys.set(@asyncgen.ty_slug(c.ty), ())
    entries.set(@asyncgen.entry_slug(c.entry), ())
  }
  assert_eq(shapes.length(), 5)
  assert_eq(susps.length(), 4)
  assert_eq(ctrls.length(), 8)
  assert_eq(tys.length(), 2)
  assert_eq(entries.length(), 2)
}

///|
test "enumeration is deterministic" {
  let a = @asyncgen.matrix()
  let b = @asyncgen.matrix()
  assert_eq(a.length(), b.length())
  for i in 0..<a.length() {
    assert_eq(a[i].id, b[i].id)
    assert_eq(@asyncgen.render_lib(a[i]), @asyncgen.render_lib(b[i]))
    assert_eq(@asyncgen.render_test(a[i]), @asyncgen.render_test(b[i]))
  }
  let first = @asyncgen.select_cases(40)
  assert_eq(first.length(), 40)
  for i in 0..<40 {
    assert_eq(first[i].id, a[i].id)
  }
}

///|
test "F8 control renders the exact known signature" {
  let mut found = false
  for c in @asyncgen.matrix() {
    if c.f8_control {
      found = true
      let lib = @asyncgen.render_lib(c)
      assert_true(
        lib.contains(
          "pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {\n  @aio.pause()\n  select(1)\n}",
        ),
      )
      let t = @asyncgen.render_test(c)
      assert_true(t.contains("x => if x == 1 { Some(x) } else { None }"))
      assert_true(t.contains("Some(1)"))
    }
  }
  assert_true(found)
}

///|
test "package has the four required files" {
  let c = @asyncgen.matrix()[0]
  let files = @asyncgen.render_package(c)
  assert_eq(files.length(), 4)
  assert_eq(files[0].0, "moon.mod")
  assert_eq(files[1].0, "lib/moon.pkg")
  assert_eq(files[2].0, "lib/lib.mbt")
  assert_eq(files[3].0, "lib/lib_test.mbt")
  assert_true(files[0].1.contains("moonbitlang/async@0.22.9"))
  assert_true(files[1].1.contains("\"moonbitlang/async\" @aio"))
}

///|
test "loop renderer places suspension in the requested position" {
  let mut before = false
  let mut inside = false
  let mut after = false
  for c in @asyncgen.matrix() {
    if c.control == @asyncgen.CtrlFor && c.suspension == @asyncgen.SuspBefore {
      before = before ||
        @asyncgen.render_lib(c).contains("@aio.pause()\n  let mut last")
    }
    if c.control == @asyncgen.CtrlFor && c.suspension == @asyncgen.SuspInside {
      inside = @asyncgen.render_lib(c).contains(
        "for i in 0..<2 {\n    @aio.pause()",
      )
    }
    if c.control == @asyncgen.CtrlFor && c.suspension == @asyncgen.SuspAfter {
      after = after ||
        @asyncgen.render_lib(c).contains("}\n  @aio.pause()\n  last")
    }
  }
  assert_true(before && inside && after)
}

///|
test "signature normalisation recognises F8" {
  let blob = "Error: failed to link x\nOops...\nError: File \"moonc.ml\", line 125623, characters 29-35: Assertion failed\nmoonc version: v0.10.20"
  let sig = @asyncgen.normalize_signature(blob, 1)
  assert_eq(sig, @asyncgen.known_f8_signature())
  assert_true(@asyncgen.is_known_f8(sig))
  assert_true(@asyncgen.is_crash_signature(sig))
}

///|
test "signature normalisation covers machine errors, signals and infra" {
  assert_eq(
    @asyncgen.normalize_signature("Fatal error: Machine_error", 2),
    "Machine_error",
  )
  assert_eq(
    @asyncgen.normalize_signature("segmentation fault", -11),
    "signal:-11",
  )
  assert_eq(
    @asyncgen.normalize_signature("Fatal error: exception Stack_overflow", 2),
    "ocaml_exception:Stack_overflow",
  )
  assert_true(
    @asyncgen.is_infra(
      "Error: module was not found in the registry: moonbitlang/async",
    ),
  )
  assert_false(
    @asyncgen.is_infra(
      "Error: File \"moonc.ml\", line 1, characters 2-3: Assertion failed",
    ),
  )
}

///|
test "continue cases expect the last iteration index" {
  let mut opt_ok = false
  let mut plain_ok = false
  for c in @asyncgen.matrix() {
    if c.control == @asyncgen.CtrlContinue && c.shape == @asyncgen.Opt {
      opt_ok = opt_ok || @asyncgen.render_test(c).contains("Some(2)")
    }
    if c.control == @asyncgen.CtrlContinue && c.shape == @asyncgen.Plain {
      plain_ok = plain_ok ||
        @asyncgen.render_test(c).contains("assert_eq(r, 3)")
    }
  }
  assert_true(opt_ok)
  assert_true(plain_ok)
}
