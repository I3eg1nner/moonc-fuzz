///|
/// Feature-directed layout generator.
///
/// This is deliberately *not* a byte mutator.  A `LayoutCase` names a small,
/// valid MoonBit aggregate and one array operation; `render_package` emits a
/// complete compilable package.  The curated matrix is fixed, so runs are
/// reproducible and a candidate can be reduced by moving one axis.
///
/// The generated package has this shape:
///
///   moon.mod / moon.pkg / lib.mbt / main.mbt / main_test.mbt
///
/// `lib.mbt` defines `Entry`, `entry`, `score`, `collect` and
/// `pub fn checksum() -> Int64`.  Both `main.mbt` and the blackbox test call
/// `checksum`, so `moon test --target native --build-only` must produce and
/// link a test driver rather than only type-checking the library.

///|
/// The small field alphabet.  Enum payloads are intentionally different:
/// `EnumStringT` is the F7 shape; `EnumArrayIntT` is its array-payload sibling.
pub(all) enum FieldType {
  IntT
  Int64T
  BoolT
  StringT
  ArrayIntT
  EnumStringT
  EnumArrayIntT
}

///|
pub fn field_tag(t : FieldType) -> String {
  match t {
    IntT => "int"
    Int64T => "int64"
    BoolT => "bool"
    StringT => "string"
    ArrayIntT => "array_int"
    EnumStringT => "enum_string"
    EnumArrayIntT => "enum_array_int"
  }
}

///|
/// MoonBit source spelling for a field type.
pub fn field_type_src(t : FieldType) -> String {
  match t {
    IntT => "Int"
    Int64T => "Int64"
    BoolT => "Bool"
    StringT => "String"
    ArrayIntT => "Array[Int]"
    EnumStringT => "Kind"
    EnumArrayIntT => "Bag"
  }
}

///|
pub(all) struct FieldSpec {
  name : String
  ty : FieldType
}

///|
/// The array operation under test.  `push`/`makei`/`map` all reach an
/// uninitialized aggregate array path in the native backend; `filter` and
/// `slice` are controls that build arrays through other routes.
pub(all) enum LayoutOp {
  Push
  Makei
  Map
  Filter
  Slice
}

///|
pub fn op_tag(op : LayoutOp) -> String {
  match op {
    Push => "push"
    Makei => "makei"
    Map => "map"
    Filter => "filter"
    Slice => "slice"
  }
}

///|
pub(all) struct LayoutCase {
  /// Stable, human-readable ID; also the on-disk case directory name.
  id : String
  /// Position in the deterministic enumeration (0-based).
  index : Int32
  /// `#valtype` on the generated `Entry` struct.
  valtype : Bool
  fields : Array[FieldSpec]
  op : LayoutOp
  /// Index of the curated field suite, for feature reporting.
  suite : Int32
}

///|
pub(all) struct RenderedPackage {
  moon_mod : String
  moon_pkg : String
  lib_mbt : String
  main_mbt : String
  main_test_mbt : String
}

///|
fn suite(types : Array[FieldType]) -> Array[FieldType] {
  types
}

///|
/// Curated field suites: 0, 1, 2, 3 and 4 fields.  They are chosen for layout
/// diversity, not sampled from a cross product.  Suite 8 is the F7 shape
/// (`Int` + enum with a `String` payload).
pub fn field_suites() -> Array[Array[FieldType]] {
  [
    suite([]),
    suite([IntT]),
    suite([Int64T]),
    suite([BoolT]),
    suite([StringT]),
    suite([ArrayIntT]),
    suite([EnumStringT]),
    suite([EnumArrayIntT]),
    suite([IntT, EnumStringT]),
    suite([IntT, EnumArrayIntT]),
    suite([IntT, StringT]),
    suite([Int64T, BoolT]),
    suite([StringT, ArrayIntT]),
    suite([IntT, BoolT, StringT]),
    suite([Int64T, EnumStringT, ArrayIntT]),
    suite([IntT, BoolT, EnumArrayIntT, StringT]),
  ]
}

///|
pub fn ops() -> Array[LayoutOp] {
  [Push, Makei, Map, Filter, Slice]
}

///|
fn pad4(n : Int32) -> String {
  let s = n.to_string()
  let mut pad = ""
  let mut k = s.length()
  while k < 4 {
    pad = pad + "0"
    k += 1
  }
  pad + s
}

///|
fn make_fields(types : Array[FieldType]) -> Array[FieldSpec] {
  let out : Array[FieldSpec] = []
  for i, ty in types {
    out.push({ name: "f" + i.to_string(), ty, })
  }
  out
}

///|
fn suite_tag(types : Array[FieldType]) -> String {
  if types.length() == 0 {
    return "none"
  }
  let mut s = ""
  for i, t in types {
    if i > 0 {
      s = s + "_"
    }
    s = s + field_tag(t)
  }
  s
}

///|
/// Deterministic enumeration.  Axis order is suite -> valtype -> operation, so
/// the first occurrence of a signature is also the smallest field suite that
/// triggers it.  Size: 16 suites * 2 valtype settings * 5 operations = 160.
pub fn layout_cases() -> Array[LayoutCase] {
  let out : Array[LayoutCase] = []
  let suites = field_suites()
  let all_ops = ops()
  let mut index = 0
  for si, types in suites {
    for valtype in [true, false] {
      for op in all_ops {
        let id = "L" +
          pad4(index) +
          "-" +
          (if valtype { "vt" } else { "plain" }) +
          "-" +
          op_tag(op) +
          "-" +
          suite_tag(types)
        out.push({
          id,
          index,
          valtype,
          fields: make_fields(types),
          op,
          suite: si,
        })
        index += 1
      }
    }
  }
  out
}

///|
/// Exact curated matrix size.
pub fn matrix_size() -> Int32 {
  field_suites().length() * 2 * ops().length()
}

///|
fn has_field_type(fields : Array[FieldSpec], t : FieldType) -> Bool {
  let tag = field_tag(t)
  for f in fields {
    if field_tag(f.ty) == tag {
      return true
    }
  }
  false
}

///|
/// The built-in F7 seed: `#valtype`, `Int` + enum-with-String-payload, `push`.
pub fn f7_seed() -> LayoutCase {
  for c in layout_cases() {
    if c.valtype &&
      c.op is Push &&
      c.fields.length() == 2 &&
      c.fields[0].ty is IntT &&
      c.fields[1].ty is EnumStringT {
      return c
    }
  }
  abort("featuregen: F7 seed missing from matrix")
}

///|
/// Known-good control for the F7 seed: same fields and operation without
/// `#valtype`.
pub fn f7_control() -> LayoutCase {
  for c in layout_cases() {
    if !c.valtype &&
      c.op is Push &&
      c.fields.length() == 2 &&
      c.fields[0].ty is IntT &&
      c.fields[1].ty is EnumStringT {
      return c
    }
  }
  abort("featuregen: F7 control missing from matrix")
}

///|
fn write_line(b : StringBuilder, s : String) -> Unit {
  b.write_string(s)
  b.write_char('\n')
}

///|
/// Per-field constructor for logical element `i`.
fn field_ctor(f : FieldSpec, i : String) -> String {
  match f.ty {
    IntT => i + " * 3 + 1"
    Int64T => "(" + i + " * 3 + 2).to_int64()"
    BoolT => i + " % 2 == 0"
    StringT => "\"s\" + " + i + ".to_string()"
    ArrayIntT => "[" + i + ", " + i + " + 1]"
    EnumStringT => "Kind::Ref(\"k\" + " + i + ".to_string())"
    EnumArrayIntT => "Bag::Ref([" + i + ", " + i + " + 2])"
  }
}

///|
/// Per-field score expression, mirroring `field_score_value` below.
fn field_score_expr(f : FieldSpec) -> String {
  let v = "e." + f.name
  match f.ty {
    IntT => v
    Int64T => v + ".to_int()"
    BoolT => "(if " + v + " { 3 } else { 5 })"
    StringT => v + ".length()"
    ArrayIntT =>
      "(" +
      v +
      ".length() * 11 + (if " +
      v +
      ".length() > 0 { " +
      v +
      "[0] } else { 0 }))"
    EnumStringT => "(match " + v + " { Kind::Ref(s) => s.length() + 17 })"
    EnumArrayIntT => "(match " + v + " { Bag::Ref(a) => a.length() + 19 })"
  }
}

///|
fn collect_body(c : LayoutCase) -> String {
  match c.op {
    Push =>
      "  let xs : Array[Entry] = []\n" +
      "  for i in 0..<4 {\n" +
      "    xs.push(entry(i))\n" +
      "  }\n" +
      "  xs\n"
    Makei => "  Array::makei(4, fn(i) { entry(i) })\n"
    Map =>
      "  let base : Array[Int] = [0, 1, 2, 3]\n" +
      "  base.map(fn(i) { entry(i) })\n"
    Filter =>
      "  let all : Array[Entry] = []\n" +
      "  for i in 0..<5 {\n" +
      "    all.push(entry(i))\n" +
      "  }\n" +
      "  all.filter(fn(e) { score(e) % 2 == 0 })\n"
    Slice =>
      "  let all : Array[Entry] = []\n" +
      "  for i in 0..<6 {\n" +
      "    all.push(entry(i))\n" +
      "  }\n" +
      "  all[1:5].to_owned()\n"
  }
}

///|
fn render_lib(c : LayoutCase) -> String {
  let b = StringBuilder()
  if has_field_type(c.fields, EnumStringT) {
    write_line(b, "enum Kind {")
    write_line(b, "  Ref(String)")
    write_line(b, "}")
    write_line(b, "")
  }
  if has_field_type(c.fields, EnumArrayIntT) {
    write_line(b, "enum Bag {")
    write_line(b, "  Ref(Array[Int])")
    write_line(b, "}")
    write_line(b, "")
  }
  if c.valtype {
    write_line(b, "#valtype")
  }
  write_line(b, "struct Entry {")
  for f in c.fields {
    write_line(b, "  " + f.name + " : " + field_type_src(f.ty))
  }
  write_line(b, "}")
  write_line(b, "")
  if c.fields.length() == 0 {
    write_line(b, "fn entry(i : Int) -> Entry {")
    write_line(b, "  let _ = i")
    write_line(b, "  Entry::{ }")
    write_line(b, "}")
  } else {
    write_line(b, "fn entry(i : Int) -> Entry {")
    let mut line = "  { "
    for j, f in c.fields {
      if j > 0 {
        line = line + ", "
      }
      line = line + f.name + ": " + field_ctor(f, "i")
    }
    line = line + " }"
    write_line(b, line)
    write_line(b, "}")
  }
  write_line(b, "")
  write_line(b, "fn score(e : Entry) -> Int {")
  if c.fields.length() == 0 {
    write_line(b, "  let _ = e")
    write_line(b, "  0")
  } else {
    write_line(b, "  let mut s = 0")
    for f in c.fields {
      write_line(b, "  s = s * 37 + " + field_score_expr(f))
    }
    write_line(b, "  s")
  }
  write_line(b, "}")
  write_line(b, "")
  write_line(b, "fn collect() -> Array[Entry] {")
  b.write_string(collect_body(c))
  write_line(b, "}")
  write_line(b, "")
  write_line(b, "pub fn checksum() -> Int64 {")
  write_line(b, "  let xs = collect()")
  write_line(b, "  let mut h : Int64 = 7L")
  write_line(b, "  for e in xs {")
  write_line(b, "    h = h * 131L + score(e).to_int64()")
  write_line(b, "  }")
  write_line(b, "  h")
  write_line(b, "}")
  b.to_string()
}

///|
/// Render the complete package.  Pure function: same case -> byte-identical
/// files, which makes the deterministic-ID/renderer tests meaningful.
pub fn render_package(c : LayoutCase) -> RenderedPackage {
  {
    moon_mod: "name = \"featfuzz/generated\"\n\nversion = \"0.1.0\"\n",
    moon_pkg: "pkgtype(kind: \"executable\")\n",
    lib_mbt: render_lib(c),
    main_mbt: "fn main {\n  println(checksum())\n}\n",
    main_test_mbt: "test \"checksum is deterministic\" {\n" +
    "  let a = @generated.checksum()\n" +
    "  let b = @generated.checksum()\n" +
    "  assert_eq(a, b)\n" +
    "  assert_eq(a, " +
    expected_checksum(c).to_string() +
    "L)\n" +
    "}\n",
  }
}

///|
fn digits(n : Int32) -> Int32 {
  let s = n.to_string()
  s.length()
}

///|
fn field_score_value(t : FieldType, i : Int32) -> Int32 {
  match t {
    IntT => i * 3 + 1
    Int64T => i * 3 + 2
    BoolT => if i % 2 == 0 { 3 } else { 5 }
    StringT => 1 + digits(i)
    ArrayIntT => 22 + i
    EnumStringT => 18 + digits(i)
    EnumArrayIntT => 21
  }
}

///|
fn entry_score(c : LayoutCase, i : Int32) -> Int32 {
  let mut s = 0
  for f in c.fields {
    s = s * 37 + field_score_value(f.ty, i)
  }
  s
}

///|
/// Independent evaluation of the generated checksum.  Kept in lockstep with
/// `render_lib`; the generated test asserts this constant and the unit tests
/// cover the zero-field value.
pub fn expected_checksum(c : LayoutCase) -> Int64 {
  let mut h : Int64 = 7L
  match c.op {
    Push | Makei | Map =>
      for i in 0..<4 {
        h = h * 131L + entry_score(c, i).to_int64()
      }
    Filter =>
      for i in 0..<5 {
        let s = entry_score(c, i)
        if s % 2 == 0 {
          h = h * 131L + s.to_int64()
        }
      }
    Slice =>
      for i in 1..<5 {
        h = h * 131L + entry_score(c, i).to_int64()
      }
  }
  h
}

///|
/// `features` object for the JSONL record (sans braces).
pub fn features_json(c : LayoutCase) -> String {
  let mut types = ""
  for i, f in c.fields {
    if i > 0 {
      types = types + ","
    }
    types = types + "\"" + field_tag(f.ty) + "\""
  }
  "\"valtype\":" +
  (if c.valtype { "true" } else { "false" }) +
  ",\"fields\":[" +
  types +
  "],\"op\":\"" +
  op_tag(c.op) +
  "\",\"suite\":" +
  c.suite.to_string()
}
