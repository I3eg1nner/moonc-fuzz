///|
/// Random-value grids.
///
/// The hand-written cases pin down specific operations; these pin down a large
/// sample of *values*.  Bit patterns are generated here (deterministically, at
/// generation time) and embedded as literals, so the program itself stays
/// dependency-free and the input is reproducible from the source.
///
/// 12 special values + 36 pseudo-random patterns for doubles (48x48), 8 + 36
/// for ints (44x44).  The
/// specials are the ones a random draw almost never hits: signed zero, both
/// infinities, quiet and signalling NaN, the smallest denormal, the largest
/// finite, 2^53, 1.0 and -1.0.

///|
/// Fixed LCG constants: any change here changes every generated program, so
/// they are part of the corpus identity.
fn lcg(s : UInt64) -> UInt64 {
  s * 6364136223846793005UL + 1442695040888963407UL
}

///|
fn hex64(x : UInt64) -> String {
  "0x" + x.to_string(radix=16) + "UL"
}

///|
fn special_doubles() -> Array[UInt64] {
  [
    0x0UL, // +0.0
     0x8000000000000000UL, // -0.0
     0x7FF0000000000000UL, // +inf
     0xFFF0000000000000UL, // -inf
     0x7FF8000000000000UL, // quiet NaN
     0x7FF0000000000001UL, // signalling NaN
     0x1UL, // smallest denormal
     0x0010000000000000UL, // smallest normal
     0x7FEFFFFFFFFFFFFFUL, // largest finite
     0x3FF0000000000000UL, // 1.0
     0xBFF0000000000000UL, // -1.0
     0x4340000000000000UL, // 2^53
  ]
}

///|
fn values_48(specials : Array[UInt64]) -> Array[UInt64] {
  let out : Array[UInt64] = []
  for v in specials {
    out.push(v)
  }
  let mut s = 0x243F6A8885A308D3UL
  for _ in 0..<36 {
    s = lcg(s)
    out.push(s)
  }
  out
}

///|
fn u64_array(name : String, vals : Array[UInt64]) -> String {
  let b = StringBuilder()
  b.write_string("fn ")
  b.write_string(name)
  b.write_string("() -> Array[UInt64] {\n  [\n")
  for i, v in vals {
    b.write_string("    ")
    b.write_string(hex64(v))
    b.write_string(",\n")
    if i % 4 == 3 {
      b.write_string("\n")
    }
  }
  b.write_string("  ]\n}\n")
  b.to_string()
}

///|
/// 48x48 doubles: arithmetic bits plus compare/min/max.  4608 printed lines,
/// which is more comparisons than the entire hand-written suite.
pub fn f64_bits_grid() -> String {
  let vals = values_48(special_doubles())
  let b = StringBuilder()
  b.write_string(u64_array("bits", vals))
  let body =
    #|fn to_double(u : UInt64) -> Double {
    #|  u.reinterpret_as_double()
    #|}
    #|
    #|fn main {
    #|  let us = bits()
    #|  let xs : Array[Double] = []
    #|  for u in us {
    #|    xs.push(to_double(u))
    #|  }
    #|  for i, x in xs {
    #|    for j, y in xs {
    #|      if x.is_nan() || y.is_nan() {
    #|        continue
    #|      }
    #|      println(
    #|        "n" + i.to_string() + "," + j.to_string() + "=" +
    #|        u((x + y).reinterpret_as_uint64()) + "/" +
    #|        u((x - y).reinterpret_as_uint64()) + "/" +
    #|        u((x * y).reinterpret_as_uint64()) + "/" +
    #|        u((x / y).reinterpret_as_uint64()),
    #|      )
    #|      println(
    #|        "c" + i.to_string() + "," + j.to_string() + "=" +
    #|        x.compare(y).to_string() + "/" +
    #|        u(x.min(y).reinterpret_as_uint64()) + "/" +
    #|        u(x.max(y).reinterpret_as_uint64()) + "/" +
    #|        b(x < y) + b(x == y),
    #|      )
    #|    }
    #|  }
    #|}
    #|
  b.write_string(body)
  b.to_string()
}

///|
fn special_ints() -> Array[UInt64] {
  [
    0x0UL, // 0
     0x1UL, // 1
     0xFFFFFFFFUL, // -1
     0x7FFFFFFFUL, // max
     0x80000000UL, // min
     0x7FFFFFFEUL, // max - 1
     0x80000001UL, // min + 1
     0x40000000UL, // 2^30
  ]
}

///|
/// 44x44 ints (8 specials + 36 random) over `+ - * & | ^` and guarded `/ %`.  Division and modulo are
/// skipped for a zero divisor and for `min / -1`, the two cases that trap.
pub fn int_bits_grid() -> String {
  let vals = values_48(special_ints())
  let b = StringBuilder()
  b.write_string(u64_array("bits", vals))
  let body =
    #|fn to_int(u : UInt64) -> Int {
    #|  u.to_int()
    #|}
    #|
    #|fn main {
    #|  let us = bits()
    #|  let xs : Array[Int] = []
    #|  for u in us {
    #|    xs.push(to_int(u))
    #|  }
    #|  for i, x in xs {
    #|    for j, y in xs {
    #|      println(
    #|        "a" + i.to_string() + "," + j.to_string() + "=" +
    #|        (x + y).to_string() + "/" +
    #|        (x - y).to_string() + "/" +
    #|        (x * y).to_string() + "/" +
    #|        (x & y).to_string() + "/" +
    #|        (x | y).to_string() + "/" +
    #|        (x ^ y).to_string(),
    #|      )
    #|      if y != 0 && !(x == -2147483647 - 1 && y == -1) {
    #|        println(
    #|          "d" + i.to_string() + "," + j.to_string() + "=" +
    #|          (x / y).to_string() + "/" +
    #|          (x % y).to_string(),
    #|        )
    #|      }
    #|    }
    #|  }
    #|}
    #|
  b.write_string(body)
  b.to_string()
}
