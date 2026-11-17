///|
/// String rendering for a complete generated MoonBit package.  The renderer is
/// pure: no filesystem, no process, no clock, so tests can compare exact text.

///|
pub fn t_text(c : Case) -> String {
  match c.ty {
    TyGeneric => "T"
    TyConcrete => "Int"
  }
}

///|
pub fn is_option_shape(shape : CallbackShape) -> Bool {
  match shape {
    Opt | OptRaise | OptRaiseOpt => true
    Plain | Unit => false
  }
}

///|
pub fn param_type(c : Case) -> String {
  let t = t_text(c)
  match c.shape {
    Opt => "(Int) -> " + t + "?"
    OptRaise => "(Int) -> " + t + "? raise"
    OptRaiseOpt => "(Int) -> " + t + "? raise?"
    Plain => "(Int) -> " + t
    Unit => "() -> Unit"
  }
}

///|
pub fn return_type(c : Case) -> String {
  match c.shape {
    Opt | OptRaise | OptRaiseOpt => t_text(c) + "?"
    Plain => t_text(c)
    Unit => "Unit"
  }
}

///|
pub fn raise_suffix(c : Case) -> String {
  match c.shape {
    OptRaise => " raise"
    _ => ""
  }
}

///|
fn generic_suffix(c : Case) -> String {
  match c.ty {
    TyGeneric => "[T]"
    TyConcrete => ""
  }
}

///|
fn pause_line() -> String {
  "  @aio.pause()\n"
}

///|
fn call_expr(c : Case, arg : String) -> String {
  match c.shape {
    Unit => "select()"
    _ => "select(" + arg + ")"
  }
}

///|
fn render_straight(c : Case) -> String {
  let sb = StringBuilder()
  match c.suspension {
    SuspBefore => sb.write_string(pause_line())
    _ => ()
  }
  if c.f8_control && c.control == CtrlStraight {
    sb.write_string("  select(1)\n")
    return sb.to_string()
  }
  if c.shape == Unit {
    sb.write_string("  " + call_expr(c, "1") + "\n")
    match c.suspension {
      SuspAfter => sb.write_string(pause_line())
      _ => ()
    }
    sb.write_string("  ()\n")
  } else {
    sb.write_string("  let r = " + call_expr(c, "1") + "\n")
    match c.suspension {
      SuspAfter => sb.write_string(pause_line())
      _ => ()
    }
    sb.write_string("  r\n")
  }
  sb.to_string()
}

///|
fn accumulator_decl(c : Case) -> String {
  if c.shape == Unit {
    ""
  } else if c.shape == Plain {
    "  let mut last : " + t_text(c) + " = select(0)\n"
  } else {
    "  let mut last : " + t_text(c) + "? = None\n"
  }
}

///|
fn call_assign(c : Case, arg : String, indent : String) -> String {
  if c.shape == Unit {
    indent + "select()\n"
  } else {
    indent + "last = select(" + arg + ")\n"
  }
}

///|
fn loop_result(c : Case, indent : String) -> String {
  if c.shape == Unit {
    indent + "()\n"
  } else {
    indent + "last\n"
  }
}

///|
fn render_loop(c : Case) -> String {
  let sb = StringBuilder()
  if c.suspension == SuspBefore {
    sb.write_string(pause_line())
  }
  sb.write_string(accumulator_decl(c))
  let inside = if c.suspension == SuspInside {
    "    @aio.pause()\n"
  } else {
    ""
  }
  match c.control {
    CtrlWhile => {
      sb.write_string("  let mut i = 0\n")
      sb.write_string("  while i < 2 {\n")
      sb.write_string(inside)
      sb.write_string(call_assign(c, "i", "    "))
      sb.write_string("    i = i + 1\n")
      sb.write_string("  }\n")
    }
    CtrlBreak => {
      sb.write_string("  for i in 0..<3 {\n")
      sb.write_string(inside)
      sb.write_string(call_assign(c, "i", "    "))
      sb.write_string("    break\n")
      sb.write_string("  }\n")
    }
    CtrlContinue => {
      sb.write_string("  for i in 0..<3 {\n")
      sb.write_string(inside)
      sb.write_string("    if i == 0 {\n")
      sb.write_string("      continue\n")
      sb.write_string("    }\n")
      sb.write_string(call_assign(c, "i", "    "))
      sb.write_string("  }\n")
    }
    _ => {
      sb.write_string("  for i in 0..<2 {\n")
      sb.write_string(inside)
      sb.write_string(call_assign(c, "i", "    "))
      sb.write_string("  }\n")
    }
  }
  if c.suspension == SuspAfter {
    sb.write_string(pause_line())
  }
  sb.write_string(loop_result(c, "  "))
  sb.to_string()
}

///|
fn render_early_return(c : Case) -> String {
  match c.shape {
    Unit => "  select()\n  return ()\n"
    _ => {
      let sb = StringBuilder()
      sb.write_string("  let first = select(0)\n")
      sb.write_string("  if first is Some(_) {\n")
      sb.write_string("    return first\n")
      sb.write_string("  }\n")
      sb.write_string("  select(1)\n")
      sb.to_string()
    }
  }
}

///|
fn render_try_catch(c : Case) -> String {
  let sb = StringBuilder()
  sb.write_string("  try {\n")
  sb.write_string("    " + call_expr(c, "1") + "\n")
  sb.write_string("  } catch {\n")
  if is_option_shape(c.shape) {
    sb.write_string("    _ => None\n")
  } else {
    sb.write_string("    _ => ()\n")
  }
  sb.write_string("  }\n")
  sb.to_string()
}

///|
fn render_nested_body(c : Case) -> String {
  let sb = StringBuilder()
  if c.suspension == SuspBefore {
    sb.write_string(pause_line())
  }
  sb.write_string("  nested_call(select)\n")
  sb.to_string()
}

///|
pub fn render_body(c : Case) -> String {
  match c.control {
    CtrlStraight => render_straight(c)
    CtrlFor | CtrlWhile | CtrlBreak | CtrlContinue => render_loop(c)
    CtrlEarlyReturn => render_early_return(c)
    CtrlTryCatch => render_try_catch(c)
    CtrlNested => render_nested_body(c)
  }
}

///|
fn fn_decl(c : Case) -> String {
  "///|\npub async fn" +
  generic_suffix(c) +
  " pick(select : " +
  param_type(c) +
  ") -> " +
  return_type(c) +
  raise_suffix(c) +
  " {\n" +
  render_body(c) +
  "}\n"
}

///|
fn nested_decl(c : Case) -> String {
  "///|\nasync fn" +
  generic_suffix(c) +
  " nested_call(select : " +
  param_type(c) +
  ") -> " +
  return_type(c) +
  raise_suffix(c) +
  " {\n" +
  "  " +
  call_expr(c, "1") +
  "\n" +
  "}\n"
}

///|
pub fn render_lib(c : Case) -> String {
  match c.entry {
    EntryTest =>
      "///|\n/// Test-only case: the scenario is rendered directly in lib_test.mbt.\npub fn marker() -> Unit {\n  ()\n}\n"
    EntryFn => {
      let sb = StringBuilder()
      if c.control == CtrlNested {
        sb.write_string(nested_decl(c))
        sb.write_string("\n")
      }
      sb.write_string(fn_decl(c))
      sb.to_string()
    }
  }
}

///|
fn expected_index(c : Case) -> Int32 {
  match c.control {
    CtrlBreak | CtrlEarlyReturn => 0
    // `continue` skips i = 0, so the last callback sees i = 2.
    CtrlContinue => 2
    _ => 1
  }
}

///|
fn option_callback(c : Case) -> String {
  if c.f8_control {
    "x => if x == 1 { Some(x) } else { None }"
  } else {
    "x => Some(x)"
  }
}

///|
fn test_invoke(c : Case) -> String {
  let sb = StringBuilder()
  match c.shape {
    Opt | OptRaiseOpt => {
      sb.write_string("  let r = @lib.pick(" + option_callback(c) + ")\n")
      sb.write_string(
        "  assert_eq(r, Some(" + expected_index(c).to_string() + "))\n",
      )
    }
    OptRaise => {
      sb.write_string("  let r = try {\n")
      sb.write_string("    @lib.pick(" + option_callback(c) + ")\n")
      sb.write_string("  } catch {\n")
      sb.write_string("    _ => None\n")
      sb.write_string("  }\n")
      sb.write_string(
        "  assert_eq(r, Some(" + expected_index(c).to_string() + "))\n",
      )
    }
    Plain => {
      sb.write_string("  let r = @lib.pick(x => x + 1)\n")
      let expected = match c.control {
        CtrlBreak => 1
        // Plain callbacks add one; `continue` leaves i = 2.
        CtrlContinue => 3
        _ => 2
      }
      sb.write_string("  assert_eq(r, " + expected.to_string() + ")\n")
    }
    Unit => sb.write_string("  @lib.pick(() => ())\n")
  }
  sb.to_string()
}

///|
fn test_only_body(c : Case) -> String {
  let sb = StringBuilder()
  match c.shape {
    Unit => {
      sb.write_string("  let select : () -> Unit = () => ()\n")
      sb.write_string(pause_line())
      sb.write_string("  select()\n")
    }
    Plain => {
      sb.write_string("  let select : (Int) -> Int = x => x + 1\n")
      sb.write_string(pause_line())
      sb.write_string("  assert_eq(select(1), 2)\n")
    }
    OptRaiseOpt | Opt => {
      sb.write_string("  let select : (Int) -> Int? = x => Some(x)\n")
      sb.write_string(pause_line())
      sb.write_string("  assert_eq(select(1), Some(1))\n")
    }
    OptRaise => {
      sb.write_string("  let select : (Int) -> Int? raise = x => Some(x)\n")
      sb.write_string(pause_line())
      sb.write_string("  let r = try {\n")
      sb.write_string("    select(1)\n")
      sb.write_string("  } catch {\n")
      sb.write_string("    _ => None\n")
      sb.write_string("  }\n")
      sb.write_string("  assert_eq(r, Some(1))\n")
    }
  }
  sb.to_string()
}

///|
pub fn render_test(c : Case) -> String {
  let body = match c.entry {
    EntryTest => test_only_body(c)
    EntryFn => test_invoke(c)
  }
  "///|\nasync test \"" + c.id + "\" {\n" + body + "}\n"
}

///|
pub fn render_mod(c : Case) -> String {
  "name = \"asyncfuzz/" +
  c.id +
  "\"\nversion = \"0.0.1\"\n\nimport {\n  \"moonbitlang/async@0.22.9\",\n}\n"
}

///|
pub fn render_pkg() -> String {
  "import {\n  \"moonbitlang/async\" @aio,\n}\n\nsupported_targets = \"wasm+js+native\"\n"
}

///|
/// `(relative path, content)` for one complete generated module.  `moon.mod`
/// lives at the module root; the MoonBit package is `lib/` so blackbox tests
/// refer to it as `@lib`.
pub fn render_package(c : Case) -> Array[(String, String)] {
  [
    ("moon.mod", render_mod(c)),
    ("lib/moon.pkg", render_pkg()),
    ("lib/lib.mbt", render_lib(c)),
    ("lib/lib_test.mbt", render_test(c)),
  ]
}
