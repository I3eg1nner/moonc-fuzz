///|
/// One axis of the F7 trigger: the enum payload type.  `Int` is the control
/// that matters: the reported error says "uninitialized non-null GC ref
/// arrays are not lowered", so a non-GC payload should not trigger it.
pub(all) enum Payload {
  PString
  PArrayInt
  PInt
}

///|
pub fn payload_tag(p : Payload) -> String {
  match p {
    PString => "string"
    PArrayInt => "array_int"
    PInt => "int"
  }
}

///|
pub fn payload_type(p : Payload) -> String {
  match p {
    PString => "String"
    PArrayInt => "Array[Int]"
    PInt => "Int"
  }
}

///|
pub fn payload_value(p : Payload) -> String {
  match p {
    PString => "\"x\""
    PArrayInt => "[1, 2]"
    PInt => "0"
  }
}

///|
/// Where the valtype record sits: directly in an array literal, one level
/// deeper, or behind a struct field.
pub(all) enum Container {
  CArray
  CNested
  CField
}

///|
pub fn container_tag(c : Container) -> String {
  match c {
    CArray => "array"
    CNested => "nested"
    CField => "field"
  }
}

///|
pub(all) enum Build {
  BLiteral
  BPush
}

///|
pub fn build_tag(b : Build) -> String {
  match b {
    BLiteral => "literal"
    BPush => "push"
  }
}

///|
pub(all) struct ScriptCase {
  id : String
  valtype : Bool
  payload : Payload
  container : Container
  build : Build
}

///|
/// 3 payloads x 3 containers x 2 builds x {valtype, plain} = 36 cases.
/// `plain` is not a variant of the bug: it is the negative control that must
/// compile and run, which is how the harness detects a broken renderer.
pub fn cases() -> Array[ScriptCase] {
  let out : Array[ScriptCase] = []
  for valtype in [true, false] {
    for p in [PString, PArrayInt, PInt] {
      for c in [CArray, CNested, CField] {
        for b in [BLiteral, BPush] {
          let id = "S" +
            (if valtype { "vt" } else { "pl" }) +
            "-" +
            payload_tag(p) +
            "-" +
            container_tag(c) +
            "-" +
            build_tag(b)
          out.push({ id, valtype, payload: p, container: c, build: b, })
        }
      }
    }
  }
  out
}

///|
fn entry_literal(p : Payload) -> String {
  "{ id: 0, kind: Kind::Ref(" + payload_value(p) + ") }"
}

///|
pub fn render(c : ScriptCase) -> String {
  let b = StringBuilder()
  b.write_string("enum Kind {\n  Ref(")
  b.write_string(payload_type(c.payload))
  b.write_string(")\n}\n\n")
  if c.valtype {
    b.write_string("#valtype\n")
  }
  b.write_string("struct Entry {\n  id : Int\n  kind : Kind\n}\n\n")
  match (c.container, c.build) {
    (CField, _) =>
      b.write_string("struct Wrapper {\n  items : Array[Entry]\n}\n\n")
    _ => ()
  }
  b.write_string("fn main {\n")
  match (c.container, c.build) {
    (CArray, BLiteral) => {
      b.write_string("  let xs : Array[Entry] = [")
      b.write_string(entry_literal(c.payload))
      b.write_string("]\n  println(xs.length())\n")
    }
    (CArray, BPush) => {
      b.write_string("  let xs : Array[Entry] = []\n")
      b.write_string("  xs.push(")
      b.write_string(entry_literal(c.payload))
      b.write_string(")\n  println(xs.length())\n")
    }
    (CNested, BLiteral) => {
      b.write_string("  let xs : Array[Array[Entry]] = [[")
      b.write_string(entry_literal(c.payload))
      b.write_string("]]\n  println(xs.length())\n")
    }
    (CNested, BPush) => {
      b.write_string("  let xs : Array[Array[Entry]] = []\n")
      b.write_string("  let row : Array[Entry] = [")
      b.write_string(entry_literal(c.payload))
      b.write_string("]\n  xs.push(row)\n  println(xs.length())\n")
    }
    (CField, BLiteral) => {
      b.write_string("  let w : Wrapper = { items: [")
      b.write_string(entry_literal(c.payload))
      b.write_string("] }\n  println(w.items.length())\n")
    }
    (CField, BPush) => {
      b.write_string("  let w : Wrapper = { items: [] }\n")
      b.write_string("  w.items.push(")
      b.write_string(entry_literal(c.payload))
      b.write_string(")\n  println(w.items.length())\n")
    }
  }
  b.write_string("}\n")
  b.to_string()
}

///|
/// A fixed boundary probe: the exact source plus whether this pin is expected
/// to reject it with the `lower_array_make` ICE.
///
/// These are not generated variants; each one exists to separate two competing
/// explanations of the trigger, so that a future compiler change either keeps
/// the characterisation or falsifies it in a specific place.
pub(all) struct BoundaryCase {
  id : String
  src : String
  expect_defect : Bool
  why : String
}

///|
fn boundary(
  id : String,
  src : String,
  expect_defect : Bool,
  why : String,
) -> BoundaryCase {
  { id, src, expect_defect, why, }
}

///|
/// The script-mode trigger surface, one variable at a time.  Expected values
/// were measured on `moonc v0.10.20+65efd5b93`; a mismatch is either an
/// upstream fix or a change in representation, and both are worth knowing.
pub fn boundary_cases() -> Array[BoundaryCase] {
  [
    boundary(
      "b01-scalar-only", "#valtype\nstruct E {\n  id : Int\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0 })\n  println(xs.length())\n}\n",
      false, "no GC-ref field at all",
    ),
    boundary(
      "b02-string-only", "#valtype\nstruct E {\n  s : String\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ s: \"x\" })\n  println(xs.length())\n}\n",
      false, "single field: the record is represented as the field, no array layout",
    ),
    boundary(
      "b03-enum-only", "enum K {\n  A(Int)\n}\n\n#valtype\nstruct E {\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ k: K::A(0) })\n  println(xs.length())\n}\n",
      false, "same single-field collapse, so the enum alone is not enough",
    ),
    boundary(
      "b04-int-plus-enum-int-payload", "enum K {\n  A(Int)\n}\n\n#valtype\nstruct E {\n  id : Int\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, k: K::A(0) })\n  println(xs.length())\n}\n",
      true, "two fields, one payload enum: the minimal witness",
    ),
    boundary(
      "b05-string-plus-enum", "enum K {\n  A(Int)\n}\n\n#valtype\nstruct E {\n  s : String\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ s: \"x\", k: K::A(0) })\n  println(xs.length())\n}\n",
      true, "the other GC field type does not change the outcome",
    ),
    boundary(
      "b06-enum-nullary", "enum K {\n  A\n}\n\n#valtype\nstruct E {\n  id : Int\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, k: K::A })\n  println(xs.length())\n}\n",
      false, "a payload-free enum is an immediate, not a GC ref",
    ),
    boundary(
      "b07-int-bool", "#valtype\nstruct E {\n  id : Int\n  b : Bool\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, b: true })\n  println(xs.length())\n}\n",
      false, "two scalar fields: nothing to leave uninitialised",
    ),
    boundary(
      "b08-int-string", "#valtype\nstruct E {\n  id : Int\n  s : String\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, s: \"x\" })\n  println(xs.length())\n}\n",
      false, "String is a nullable ref; the message says *non-null*",
    ),
    boundary(
      "b09-two-enums", "enum K {\n  A(Int)\n}\n\n#valtype\nstruct E {\n  k : K\n  j : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ k: K::A(0), j: K::A(1) })\n  println(xs.length())\n}\n",
      true, "no scalar field needed, only a non-null GC ref and two fields",
    ),
    boundary(
      "b11-two-variant-enum-string", "enum K {\n  A\n  B(String)\n}\n\n#valtype\nstruct E {\n  id : Int\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, k: K::B(\"x\") })\n  println(xs.length())\n}\n",
      false, "two variants make the enum nullable, so it is not a non-null ref",
    ),
    boundary(
      "b12-two-variant-enum-int", "enum K {\n  A\n  B(Int)\n}\n\n#valtype\nstruct E {\n  id : Int\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ id: 0, k: K::B(1) })\n  println(xs.length())\n}\n",
      false, "same with a non-GC payload: the variant count is what matters",
    ),
    boundary(
      "b10-three-fields", "enum K {\n  A(Int)\n}\n\n#valtype\nstruct E {\n  a : Int\n  b : Int\n  k : K\n}\n\nfn main {\n  let xs : Array[E] = []\n  xs.push({ a: 0, b: 1, k: K::A(0) })\n  println(xs.length())\n}\n",
      true, "field count above two does not change it",
    ),
  ]
}
