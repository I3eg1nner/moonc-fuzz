///|
/// One scale case.  `fields` is the number of scalar fields in front of the
/// aggregate that carries the GC reference, so the struct has `fields + 1`
/// fields in total unless the shape says otherwise.
pub(all) struct Case {
  id : String
  shape : Shape
  fields : Int32
  valtype : Bool
}

///|
/// What kind of aggregate sits in the array.  Each shape reaches the same
/// lowering from a different direction, which is why a threshold could show up
/// in one and not the others.
pub(all) enum Shape {
  /// scalars + a single-constructor payload enum (the F7 shape)
  Record
  /// scalars + a plain struct that itself holds the enum
  Nested
  /// Array[Array[record]]: the empty allocation is one level out
  Arr2
  /// scalars + an enum with 64 payload variants (nullable: a control)
  ManyVar
}

///|
pub fn shape_tag(s : Shape) -> String {
  match s {
    Record => "record"
    Nested => "nested"
    Arr2 => "arr2"
    ManyVar => "manyvar"
  }
}

///|
/// Field counts straddle the usual encoding boundaries: 0/1 (singleton), 3
/// (tagged pointer budget), 7/15/31/63 (power-of-two size classes).
pub fn field_counts() -> Array[Int32] {
  [0, 1, 2, 3, 7, 15, 31, 63]
}

///|
/// 4 shapes x 8 sizes = 32 valtype cases, plus one non-valtype control per
/// shape.  Small enough to run every time, large enough to cross the size
/// classes where a layout threshold would sit.
pub fn cases() -> Array[Case] {
  let out : Array[Case] = []
  for shape in [Record, Nested, Arr2, ManyVar] {
    for n in field_counts() {
      let id = "S-" + shape_tag(shape) + "-" + n.to_string() + "-vt"
      out.push({ id, shape, fields: n, valtype: true, })
    }
    let cid = "S-" + shape_tag(shape) + "-2-plain"
    out.push({ id: cid, shape, fields: 2, valtype: false, })
  }
  out
}

///|
fn scalar_fields(n : Int32) -> String {
  let b = StringBuilder()
  for i in 0..<n {
    b.write_string("  f")
    b.write_string(i.to_string())
    b.write_string(" : Int\n")
  }
  b.to_string()
}

///|
fn scalar_init(n : Int32) -> String {
  let b = StringBuilder()
  for i in 0..<n {
    b.write_string("f")
    b.write_string(i.to_string())
    b.write_string(": 0, ")
  }
  b.to_string()
}

///|
fn enum_decl(shape : Shape) -> String {
  match shape {
    ManyVar => {
      let b = StringBuilder()
      b.write_string("enum K {\n")
      for i in 0..<64 {
        b.write_string("  A")
        b.write_string(i.to_string())
        b.write_string("(Int)\n")
      }
      b.write_string("}\n\n")
      b.to_string()
    }
    _ => "enum K {\n  A(Int)\n}\n\n"
  }
}

///|
fn enum_value(shape : Shape) -> String {
  match shape {
    ManyVar => "K::A0(0)"
    _ => "K::A(0)"
  }
}

///|
pub fn lib_source(c : Case) -> String {
  let b = StringBuilder()
  b.write_string(enum_decl(c.shape))
  match c.shape {
    Nested => b.write_string("struct Inner {\n  k : K\n}\n\n")
    _ => ()
  }
  if c.valtype {
    b.write_string("#valtype\n")
  }
  b.write_string("struct E {\n")
  b.write_string(scalar_fields(c.fields))
  match c.shape {
    Record | ManyVar | Arr2 => b.write_string("  k : K\n")
    Nested => b.write_string("  inner : Inner\n")
  }
  b.write_string("}\n\n")
  // The empty allocation is the trigger; a non-empty literal is the control
  // that must keep passing.
  b.write_string("pub fn make() -> Array[E] {\n")
  match c.shape {
    Arr2 => {
      b.write_string("  let rows : Array[Array[E]] = []\n")
      b.write_string("  let row : Array[E] = []\n")
      b.write_string("  row.push({ ")
      b.write_string(scalar_init(c.fields))
      b.write_string("k: ")
      b.write_string(enum_value(c.shape))
      b.write_string(" })\n  rows.push(row)\n  rows[0]\n")
    }
    Nested => {
      b.write_string("  let xs : Array[E] = []\n")
      b.write_string("  xs.push({ ")
      b.write_string(scalar_init(c.fields))
      b.write_string("inner: { k: ")
      b.write_string(enum_value(c.shape))
      b.write_string(" } })\n  xs\n")
    }
    _ => {
      b.write_string("  let xs : Array[E] = []\n")
      b.write_string("  xs.push({ ")
      b.write_string(scalar_init(c.fields))
      b.write_string("k: ")
      b.write_string(enum_value(c.shape))
      b.write_string(" })\n  xs\n")
    }
  }
  b.write_string("}\n")
  b.to_string()
}

///|
pub fn main_source() -> String {
  "fn main {\n  let xs = make()\n  println(xs.length())\n}\n"
}

///|
pub fn pkg_source() -> String {
  "pkgtype(kind: \"executable\")\n"
}

///|
pub fn mod_source() -> String {
  "name = \"repro/scale\"\nversion = \"0.1.0\"\n"
}
