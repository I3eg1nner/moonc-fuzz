///|
/// Pure unit tests: no compiler, no child process, no network.

///|
fn t_obs(
  target : String,
  rc : Int32,
  out : String,
  executed : Bool,
  klass : String,
) -> TargetObs {
  {
    target,
    stage: if executed {
      "run"
    } else {
      "build"
    },
    rc,
    executed,
    stdout: out,
    stderr_short: "",
    digest: output_digest(out),
    ms: 0L,
    klass,
    signature: "",
    artifact: "",
  }
}

///|
fn t_cfg(targets : Array[String], limit : Int32) -> Config {
  {
    out: "/tmp/xdiff-unit",
    family: "layout",
    targets,
    limit,
    timeout_ms: 1000,
    jobs: 1,
    keep: false,
    only: "",
  }
}

///|
test "trailing whitespace normalization only touches the tail" {
  assert_eq(strip_trailing_ws("abc\n"), "abc")
  assert_eq(strip_trailing_ws("abc \r\n\t"), "abc")
  assert_eq(strip_trailing_ws("a\n\nb\n"), "a\n\nb")
  assert_eq(strip_trailing_ws(" a\n b "), " a\n b")
  assert_eq(strip_trailing_ws(""), "")
  assert_eq(strip_trailing_ws("\n\n"), "")
}

///|
test "digest is over raw stdout, comparison over normalized stdout" {
  let a = t_obs("wasm-gc", 0, "42\n", true, "OK")
  let b = t_obs("js", 0, "42", true, "OK")
  assert_eq(output_digest("42\n") == output_digest("42"), false)
  assert_eq(obs_equal(a, b), true)
  let c = t_obs("js", 0, "42 \n\n", true, "OK")
  assert_eq(obs_equal(a, c), true)
}

///|
test "exit status is compared exactly" {
  let a = t_obs("wasm-gc", 0, "42\n", true, "OK")
  let b = t_obs("js", 3, "42\n", true, "RUN_RC")
  assert_eq(obs_equal(a, b), false)
  let obs = [a, b]
  assert_eq(verdict_of(obs), "OUTPUT_MISMATCH")
}

///|
test "identical outputs on all targets is ALL_EQUAL" {
  let obs = [
    t_obs("wasm-gc", 0, "2061499447\n", true, "OK"),
    t_obs("wasm", 0, "2061499447", true, "OK"),
    t_obs("js", 0, "2061499447\n", true, "OK"),
  ]
  assert_eq(verdict_of(obs), "ALL_EQUAL")
}

///|
test "stdout divergence is OUTPUT_MISMATCH" {
  let obs = [
    t_obs("wasm-gc", 0, "2061499447\n", true, "OK"),
    t_obs("js", 0, "2061499448\n", true, "OK"),
  ]
  assert_eq(verdict_of(obs), "OUTPUT_MISMATCH")
}

///|
test "known ICE is never compared and never becomes a mismatch" {
  let obs = [
    t_obs("wasm-gc", 0, "7\n", true, "OK"),
    t_obs("js", 0, "7\n", true, "OK"),
    t_obs("native", 2, "", false, "KNOWN_LINK_ICE"),
  ]
  assert_eq(verdict_of(obs), "KNOWN_LINK_ICE")
}

///|
test "only one executed target can never diverge" {
  let obs = [
    t_obs("wasm-gc", 0, "7\n", true, "OK"),
    t_obs("native", 2, "", false, "BUILD_FAIL"),
  ]
  assert_eq(verdict_of(obs), "SINGLE_TARGET")
  // With two executed targets, a third failing target is a build failure.
  let obs2 = [
    t_obs("wasm-gc", 0, "7\n", true, "OK"),
    t_obs("js", 0, "7\n", true, "OK"),
    t_obs("native", 2, "", false, "BUILD_FAIL"),
  ]
  assert_eq(verdict_of(obs2), "BUILD_FAIL")
  let none : Array[TargetObs] = []
  assert_eq(verdict_of(none), "NO_RUN")
  let infra = [t_obs("js", 1, "", false, "INFRA")]
  assert_eq(verdict_of(infra), "INFRA")
}

///|
test "unknown ICE outranks a plain build failure" {
  let obs = [
    t_obs("wasm-gc", 0, "7\n", true, "OK"),
    t_obs("native", 2, "", false, "ICE"),
    t_obs("js", 0, "7\n", true, "OK"),
  ]
  assert_eq(verdict_of(obs), "ICE")
}

///|
test "known upstream signature labels" {
  assert_eq(
    known_ice_label("Error: Machine_of_clam_lower.lower_array_make"),
    "known_f7:lower_array_make",
  )
  assert_eq(
    known_ice_label("error: finish_stub_wrapper_shell failed"),
    "known_f9:finish_stub_wrapper_shell",
  )
  assert_eq(
    known_ice_label("File \"moonc.ml\", line 125623, characters 29-35"),
    "known_f8:moonc.ml:125623",
  )
  assert_eq(known_ice_label("unrelated compiler output"), "")
}

///|
test "build failure classification separates known, unknown and infra" {
  let (c1, s1) = classify_build_failure(
    "build", 2, false, "Oops, ... lower_array_make ...",
  )
  assert_eq(c1, "KNOWN_LINK_ICE")
  assert_eq(s1, "known_f7:lower_array_make")
  let (c2, _) = classify_build_failure(
    "build", 2, false, "Oops, the compiler has encountered an error",
  )
  assert_eq(c2, "ICE")
  let (c3, _) = classify_build_failure(
    "build", 2, false, "failed to download moonbitlang/async@0.22.9",
  )
  assert_eq(c3, "INFRA")
  let (c4, s4) = classify_build_failure("build", 2, false, "some type error")
  assert_eq(c4, "BUILD_FAIL")
  assert_eq(s4, "build:rc=2")
  let (c5, _) = classify_build_failure("build", -999, true, "")
  assert_eq(c5, "TIMEOUT")
}

///|
test "layout selection always carries the F7 seed and control" {
  let cfg = t_cfg(["wasm-gc", "js"], 2)
  let cases = select_layout(cfg)
  assert_eq(cases.length(), 4)
  let seed = @featuregen.f7_seed()
  let control = @featuregen.f7_control()
  let mut saw_seed = false
  let mut saw_control = false
  for c in cases {
    if c.id == seed.id {
      saw_seed = true
    }
    if c.id == control.id {
      saw_control = true
    }
  }
  assert_eq(saw_seed, true)
  assert_eq(saw_control, true)
  // Duplicate suppression: the seed already sits in the prefix for a full run.
  let all = select_layout(t_cfg(["js"], 0))
  assert_eq(all.length(), @featuregen.layout_cases().length())
}

///|
test "target list parsing" {
  let t = parse_targets("wasm-gc, wasm ,js,native,")
  assert_eq(t.length(), 4)
  assert_eq(t[0], "wasm-gc")
  assert_eq(t[1], "wasm")
  assert_eq(t[3], "native")
  assert_eq(parse_targets("").length(), 0)
}

///|
test "summary renders mismatch observations and class counts" {
  let cfg = t_cfg(["wasm-gc", "js"], 0)
  let rec : CaseRec = {
    index: 0,
    id: "LX",
    verdict: "OUTPUT_MISMATCH",
    obs: [
      t_obs("wasm-gc", 0, "1\n", true, "OK"),
      t_obs("js", 0, "2\n", true, "OK"),
    ],
    dir: "/tmp/xdiff-unit/LX",
    note: "",
  }
  let s = summary_json(cfg, [rec])
  assert_true(s.contains("\"mismatches\":[{\"id\":\"LX\""))
  assert_true(s.contains("\"OUTPUT_MISMATCH\":1"))
  assert_true(s.contains("\"wasm-gc\":1"))
  assert_true(s.contains("\"js\":1"))
}
