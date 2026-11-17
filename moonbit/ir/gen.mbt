///|
/// Deterministic generator for the small IR subset.  It intentionally avoids
/// division, floats, strings, closures, unbounded loops and array rebinding.

///|
fn pick_i32(rng : @mutate.Rng, vars : Array[(String, Ty)]) -> Expr {
  let ints : Array[String] = []
  for v in vars {
    let (name, ty) = v
    if ty == I32 {
      ints.push(name)
    }
  }
  if ints.length() > 0 && rng.chance(0.55) {
    Var(ints[rng.int(ints.length())])
  } else {
    ConstI32(rng.int(101) - 50)
  }
}

///|
fn gen_i32(
  rng : @mutate.Rng,
  vars : Array[(String, Ty)],
  depth : Int32,
) -> Expr {
  if depth <= 0 {
    pick_i32(rng, vars)
  } else {
    let arrays : Array[String] = []
    for v in vars {
      let (name, ty) = v
      if ty == I32Array {
        arrays.push(name)
      }
    }
    if arrays.length() > 0 && rng.chance(0.2) {
      let name = arrays[rng.int(arrays.length())]
      if rng.chance(0.3) {
        Len(Var(name))
      } else if rng.chance(0.5) {
        Index(Var(name), ConstI32(0))
      } else {
        Index(Var(name), Sub(Len(Var(name)), ConstI32(1)))
      }
    } else {
      let choice = rng.int(12)
      if choice < 3 {
        pick_i32(rng, vars)
      } else if choice < 5 {
        Add(gen_i32(rng, vars, depth - 1), gen_i32(rng, vars, depth - 1))
      } else if choice < 7 {
        Sub(gen_i32(rng, vars, depth - 1), gen_i32(rng, vars, depth - 1))
      } else if choice < 8 {
        Mul(ConstI32(rng.int(7) - 3), gen_i32(rng, vars, depth - 1))
      } else if choice < 9 {
        If(
          gen_bool(rng, vars, depth - 1),
          gen_i32(rng, vars, depth - 1),
          gen_i32(rng, vars, depth - 1),
        )
      } else if choice < 10 {
        Call("add", [
          gen_i32(rng, vars, depth - 1),
          gen_i32(rng, vars, depth - 1),
        ])
      } else if choice < 11 {
        Call("choose", [
          gen_bool(rng, vars, depth - 1),
          gen_i32(rng, vars, depth - 1),
          gen_i32(rng, vars, depth - 1),
        ])
      } else {
        Call("abs", [gen_i32(rng, vars, depth - 1)])
      }
    }
  }
}

///|
fn gen_bool(
  rng : @mutate.Rng,
  vars : Array[(String, Ty)],
  depth : Int32,
) -> Expr {
  if depth <= 0 {
    ConstBool(rng.chance(0.5))
  } else if rng.chance(0.6) {
    Lt(gen_i32(rng, vars, depth - 1), gen_i32(rng, vars, depth - 1))
  } else {
    Eq(gen_i32(rng, vars, depth - 1), gen_i32(rng, vars, depth - 1))
  }
}

///|
pub fn generate(seed : UInt64, size : Int32) -> Program {
  let rng = @mutate.Rng::new(seed)
  let vars : Array[(String, Ty)] = []
  let body : Array[Stmt] = []
  let mut site = 1
  let slots = if size <= 0 { 1 } else { size }
  let n_lets = 2 + rng.int(2) + slots / 2
  for k in 0..<n_lets {
    let name = "x" + k.to_string()
    body.push(Let(name, I32, gen_i32(rng, vars, 2), true))
    vars.push((name, I32))
  }
  // Optional array with an explicit, in-bounds update.
  if rng.chance(0.7) {
    let n = 2 + rng.int(3)
    let items : Array[Expr] = []
    for _ in 0..<n {
      items.push(ConstI32(rng.int(19) - 9))
    }
    body.push(Let("a", I32Array, ArrayLit(items), true))
    vars.push(("a", I32Array))
    let set_index = if rng.chance(0.5) {
      ConstI32(0)
    } else {
      Sub(Len(Var("a")), ConstI32(1))
    }
    body.push(ArraySet("a", set_index, gen_i32(rng, vars, 1)))
    body.push(Emit(site, Index(Var("a"), ConstI32(0))))
    site += 1
    if rng.chance(0.5) {
      body.push(Let("b", I32Array, Var("a"), true))
      vars.push(("b", I32Array))
      body.push(ArraySet("b", ConstI32(0), gen_i32(rng, vars, 1)))
      body.push(Emit(site, Index(Var("a"), ConstI32(0))))
      site += 1
    }
  }
  // Independent scalar outputs.
  let n_emit = 1 + rng.int(3) + slots / 3
  for _ in 0..<n_emit {
    if rng.chance(0.6) {
      body.push(Emit(site, gen_i32(rng, vars, 2)))
    } else {
      body.push(Emit(site, gen_bool(rng, vars, 2)))
    }
    site += 1
  }
  // One branch with only side effects on existing state.
  body.push(
    If(gen_bool(rng, vars, 2), [Emit(site, gen_i32(rng, vars, 1))], [
      Emit(site, gen_i32(rng, vars, 1)),
    ]),
  )
  site += 1
  // One bounded loop with an explicit counter increment.
  body.push(Let("i", I32, ConstI32(0), true))
  vars.push(("i", I32))
  let bound = 2 + rng.int(2)
  let mut array_name = ""
  for v in vars {
    let (name, ty) = v
    if ty == I32Array && array_name == "" {
      array_name = name
    }
  }
  let use_len = array_name != "" && rng.chance(0.5)
  let loop_body : Array[Stmt] = []
  if rng.chance(0.5) {
    loop_body.push(
      If(gen_bool(rng, vars, 2), [Emit(site, gen_i32(rng, vars, 1))], [
        Emit(site, gen_i32(rng, vars, 1)),
      ]),
    )
    site += 1
  }
  loop_body.push(Emit(site, gen_i32(rng, vars, 1)))
  site += 1
  // A len-bound loop is the only place where i is guaranteed in bounds.
  if use_len && rng.chance(0.5) {
    loop_body.push(ArraySet(array_name, Var("i"), gen_i32(rng, vars, 1)))
    loop_body.push(Emit(site, Index(Var(array_name), Var("i"))))
    site += 1
  }
  loop_body.push(Assign("i", Add(Var("i"), ConstI32(1))))
  let loop_cond = if use_len {
    Lt(Var("i"), Len(Var(array_name)))
  } else {
    Lt(Var("i"), ConstI32(bound))
  }
  let loop_bound = if use_len { 8 } else { bound + 1 }
  body.push(While(loop_cond, loop_body, loop_bound))
  site += 1
  let muts : Array[String] = []
  for v in vars {
    let (name, ty) = v
    if ty == I32 && name != "i" {
      muts.push(name)
    }
  }
  if muts.length() > 0 && rng.chance(0.5) {
    let name = muts[rng.int(muts.length())]
    body.push(
      If(gen_bool(rng, vars, 2), [Assign(name, gen_i32(rng, vars, 2))], [
        Assign(name, gen_i32(rng, vars, 2)),
      ]),
    )
  }
  body.push(Emit(site, gen_i32(rng, vars, 2)))
  let add : Func = {
    name: "add",
    params: [("a", I32), ("b", I32)],
    ret: I32,
    body: [Return(Add(Var("a"), Var("b")))],
  }
  let choose : Func = {
    name: "choose",
    params: [("c", Bool), ("a", I32), ("b", I32)],
    ret: I32,
    body: [Return(If(Var("c"), Var("a"), Var("b")))],
  }
  let abs : Func = {
    name: "abs",
    params: [("x", I32)],
    ret: I32,
    body: [
      If(Lt(Var("x"), ConstI32(0)), [Return(Sub(ConstI32(0), Var("x")))], []),
      Return(Var("x")),
    ],
  }
  { funcs: [add, choose, abs, { name: "main", params: [], ret: Unit, body, }], }
}
