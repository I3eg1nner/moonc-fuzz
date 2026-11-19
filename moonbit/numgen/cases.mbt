///|
/// The case list.  Each program is total (no traps) in the common case, prints
/// only deterministic values, and uses bit patterns for floats so formatting
/// never masquerades as a semantic difference.

///|
/// Sources live in `let` bindings because a multiline string literal is only
/// accepted there (elsewhere it is deprecated syntax and warns).
pub fn cases() -> Array[Case] {
  let p = prelude()
  let f64_nan_bits =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let nan = d(0.0) / d(0.0)
    #|  println("nan_bits=" + u(nan.reinterpret_as_uint64()))
    #|  println("nan_is_nan=" + b(nan.is_nan()))
    #|  println("nan_eq_self=" + b(nan == nan))
    #|  println("nan_lt_1=" + b(nan < d(1.0)))
    #|  println("nan_gt_1=" + b(nan > d(1.0)))
    #|  println("nan_cmp_1=" + nan.compare(d(1.0)).to_string())
    #|  println("nan_add_1=" + u((nan + d(1.0)).reinterpret_as_uint64()))
    #|  println("nan_mul_2=" + u((nan * d(2.0)).reinterpret_as_uint64()))
    #|}

  let f64_zero_inf =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let pz = d(0.0)
    #|  let nz = -d(0.0)
    #|  let inf = d(1.0) / pz
    #|  println("pz_bits=" + u(pz.reinterpret_as_uint64()))
    #|  println("nz_bits=" + u(nz.reinterpret_as_uint64()))
    #|  println("pz_eq_nz=" + b(pz == nz))
    #|  println("pos_inf_bits=" + u(inf.reinterpret_as_uint64()))
    #|  println("neg_inf_bits=" + u((d(1.0) / nz).reinterpret_as_uint64()))
    #|  println("inf_plus_1=" + u((inf + d(1.0)).reinterpret_as_uint64()))
    #|  println("inf_minus_inf_nan=" + b((inf - inf).is_nan()))
    #|  println("nz_times_neg1=" + u((nz * -d(1.0)).reinterpret_as_uint64()))
    #|  println("inf_gt_max=" + b(inf > d(1.7976931348623157e308)))
    #|}

  let f64_round_half =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn bits(x : Double) -> String {
    #|  u(x.reinterpret_as_uint64())
    #|}
    #|
    #|fn main {
    #|  println("r_0.5=" + bits(d(0.5).round()))
    #|  println("r_1.5=" + bits(d(1.5).round()))
    #|  println("r_2.5=" + bits(d(2.5).round()))
    #|  println("r_m0.5=" + bits((d(-0.5)).round()))
    #|  println("r_m1.5=" + bits((d(-1.5)).round()))
    #|  println("r_m2.5=" + bits((d(-2.5)).round()))
    #|  println("f_1.5=" + bits(d(1.5).floor()))
    #|  println("c_1.5=" + bits(d(1.5).ceil()))
    #|  println("t_m1.9=" + bits((d(-1.9)).trunc()))
    #|  println("r_2.675=" + bits(d(2.675).round()))
    #|}

  let f64_to_int_bounds =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  println("i_1.9=" + d(1.9).to_int().to_string())
    #|  println("i_m1.9=" + (d(-1.9)).to_int().to_string())
    #|  println("i_max=" + d(2147483647.0).to_int().to_string())
    #|  println("i_max_plus=" + d(2147483648.0).to_int().to_string())
    #|  println("i_min=" + (d(-2147483648.0)).to_int().to_string())
    #|  println("i_min_minus=" + (d(-2147483649.0)).to_int().to_string())
    #|  println("i_huge=" + d(1.0e18).to_int().to_string())
    #|  println("i_nan=" + d(0.0 / 0.0).to_int().to_string())
    #|  println("i_pos_inf=" + (d(1.0) / d(0.0)).to_int().to_string())
    #|}

  let f64_int64_mix =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn l(x : Int64) -> Int64 {
    #|  x
    #|}
    #|
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn main {
    #|  println("d_2p53=" + u(d(9007199254740992.0).reinterpret_as_uint64()))
    #|  println("i_2p53p1=" + u(l(9007199254740993L).to_double().reinterpret_as_uint64()))
    #|  println("i_max=" + u(l(9223372036854775807L).to_double().reinterpret_as_uint64()))
    #|  println("i_min=" + u(l(-9223372036854775808L).to_double().reinterpret_as_uint64()))
    #|  println("d_to_l=" + d(1.5).to_int64().to_string())
    #|  println("d_to_l_neg=" + (d(-1.5)).to_int64().to_string())
    #|  println("d_to_l_big=" + d(1.0e19).to_int64().to_string())
    #|}

  let int_edges =
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let min = i(-2147483647 - 1)
    #|  let max = i(2147483647)
    #|  println("max_plus_1=" + (max + i(1)).to_string())
    #|  println("min_minus_1=" + (min - i(1)).to_string())
    #|  println("max_times_2=" + (max * i(2)).to_string())
    #|  println("neg_div=" + (i(-7) / i(2)).to_string())
    #|  println("neg_mod=" + (i(-7) % i(2)).to_string())
    #|  println("neg_div_neg=" + (i(-7) / i(-2)).to_string())
    #|  println("neg_mod_neg=" + (i(-7) % i(-2)).to_string())
    #|}

  let int_shift =
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn uu(x : UInt) -> UInt {
    #|  x
    #|}
    #|
    #|fn main {
    #|  println("shl_31=" + (i(1) << i(31)).to_string())
    #|  println("shl_32=" + (i(1) << i(32)).to_string())
    #|  println("shr_neg1=" + (i(-1) >> i(1)).to_string())
    #|  println("shr_neg1_31=" + (i(-1) >> i(31)).to_string())
    #|  println("ushr_ffffffff=" + uu(4294967295U).to_string())
    #|  println("ushr1=" + (uu(4294967295U) >> i(1)).to_string())
    #|  println("ushl31=" + (uu(4294967295U) << i(31)).to_string())
    #|}

  let int64_edges =
    #|fn l(x : Int64) -> Int64 {
    #|  x
    #|}
    #|
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let max = l(9223372036854775807L)
    #|  let min = l(-9223372036854775807L - 1L)
    #|  println("max_plus_1=" + (max + l(1L)).to_string())
    #|  println("min_minus_1=" + (min - l(1L)).to_string())
    #|  println("shl_63=" + (l(1L) << 63).to_string())
    #|  println("shl_64=" + (l(1L) << 64).to_string())
    #|  println("shr_neg1_63=" + (l(-1L) >> 63).to_string())
    #|  println("to_int=" + l(4294967297L).to_int().to_string())
    #|  println("to_uint64=" + max.to_uint64().to_string())
    #|}

  let str_units =
    #|fn units(s : String) -> String {
    #|  let mut acc = ""
    #|  let mut k = 0
    #|  for c in s {
    #|    if k > 0 {
    #|      acc = acc + ","
    #|    }
    #|    acc = acc + c.to_int().to_string()
    #|    k += 1
    #|  }
    #|  acc
    #|}
    #|
    #|fn main {
    #|  let ascii = "abc"
    #|  let cjk = "中文"
    #|  let emoji = "🙂"
    #|  let comb = "e\u{301}"
    #|  println("ascii_len=" + ascii.length().to_string())
    #|  println("ascii_clen=" + ascii.char_length().to_string())
    #|  println("ascii_chars=" + units(ascii))
    #|  println("cjk_len=" + cjk.length().to_string())
    #|  println("cjk_clen=" + cjk.char_length().to_string())
    #|  println("cjk_chars=" + units(cjk))
    #|  println("emoji_len=" + emoji.length().to_string())
    #|  println("emoji_clen=" + emoji.char_length().to_string())
    #|  println("emoji_chars=" + units(emoji))
    #|  println("comb_len=" + comb.length().to_string())
    #|  println("comb_clen=" + comb.char_length().to_string())
    #|  println("comb_chars=" + units(comb))
    #|}

  let str_ops =
    #|fn main {
    #|  let s = "a中🙂z"
    #|  println("len=" + s.length().to_string())
    #|  println("clen=" + s.char_length().to_string())
    #|  println("at0=" + s.at(0).to_string())
    #|  println("at1=" + s.at(1).to_string())
    #|  println("gc0=" + b(s.get_char(0) is Some(_)))
    #|  println("gc1=" + b(s.get_char(1) is Some(_)))
    #|  println("gc9=" + b(s.get_char(9) is Some(_)))
    #|  println("find_mid=" + b(s.find("中") is Some(_)))
    #|  println("find_missing=" + b(s.find("q") is Some(_)))
    #|  println("prefix=" + b(s.has_prefix("a中")))
    #|  println("suffix=" + b(s.has_suffix("🙂z")))
    #|  println("cmp_eq=" + s.compare("a中🙂z").to_string())
    #|  println("cmp_lt=" + b(s.compare("a中🙂zz") < 0))
    #|  let off2 = match s.offset_of_nth_char(2) {
    #|    Some(v) => v.to_string()
    #|    None => "none"
    #|  }
    #|  println("off2=" + off2)
    #|  println("concat_len=" + (s + "🙂").length().to_string())
    #|}

  let f64_minmax =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let nan = d(0.0) / d(0.0)
    #|  println("min_nan_1=" + u(nan.min(d(1.0)).reinterpret_as_uint64()))
    #|  println("min_1_nan=" + u(d(1.0).min(nan).reinterpret_as_uint64()))
    #|  println("max_nan_1=" + u(nan.max(d(1.0)).reinterpret_as_uint64()))
    #|  println("min_pz_nz=" + u(d(0.0).min(-d(0.0)).reinterpret_as_uint64()))
    #|  println("max_pz_nz=" + u(d(0.0).max(-d(0.0)).reinterpret_as_uint64()))
    #|  println("pow_2_10=" + u(d(2.0).pow(d(10.0)).reinterpret_as_uint64()))
    #|  println("pow_2_m1=" + u(d(2.0).pow(-d(1.0)).reinterpret_as_uint64()))
    #|  println("mod_7_3=" + u(d(7.0).mod(d(3.0)).reinterpret_as_uint64()))
    #|  println("mod_m7_3=" + u((d(-7.0)).mod(d(3.0)).reinterpret_as_uint64()))
    #|}

  let f64_abs_neg =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  println("abs_nz=" + u((d(-0.0)).abs().reinterpret_as_uint64()))
    #|  println("abs_m3.5=" + u((d(-3.5)).abs().reinterpret_as_uint64()))
    #|  println("neg_pz=" + u((d(0.0)).neg().reinterpret_as_uint64()))
    #|  println("neg_neg1=" + u((d(-1.0)).neg().reinterpret_as_uint64()))
    #|  println("abs_nan_is_nan=" + b((d(0.0) / d(0.0)).abs().is_nan()))
    #|}

  let u64_arith =
    #|fn q(x : UInt64) -> UInt64 {
    #|  x
    #|}
    #|
    #|fn main {
    #|  println("max=" + q(18446744073709551615UL).to_string())
    #|  println("add1=" + (q(18446744073709551615UL) + 1UL).to_string())
    #|  println("mul=" + (q(4294967296UL) * q(4294967296UL)).to_string())
    #|  println("div=" + (q(18446744073709551615UL) / 3UL).to_string())
    #|  println("mod=" + (q(18446744073709551615UL) % 3UL).to_string())
    #|  println("to_int=" + q(4294967297UL).to_int().to_string())
    #|  println("to_double=" + u(q(18446744073709551615UL).to_double().reinterpret_as_uint64()))
    #|}

  let str_make_pad =
    #|fn main {
    #|  println("make=" + String::make(3, 'x'))
    #|  println("make_len=" + String::make(3, 'x').length().to_string())
    #|  println("pad=" + "ab".pad_end(5, '.'))
    #|  println("pad_len=" + "ab".pad_end(5, '.').length().to_string())
    #|  println("make_cjk=" + String::make(2, '中').length().to_string())
    #|  println("blanks=" + b("  ".is_blank()))
    #|}

  let str_views =
    #|fn main {
    #|  let s = "a中🙂z"
    #|  println("len=" + s.length().to_string())
    #|  let v03 = match s.get_view(start=0, end=3) {
    #|    Some(v) => v.length().to_string()
    #|    None => "none"
    #|  }
    #|  let v33 = match s.get_view(start=3, end=3) {
    #|    Some(v) => v.length().to_string()
    #|    None => "none"
    #|  }
    #|  let v40 = match s.get_view(start=4, end=0) {
    #|    Some(v) => v.length().to_string()
    #|    None => "none"
    #|  }
    #|  let find_off = match s.find("🙂") {
    #|    Some(v) => v.to_string()
    #|    None => "none"
    #|  }
    #|  let nth1 = match s.offset_of_nth_char(1) {
    #|    Some(v) => v.to_string()
    #|    None => "none"
    #|  }
    #|  let nth9 = match s.offset_of_nth_char(9) {
    #|    Some(v) => v.to_string()
    #|    None => "none"
    #|  }
    #|  println("v03=" + v03)
    #|  println("v33=" + v33)
    #|  println("v40=" + v40)
    #|  println("find_off=" + find_off)
    #|  println("nth1=" + nth1)
    #|  println("nth9=" + nth9)
    #|}

  let str_split =
    #|fn main {
    #|  let parts = "a中b中c".split("中")
    #|  println("n=" + parts.length().to_string())
    #|  for i, p in parts {
    #|    println("p" + i.to_string() + "=" + p.to_owned())
    #|  }
    #|  println("lens=" + parts.length().to_string())
    #|  println("contains=" + b("a中b".contains("中b")))
    #|  println("prefix_cjk=" + b("中a".has_prefix("中")))
    #|}

  let f64_opgrid =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn bits(x : Double) -> String {
    #|  u(x.reinterpret_as_uint64())
    #|}
    #|
    #|fn main {
    #|  let inf = d(1.0) / d(0.0)
    #|  let nan = d(0.0) / d(0.0)
    #|  let xs : Array[Double] = [
    #|    0.0, -0.0, 1.0, -1.0, inf, -inf, nan, 1.5, -1.5,
    #|    9007199254740992.0, 1.0e-320, 1.7976931348623157e308,
    #|  ]
    #|  for i, x in xs {
    #|    for j, y in ys_values() {
    #|      println(
    #|        "n" + i.to_string() + "," + j.to_string() + "=" +
    #|        bits(x + y) + "/" +
    #|        bits(x - y) + "/" +
    #|        bits(x * y) + "/" +
    #|        bits(x / y),
    #|      )
    #|      println(
    #|        "c" + i.to_string() + "," + j.to_string() + "=" +
    #|        x.compare(y).to_string() + "/" +
    #|        bits(x.min(y)) + "/" +
    #|        bits(x.max(y)),
    #|      )
    #|    }
    #|  }
    #|}
    #|
    #|fn ys_values() -> Array[Double] {
    #|  let inf = 1.0 / 0.0
    #|  let nan = 0.0 / 0.0
    #|  [0.0, -0.0, 1.0, -1.0, inf, -inf, nan, 1.5, -1.5, 9007199254740992.0, 1.0e-320, 1.7976931348623157e308]
    #|}

  let int_opgrid =
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let xs : Array[Int] = [
    #|    i(0), i(1), i(-1), i(7), i(-7), i(2147483647), i(-2147483647 - 1),
    #|    i(1073741824), i(-1073741824),
    #|  ]
    #|  for a, x in xs {
    #|    for b, y in ys_values() {
    #|      println(
    #|        "a" + a.to_string() + "," + b.to_string() + "=" +
    #|        (x + y).to_string() + "/" +
    #|        (x - y).to_string() + "/" +
    #|        (x * y).to_string() + "/" +
    #|        (x & y).to_string() + "/" +
    #|        (x | y).to_string() + "/" +
    #|        (x ^ y).to_string(),
    #|      )
    #|      if y != 0 && !(x == i(-2147483647 - 1) && y == i(-1)) {
    #|        println(
    #|          "d" + a.to_string() + "," + b.to_string() + "=" +
    #|          (x / y).to_string() + "/" +
    #|          (x % y).to_string(),
    #|        )
    #|      }
    #|    }
    #|  }
    #|  for k in [0, 1, 15, 30, 31] {
    #|    println(
    #|      "s" + k.to_string() + "=" +
    #|      (i(1) << k).to_string() + "/" +
    #|      (i(-1) >> k).to_string() + "/" +
    #|      (i(2147483647) << k).to_string(),
    #|    )
    #|  }
    #|}
    #|
    #|fn ys_values() -> Array[Int] {
    #|  [0, 1, -1, 7, -7, 2147483647, -2147483647 - 1, 1073741824, -1073741824]
    #|}

  let str_rep =
    #|fn main {
    #|  let ss : Array[String] = [
    #|    "", "a", "ab", "abc", "中", "中文", "🙂", "a中🙂", "e\u{301}",
    #|  ]
    #|  for i, x in ss {
    #|    println(
    #|      "s" + i.to_string() + "=" +
    #|      x.length().to_string() + "/" +
    #|      x.char_length().to_string() + "/" +
    #|      b(x.is_empty()).to_string(),
    #|    )
    #|    for j, y in ss {
    #|      println(
    #|        "c" + i.to_string() + "," + j.to_string() + "=" +
    #|        x.compare(y).to_string() + "/" +
    #|        b(x == y) + "/" +
    #|        b(x.contains(y)) + "/" +
    #|        b(x.has_prefix(y)),
    #|      )
    #|    }
    #|  }
    #|}

  let num_fmt =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn l(x : Int64) -> Int64 {
    #|  x
    #|}
    #|
    #|fn i(x : Int) -> Int {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let xs : Array[Double] = [
    #|    0.0, -0.0, 1.0, -1.0, 0.1, 1.0 / 3.0, 1.0e21, 1.0e-7,
    #|    9007199254740992.0, 1.7976931348623157e308, 5.0e-324,
    #|  ]
    #|  for i, x in xs {
    #|    println("d" + i.to_string() + "=" + x.to_string())
    #|  }
    #|  let inf = d(1.0) / d(0.0)
    #|  let nan = d(0.0) / d(0.0)
    #|  println("inf=" + inf.to_string())
    #|  println("ninf=" + (-inf).to_string())
    #|  println("nan=" + nan.to_string())
    #|  println("l_max=" + l(9223372036854775807L).to_string())
    #|  println("l_min=" + l(-9223372036854775807L - 1L).to_string())
    #|  println("l_radix16=" + l(255L).to_string(radix=16))
    #|  println("i_radix2=" + i(5).to_string(radix=2))
    #|  println("i_radix36=" + i(123456).to_string(radix=36))
    #|}

  let nan_array_bits =
    #|fn d(x : Double) -> Double {
    #|  x
    #|}
    #|
    #|fn main {
    #|  let nan = 0.0 / 0.0
    #|  let inf = 1.0 / 0.0
    #|  println("folded_div00=" + nan.reinterpret_as_uint64().to_string())
    #|  println("folded_infminf=" + (inf - inf).reinterpret_as_uint64().to_string())
    #|  println("folded_add=" + (nan + 1.0).reinterpret_as_uint64().to_string())
    #|  let runtime = d(0.0) / d(0.0)
    #|  println("runtime_div00=" + runtime.reinterpret_as_uint64().to_string())
    #|}

  let f32_bits =
    #|fn main {
    #|  let ds : Array[Double] = [
    #|    0.1, -0.0, 0.0, 1.0 / 3.0, 1.0e-45, 3.4028234663852886e38,
    #|    0.0 / 0.0, 1.0 / 0.0,
    #|  ]
    #|  for i, d in ds {
    #|    let f = Float::from_double(d)
    #|    println(
    #|      "f" + i.to_string() + "=" +
    #|      f.reinterpret_as_int().to_string() + "/" +
    #|      u(f.to_double().reinterpret_as_uint64()),
    #|    )
    #|  }
    #|}

  let f32_arith =
    #|fn main {
    #|  let a = Float::from_double(1.0 / 3.0)
    #|  let b = Float::from_double(3.0)
    #|  println("add=" + a.add(b).reinterpret_as_int().to_string())
    #|  println("sub=" + a.sub(b).reinterpret_as_int().to_string())
    #|  println("mul=" + a.mul(b).reinterpret_as_int().to_string())
    #|  println("div=" + a.div(b).reinterpret_as_int().to_string())
    #|  println("cmp=" + a.compare(b).to_string())
    #|  println("min=" + a.min(b).reinterpret_as_int().to_string())
    #|  println("max=" + a.max(b).reinterpret_as_int().to_string())
    #|  println("total=" + a.total_compare(b).to_string())
    #|}

  let f32_nan =
    #|fn main {
    #|  let n = Float::from_double(0.0 / 0.0)
    #|  let one = Float::from_double(1.0)
    #|  println("bits=" + n.reinterpret_as_int().to_string())
    #|  println("isnan=" + b(n.is_nan()))
    #|  println("eq_self=" + b(n.equal(n)))
    #|  println("cmp_self=" + n.compare(n).to_string())
    #|  println("total_self=" + n.total_compare(n).to_string())
    #|  println("min_one=" + n.min(one).reinterpret_as_int().to_string())
    #|  println("max_one=" + n.max(one).reinterpret_as_int().to_string())
    #|  println("add_one=" + n.add(one).reinterpret_as_int().to_string())
    #|}

  let f32_conv =
    #|fn main {
    #|  let a = Float::from_double(1.9)
    #|  let b = Float::from_double(-1.9)
    #|  let big = Float::from_double(3.5e9)
    #|  println("to_int=" + a.to_int().to_string())
    #|  println("to_int_neg=" + b.to_int().to_string())
    #|  println("to_int_big=" + big.to_int().to_string())
    #|  println("rt_0.1=" + Float::from_double(a.to_double()).reinterpret_as_int().to_string())
    #|}

  [
    { id: "f64-nan-bits", family: "f64", src: p + f64_nan_bits, },
    { id: "f64-zero-inf", family: "f64", src: p + f64_zero_inf, },
    { id: "f64-round-half", family: "f64", src: p + f64_round_half, },
    { id: "f64-to-int-bounds", family: "f64", src: p + f64_to_int_bounds, },
    { id: "f64-int64-mix", family: "f64", src: p + f64_int64_mix, },
    { id: "int-edges", family: "int", src: p + int_edges, },
    { id: "int-shift", family: "int", src: p + int_shift, },
    { id: "int64-edges", family: "int", src: p + int64_edges, },
    { id: "str-units", family: "str", src: p + str_units, },
    { id: "str-ops", family: "str", src: p + str_ops, },
    { id: "f64-minmax", family: "f64", src: p + f64_minmax, },
    { id: "f64-abs-neg", family: "f64", src: p + f64_abs_neg, },
    { id: "u64-arith", family: "int", src: p + u64_arith, },
    { id: "str-make-pad", family: "str", src: p + str_make_pad, },
    { id: "str-views", family: "str", src: p + str_views, },
    { id: "str-split", family: "str", src: p + str_split, },
    { id: "f64-opgrid", family: "f64", src: p + f64_opgrid, },
    { id: "int-opgrid", family: "int", src: p + int_opgrid, },
    { id: "str-rep", family: "str", src: p + str_rep, },
    { id: "num-fmt", family: "fmt", src: p + num_fmt, },
    { id: "nan-array-bits", family: "nan", src: p + nan_array_bits, },
    { id: "f32-bits", family: "f32", src: p + f32_bits, },
    { id: "f32-arith", family: "f32", src: p + f32_arith, },
    { id: "f32-nan", family: "f32", src: p + f32_nan, },
    { id: "f32-conv", family: "f32", src: p + f32_conv, },
    { id: "f64-bits-grid", family: "f64", src: p + f64_bits_grid(), },
    { id: "int-bits-grid", family: "int", src: p + int_bits_grid(), },
  ]
}

///|
/// Case ids are used as directory names, so keep them path-safe and unique.
pub fn ids() -> Array[String] {
  let out : Array[String] = []
  for c in cases() {
    out.push(c.id)
  }
  out
}

///|
pub fn select(family : String) -> Array[Case] {
  let out : Array[Case] = []
  for c in cases() {
    if family == "" || c.family == family {
      out.push(c)
    }
  }
  out
}
