///|
/// Pure parsing of `moon test` output, plus the test-driver verdict rule.
///
/// Async cases cannot be compared through a `main`: `asyncgen` renders a
/// library plus a blackbox test and declares `supported_targets =
/// "wasm+js+native"`, so `moon build` produces no executable artifact.  The
/// comparison surface is instead the *test driver's* output:
///
///   [pkg] test lib/lib_test.mbt:2 ("c000-...") ok
///   [pkg] test lib/lib_test.mbt:4 ("c000-...") failed: ... FAILED: `...`
///   Total tests: 1, passed: 1, failed: 0.
///
/// Everything here is pure: no compiler, no child process, no clock, so the
/// unit tests can cover arbitrary malformed blobs cheaply.

///|
/// One target's parsed test-driver output.
///
/// `statuses` maps the test name to `pass` / `fail` / `skip` (or `other:<word>`
/// for an unrecognised status word).  `has_counts` records whether a
/// `Total tests:` line was seen at all, which separates "the driver ran and
/// reported" from "the link failed before the driver existed".  `unparsed`
/// counts lines that looked like a test line but could not be split into
/// name+status, so a parser regression is visible in the report rather than
/// silently shrinking the comparison table.
struct TestSummary {
  statuses : Map[String, String]
  mut total : Int32
  mut passed : Int32
  mut failed : Int32
  mut has_counts : Bool
  mut unparsed : Int32
}

///|
fn empty_summary() -> TestSummary {
  {
    statuses: Map([]),
    total: 0,
    passed: 0,
    failed: 0,
    has_counts: false,
    unparsed: 0,
  }
}

///|
/// Leading decimal integer, skipping leading spaces; returns 0 when the text
/// does not start with a digit.  Used for `Total tests: 1, passed: 1, ...`.
fn leading_int(v : StringView) -> Int32 {
  let mut n = 0
  let mut any = false
  for c in v {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else if !any && (c == ' ' || c == '\t') {
      continue
    } else {
      break
    }
  }
  if any {
    n
  } else {
    0
  }
}

///|
/// First bare word of `s`, stopping at space, tab, CR or `:`.  `" ok"` gives
/// `"ok"`, `" failed: lib/..."` gives `"failed"`.
fn status_word(s : StringView) -> String {
  let b = StringBuilder()
  let mut started = false
  for c in s {
    if c == ' ' || c == '\t' || c == '\r' {
      if started {
        break
      }
    } else if c == ':' {
      break
    } else {
      b.write_char(c)
      started = true
    }
  }
  b.to_string()
}

///|
/// Normalize the driver's status word to the compared vocabulary.  Unknown
/// words are preserved (`other:<word>`) so two targets that both print the
/// same exotic status still compare equal, while a target that prints a
/// different one is flagged.
fn status_norm(w : String) -> String {
  if w == "ok" || w == "pass" || w == "passed" {
    "pass"
  } else if w == "failed" || w == "fail" {
    "fail"
  } else if w == "skipped" || w == "skip" {
    "skip"
  } else if w == "" {
    "other"
  } else {
    "other:" + w
  }
}

///|
/// Parse one verbose test line.  Recognised shape:
///
///   [<pkg>] test <file>:<line> ("<name>") <status>[: detail]
///
/// The name is taken between the first `("` and the following `")`; generated
/// names cannot contain that sequence (documented limitation).  A line that
/// starts with `[` and contains `] test ` but lacks the name/status markers is
/// counted in `unparsed` instead of being dropped silently.
fn parse_test_line(line : StringView, sum : TestSummary) -> Unit {
  if !line.has_prefix("[") {
    return
  }
  let pos = match line.find("] test ") {
    Some(p) => p
    None => return
  }
  let rest = line[pos + 7:]
  let a = match rest.find("(\"") {
    Some(p) => p
    None => {
      sum.unparsed += 1
      return
    }
  }
  let after = rest[a + 2:]
  let b = match after.find("\")") {
    Some(p) => p
    None => {
      sum.unparsed += 1
      return
    }
  }
  let name = after[0:b].to_owned()
  if name == "" {
    sum.unparsed += 1
    return
  }
  let tail = after[b + 2:]
  sum.statuses[name] = status_norm(status_word(tail))
}

///|
/// Parse one `Total tests: N, passed: N, failed: N.` line into the running
/// totals.  Counts from several packages (if any) are summed; the current
/// renderer emits exactly one package, so this is only robustness.
fn parse_counts_line(line : StringView, sum : TestSummary) -> Bool {
  if !line.has_prefix("Total tests:") {
    return false
  }
  let rest = line[12:]
  sum.total += leading_int(rest)
  match rest.find("passed:") {
    Some(i) => sum.passed += leading_int(rest[i + 7:])
    None => ()
  }
  match rest.find("failed:") {
    Some(i) => sum.failed += leading_int(rest[i + 7:])
    None => ()
  }
  sum.has_counts = true
  true
}

///|
/// Parse a complete `moon test -v --no-parallelize` stdout blob.
fn parse_test_output(stdout : String) -> TestSummary {
  let sum = empty_summary()
  for raw in stdout.split("\n") {
    let line = raw.trim_end()
    if parse_counts_line(line, sum) {
      continue
    }
    parse_test_line(line, sum)
  }
  sum
}

///|
/// Canonical, order-insensitive encoding of the per-test outcome table.  Test
/// execution order is not stable (the driver may reverse file order), so the
/// names are sorted before encoding; two targets compare equal iff this string
/// is byte-identical.  Sorted form: `name=pass;name2=fail`.
fn canonical_statuses(sum : TestSummary) -> String {
  let names : Array[String] = []
  for k in sum.statuses.keys() {
    names.push(k)
  }
  names.sort()
  let b = StringBuilder()
  let mut first = true
  for n in names {
    if !first {
      b.write_char(';')
    }
    first = false
    b.write_string(n)
    b.write_char('=')
    match sum.statuses.get(n) {
      Some(v) => b.write_string(v)
      None => b.write_string("?")
    }
  }
  b.to_string()
}

///|
/// Per-target summary of the compared surfaces, for the JSONL `signature`.
fn test_signature(total : Int32, passed : Int32, failed : Int32) -> String {
  "tests:" +
  total.to_string() +
  "/" +
  passed.to_string() +
  "/" +
  failed.to_string()
}

///|
/// What diverged between the executed targets in test-driver mode:
/// `"status"` (per-test outcome table), `"counts"` (printed totals) or
/// `"rc"` (exit status only).  Empty when all executed targets agree.
///
/// Status and counts are the strong signal; rc alone is the weak one.  Counts
/// are compared even when the status tables agree, because the printed totals
/// are part of what the driver reports to a user.
fn async_divergence(obs : Array[TargetObs]) -> String {
  let ex = executed(obs)
  if ex.length() < 2 {
    return ""
  }
  let mut status = false
  let mut counts = false
  let mut rc = false
  for i in 1..<ex.length() {
    if ex[0].test_statuses != ex[i].test_statuses {
      status = true
    }
    if ex[0].tests_total != ex[i].tests_total ||
      ex[0].tests_passed != ex[i].tests_passed ||
      ex[0].tests_failed != ex[i].tests_failed {
      counts = true
    }
    if ex[0].rc != ex[i].rc {
      rc = true
    }
  }
  if status {
    "status"
  } else if counts {
    "counts"
  } else if rc {
    "rc"
  } else {
    ""
  }
}

///|
/// Verdict for the test-driver family.
///
/// Precedence: `TEST_STATUS_MISMATCH` (per-test outcome or printed counts
/// differ between two executed targets) > `TEST_RC_MISMATCH` (everything the
/// driver printed agrees, only the process exit status differs) > `ICE` >
/// `KNOWN_LINK_ICE` > `TIMEOUT` > `SINGLE_TARGET` > `BUILD_FAIL` > `INFRA` >
/// `NO_TESTS` > `ALL_EQUAL` > `NO_RUN`.
///
/// A known upstream ICE is never compared: the target never produced a test
/// outcome, so it cannot be a divergence.  It still labels the case when it is
/// the only reason the case is not fully equal (e.g. the F8 control, where
/// every target fails to link).
fn async_verdict_of(obs : Array[TargetObs]) -> String {
  let div = async_divergence(obs)
  if div == "status" || div == "counts" {
    return "TEST_STATUS_MISMATCH"
  }
  if div == "rc" {
    return "TEST_RC_MISMATCH"
  }
  if has_class(obs, "ICE") {
    return "ICE"
  }
  if has_class(obs, "KNOWN_LINK_ICE") {
    return "KNOWN_LINK_ICE"
  }
  if has_class(obs, "TIMEOUT") {
    return "TIMEOUT"
  }
  let ex = executed(obs)
  if ex.length() == 0 {
    if has_class(obs, "BUILD_FAIL") {
      return "BUILD_FAIL"
    }
    if has_class(obs, "INFRA") {
      return "INFRA"
    }
    if has_class(obs, "NO_TESTS") {
      return "NO_TESTS"
    }
    return "NO_RUN"
  }
  if ex.length() == 1 {
    return "SINGLE_TARGET"
  }
  if has_class(obs, "BUILD_FAIL") {
    return "BUILD_FAIL"
  }
  if has_class(obs, "INFRA") {
    return "INFRA"
  }
  "ALL_EQUAL"
}
