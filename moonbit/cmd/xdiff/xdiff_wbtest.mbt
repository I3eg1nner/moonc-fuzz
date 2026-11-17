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
    test_statuses: "",
    tests_total: 0,
    tests_passed: 0,
    tests_failed: 0,
    tests_unparsed: 0,
  }
}

///|
/// Test-driver observation shorthand.  `executed` mirrors the driver rule: only
/// a parsed summary with at least one test counts as executed.
fn t_tobs(
  target : String,
  rc : Int32,
  statuses : String,
  total : Int32,
  passed : Int32,
  failed : Int32,
  klass : String,
) -> TargetObs {
  {
    target,
    stage: "test",
    rc,
    executed: klass == "OK" || klass == "RUN_RC",
    stdout: "",
    stderr_short: "",
    digest: "",
    ms: 0L,
    klass,
    signature: test_signature(total, passed, failed),
    artifact: "",
    test_statuses: statuses,
    tests_total: total,
    tests_passed: passed,
    tests_failed: failed,
    tests_unparsed: 0,
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

///|
/// One verbose pass line and the matching summary line, exactly as `moon test
/// -v --no-parallelize` prints them for a single async case.
fn t_pass_blob(name : String) -> String {
  "[pkg] test lib/lib_test.mbt:2 (\"" +
  name +
  "\") ok\nTotal tests: 1, passed: 1, failed: 0.\n"
}

///|
fn t_fail_blob(name : String) -> String {
  "[pkg] test lib/lib_test.mbt:2 (\"" +
  name +
  "\") failed: lib/lib_test.mbt:4:3-4:24@pkg FAILED: `Some(1) != Some(2)`\ndiff:\nSome(-1 +2)\nTotal tests: 1, passed: 0, failed: 1.\n"
}

///|
test "test driver parsing: all pass" {
  let sum = parse_test_output(t_pass_blob("c000-opt"))
  assert_eq(sum.statuses.length(), 1)
  assert_eq(sum.statuses.get("c000-opt"), Some("pass"))
  assert_true(sum.has_counts)
  assert_eq(sum.total, 1)
  assert_eq(sum.passed, 1)
  assert_eq(sum.failed, 0)
  assert_eq(sum.unparsed, 0)
  assert_eq(canonical_statuses(sum), "c000-opt=pass")
}

///|
test "test driver parsing: one fail keeps the name and the failure" {
  let sum = parse_test_output(t_fail_blob("c081-f8"))
  assert_eq(sum.statuses.get("c081-f8"), Some("fail"))
  assert_eq(sum.total, 1)
  assert_eq(sum.failed, 1)
  assert_eq(canonical_statuses(sum), "c081-f8=fail")
}

///|
test "test driver parsing: per-test table is order insensitive" {
  let a = parse_test_output(
    "[p] test a.mbt:1 (\"b\") ok\n[p] test a.mbt:2 (\"a\") ok\nTotal tests: 2, passed: 2, failed: 0.\n",
  )
  let b = parse_test_output(
    "[p] test a.mbt:2 (\"a\") ok\n[p] test a.mbt:1 (\"b\") ok\nTotal tests: 2, passed: 2, failed: 0.\n",
  )
  assert_eq(canonical_statuses(a), canonical_statuses(b))
  assert_eq(canonical_statuses(a), "a=pass;b=pass")
}

///|
test "test driver parsing: malformed output never invents a result" {
  let sum = parse_test_output("")
  assert_false(sum.has_counts)
  assert_eq(sum.statuses.length(), 0)
  assert_eq(sum.total, 0)
  // A line that looks like a test line but has no name/status is counted.
  let bad = parse_test_output("[pkg] test lib/lib_test.mbt:2 broken\n")
  assert_eq(bad.unparsed, 1)
  assert_eq(bad.statuses.length(), 0)
  assert_false(bad.has_counts)
  // Garbage that is not a test line at all is ignored, not counted.
  let noise = parse_test_output("Warning: [0029] unused package\nbuilding...\n")
  assert_eq(noise.unparsed, 0)
}

///|
test "test driver parsing: no test entry yields zero counts, not a failure" {
  let sum = parse_test_output(
    "Warning: no test entry found.\nTotal tests: 0, passed: 0, failed: 0.\n",
  )
  assert_true(sum.has_counts)
  assert_eq(sum.total, 0)
  assert_eq(canonical_statuses(sum), "")
}

///|
test "async verdict: identical outcomes are ALL_EQUAL" {
  let obs = [
    t_tobs("js", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("wasm", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("native", 0, "c000=pass", 1, 1, 0, "OK"),
  ]
  assert_eq(async_divergence(obs), "")
  assert_eq(async_verdict_of(obs), "ALL_EQUAL")
}

///|
test "async verdict: a per-test status divergence is TEST_STATUS_MISMATCH" {
  // Same counts, different outcome: the strong signal comes from the table.
  let obs = [
    t_tobs("js", 2, "c000=pass;c001=fail", 2, 1, 1, "RUN_RC"),
    t_tobs("wasm", 2, "c000=fail;c001=pass", 2, 1, 1, "RUN_RC"),
  ]
  assert_eq(async_divergence(obs), "status")
  assert_eq(async_verdict_of(obs), "TEST_STATUS_MISMATCH")
}

///|
test "async verdict: missing test on one target is a status divergence" {
  // js ran both tests, wasm only one: the table differs by a missing key.
  let obs = [
    t_tobs("js", 0, "c000=pass;c001=pass", 2, 2, 0, "OK"),
    t_tobs("wasm", 0, "c000=pass", 1, 1, 0, "OK"),
  ]
  assert_eq(async_verdict_of(obs), "TEST_STATUS_MISMATCH")
}

///|
test "async verdict: printed counts divergence is TEST_STATUS_MISMATCH" {
  // Same status table, different printed totals: a reporting divergence.
  let obs = [
    t_tobs("js", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("wasm", 0, "c000=pass", 2, 2, 0, "OK"),
  ]
  assert_eq(async_divergence(obs), "counts")
  assert_eq(async_verdict_of(obs), "TEST_STATUS_MISMATCH")
}

///|
test "async verdict: rc-only divergence is labelled separately and weakened" {
  let obs = [
    t_tobs("js", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("wasm", 1, "c000=pass", 1, 1, 0, "RUN_RC"),
  ]
  assert_eq(async_divergence(obs), "rc")
  assert_eq(async_verdict_of(obs), "TEST_RC_MISMATCH")
}

///|
test "async verdict: known ICE is excluded from comparison and labels the case" {
  // The F8 control: every target fails to link, no test outcome exists.
  let all_ice = [
    t_tobs("js", 1, "", 0, 0, 0, "KNOWN_LINK_ICE"),
    t_tobs("wasm", 1, "", 0, 0, 0, "KNOWN_LINK_ICE"),
    t_tobs("native", 1, "", 0, 0, 0, "KNOWN_LINK_ICE"),
  ]
  assert_eq(async_divergence(all_ice), "")
  assert_eq(async_verdict_of(all_ice), "KNOWN_LINK_ICE")
  // One target ran, the other hit the known ICE: still a known-ICE label,
  // never SINGLE_TARGET and never a mismatch.
  let mixed = [
    t_tobs("js", 0, "c081=pass", 1, 1, 0, "OK"),
    t_tobs("wasm", 1, "", 0, 0, 0, "KNOWN_LINK_ICE"),
  ]
  assert_eq(async_verdict_of(mixed), "KNOWN_LINK_ICE")
}

///|
test "async verdict: unknown ICE outranks the known label" {
  let obs = [
    t_tobs("js", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("wasm", 2, "", 0, 0, 0, "ICE"),
    t_tobs("native", 1, "", 0, 0, 0, "KNOWN_LINK_ICE"),
  ]
  assert_eq(async_verdict_of(obs), "ICE")
}

///|
test "async verdict: missing target cannot diverge" {
  // wasm-gc reports "no test entry": total 0, excluded.
  let one = [
    t_tobs("js", 0, "c000=pass", 1, 1, 0, "OK"),
    t_tobs("wasm-gc", 0, "", 0, 0, 0, "NO_TESTS"),
  ]
  assert_eq(async_verdict_of(one), "SINGLE_TARGET")
  // No target produced a test at all.
  let none = [
    t_tobs("wasm-gc", 0, "", 0, 0, 0, "NO_TESTS"),
    t_tobs("wasm-gc2", 0, "", 0, 0, 0, "NO_TESTS"),
  ]
  assert_eq(async_verdict_of(none), "NO_TESTS")
  // An unparseable failure is a build failure, not an empty outcome table.
  let bf = [t_tobs("js", 2, "", 0, 0, 0, "BUILD_FAIL")]
  assert_eq(async_verdict_of(bf), "BUILD_FAIL")
  let empty : Array[TargetObs] = []
  assert_eq(async_verdict_of(empty), "NO_RUN")
}

///|
test "async summary reports the test-driver mode and mismatch detail" {
  let cfg : Config = {
    out: "/tmp/xdiff-unit",
    family: "async",
    targets: ["js", "wasm"],
    limit: 1,
    timeout_ms: 1000,
    jobs: 1,
    keep: false,
    only: "",
  }
  let rec : CaseRec = {
    index: 0,
    id: "c000-opt",
    verdict: "TEST_STATUS_MISMATCH",
    obs: [
      t_tobs("js", 2, "c000=fail", 1, 0, 1, "RUN_RC"),
      t_tobs("wasm", 0, "c000=pass", 1, 1, 0, "OK"),
    ],
    dir: "/tmp/xdiff-unit/c000-opt",
    note: "test-driver:per-test-status",
  }
  let s = summary_json(cfg, [rec])
  assert_true(s.contains("\"mode\":\"test-driver\""))
  assert_true(s.contains("\"test_status_compared\":true"))
  assert_true(s.contains("\"TEST_STATUS_MISMATCH\":1"))
  assert_true(s.contains("\"mismatches\":[{\"id\":\"c000-opt\""))
  assert_true(s.contains("\"test_statuses\":\"c000=fail\""))
  assert_true(s.contains("\"tests_failed\":1"))
  // The exec-mode summary keeps its old comparison block.
  let lcfg : Config = {
    out: "/tmp/xdiff-unit",
    family: "layout",
    targets: ["js"],
    limit: 1,
    timeout_ms: 1000,
    jobs: 1,
    keep: false,
    only: "",
  }
  let ls = summary_json(lcfg, [])
  assert_true(ls.contains("\"mode\":\"exec\""))
  assert_true(ls.contains("\"only_built_targets_compared\":true"))
}

///|
test "only accepts a comma-separated list" {
  assert_true(only_matches("", "x"))
  assert_true(only_matches("a", "a"))
  assert_false(only_matches("a", "b"))
  assert_true(only_matches("a, b,c", "b"))
  assert_false(only_matches("a,b", "ab"))
  let cfg = t_cfg(["js"], 0)
  cfg.only = "c000-opt-np-straight-g-fn,c081-optraiseopt-bef-straight-g-fn"
  let picked = select_async(cfg)
  assert_eq(picked.length(), 2)
  assert_eq(picked[0].id, "c000-opt-np-straight-g-fn")
  assert_true(picked[1].f8_control)
}
