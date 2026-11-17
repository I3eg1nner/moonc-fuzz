///|
fn empty_params() -> Array[(String, Ty)] {
  []
}

///|
fn main_func(body : Array[Stmt]) -> Func {
  { name: "main", params: empty_params(), ret: Unit, body, }
}

///|
test "interpreter evaluates arithmetic, mutation and if" {
  let p : Program = {
    funcs: [
      main_func([
        Let("x", I32, ConstI32(4), true),
        Assign("x", Mul(Var("x"), ConstI32(5))),
        Emit(1, Add(ConstI32(2), ConstI32(3))),
        Emit(2, Var("x")),
        If(Lt(Var("x"), ConstI32(10)), [Emit(3, ConstI32(1))], [
          Emit(3, ConstI32(0)),
        ]),
      ]),
    ],
  }
  let events = run(p, 1000) catch { _ => [] }
  assert_eq(events, ["Emit(1, 5)", "Emit(2, 20)", "Emit(3, 0)"])
}

///|
test "interpreter calls first-order functions" {
  let add : Func = {
    name: "add",
    params: [("a", I32), ("b", I32)],
    ret: I32,
    body: [Return(Add(Var("a"), Var("b")))],
  }
  let p : Program = {
    funcs: [
      add,
      main_func([Emit(7, Call("add", [ConstI32(20), ConstI32(22)]))]),
    ],
  }
  let events = run(p, 1000) catch { _ => [] }
  assert_eq(events, ["Emit(7, 42)"])
}

///|
test "interpreter handles mutable int arrays and bounded loops" {
  let p : Program = {
    funcs: [
      main_func([
        Let(
          "a",
          I32Array,
          ArrayLit([ConstI32(1), ConstI32(2), ConstI32(3)]),
          true,
        ),
        Let("i", I32, ConstI32(0), true),
        Let("s", I32, ConstI32(0), true),
        While(
          Lt(Var("i"), Len(Var("a"))),
          [
            Assign("s", Add(Var("s"), Index(Var("a"), Var("i")))),
            Assign("i", Add(Var("i"), ConstI32(1))),
          ],
          10,
        ),
        ArraySet("a", ConstI32(0), ConstI32(9)),
        Emit(1, Var("s")),
        Emit(2, Index(Var("a"), ConstI32(0))),
      ]),
    ],
  }
  let events = run(p, 1000) catch { _ => [] }
  assert_eq(events, ["Emit(1, 6)", "Emit(2, 9)"])
}

///|
test "type checker rejects a bad assignment" {
  let p : Program = {
    funcs: [
      main_func([Let("x", I32, ConstI32(1), true), Assign("x", ConstBool(true))]),
    ],
  }
  let ok = try {
    check_program(p)
    true
  } catch {
    _ => false
  }
  assert_false(ok)
}

///|
test "emitter emits functions, mutation and bounded loops" {
  let p : Program = {
    funcs: [
      main_func([
        Let("x", I32, ConstI32(1), true),
        While(
          Lt(Var("x"), ConstI32(3)),
          [Assign("x", Add(Var("x"), ConstI32(1)))],
          5,
        ),
        Emit(1, Var("x")),
      ]),
    ],
  }
  let src = emit_program(p)
  assert_true(src.contains("fn main {"))
  assert_true(src.contains("let mut x : Int = 1"))
  assert_true(src.contains("for __w in 0..<5"))
  assert_true(src.contains("println(\"Emit(1, \" + (x).to_string() + \")\")"))
}

///|
fn check_fails(p : Program) -> Bool {
  try {
    check_program(p)
    false
  } catch {
    _ => true
  }
}

///|
test "type checker rejects Bool lt, array rebinding, array emit and missing return" {
  let bool_lt : Program = {
    funcs: [main_func([Emit(1, Lt(ConstBool(true), ConstBool(false)))])],
  }
  assert_true(check_fails(bool_lt))
  let array_rebind : Program = {
    funcs: [
      main_func([
        Let("a", I32Array, ArrayLit([]), true),
        Assign("a", ArrayLit([])),
      ]),
    ],
  }
  assert_true(check_fails(array_rebind))
  let array_emit : Program = { funcs: [main_func([Emit(1, ArrayLit([]))])], }
  assert_true(check_fails(array_emit))
  let missing_return : Program = {
    funcs: [
      { name: "f", params: [], ret: I32, body: [Emit(1, ConstI32(1))], },
      main_func([]),
    ],
  }
  assert_true(check_fails(missing_return))
}

///|
test "bounded while stops at the bound without an extra condition event" {
  let p : Program = { funcs: [main_func([While(ConstBool(true), [], 1)])], }
  let events = run(p, 1000) catch { _ => ["<error>"] }
  assert_eq(events, [])
}

///|
test "bounded while does not evaluate an emitting condition after the bound" {
  let cond : Func = {
    name: "cond",
    params: [],
    ret: Bool,
    body: [Emit(9, ConstI32(1)), Return(ConstBool(true))],
  }
  let p : Program = {
    funcs: [cond, main_func([While(Call("cond", []), [], 1)])],
  }
  let events = run(p, 1000) catch { _ => ["<error>"] }
  assert_eq(events, ["Emit(9, 1)"])
}

///|
test "type checker rejects locals that shadow functions or println" {
  let p : Program = {
    funcs: [
      { name: "f", params: [], ret: I32, body: [Return(ConstI32(1))], },
      main_func([Let("f", I32, ConstI32(1), false)]),
    ],
  }
  assert_true(check_fails(p))
  let q : Program = {
    funcs: [main_func([Let("println", I32, ConstI32(1), false)])],
  }
  assert_true(check_fails(q))
}

///|
test "random generator is deterministic and type-correct" {
  let a = generate(7UL, 8)
  let b = generate(7UL, 8)
  check_program(a) catch {
    _ => fail("generated program is invalid")
  }
  assert_eq(emit_program(a), emit_program(b))
  assert_true(emit_program(a).contains("fn main"))
}

///|
test "trace-preserving reducer removes dead lets and no-op assignments" {
  let p : Program = {
    funcs: [
      main_func([
        Let("x", I32, ConstI32(1), true),
        Let("dead", I32, ConstI32(2), false),
        Assign("x", Var("x")),
        Assign("x", Add(Var("x"), ConstI32(1))),
        Emit(1, Var("x")),
      ]),
    ],
  }
  let expected = run(p, 1000) catch { _ => [] }
  let r = reduce(p, expected, 1000) catch { _ => p }
  assert_eq(statement_count(r), 3)
  assert_eq(run(r, 1000) catch { _ => [] }, expected)
}

///|
test "reducer keeps the assignment that changes the trace" {
  let p : Program = {
    funcs: [
      main_func([
        Let("x", I32, ConstI32(1), true),
        Assign("x", Add(Var("x"), ConstI32(4))),
        Emit(1, Var("x")),
      ]),
    ],
  }
  let expected = run(p, 1000) catch { _ => [] }
  let r = reduce(p, expected, 1000) catch { _ => p }
  assert_eq(statement_count(r), 3)
  assert_eq(run(r, 1000) catch { _ => [] }, ["Emit(1, 5)"])
}

///|
test "reducer rejects a mismatched target" {
  let p : Program = { funcs: [main_func([Emit(1, ConstI32(1))])], }
  let failed = try {
    ignore(reduce(p, ["Emit(1, 2)"], 1000))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "targeted shapes: alias write, while-if and choose" {
  let p = sample_programs()[4]
  let events = run(p, 1000) catch { _ => ["<error>"] }
  assert_eq(events, ["Emit(1, 10)", "Emit(1, 20)", "Emit(2, 9)", "Emit(3, 7)"])
}

///|
test "Len=1 last-index access and len-bound loop" {
  let p = sample_programs()[5]
  let events = run(p, 1000) catch { _ => ["<error>"] }
  assert_eq(events, ["Emit(1, 5)", "Emit(2, 5)"])
}

///|
test "Len=0 last-index access fails instead of wrapping" {
  let p : Program = {
    funcs: [
      main_func([
        Let("a", I32Array, ArrayLit([]), true),
        Emit(1, Index(Var("a"), Sub(Len(Var("a")), ConstI32(1)))),
      ]),
    ],
  }
  let failed = try {
    ignore(run(p, 1000))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "fixed branch-state merge regression" {
  let p = sample_programs()[6]
  let events = run(p, 1000) catch { _ => ["<error>"] }
  assert_eq(events, ["Emit(1, 10)", "Emit(2, 40)"])
}
