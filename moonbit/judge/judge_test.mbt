///|
/// Tests for the oracle layer.  These are the properties the injection matrix
/// relies on; if one of them breaks, the audit table becomes meaningless even
/// though `oracleaudit` may still print "ok".

///|
fn obs_ice() -> Observation {
  observation(
    "build", 1, false, 900L, 700L, 0, false, false, "", "Oops, the compiler has encountered an exception\nError: i32\n",
  )
}

///|
test "crash: marker on stdout is not a crash" {
  let o = observation(
    "test", 1, false, 100L, 90L, 1, true, false, "Oops, the compiler has encountered an exception\n",
    "",
  )
  let s = spec(Crash, "t")
  assert_eq(check(s, o).length(), 0)
}

///|
test "crash: signal exit is classified from rc alone" {
  let o = observation(
    "test-build", -11, false, 300L, 280L, 0, false, false, "", "",
  )
  let f = check(spec(Crash, "t"), o)
  assert_eq(f.length(), 1)
  assert_eq(f[0].class, "SIG")
  assert_eq(severity_name(f[0].severity), "defect")
}

///|
test "crash: Error line is captured and truncated at 160 chars" {
  let long = "Oops, the compiler has encountered an exception\nError: " +
    "x".repeat(400)
  let o = observation("build", 1, false, 10L, 10L, 0, false, false, "", long)
  let f = check(spec(Crash, "t"), o)
  assert_eq(f.length(), 1)
  assert_eq(f[0].detail.char_length(), 160)
}

///|
test "busy_hang: half CPU is the boundary and counts as busy" {
  let o = observation("lsp", -1, true, 2000L, 1000L, 0, true, true, "", "")
  assert_eq(check(spec(BusyHang, "t"), o).length(), 1)
  let slower = observation("lsp", -1, true, 2000L, 999L, 0, true, true, "", "")
  assert_eq(check(spec(BusyHang, "t"), slower).length(), 0)
}

///|
test "blocked_stall: needs timeout, low CPU, live child and owed output" {
  let base = observation("lsp", -1, true, 3000L, 10L, 0, true, true, "", "")
  assert_eq(check(spec(BlockedStall, "t"), base).length(), 1)
  let wrong : Array[Observation] = [
    observation("lsp", -1, true, 3000L, 10L, 0, false, true, "", ""),
    observation("lsp", -1, true, 3000L, 10L, 0, true, false, "", ""),
    observation("lsp", -1, false, 3000L, 10L, 0, true, true, "", ""),
    observation("lsp", -1, true, 3000L, 2900L, 0, true, true, "", ""),
  ]
  for o in wrong {
    assert_eq(check(spec(BlockedStall, "t"), o).length(), 0)
  }
}

///|
test "timeout_plain: does not double-report busy or stalled" {
  let busy = observation("lsp", -1, true, 3000L, 2980L, 0, true, true, "", "")
  let stall = observation("lsp", -1, true, 3000L, 8L, 0, true, true, "", "")
  let plain = observation("build", -1, true, 5000L, 20L, 0, true, false, "", "")
  assert_eq(check(spec(TimeoutPlain, "t"), busy).length(), 0)
  assert_eq(check(spec(TimeoutPlain, "t"), stall).length(), 0)
  assert_eq(check(spec(TimeoutPlain, "t"), plain).length(), 1)
}

///|
test "missing_frames: success plus owed output only" {
  let owes = observation("run", 0, false, 90L, 60L, 0, true, false, "", "")
  let no_owe = observation("run", 0, false, 90L, 60L, 0, false, false, "", "")
  let has = observation("run", 0, false, 90L, 60L, 2, true, false, "", "")
  let failed = observation("run", 1, false, 90L, 60L, 0, true, false, "", "")
  assert_eq(check(spec(MissingFrames, "t"), owes).length(), 1)
  assert_eq(check(spec(MissingFrames, "t"), no_owe).length(), 0)
  assert_eq(check(spec(MissingFrames, "t"), has).length(), 0)
  assert_eq(check(spec(MissingFrames, "t"), failed).length(), 0)
}

///|
test "nonzero_silent: suppressed by any diagnostic" {
  let silent = observation("test", 2, false, 100L, 90L, 0, false, false, "", "")
  let loud = observation(
    "test", 2, false, 100L, 90L, 0, false, false, "", "Error: no\n",
  )
  let json = observation(
    "test", 2, false, 100L, 90L, 0, false, false, "", "{\"level\":\"error\",\"message\":\"bad\"}\n",
  )
  assert_eq(check(spec(NonzeroSilent, "t"), silent).length(), 1)
  assert_eq(check(spec(NonzeroSilent, "t"), loud).length(), 0)
  assert_eq(check(spec(NonzeroSilent, "t"), json).length(), 0)
}

///|
test "orphan_leak: a timeout is not also a leak" {
  let leak = observation("run", 0, false, 100L, 80L, 1, true, true, "ok\n", "")
  let timed = observation("run", -1, true, 100L, 80L, 1, true, true, "ok\n", "")
  assert_eq(check(spec(OrphanLeak, "t"), leak).length(), 1)
  assert_eq(check(spec(OrphanLeak, "t"), timed).length(), 0)
}

///|
test "check_all: an ICE that also times out reports both shapes" {
  let o = observation(
    "build", -1, true, 3000L, 2900L, 0, false, true, "", "Oops, the compiler has encountered an exception\n",
  )
  let fs = check_all(registry(), o)
  let classes : Array[String] = []
  for f in fs {
    classes.push(f.class)
  }
  assert_eq(classes.length(), 2)
  assert_true(classes.contains("ICE"))
  assert_true(classes.contains("hang/busy"))
}

///|
test "audit: an oracle with no positive probe is unproven, not ok" {
  let specs : Array[OracleSpec] = [spec(OrphanLeak, "t")]
  let probes : Array[Probe] = [
    { label: "elsewhere", spec: "crash", obs: obs_ice(), want_hit: true, },
  ]
  let a = audit(specs, probes, [])
  assert_false(a.ok())
  assert_eq(a.unproven.length(), 1)
  assert_eq(a.unproven[0], "orphan_leak")
}

///|
test "audit: a positive probe that cannot fire marks the oracle blind" {
  let specs : Array[OracleSpec] = [spec(MissingFrames, "t")]
  let probes : Array[Probe] = [
    {
      label: "impossible",
      spec: "missing_frames",
      // frames=2 contradicts "missing", so the oracle can never fire.
      obs: observation("run", 0, false, 90L, 60L, 2, true, false, "", ""),
      want_hit: true,
    },
  ]
  let a = audit(specs, probes, [])
  assert_false(a.ok())
  assert_eq(a.blind.length(), 1)
  assert_eq(a.scores[0].missed[0], "impossible")
}

///|
test "audit: a control that fires marks the oracle noisy" {
  let specs : Array[OracleSpec] = [spec(Crash, "t")]
  let probes : Array[Probe] = [
    { label: "ice", spec: "crash", obs: obs_ice(), want_hit: true, },
    { label: "control", spec: "crash", obs: obs_ice(), want_hit: false, },
  ]
  let a = audit(specs, probes, [])
  assert_false(a.ok())
  assert_eq(a.noisy.length(), 1)
  assert_eq(a.scores[0].spurious[0], "control")
}

///|
test "audit: global negatives apply to every oracle" {
  let specs = registry()
  let a = audit(specs, probes(), global_negatives())
  assert_true(a.ok())
  for s in a.scores {
    assert_true(s.sensitive())
    assert_true(s.negatives >= 3)
  }
}

///|
test "compare: timeout asymmetry explains the status difference" {
  let lo = observation("wasm", -1, true, 3000L, 10L, 0, true, true, "", "")
  let ro = observation("js", 1, false, 200L, 100L, 0, true, false, "", "")
  let f = compare("wasm", "js", lo, ro)
  assert_eq(f.length(), 1)
  assert_eq(f[0].class, "pair/timeout")
}

///|
test "compare: status and stdout asymmetry, and agreement" {
  let a = observation("wasm", 1, false, 100L, 90L, 0, true, false, "", "")
  let b = observation("js", 0, false, 100L, 90L, 0, true, false, "", "")
  assert_eq(compare("wasm", "js", a, b)[0].class, "pair/status")
  let c = observation("wasm", 0, false, 100L, 90L, 0, true, false, "1\n", "")
  let d = observation("js", 0, false, 100L, 90L, 0, true, false, "2\n", "")
  assert_eq(compare("wasm", "js", c, d)[0].class, "pair/stdout")
  assert_eq(compare("wasm", "js", c, c).length(), 0)
}

///|
test "severity: infra oracles never count as defects" {
  assert_eq(severity_name(kind_severity(OrphanLeak)), "infra")
  assert_eq(severity_name(kind_severity(BlockedStall)), "defect")
  assert_eq(severity_name(kind_severity(TimeoutPlain)), "suspicious")
}

///|
test "json: findings and audits escape quotes and newlines" {
  let f : Finding = {
    oracle: "crash",
    class: "ICE",
    severity: Defect,
    signature: "crash|ICE|x\"y",
    detail: "line1\nline2",
  }
  assert_eq(
    f.to_json(),
    "{\"oracle\":\"crash\",\"class\":\"ICE\",\"severity\":\"defect\",\"signature\":\"crash|ICE|x\\\"y\",\"detail\":\"line1\\nline2\"}",
  )
  let a = audit(registry(), probes(), global_negatives())
  assert_true(a.to_json().has_prefix("{\"ok\":true"))
}
