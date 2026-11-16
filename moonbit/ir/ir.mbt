///|
/// A deliberately small typed IR.  It is not a MoonBit parser or a general
/// language model: it exists to give the fuzzer a semantic oracle for a
/// subset whose evaluation order and state are explicit.

///|
#derive(Eq)
pub(all) enum Ty {
  I32
  Bool
  Unit
  I32Array
}

///|
pub extend Ty with Eq::{not_equal, equal}

///|
pub fn ty_name(t : Ty) -> String {
  match t {
    I32 => "Int"
    Bool => "Bool"
    Unit => "Unit"
    I32Array => "Array[Int]"
  }
}

///|
pub(all) enum Expr {
  ConstI32(Int32)
  ConstBool(Bool)
  Var(String)
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Lt(Expr, Expr)
  Eq(Expr, Expr)
  If(Expr, Expr, Expr)
  Call(String, Array[Expr])
  ArrayLit(Array[Expr])
  Index(Expr, Expr)
  Len(Expr)
}

///|
pub(all) enum Stmt {
  Let(String, Ty, Expr, Bool)
  Assign(String, Expr)
  ArraySet(String, Expr, Expr)
  Emit(Int32, Expr)
  If(Expr, Array[Stmt], Array[Stmt])
  While(Expr, Array[Stmt], Int32)
  Return(Expr)
}

///|
pub(all) struct Func {
  name : String
  params : Array[(String, Ty)]
  ret : Ty
  body : Array[Stmt]
}

///|
pub(all) struct Program {
  funcs : Array[Func]
}

///|
priv struct VarInfo {
  ty : Ty
  mutable : Bool
}

///|
fn valid_name(name : String, funcs : Map[String, Func]) -> Bool {
  name != "" &&
  !name.has_prefix("__") &&
  name != "println" &&
  !funcs.contains(name)
}

///|
fn clone_vars(vars : Map[String, VarInfo]) -> Map[String, VarInfo] {
  let out : Map[String, VarInfo] = Map([])
  for k in vars.keys() {
    match vars.get(k) {
      Some(v) => out.set(k, v)
      None => ()
    }
  }
  out
}

///|
fn func_map(program : Program) -> Map[String, Func] raise Failure {
  let out : Map[String, Func] = Map([])
  for f in program.funcs {
    if out.contains(f.name) {
      fail("duplicate function: " + f.name)
    }
    out.set(f.name, f)
  }
  out
}

///|
fn type_of(
  e : Expr,
  vars : Map[String, VarInfo],
  funcs : Map[String, Func],
) -> Ty raise Failure {
  match e {
    ConstI32(_) => I32
    ConstBool(_) => Bool
    Var(n) =>
      match vars.get(n) {
        Some(v) => v.ty
        None => fail("unbound variable: " + n)
      }
    Add(a, b) | Sub(a, b) | Mul(a, b) => {
      if type_of(a, vars, funcs) != I32 || type_of(b, vars, funcs) != I32 {
        fail("arithmetic requires Int")
      }
      I32
    }
    Lt(a, b) => {
      if type_of(a, vars, funcs) != I32 || type_of(b, vars, funcs) != I32 {
        fail("lt requires Int")
      }
      Bool
    }
    Eq(a, b) => {
      let ta = type_of(a, vars, funcs)
      let tb = type_of(b, vars, funcs)
      if ta != tb {
        fail("eq types differ")
      }
      match ta {
        I32 | Bool => Bool
        _ => fail("eq supports Int/Bool only")
      }
    }
    If(c, a, b) => {
      if type_of(c, vars, funcs) != Bool {
        fail("if condition must be Bool")
      }
      let ta = type_of(a, vars, funcs)
      let tb = type_of(b, vars, funcs)
      if ta != tb {
        fail("if branch types differ")
      }
      ta
    }
    Call(name, args) =>
      match funcs.get(name) {
        Some(f) => {
          if f.params.length() != args.length() {
            fail("arity mismatch: " + name)
          }
          for i, arg in args {
            let (_, ty) = f.params[i]
            if type_of(arg, vars, funcs) != ty {
              fail("argument type mismatch: " + name)
            }
          }
          f.ret
        }
        None => fail("unknown function: " + name)
      }
    ArrayLit(items) => {
      for item in items {
        if type_of(item, vars, funcs) != I32 {
          fail("array literal must contain Int")
        }
      }
      I32Array
    }
    Index(a, i) => {
      if type_of(a, vars, funcs) != I32Array || type_of(i, vars, funcs) != I32 {
        fail("index requires Array[Int] and Int")
      }
      I32
    }
    Len(a) => {
      if type_of(a, vars, funcs) != I32Array {
        fail("len requires Array[Int]")
      }
      I32
    }
  }
}

///|
fn check_block(
  stmts : Array[Stmt],
  vars : Map[String, VarInfo],
  funcs : Map[String, Func],
  ret : Ty,
) -> Unit raise Failure {
  for stmt in stmts {
    match stmt {
      Let(name, ty, e, mutable) => {
        if !valid_name(name, funcs) {
          fail("invalid or shadowing local name: " + name)
        }
        if vars.contains(name) {
          fail("duplicate local: " + name)
        }
        if type_of(e, vars, funcs) != ty {
          fail("let type mismatch: " + name)
        }
        vars.set(name, { ty, mutable, })
      }
      Assign(name, e) =>
        match vars.get(name) {
          Some(v) =>
            if !v.mutable {
              fail("assignment to immutable local: " + name)
            } else if v.ty == I32Array {
              fail("array rebinding is unsupported; use ArraySet")
            } else if type_of(e, vars, funcs) != v.ty {
              fail("assignment type mismatch: " + name)
            }
          None => fail("assignment to unbound local: " + name)
        }
      ArraySet(name, i, v) => {
        let a = match vars.get(name) {
          Some(a) => a
          None => fail("array assignment to unbound local: " + name)
        }
        if a.ty != I32Array || !a.mutable {
          fail("array assignment requires mutable Array[Int]")
        }
        if type_of(i, vars, funcs) != I32 || type_of(v, vars, funcs) != I32 {
          fail("array assignment requires Int index/value")
        }
      }
      Emit(_, e) => {
        let t = type_of(e, vars, funcs)
        if t != I32 && t != Bool {
          fail("emit supports Int/Bool only")
        }
      }
      If(c, a, b) => {
        if type_of(c, vars, funcs) != Bool {
          fail("if condition must be Bool")
        }
        check_block(a, clone_vars(vars), funcs, ret)
        check_block(b, clone_vars(vars), funcs, ret)
      }
      While(c, body, bound) => {
        if type_of(c, vars, funcs) != Bool {
          fail("while condition must be Bool")
        }
        if bound <= 0 {
          fail("while bound must be positive")
        }
        check_block(body, clone_vars(vars), funcs, ret)
      }
      Return(e) =>
        if type_of(e, vars, funcs) != ret {
          fail("return type mismatch")
        }
    }
  }
}

///|
pub fn check_program(program : Program) -> Unit raise Failure {
  let funcs = func_map(program)
  let mut has_main = false
  for f in program.funcs {
    if f.name == "println" {
      fail("function name shadows println")
    }
    if f.name == "main" {
      has_main = true
      if f.params.length() != 0 || f.ret != Unit {
        fail("main must have no params and return Unit")
      }
    }
    let vars : Map[String, VarInfo] = Map([])
    for p in f.params {
      let (name, ty) = p
      if !valid_name(name, funcs) {
        fail("invalid or shadowing parameter name: " + name)
      }
      if vars.contains(name) {
        fail("duplicate parameter: " + name)
      }
      vars.set(name, { ty, mutable: false, })
    }
    check_block(f.body, vars, funcs, f.ret)
    if f.ret != Unit {
      let tail_ok = match f.body.get(f.body.length() - 1) {
        Some(Return(_)) => true
        _ => false
      }
      if !tail_ok {
        fail("non-Unit function must end in return: " + f.name)
      }
    }
  }
  if !has_main {
    fail("program has no main")
  }
}

///|
pub(all) enum Value {
  VI32(Int32)
  VBool(Bool)
  VUnit
  VArray(Array[Int32])
}

///|
pub fn show_value(v : Value) -> String {
  match v {
    VI32(n) => n.to_string()
    VBool(b) => b.to_string()
    VUnit => "Unit"
    VArray(a) => {
      let b = StringBuilder()
      b.write_string("[")
      for i, x in a {
        if i > 0 {
          b.write_string(", ")
        }
        b.write_string(x.to_string())
      }
      b.write_string("]")
      b.to_string()
    }
  }
}

///|
priv enum Outcome {
  Normal
  Returned(Value)
}

///|
priv struct Interp {
  funcs : Map[String, Func]
  events : Array[String]
  mut fuel : Int32
}

///|
fn eval(e : Expr, env : Map[String, Value], it : Interp) -> Value raise Failure {
  it.fuel = it.fuel - 1
  if it.fuel < 0 {
    fail("interpreter fuel exhausted")
  }
  match e {
    ConstI32(n) => VI32(n)
    ConstBool(b) => VBool(b)
    Var(n) =>
      match env.get(n) {
        Some(v) => v
        None => fail("unbound runtime variable: " + n)
      }
    Add(a, b) =>
      VI32(
        (match eval(a, env, it) {
          VI32(n) => n
          _ => fail("add operand is not Int")
        }) +
        (match eval(b, env, it) {
          VI32(n) => n
          _ => fail("add operand is not Int")
        }),
      )
    Sub(a, b) =>
      VI32(
        (match eval(a, env, it) {
          VI32(n) => n
          _ => fail("sub operand is not Int")
        }) -
        (match eval(b, env, it) {
          VI32(n) => n
          _ => fail("sub operand is not Int")
        }),
      )
    Mul(a, b) =>
      VI32(
        (match eval(a, env, it) {
          VI32(n) => n
          _ => fail("mul operand is not Int")
        }) *
        (match eval(b, env, it) {
          VI32(n) => n
          _ => fail("mul operand is not Int")
        }),
      )
    Lt(a, b) =>
      VBool(
        (match eval(a, env, it) {
          VI32(n) => n
          _ => fail("lt operand is not Int")
        }) <
        (match eval(b, env, it) {
          VI32(n) => n
          _ => fail("lt operand is not Int")
        }),
      )
    Eq(a, b) =>
      match (eval(a, env, it), eval(b, env, it)) {
        (VI32(x), VI32(y)) => VBool(x == y)
        (VBool(x), VBool(y)) => VBool(x == y)
        _ => fail("eq supports Int/Bool only")
      }
    If(c, a, b) =>
      match eval(c, env, it) {
        VBool(true) => eval(a, env, it)
        VBool(false) => eval(b, env, it)
        _ => fail("if condition is not Bool")
      }
    Call(name, args) => call(name, args, env, it)
    ArrayLit(items) => {
      let out : Array[Int32] = []
      for item in items {
        match eval(item, env, it) {
          VI32(n) => out.push(n)
          _ => fail("array item is not Int")
        }
      }
      VArray(out)
    }
    Index(a, i) => {
      let arr = match eval(a, env, it) {
        VArray(x) => x
        _ => fail("index target is not Array[Int]")
      }
      let idx = match eval(i, env, it) {
        VI32(x) => x
        _ => fail("index is not Int")
      }
      if idx < 0 || idx >= arr.length() {
        fail("array index out of bounds")
      }
      VI32(arr[idx])
    }
    Len(a) =>
      match eval(a, env, it) {
        VArray(x) => VI32(x.length())
        _ => fail("len target is not Array[Int]")
      }
  }
}

///|
fn call(
  name : String,
  args : Array[Expr],
  caller : Map[String, Value],
  it : Interp,
) -> Value raise Failure {
  let f = match it.funcs.get(name) {
    Some(f) => f
    None => fail("unknown runtime function: " + name)
  }
  let env : Map[String, Value] = Map([])
  for i, arg in args {
    let (pname, _) = f.params[i]
    env.set(pname, eval(arg, caller, it))
  }
  match exec_block(f.body, env, it) {
    Normal => VUnit
    Returned(v) => v
  }
}

///|
fn exec_block(
  stmts : Array[Stmt],
  env : Map[String, Value],
  it : Interp,
) -> Outcome raise Failure {
  for stmt in stmts {
    match stmt {
      Let(name, _, e, _) => env.set(name, eval(e, env, it))
      Assign(name, e) => env.set(name, eval(e, env, it))
      ArraySet(name, i, v) => {
        let arr = match env.get(name) {
          Some(VArray(a)) => a
          _ => fail("array assignment target is not Array[Int]")
        }
        let idx = match eval(i, env, it) {
          VI32(x) => x
          _ => fail("array index is not Int")
        }
        if idx < 0 || idx >= arr.length() {
          fail("array index out of bounds")
        }
        arr[idx] = match eval(v, env, it) {
          VI32(x) => x
          _ => fail("array value is not Int")
        }
      }
      Emit(site, e) => {
        let v = eval(e, env, it)
        it.events.push("Emit(" + site.to_string() + ", " + show_value(v) + ")")
      }
      If(c, a, b) =>
        match eval(c, env, it) {
          VBool(true) => {
            let o = exec_block(a, env, it)
            if o is Returned(_) {
              return o
            }
          }
          VBool(false) => {
            let o = exec_block(b, env, it)
            if o is Returned(_) {
              return o
            }
          }
          _ => fail("if condition is not Bool")
        }
      While(c, body, bound) => {
        let mut n = 0
        while n < bound {
          match eval(c, env, it) {
            VBool(true) => {
              n += 1
              let o = exec_block(body, env, it)
              if o is Returned(_) {
                return o
              }
            }
            VBool(false) => break
            _ => fail("while condition is not Bool")
          }
        }
      }
      Return(e) => return Returned(eval(e, env, it))
    }
  }
  Normal
}

///|
pub fn run(program : Program, fuel : Int32) -> Array[String] raise Failure {
  check_program(program)
  let funcs = func_map(program)
  let main = match funcs.get("main") {
    Some(f) => f
    None => fail("no main")
  }
  let it : Interp = { funcs, events: [], fuel, }
  ignore(exec_block(main.body, Map([]), it))
  it.events
}
