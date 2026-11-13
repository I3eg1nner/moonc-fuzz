///|
async test "run captures stdout and rc" {
  let r = @exec.run(
    "/bin/sh",
    ["-c", "printf hi; printf err >&2; exit 7"],
    "/tmp",
    5000,
  )
  assert_eq(r.rc, 7)
  assert_eq(r.stdout, "hi")
  assert_eq(r.stderr, "err")
  assert_true(!r.timed_out)
}

///|
async test "timeout kills the child and is reported" {
  let r = @exec.run("/bin/sleep", ["5"], "/tmp", 150)
  assert_true(r.timed_out)
  assert_eq(r.rc, -999)
}

///|
test "classify ICE and OOM markers" {
  assert_eq(
    @exec.classify({
      rc: 199,
      stdout: "",
      stderr: "Oops, the compiler has encountered",
      ms: 0,
      timed_out: false,
    }),
    "ICE",
  )
  assert_eq(
    @exec.classify({
      rc: -6,
      stdout: "",
      stderr: "Fatal error: out of memory",
      ms: 0,
      timed_out: false,
    }),
    "OOM",
  )
  assert_eq(
    @exec.classify({ rc: -11, stdout: "", stderr: "", ms: 0, timed_out: false, }),
    "SIG",
  )
  assert_eq(
    @exec.classify({ rc: 0, stdout: "", stderr: "", ms: 0, timed_out: false, }),
    "OK",
  )
}
