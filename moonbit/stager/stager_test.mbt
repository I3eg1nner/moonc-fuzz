///|
/// Tests for the staging layer.  The properties that matter here are the ones
/// every driver depends on: signatures must be stable against path and number
/// noise, and a parse error must never be classified as a defect.

///|
fn crash_obs(stage : String, text : String) -> @judge.Observation {
  @judge.observation(stage, 1, false, 100L, 90L, 0, false, false, "", text)
}

///|
test "normalize: digit runs collapse, whitespace collapses" {
  assert_eq(
    normalize("failed to link a/core at offset 4096 (0x1000)"),
    "failed to link a/core at offset # (#x#)",
  )
  assert_eq(normalize("a   b\t\tc"), "a b c")
}

///|
test "signature: same ICE at different temp paths has one signature" {
  let one = crash_obs(
    "build",
    "Error: failed to build x (native): /tmp/mbtfuzz_seedfuzz/cmd/main.mbt\n" +
    "Oops, the compiler has encountered an exception\n" +
    "Error: Machine_error(kind=unescape; message=\"bad byte\")\n",
  )
  let two = crash_obs(
    "build",
    "Error: failed to build x (native): /tmp/mbtfuzz_seedbase99/cmd/main.mbt\n" +
    "Oops, the compiler has encountered an exception\n" +
    "Error: Machine_error(kind=unescape; message=\"bad byte\")\n",
  )
  assert_eq(
    signature("build", run_result(one)),
    signature("build", run_result(two)),
  )
}

///|
/// Rebuild a `RunResult` from an observation so the test exercises the public
/// entry point instead of the judge directly.
fn run_result(o : @judge.Observation) -> @exec.RunResult {
  {
    rc: o.rc,
    stdout: o.stdout,
    stderr: o.stderr,
    ms: o.wall_ms,
    timed_out: o.timed_out,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
}

///|
test "is_defect: a parse error is not a defect" {
  let r = run_result(
    crash_obs("build", "Error: [4021] Parse error, unexpected token `while`\n"),
  )
  assert_false(is_defect("build", r))
  assert_eq(signature("build", r), "fail/rc=#")
}

///|
test "is_defect: a compiler ICE is a defect" {
  let r = run_result(
    crash_obs(
      "build", "Oops, the compiler has encountered an exception\nError: Machine_error()\n",
    ),
  )
  assert_true(is_defect("build", r))
  assert_true(signature("build", r).has_prefix("crash|ICE|Machine_error"))
}

///|
test "count_lines: blank lines are not counted" {
  assert_eq(count_lines("a\n\nb\n"), 2)
  assert_eq(count_lines(""), 0)
}

///|
test "mbt_files: recursive, _build excluded" {
  let dir = "/tmp/mbtfuzz_stager_test"
  rm_rf(dir)
  let _ = @fs.create_dir(dir)
  let _ = @fs.create_dir(join(dir, "cmd"))
  let _ = @fs.create_dir(join(dir, "_build"))
  let _ = write_text(join(dir, "lib.mbt"), "pub fn a() -> Int { 1 }")
  let _ = write_text(join(dir, "cmd/main.mbt"), "fn main { () }")
  let _ = write_text(join(dir, "_build/x.mbt"), "junk")
  let _ = write_text(join(dir, "moon.mod"), "")
  let files = mbt_files(dir)
  assert_eq(files.length(), 2)
  assert_true(files.contains("lib.mbt"))
  assert_true(files.contains("cmd/main.mbt"))
  rm_rf(dir)
}

///|
test "copy_pkg: copies sources and skips _build" {
  let src = "/tmp/mbtfuzz_stager_src"
  let dst = "/tmp/mbtfuzz_stager_dst"
  rm_rf(src)
  rm_rf(dst)
  let _ = @fs.create_dir(src)
  let _ = @fs.create_dir(join(src, "_build"))
  let _ = write_text(join(src, "lib.mbt"), "x")
  let _ = write_text(join(src, "_build/big.bin"), "y")
  assert_true(copy_pkg(src, dst))
  assert_true(@fs.path_exists(join(dst, "lib.mbt")))
  assert_false(@fs.path_exists(join(dst, "_build")))
  rm_rf(src)
  rm_rf(dst)
}

///|
/// Adapter regression: wall time is not CPU time.  A timeout observed through
/// `observation_of` must not be reported as a busy hang (unknown CPU), and a
/// normal exit must stay clean.
test "timeout without CPU accounting is timeout_plain, not busy_hang" {
  let timeout : @exec.RunResult = {
    rc: -999,
    stdout: "",
    stderr: "",
    ms: 3000L,
    timed_out: true,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  let obs = observation_of("build", timeout)
  assert_eq(obs.cpu_ms, 0L)
  let mut buses = 0
  let mut plains = 0
  for f in findings("build", timeout) {
    if f.oracle == "busy_hang" {
      buses += 1
    }
    if f.oracle == "timeout_plain" {
      plains += 1
    }
  }
  assert_eq(buses, 0)
  assert_eq(plains, 1)
}
