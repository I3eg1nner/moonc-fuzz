///|
/// One axis of the async feature matrix: the shape of the callback that the
/// suspending function calls after (or around) a suspension point.
#derive(Eq)
pub(all) enum CallbackShape {
  Opt // (Int) -> T?
  OptRaise // (Int) -> T? raise
  OptRaiseOpt // (Int) -> T? raise?
  Plain // (Int) -> T
  Unit // () -> Unit
}

///|
/// Where a suspension point is placed relative to the loop / callback.
#derive(Eq)
pub(all) enum Suspension {
  SuspNone
  SuspBefore
  SuspInside
  SuspAfter
}

///|
/// Control-flow skeleton between the suspension and the callback call.
#derive(Eq)
pub(all) enum Control {
  CtrlStraight
  CtrlFor
  CtrlWhile
  CtrlBreak
  CtrlContinue
  CtrlEarlyReturn
  CtrlTryCatch
  CtrlNested
}

///|
/// Whether `T` is a type parameter or the concrete `Int`.
#derive(Eq)
pub(all) enum TypeMode {
  TyGeneric
  TyConcrete
}

///|
/// Whether the case is emitted as an exported async function exercised by an
/// async test, or as an async test containing the whole scenario.
#derive(Eq)
pub(all) enum Entry {
  EntryFn
  EntryTest
}

///|
/// A fully materialised matrix row.  `id` is derived only from the ordinal and
/// the axis values, so enumeration is deterministic and reproducible.
pub(all) struct Case {
  id : String
  shape : CallbackShape
  suspension : Suspension
  control : Control
  ty : TypeMode
  entry : Entry
  f8_control : Bool
}

///|
pub fn shape_slug(shape : CallbackShape) -> String {
  match shape {
    Opt => "opt"
    OptRaise => "optraise"
    OptRaiseOpt => "optraiseopt"
    Plain => "plain"
    Unit => "unit"
  }
}

///|
pub fn suspension_slug(s : Suspension) -> String {
  match s {
    SuspNone => "np"
    SuspBefore => "bef"
    SuspInside => "in"
    SuspAfter => "aft"
  }
}

///|
pub fn control_slug(c : Control) -> String {
  match c {
    CtrlStraight => "straight"
    CtrlFor => "for"
    CtrlWhile => "while"
    CtrlBreak => "break"
    CtrlContinue => "continue"
    CtrlEarlyReturn => "earlyret"
    CtrlTryCatch => "try"
    CtrlNested => "nested"
  }
}

///|
pub fn ty_slug(t : TypeMode) -> String {
  match t {
    TyGeneric => "g"
    TyConcrete => "c"
  }
}

///|
pub fn entry_slug(e : Entry) -> String {
  match e {
    EntryFn => "fn"
    EntryTest => "test"
  }
}

///|
fn pad3(n : Int32) -> String {
  if n < 10 {
    "00" + n.to_string()
  } else if n < 100 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
/// Deterministic ID.  The ordinal keeps IDs unique even if two axis tuples
/// ever look alike; the axis slugs make failures readable in JSONL.
pub fn case_id(
  index : Int32,
  shape : CallbackShape,
  suspension : Suspension,
  control : Control,
  ty : TypeMode,
  entry : Entry,
) -> String {
  "c" +
  pad3(index) +
  "-" +
  shape_slug(shape) +
  "-" +
  suspension_slug(suspension) +
  "-" +
  control_slug(control) +
  "-" +
  ty_slug(ty) +
  "-" +
  entry_slug(entry)
}

///|
fn add(
  out : Array[Case],
  shape : CallbackShape,
  suspension : Suspension,
  control : Control,
  ty : TypeMode,
  entry : Entry,
) -> Unit {
  let index = out.length()
  let ty = if shape == Unit { TyConcrete } else { ty }
  out.push({
    id: case_id(index, shape, suspension, control, ty, entry),
    shape,
    suspension,
    control,
    ty,
    entry,
    f8_control: false,
  })
}

///|
/// Curated matrix (~80 cases).  It is deliberately not a full Cartesian
/// product: loops get all three suspension positions, straight-line and
/// special control flow get the positions that are meaningful for them.
pub fn matrix() -> Array[Case] {
  let out : Array[Case] = []
  // Straight-line baseline for every callback shape.
  add(out, Opt, SuspNone, CtrlStraight, TyGeneric, EntryFn)
  add(out, OptRaise, SuspNone, CtrlStraight, TyGeneric, EntryFn)
  add(out, OptRaiseOpt, SuspNone, CtrlStraight, TyGeneric, EntryFn)
  add(out, Plain, SuspNone, CtrlStraight, TyGeneric, EntryFn)
  add(out, Unit, SuspNone, CtrlStraight, TyConcrete, EntryFn)
  add(out, Opt, SuspNone, CtrlStraight, TyConcrete, EntryFn)
  add(out, OptRaiseOpt, SuspNone, CtrlStraight, TyConcrete, EntryFn)
  add(out, Plain, SuspNone, CtrlStraight, TyConcrete, EntryFn)
  // Test-only entry points.
  for shape in [Opt, OptRaise, OptRaiseOpt, Plain, Unit] {
    add(out, shape, SuspNone, CtrlStraight, TyConcrete, EntryTest)
  }
  // Loop suite: for/while/break/continue × before/inside/after the loop.
  let loops = [CtrlFor, CtrlWhile, CtrlBreak, CtrlContinue]
  let susps = [SuspBefore, SuspInside, SuspAfter]
  let shapes = [Opt, OptRaise, OptRaiseOpt, Plain, Unit]
  for shape in shapes {
    for li, control in loops {
      for si, susp in susps {
        let ty = if (li + si) % 2 == 0 { TyConcrete } else { TyGeneric }
        add(out, shape, susp, control, ty, EntryFn)
      }
    }
  }
  // Early return: option-returning shapes can return the first result.
  add(out, Opt, SuspNone, CtrlEarlyReturn, TyGeneric, EntryFn)
  add(out, OptRaiseOpt, SuspNone, CtrlEarlyReturn, TyGeneric, EntryFn)
  add(out, Unit, SuspNone, CtrlEarlyReturn, TyConcrete, EntryFn)
  // try/catch around a raising callback.
  add(out, OptRaise, SuspNone, CtrlTryCatch, TyGeneric, EntryFn)
  add(out, OptRaise, SuspNone, CtrlTryCatch, TyConcrete, EntryFn)
  // Nested async call after a suspension.
  add(out, Opt, SuspBefore, CtrlNested, TyGeneric, EntryFn)
  add(out, OptRaiseOpt, SuspBefore, CtrlNested, TyGeneric, EntryFn)
  add(out, Unit, SuspBefore, CtrlNested, TyConcrete, EntryFn)
  // Known-positive F8 control: exact POC shape, flagged so the driver reports
  // it separately from searched cases.
  let index = out.length()
  out.push({
    id: case_id(
      index,
      OptRaiseOpt,
      SuspBefore,
      CtrlStraight,
      TyGeneric,
      EntryFn,
    ),
    shape: OptRaiseOpt,
    suspension: SuspBefore,
    control: CtrlStraight,
    ty: TyGeneric,
    entry: EntryFn,
    f8_control: true,
  })
  out
}

///|
/// First `limit` cases of the deterministic matrix.
pub fn select_cases(limit : Int32) -> Array[Case] {
  let all = matrix()
  let n = if limit <= 0 || limit > all.length() { all.length() } else { limit }
  let out : Array[Case] = []
  for i in 0..<n {
    out.push(all[i])
  }
  out
}
