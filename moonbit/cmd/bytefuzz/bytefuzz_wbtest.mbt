///|
test "mode selects the generated file name and suffixes" {
  assert_eq(fname_of("pkg"), "moon.pkg")
  assert_eq(fname_of("mod"), "moon.mod")
  assert_eq(fname_of("mbtmd"), "in.mbt.md")
  assert_eq(fname_of("mbti"), "in.mbti")
  assert_eq(fname_of("mbtx"), "in.mbtx")
  assert_eq(fname_of("mbt"), "in.mbt")
  assert_eq(fname_of("unknown"), "in.mbt")
  assert_eq(suffixes_of("pkg"), ["moon.pkg"])
  assert_eq(suffixes_of("mbtmd"), [".mbt.md"])
  assert_eq(suffixes_of("unknown"), [".mbt"])
}

///|
test "parse_int falls back on malformed input" {
  assert_eq(parse_int("42", 0), 42)
  // Only non-negative digit strings parse; signs fall back.
  assert_eq(parse_int("-7", 99), 99)
  assert_eq(parse_int("", 9), 9)
  assert_eq(parse_int("12x", 9), 9)
}

///|
test "mutate_bytes is deterministic per seed" {
  let src = b"fn main { println(1) }\n"
  let pool : Array[Bytes] = [b"fn f { 1 }\n"]
  let a = mutate_bytes(src, @mutate.Rng::new(7UL), pool)
  let b = mutate_bytes(src, @mutate.Rng::new(7UL), pool)
  let c = mutate_bytes(src, @mutate.Rng::new(8UL), pool)
  assert_eq(a, b)
  assert_true(a != c)
}
