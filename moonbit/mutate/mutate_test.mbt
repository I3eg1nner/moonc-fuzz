///|
/// Black-box tests for the structure-aware mutator package.

///|
test "parse_dict: quoted tokens, blanks and comments" {
  let text = "\"fn\"\n\"Array\"\n\n// not a token\nname=\"ignored\"\n\"with space\"\n\"\"\n"
  let d = parse_dict(text)
  @test.assert_eq(d.length(), 4)
  @test.assert_eq(d[0], "fn")
  @test.assert_eq(d[1], "Array")
  @test.assert_eq(d[2], "with space")
  @test.assert_eq(d[3], "")
}

///|
test "parse_dict: escapes are kept verbatim and CRLF is accepted" {
  let text = "\"\\x00\"\r\n\"a\\\"b\"\r\n"
  let d = parse_dict(text)
  @test.assert_eq(d.length(), 2)
  @test.assert_eq(d[0], "\\x00")
  @test.assert_eq(d[1], "a\\\"b")
  let lone_cr = parse_dict("\"a\"\r\"b\"\r")
  @test.assert_eq(lone_cr.length(), 2)
  @test.assert_eq(lone_cr[1], "b")
}

///|
test "Rng: same seed gives the same stream, different seed diverges" {
  let a = Rng::new(42UL)
  let b = Rng::new(42UL)
  for _ in 0..<32 {
    @test.assert_eq(a.next_u64(), b.next_u64())
  }
  @test.assert_eq(a.next_u64(), b.next_u64())
  let c = Rng::new(43UL)
  let d = Rng::new(42UL)
  let mut same = true
  for _ in 0..<8 {
    if c.next_u64() != d.next_u64() {
      same = false
    }
  }
  @test.assert_eq(same, false)
}

///|
test "Rng: splitmix64 reference vector is target independent" {
  let r = Rng::new(42UL)
  @test.assert_eq(r.next_u64(), 0xBDD732262FEB6E95UL)
  @test.assert_eq(r.next_u64(), 0x28EFE333B266F103UL)
  @test.assert_eq(r.next_u64(), 0x47526757130F9F52UL)
}

///|
test "Rng: int range and choice stay in bounds" {
  let r = Rng::new(7UL)
  for _ in 0..<200 {
    let v = r.int(10)
    assert_true(v >= 0 && v < 10)
    let w = r.int_range(-3, 3)
    assert_true(w >= -3 && w <= 3)
    let f = r.float()
    assert_true(f >= 0.0 && f < 1.0)
  }
  let xs : Array[String] = ["a", "b", "c"]
  for _ in 0..<100 {
    let v = r.choice(xs)
    assert_true(v == "a" || v == "b" || v == "c")
  }
  let empty : Array[Int32] = []
  @test.assert_eq(r.choice_opt(empty), None)
  let one : Array[Int32] = [9]
  @test.assert_eq(r.choice_opt(one), Some(9))
}

///|
test "balanced blocks are detected and duplicated" {
  let src = "{ let x = 1 }"
  let out = dup_block(src, Rng::new(1UL))
  @test.assert_eq(out, "{ let x = 1 }\n{ let x = 1 }")
  @test.assert_eq(del_block(src, Rng::new(1UL)), "")
}

///|
test "unbalanced and quoted brackets are not blocks" {
  @test.assert_eq(dup_block("{", Rng::new(0UL)), "{")
  @test.assert_eq(del_block("}", Rng::new(0UL)), "}")
  @test.assert_eq(dup_block("\"{\"", Rng::new(0UL)), "\"{\"")
  @test.assert_eq(dup_block("'{'", Rng::new(0UL)), "'{'")
  @test.assert_eq(del_block("let s = \"[]\"", Rng::new(0UL)), "let s = \"[]\"")
}

///|
test "string and char literals are protected and replaced as wholes" {
  for seed in 0..<16 {
    let s = replace_token("\"hello\"", Rng::new(seed.to_uint64()))
    assert_true(s.has_prefix("\""))
    assert_true(s.has_suffix("\""))
    assert_true(s != "\"hello\"")
    assert_true(s.char_length() >= 2)
  }
  for seed in 0..<16 {
    let c = replace_token("'z'", Rng::new(seed.to_uint64()))
    assert_true(c.has_prefix("'"))
    assert_true(c.has_suffix("'"))
    assert_true(c != "'z'")
  }
}

///|
test "replace_token replaces numbers and operators" {
  let n = replace_token("123", Rng::new(0UL))
  assert_true(n != "123")
  assert_true(n.char_length() > 0)
  let o = replace_token("+", Rng::new(0UL))
  assert_true(o != "+")
  assert_true(o.char_length() > 0)
}

///|
test "body mutates inside a balanced block and keeps outer structure" {
  let src = "fn f() {\n  let alpha = 1\n  let beta = 2\n  let gamma = 3\n  let delta = 4\n}\n"
  let mut changed = 0
  for seed in 0..<32 {
    let out = body(src, Rng::new(seed.to_uint64()))
    assert_true(out.has_prefix("fn f() {"))
    assert_true(out.has_suffix("}\n"))
    if out != src {
      changed = changed + 1
    }
  }
  assert_true(changed > 0)
}

///|
test "mutate with body_only=true keeps the corpus shape" {
  let src = "fn f() {\n  let alpha = 1\n  let beta = 2\n  let gamma = 3\n  let delta = 4\n}\n"
  let pool : Array[String] = []
  let mut preserved = 0
  for seed in 0..<32 {
    let out = mutate(src, Rng::new(seed.to_uint64()), pool, true)
    assert_true(out.char_length() > 0)
    if out.has_prefix("fn f() {") {
      preserved = preserved + 1
    }
  }
  // 85% of rounds go through `body`; over 32 seeds most outputs keep the
  // top-level signature.
  assert_true(preserved >= 20)
}

///|
test "unicode inserts exactly one seed and includes astral characters" {
  let mut saw_emoji = false
  for seed in 0..<256 {
    let out = unicode("abc", Rng::new(seed.to_uint64()))
    @test.assert_eq(out.char_length(), 4)
    assert_true(out != "abc")
    if out.contains("\u{1F600}") {
      saw_emoji = true
    }
  }
  assert_true(saw_emoji)
}

///|
test "truncate cuts to a non-empty proper prefix and ignores short inputs" {
  let src = "abcdefghij"
  for seed in 0..<32 {
    let out = truncate(src, Rng::new(seed.to_uint64()))
    assert_true(out.char_length() >= 1)
    assert_true(out.char_length() < src.char_length())
    assert_true(src.has_prefix(out))
  }
  @test.assert_eq(truncate("abc", Rng::new(0UL)), "abc")
  @test.assert_eq(truncate("", Rng::new(0UL)), "")
}

///|
test "bitflip is deterministic, non-empty, and can change bytes" {
  @test.assert_eq(bitflip("", Rng::new(0UL)), "")
  let src = "abcdef"
  let mut changed = 0
  for seed in 0..<32 {
    let a = bitflip(src, Rng::new(seed.to_uint64()))
    let b = bitflip(src, Rng::new(seed.to_uint64()))
    @test.assert_eq(a, b)
    assert_true(a.char_length() > 0)
    if a != src {
      changed = changed + 1
    }
  }
  assert_true(changed > 0)
}

///|
test "literal_edges replaces only standalone short numbers" {
  let out = literal_edges("let x = 123", Rng::new(0UL))
  assert_true(out.has_prefix("let x = "))
  assert_true(out != "let x = 123")
  // A decimal or an over-long digit run is not a standalone short literal.
  @test.assert_eq(literal_edges("1.25", Rng::new(0UL)), "1.25")
  @test.assert_eq(
    literal_edges("1234567890123456789", Rng::new(0UL)),
    "1234567890123456789",
  )
}

///|
test "rename_ident renames all occurrences but not keywords" {
  let out = rename_ident("let foo = foo + foo", Rng::new(0UL))
  assert_true(out.has_prefix("let "))
  assert_true(out != "let foo = foo + foo")
  assert_true(!out.contains("foo"))
  @test.assert_eq(rename_ident("let let", Rng::new(0UL)), "let let")
}

///|
test "dict_token uses parsed candidates and filters keywords" {
  let dict = parse_dict("\"Array\"\n\"Option\"\n\"fn\"\n")
  let out = mutate_named("dict_token", "foo", Rng::new(0UL), [], dict~)
  assert_true(out == "Array" || out == "Option")
  let only_keyword = parse_dict("\"fn\"\n")
  @test.assert_eq(
    mutate_named("dict_token", "foo", Rng::new(0UL), [], dict=only_keyword),
    "foo",
  )
  // The fallback dictionary also yields a replacement for a plain identifier.
  assert_true(mutate_named("dict_token", "foo", Rng::new(2UL), []) != "foo")
}

///|
test "insert_stmt adds a line, wrap wraps, delim removes one bracket" {
  let src = "fn f() {\n  let x = 1\n}\n"
  let ins = insert_stmt(src, Rng::new(0UL))
  assert_true(ins.char_length() > src.char_length())
  assert_true(ins.contains("let x = 1"))
  let wrapped = wrap("let x = (1 + 2)", Rng::new(0UL))
  assert_true(wrapped != "let x = (1 + 2)")
  assert_true(wrapped.contains("(1 + 2)"))
  @test.assert_eq(delim("f()", Rng::new(0UL)).char_length(), 2)
}

///|
test "inject_attr, async and comment_cut append the expected syntax" {
  let src = "fn f() {\n}\n"
  let attr = inject_attr(src, Rng::new(0UL))
  assert_true(attr.contains("#["))
  assert_true(attr.has_suffix("fn f() {\n}\n"))
  let a = async_mut("x", Rng::new(0UL))
  assert_true(a.contains("async fn __af() -> Unit"))
  let c = comment_cut("x", Rng::new(0UL))
  assert_true(c.has_prefix("x\n/*"))
  assert_true(!c.has_suffix("*/"))
}

///|
test "generic rewrites the first function signature" {
  let out = generic("fn foo(x : Int) -> Int { x }", Rng::new(0UL))
  @test.assert_eq(out, "fn foo[T] (x : T) -> T (x : Int) -> Int { x }")
  @test.assert_eq(generic("let x = 1", Rng::new(0UL)), "let x = 1")
}

///|
test "splice_fn copies a function from the pool" {
  let src = "fn a() {\n}\n"
  let pool = ["fn b() {\n  let y = 2\n}\n"]
  let out = splice_fn(src, Rng::new(0UL), pool)
  assert_true(out.has_prefix(src))
  assert_true(out.contains("fn b() {"))
  assert_true(out.has_suffix("}\n"))
  @test.assert_eq(splice_fn(src, Rng::new(0UL), [src]), src)
  @test.assert_eq(splice_fn(src, Rng::new(0UL), []), src)
}

///|
test "mutate is deterministic from a seed" {
  let src = "fn f() {\n  let x = 1 + 2\n  if x > 0 { x } else { 0 }\n}\n"
  let pool = ["fn g() {\n  let y = 3\n}\n"]
  let a = mutate(src, Rng::new(123UL), pool, false)
  let b = mutate(src, Rng::new(123UL), pool, false)
  @test.assert_eq(a, b)
  let c = mutate(src, Rng::new(124UL), pool, false)
  assert_true(a != c)
}

///|
test "mutate_named dispatches and unknown names are no-ops" {
  let a = mutate_named("truncate", "abcdef", Rng::new(5UL), [])
  @test.assert_eq(a, truncate("abcdef", Rng::new(5UL)))
  let b = mutate_named("m_truncate", "abcdef", Rng::new(5UL), [])
  @test.assert_eq(b, a)
  @test.assert_eq(
    mutate_named("does_not_exist", "abc", Rng::new(0UL), []),
    "abc",
  )
}

///|
test "mutate output never exceeds 20000 code units" {
  let pool : Array[String] = []
  let long = "abcdefghij".repeat(2500)
  for seed in 0..<32 {
    let out = mutate(long, Rng::new(seed.to_uint64()), pool, false)
    assert_true(out.length() <= 20000)
    assert_true(out.char_length() <= 20000)
    assert_true(out.length() > 0)
  }
  let exactly = "abcdefghij".repeat(2000)
  for seed in 0..<16 {
    let out = mutate(exactly, Rng::new(seed.to_uint64()), pool, true)
    assert_true(out.length() <= 20000)
    assert_true(out.char_length() <= 20000)
  }
}
