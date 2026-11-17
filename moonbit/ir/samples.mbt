///|
fn sample_main(body : Array[Stmt]) -> Func {
  { name: "main", params: [], ret: Unit, body, }
}

///|
pub fn sample_programs() -> Array[Program] {
  [
    {
      funcs: [
        sample_main([
          Let("x", I32, ConstI32(4), true),
          Assign("x", Mul(Var("x"), ConstI32(5))),
          Emit(1, Add(ConstI32(2), ConstI32(3))),
          Emit(2, Var("x")),
          If(Lt(Var("x"), ConstI32(10)), [Emit(3, ConstI32(1))], [
            Emit(3, ConstI32(0)),
          ]),
        ]),
      ],
    },
    {
      funcs: [
        {
          name: "add",
          params: [("a", I32), ("b", I32)],
          ret: I32,
          body: [Return(Add(Var("a"), Var("b")))],
        },
        sample_main([Emit(7, Call("add", [ConstI32(20), ConstI32(22)]))]),
      ],
    },
    {
      funcs: [
        sample_main([
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
    },
    {
      funcs: [
        sample_main([Let("dead", I32, ConstI32(7), false), Emit(1, ConstI32(3))]),
      ],
    },
    {
      funcs: [
        {
          name: "choose",
          params: [("c", Bool), ("a", I32), ("b", I32)],
          ret: I32,
          body: [Return(If(Var("c"), Var("a"), Var("b")))],
        },
        sample_main([
          Let("a", I32Array, ArrayLit([ConstI32(1), ConstI32(2)]), true),
          Let("b", I32Array, Var("a"), true),
          ArraySet("b", ConstI32(0), ConstI32(9)),
          Let("i", I32, ConstI32(0), true),
          While(
            Lt(Var("i"), ConstI32(2)),
            [
              If(Eq(Var("i"), ConstI32(0)), [Emit(1, ConstI32(10))], [
                Emit(1, ConstI32(20)),
              ]),
              Assign("i", Add(Var("i"), ConstI32(1))),
            ],
            3,
          ),
          Emit(2, Index(Var("a"), ConstI32(0))),
          Emit(3, Call("choose", [ConstBool(true), ConstI32(7), ConstI32(8)])),
        ]),
      ],
    },
    {
      funcs: [
        sample_main([
          Let("a", I32Array, ArrayLit([ConstI32(5)]), true),
          Let("i", I32, ConstI32(0), true),
          While(
            Lt(Var("i"), Len(Var("a"))),
            [
              Emit(1, Index(Var("a"), Var("i"))),
              Assign("i", Add(Var("i"), ConstI32(1))),
            ],
            2,
          ),
          Emit(2, Index(Var("a"), Sub(Len(Var("a")), ConstI32(1)))),
        ]),
      ],
    },
    {
      funcs: [
        sample_main([
          Let("x", I32, ConstI32(1), true),
          If(Eq(Var("x"), ConstI32(1)), [Assign("x", ConstI32(10))], [
            Assign("x", ConstI32(20)),
          ]),
          Emit(1, Var("x")),
          If(ConstBool(false), [Assign("x", ConstI32(30))], [
            Assign("x", ConstI32(40)),
          ]),
          Emit(2, Var("x")),
        ]),
      ],
    },
  ]
}
