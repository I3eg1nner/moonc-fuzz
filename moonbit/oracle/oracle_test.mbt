///|
fn be(
  kind : String,
  rc : Int32,
  out : String,
  stage : @oracle.Stage,
) -> @oracle.BackendResult {
  {
    kind,
    rc,
    out,
    stage,
    detail: "",
    truncated: false,
    out_digest: "",
    out_len: 0L,
  }
}

///|
fn bt(
  kind : String,
  rc : Int32,
  out : String,
  stage : @oracle.Stage,
  digest : String,
  len : Int64,
) -> @oracle.BackendResult {
  {
    kind,
    rc,
    out,
    stage,
    detail: "",
    truncated: true,
    out_digest: digest,
    out_len: len,
  }
}

///|
test "oracle sensitivity: injected stdout mismatch" {
  assert_true(!@oracle.outcomes_agree("OK", 0, "a", "OK", 0, "b"))
  assert_true(@oracle.outcomes_agree("OK", 0, "a", "OK", 0, "a"))
}

///|
test "oracle sensitivity: injected rc mismatch and success/failure split" {
  assert_true(!@oracle.outcomes_agree("OK", 0, "", "OK", 1, ""))
  assert_true(!@oracle.outcomes_agree("OK", 0, "", "ERR", 1, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "OK", 0, ""))
}

///|
test "run-stage traps compare rc and output" {
  assert_true(@oracle.outcomes_agree("SIG", -11, "", "SIG", -11, ""))
  assert_true(!@oracle.outcomes_agree("SIG", -11, "", "ICE", 199, ""))
}

///|
test "outcomes_agree trims both sides before comparing stdout" {
  assert_true(@oracle.outcomes_agree("OK", 0, "a\n", "OK", 0, " a "))
  assert_true(!@oracle.outcomes_agree("OK", 0, "a b", "OK", 0, "ab"))
}

///|
test "outcomes_agree does not equate unrelated failures" {
  assert_true(!@oracle.outcomes_agree("SIG", -11, "", "SIG", -6, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "ICE", 2, ""))
  assert_true(!@oracle.outcomes_agree("ICE", 199, "", "OOM", 199, ""))
}

///|
test "link failure vs build failure is inconclusive, not same" {
  assert_true(
    @oracle.classify_diff(
      be("ERR", 2, "", @oracle.Link),
      be("ERR", 2, "", @oracle.Build),
    ) ==
    @oracle.Inconclusive,
  )
}

///|
test "one backend runs while the other is rejected is an acceptance diff" {
  assert_true(
    @oracle.classify_diff(
      be("OK", 0, "x", @oracle.Run),
      be("ERR", 2, "", @oracle.Build),
    ) ==
    @oracle.AcceptDiff,
  )
}

///|
test "compiler abort is never folded into same" {
  assert_true(
    @oracle.classify_diff(
      be("ICE", 199, "", @oracle.Link),
      be("ERR", 2, "", @oracle.Build),
    ) ==
    @oracle.CompilerAbort,
  )
  assert_true(
    @oracle.classify_diff(
      be("ICE", 199, "", @oracle.Build),
      be("ICE", 199, "", @oracle.Build),
    ) ==
    @oracle.CompilerAbort,
  )
}

///|
test "both sides execute and agree only when rc and stdout match" {
  assert_true(
    @oracle.classify_diff(
      be("OK", 0, "x\n", @oracle.Run),
      be("OK", 0, " x ", @oracle.Run),
    ) ==
    @oracle.Same,
  )
  assert_true(
    @oracle.classify_diff(
      be("OK", 0, "x", @oracle.Run),
      be("OK", 0, "y", @oracle.Run),
    ) ==
    @oracle.SemanticDiff,
  )
  assert_true(
    @oracle.classify_diff(
      be("OK", 0, "x", @oracle.Run),
      be("OK", 1, "x", @oracle.Run),
    ) ==
    @oracle.SemanticDiff,
  )
}

///|
test "both sides fail before execution is inconclusive" {
  assert_true(
    @oracle.classify_diff(
      be("ERR", 2, "", @oracle.Link),
      be("ERR", 2, "", @oracle.Build),
    ) ==
    @oracle.Inconclusive,
  )
}

///|
test "truncated outputs never produce a false SAME" {
  let a = bt(
    "OK",
    0,
    "prefix\n[output truncated]",
    @oracle.Run,
    "sha-a",
    2000000L,
  )
  let b = bt(
    "OK",
    0,
    "prefix\n[output truncated]",
    @oracle.Run,
    "sha-b",
    2000000L,
  )
  assert_true(@oracle.classify_diff(a, b) == @oracle.SemanticDiff)
  let same = bt(
    "OK",
    0,
    "prefix\n[output truncated]",
    @oracle.Run,
    "sha-a",
    2000000L,
  )
  assert_true(@oracle.classify_diff(a, same) == @oracle.Same)
}

///|
test "one truncated side is inconclusive, not SAME" {
  let a = bt(
    "OK",
    0,
    "prefix\n[output truncated]",
    @oracle.Run,
    "sha",
    2000000L,
  )
  let b = be("OK", 0, "prefix", @oracle.Run)
  assert_true(@oracle.classify_diff(a, b) == @oracle.Inconclusive)
}

///|
test "native abort is a completed run, not a build failure" {
  let wasm = be("ERR", 1, "", @oracle.Run)
  let native = be("ERR", 134, "", @oracle.NativeRun)
  assert_true(@oracle.classify_diff(wasm, native) == @oracle.RuntimeDiff)
}
