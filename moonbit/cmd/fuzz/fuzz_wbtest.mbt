///|
test "mode file names and suffixes" {
  assert_eq(fname_of("mbt"), "in.mbt")
  assert_eq(fname_of("pkg"), "moon.pkg")
  assert_eq(fname_of("mod"), "moon.mod")
  assert_eq(fname_of("mbtmd"), "in.mbt.md")
  assert_eq(fname_of("mbti"), "in.mbti")
  assert_eq(fname_of("mbtx"), "in.mbtx")
  assert_eq(suffixes_of("pkg"), ["moon.pkg"])
  assert_eq(suffixes_of("mbtmd"), [".mbt.md"])
}

///|
test "diagnostic code extraction is sorted and unique" {
  let codes = diag_codes("x [E3001] y [W0002] [E3001] [E123] [E1234]")
  assert_eq(codes, ["E1234", "E3001", "W0002"])
}

///|
test "behavior signature distinguishes accept and error codes" {
  let ok : @exec.RunResult = {
    rc: 0,
    stdout: "",
    stderr: "[E3001]",
    ms: 0,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  let err : @exec.RunResult = {
    rc: 2,
    stdout: "[E3001]",
    stderr: "",
    ms: 0,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  assert_eq(behavior_sig("t1", ok), "t1|ACC|E3001")
  assert_eq(behavior_sig("t1", err), "t1|ERR|E3001")
}

///|
test "with_main does not duplicate an existing main" {
  assert_eq(with_main("fn main { () }"), "fn main { () }")
  assert_true(with_main("fn f() { }").contains("fn main"))
}

///|
test "json diagnostics keep code, message and location" {
  let a = json_diag_sig(
    "{\"level\":\"error\",\"error_code\":3002,\"loc\":\"3:1-3:2\",\"message\":\"Parse error, unexpected token\"}",
  )
  let b = json_diag_sig(
    "{\"level\":\"error\",\"error_code\":3003,\"loc\":\"4:2-4:3\",\"message\":\"Unbound variable\"}",
  )
  assert_true(a is Some(_))
  assert_true(b is Some(_))
  assert_true(a != b)
  assert_true(a.unwrap().contains("E3002"))
  assert_true(a.unwrap().contains("3:1-3:2"))
}

///|
test "json diagnostics do not collapse into one ERR bucket" {
  let mk = fn(msg : String) -> @exec.RunResult {
    {
      rc: 2,
      stdout: "",
      stderr: "{\"level\":\"error\",\"error_code\":3002,\"loc\":\"1:1\",\"message\":\"" +
      msg +
      "\"}",
      ms: 0,
      timed_out: false,
      stdout_digest: "",
      stdout_full_len: 0L,
      stdout_truncated: false,
    }
  }
  let a = behavior_sig("t1", mk("unexpected token A"))
  let b = behavior_sig("t1", mk("unexpected token B"))
  assert_true(a != b)
  assert_true(a.contains("E3002"))
  assert_true(b.contains("E3002"))
}

///|
test "feedback corpus deduplicates and promotes coverage inputs" {
  let f = feedback_new()
  assert_true(feedback_upsert(f, "a", @cov.FuncSet::new([]), 0))
  assert_true(!feedback_upsert(f, "a", @cov.FuncSet::new([]), 0))
  let added = feedback_cover(f, "b", ["f1", "f2"])
  assert_eq(added, 2)
  assert_eq(f.total_cov.len(), 2)
  assert_eq(feedback_cover(f, "b", ["f1", "f2", "f3"]), 1)
  assert_eq(f.total_cov.len(), 3)
  assert_eq(f.coverage_adds, 3)
}

///|
test "feedback parent selection returns a retained input" {
  let f = feedback_new()
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0))
  ignore(feedback_cover(f, "new", ["x", "y"]))
  let rng = @mutate.Rng::new(7UL)
  let mut saw_seed = false
  let mut saw_new = false
  for _ in 0..<50 {
    match feedback_pick(f, rng) {
      Some(s) =>
        if s == "seed" {
          saw_seed = true
        } else if s == "new" {
          saw_new = true
        }
      None => ()
    }
  }
  assert_true(saw_seed)
  assert_true(saw_new)
}

///|
test "zero coverage growth does not admit or reward a parent" {
  let f = feedback_new()
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0))
  assert_eq(f.entries.length(), 1)
  let before = f.entries[0].energy
  assert_eq(feedback_cover(f, "seed", ["f1"]), 1)
  assert_eq(f.entries.length(), 1)
  assert_eq(feedback_cover(f, "other", ["f1"]), 0)
  assert_eq(f.entries.length(), 1)
  assert_eq(f.entries[0].energy, before + 32)
}
