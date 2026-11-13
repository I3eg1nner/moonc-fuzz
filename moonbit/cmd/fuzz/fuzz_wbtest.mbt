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
  }
  let err : @exec.RunResult = {
    rc: 2,
    stdout: "[E3001]",
    stderr: "",
    ms: 0,
    timed_out: false,
  }
  assert_eq(behavior_sig(ok), "ACC|E3001")
  assert_eq(behavior_sig(err), "ERR|E3001")
}

///|
test "with_main does not duplicate an existing main" {
  assert_eq(with_main("fn main { () }"), "fn main { () }")
  assert_true(with_main("fn f() { }").contains("fn main"))
}
