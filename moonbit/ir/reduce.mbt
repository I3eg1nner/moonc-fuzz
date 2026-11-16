///|
/// Statement-level reduction for the small IR.  The predicate is deliberately
/// explicit and conservative: the reduced program must typecheck, the
/// interpreter must succeed, and the complete event sequence must be identical.
/// This is a trace-preserving reducer, not yet a compiler-difference reducer.

///|
fn events_equal(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, x in a {
    if x != b[i] {
      return false
    }
  }
  true
}

///|
fn main_body(program : Program) -> Array[Stmt] raise Failure {
  for f in program.funcs {
    if f.name == "main" {
      return f.body
    }
  }
  fail("no main")
}

///|
fn with_main_body(program : Program, body : Array[Stmt]) -> Program {
  let funcs : Array[Func] = []
  for f in program.funcs {
    if f.name == "main" {
      funcs.push({ ..f, body, })
    } else {
      funcs.push(f)
    }
  }
  { funcs, }
}

///|
fn without_stmt(body : Array[Stmt], index : Int32) -> Array[Stmt] {
  let out : Array[Stmt] = []
  for i, s in body {
    if i != index {
      out.push(s)
    }
  }
  out
}

///|
fn try_body(
  program : Program,
  body : Array[Stmt],
  expected : Array[String],
  fuel : Int32,
) -> Bool {
  let candidate = with_main_body(program, body)
  let same = try {
    check_program(candidate)
    events_equal(run(candidate, fuel), expected)
  } catch {
    _ => false
  }
  same
}

///|
pub fn reduce(
  program : Program,
  expected : Array[String],
  fuel : Int32,
) -> Program raise Failure {
  check_program(program)
  if !events_equal(run(program, fuel), expected) {
    fail("reduce target does not match initial events")
  }
  let mut current = program
  let mut changed = true
  while changed {
    changed = false
    let body = main_body(current)
    let mut i = body.length() - 1
    while i >= 0 {
      let candidate = without_stmt(body, i)
      if try_body(current, candidate, expected, fuel) {
        current = with_main_body(current, candidate)
        changed = true
      }
      i -= 1
    }
  }
  current
}

///|
pub fn statement_count(program : Program) -> Int32 {
  let mut n = 0
  for f in program.funcs {
    for s in f.body {
      n += 1
      match s {
        If(_, a, b) => n += a.length() + b.length()
        While(_, body, _) => n += body.length()
        _ => ()
      }
    }
  }
  n
}
