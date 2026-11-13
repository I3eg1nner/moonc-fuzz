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

///|
test "classify checks timed_out first, then stderr markers only" {
  // HANG wins over any marker still in the buffer.
  assert_eq(
    @exec.classify({
      rc: -999,
      stdout: "",
      stderr: "Oops, the compiler has encountered",
      ms: 1,
      timed_out: true,
    }),
    "HANG",
  )
  // "Oops" printed by the fuzzed program itself must not look like an ICE.
  assert_eq(
    @exec.classify({
      rc: 1,
      stdout: "Oops, the compiler has encountered",
      stderr: "",
      ms: 1,
      timed_out: false,
    }),
    "ERR",
  )
  assert_eq(
    @exec.classify({
      rc: 2,
      stdout: "",
      stderr: "Out_of_memory",
      ms: 1,
      timed_out: false,
    }),
    "OOM",
  )
  assert_eq(
    @exec.classify({
      rc: 2,
      stdout: "",
      stderr: "Cannot allocate memory",
      ms: 1,
      timed_out: false,
    }),
    "OOM",
  )
  assert_eq(
    @exec.classify({
      rc: 2,
      stdout: "",
      stderr: "Fatal error: exception Failure(\"x\")",
      ms: 1,
      timed_out: false,
    }),
    "OCAML_EXN",
  )
  assert_eq(
    @exec.classify({
      rc: 2,
      stdout: "",
      stderr: "Stack overflow",
      ms: 1,
      timed_out: false,
    }),
    "STACK",
  )
  assert_eq(
    @exec.classify({
      rc: 2,
      stdout: "",
      stderr: "Assert_failure",
      ms: 1,
      timed_out: false,
    }),
    "ASSERT",
  )
}

///|
test "ice_detail takes the first Error line, trims it, and caps at 200" {
  assert_eq(
    @exec.ice_detail({
      rc: 199,
      stdout: "",
      stderr: "noise\n   Error: Boom   \nError: second\n",
      ms: 0,
      timed_out: false,
    }),
    "Boom",
  )
  assert_eq(
    @exec.ice_detail({
      rc: 1,
      stdout: "Error: from stdout\n",
      stderr: "",
      ms: 0,
      timed_out: false,
    }),
    "from stdout",
  )
  assert_eq(
    @exec.ice_detail({
      rc: 1,
      stdout: "",
      stderr: "no error line\n",
      ms: 0,
      timed_out: false,
    }),
    "",
  )
  let long = "Error: " + "x".repeat(250)
  let detail = @exec.ice_detail({
    rc: 199,
    stdout: "",
    stderr: long,
    ms: 0,
    timed_out: false,
  })
  assert_eq(detail.length(), 200)
}

///|
async test "run1 reports a clean exit" {
  let r = @exec.run1("/bin/true", "/tmp", 5000)
  assert_eq(r.rc, 0)
  assert_eq(r.stdout, "")
  assert_true(!r.timed_out)
}
