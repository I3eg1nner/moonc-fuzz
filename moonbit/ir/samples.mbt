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
  ]
}
