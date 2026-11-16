///|
/// Emit a MoonBit program from the small typed IR.  The generated program has
/// the same explicit evaluation order as the interpreter for this subset.
/// `Emit` is printed through the value's `to_string`, and array events are not
/// part of this first emitter contract.

///|
fn expr_src(e : Expr) -> String {
  match e {
    ConstI32(n) => n.to_string()
    ConstBool(b) => b.to_string()
    Var(n) => n
    Add(a, b) => "(" + expr_src(a) + " + " + expr_src(b) + ")"
    Sub(a, b) => "(" + expr_src(a) + " - " + expr_src(b) + ")"
    Mul(a, b) => "(" + expr_src(a) + " * " + expr_src(b) + ")"
    Lt(a, b) => "(" + expr_src(a) + " < " + expr_src(b) + ")"
    Eq(a, b) => "(" + expr_src(a) + " == " + expr_src(b) + ")"
    If(c, a, b) =>
      "(if " +
      expr_src(c) +
      " { " +
      expr_src(a) +
      " } else { " +
      expr_src(b) +
      " })"
    Call(n, args) => {
      let out = StringBuilder()
      out.write_string(n)
      out.write_string("(")
      for i, a in args {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(expr_src(a))
      }
      out.write_string(")")
      out.to_string()
    }
    ArrayLit(items) => {
      let out = StringBuilder()
      out.write_string("[")
      for i, a in items {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(expr_src(a))
      }
      out.write_string("]")
      out.to_string()
    }
    Index(a, i) => "(" + expr_src(a) + ")[" + expr_src(i) + "]"
    Len(a) => "(" + expr_src(a) + ").length()"
  }
}

///|
fn indent(text : String, n : Int32) -> String {
  let b = StringBuilder()
  for _ in 0..<n {
    b.write_string("  ")
  }
  b.write_string(text)
  b.to_string()
}

///|
fn collect_assigned(s : Stmt, out : Map[String, Unit]) -> Unit {
  match s {
    Let(_, _, _, _) | Emit(_, _) | Return(_) => ()
    Assign(name, _) => out.set(name, ())
    ArraySet(_, _, _) => ()
    If(_, a, b) => {
      for st in a {
        collect_assigned(st, out)
      }
      for st in b {
        collect_assigned(st, out)
      }
    }
    While(_, body, _) =>
      for st in body {
        collect_assigned(st, out)
      }
  }
}

///|
fn assigned_in(f : Func) -> Map[String, Unit] {
  let out : Map[String, Unit] = Map([])
  for st in f.body {
    collect_assigned(st, out)
  }
  out
}

///|
fn stmt_src(s : Stmt, depth : Int32, assigned : Map[String, Unit]) -> String {
  match s {
    Let(name, ty, e, mutable) =>
      indent(
        (if mutable && ty != I32Array && assigned.contains(name) {
          "let mut "
        } else {
          "let "
        }) +
        name +
        " : " +
        ty_name(ty) +
        " = " +
        expr_src(e),
        depth,
      )
    Assign(name, e) => indent(name + " = " + expr_src(e), depth)
    ArraySet(name, i, v) =>
      indent(name + "[" + expr_src(i) + "] = " + expr_src(v), depth)
    Emit(site, e) =>
      indent(
        "println(\"Emit(" +
        site.to_string() +
        ", \" + (" +
        expr_src(e) +
        ").to_string() + \")\")",
        depth,
      )
    If(c, a, b) => {
      let out = StringBuilder()
      out.write_string(indent("if " + expr_src(c) + " {", depth))
      out.write_string("\n")
      for st in a {
        out.write_string(stmt_src(st, depth + 1, assigned))
        out.write_string("\n")
      }
      out.write_string(indent("} else {", depth))
      out.write_string("\n")
      for st in b {
        out.write_string(stmt_src(st, depth + 1, assigned))
        out.write_string("\n")
      }
      out.write_string(indent("}", depth))
      out.to_string()
    }
    While(c, body, bound) => {
      let out = StringBuilder()
      out.write_string(
        indent("for __w in 0..<" + bound.to_string() + " {", depth),
      )
      out.write_string("\n")
      out.write_string(indent("if !(" + expr_src(c) + ") { break }", depth + 1))
      out.write_string("\n")
      for st in body {
        out.write_string(stmt_src(st, depth + 1, assigned))
        out.write_string("\n")
      }
      out.write_string(indent("}", depth))
      out.to_string()
    }
    Return(e) => indent("return " + expr_src(e), depth)
  }
}

///|
fn func_src(f : Func, assigned : Map[String, Unit]) -> String {
  let b = StringBuilder()
  if f.name == "main" {
    b.write_string("fn main {\n")
  } else {
    b.write_string("fn " + f.name + "(")
    for i, p in f.params {
      let (name, ty) = p
      if i > 0 {
        b.write_string(", ")
      }
      b.write_string(name + " : " + ty_name(ty))
    }
    b.write_string(") -> " + ty_name(f.ret) + " {\n")
  }
  for st in f.body {
    b.write_string(stmt_src(st, 1, assigned))
    b.write_string("\n")
  }
  b.write_string("}\n")
  b.to_string()
}

///|
pub fn emit_program(program : Program) -> String {
  let b = StringBuilder()
  for f in program.funcs {
    b.write_string(func_src(f, assigned_in(f)))
    b.write_string("\n")
  }
  b.to_string()
}
