// Candidate triage.
//
// A campaign stores findings as `status=candidate`; nothing promotes them.
// This command performs the promotion checks and refuses to guess:
//
//   1. fresh copy x3: the same package is rebuilt from scratch each time and
//      the defect signature must match on all three runs;
//   2. relaxed timeout: the run gets 3x the campaign budget, so a machine
//      hiccup cannot masquerade as a hang;
//   3. negative control: a benign package must not produce a defect under the
//      same stage and budget;
//   4. known-witness match: if the signature matches a known defect in the
//      table, the result is `known`, not `confirmed`;
//   5. optional minimise: when --minimize PATH is given, the reducer must
//      publish a verified witness (exit 0 and "published":true).
//
// Only a candidate that passes 1-3 (and 5 when requested) is `confirmed`.
// Anything else is flaky / known / inconclusive, and the JSON says why.

///|
fn ensure_dir(path : String) -> Unit {
  ignore(
    try {
      @fs.create_dir(path)
      true
    } catch {
      _ => false
    },
  )
}

///|
fn usage() -> Unit {
  println(
    "usage: triage --case DIR [--stage check|build|test|syncheck] " +
    "[--timeout-ms N] [--minimize PATH] [--json PATH]",
  )
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn parse_num(s : String, dflt : Int32) -> Int32 {
  let mut n = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      return dflt
    }
  }
  if any {
    n
  } else {
    dflt
  }
}

///|
/// Known-witness library.  Matching is substring-based on the normalised
/// signature; the entries are the classes this repository already documented.
/// A match means "this is not a new defect", not "not a defect".
fn known_match(sig : String) -> String? {
  let table : Array[(String, String)] = [
    ("lower_array_make", "F7"),
    ("finish_stub_wrapper_shell", "F9"),
    ("Char.chr", "F2"),
    ("Basic_utf8_decode", "F4"),
    ("Assertion failed", "F8"),
    ("out of memory", "F3"),
    ("Request not supported yet", "F10"),
    ("-32602", "F11"),
    ("-32601", "F11"),
  ]
  for entry in table {
    let (needle, id) = entry
    if sig.contains(needle) {
      return Some(id)
    }
  }
  None
}

///|
fn write_pkg(dir : String, src : String, mode : String) -> Bool {
  @stager.rm_rf(dir)
  let made = try {
    @fs.create_dir(dir)
    true
  } catch {
    _ => false
  }
  if !made {
    return false
  }
  let fname = if mode == "pkg" {
    "moon.pkg"
  } else if mode == "mod" {
    "moon.mod"
  } else if mode == "mbtmd" {
    "main.mbt.md"
  } else {
    "main.mbt"
  }
  @stager.write_text(
    join(dir, "moon.mod"),
    "name = \"repro/triage\"\nversion = \"0.1.0\"\n",
  ) &&
  @stager.write_text(join(dir, "moon.pkg"), "pkgtype(kind: \"executable\")\n") &&
  @stager.write_text(join(dir, fname), src)
}

///|
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let b = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' || c == '\n' {
      if b.to_string() != "" {
        out.push(b.to_string())
        b.reset()
      }
    } else {
      b.write_char(c)
    }
  }
  if b.to_string() != "" {
    out.push(b.to_string())
  }
  out
}

///|
/// Replay one capsule finding: copy the saved package, write the witness into
/// the recorded file, run the recorded argv.
fn test_line(s : String, marker : String) -> String {
  for line in s.split("\n") {
    if line.contains(marker) { return line.to_owned() }
  }
  ""
}

fn test_sig(out : String, err : String) -> String {
  let line = test_line(out + "\n" + err, "failed:")
  let mut i = match line.find("(\"") {
    Some(v) => v + 2
    None => match line.find("(\\\"") { Some(v) => v + 3; None => 0 }
  }
  let start = i
  while i < line.length() && line.get_char(i) != Some('"') { i += 1 }
  let name = if i > start { line[start:i].to_owned() } else { "" }
  let aline = test_line(out + "\n" + err, "FAILED")
  let at = match aline.find("FAILED") { Some(j) => aline[j:].to_owned(); None => "" }
  "test|" + name + "|" + at
}

///|
async fn capsule_replay(
  work : String,
  pkg_dir : String,
  file : String,
  src : String,
  moon : String,
  cmd : String,
  stage : String,
  timeout_ms : Int32,
) -> (String, Int32, String, String) {
  @stager.rm_rf(work)
  if !@stager.copy_tree(pkg_dir, work) {
    return ("", -1, "", "capsule copy failed")
  }
  ignore(@stager.write_text(join(work, file), src))
  let r = @exec.run(
    moon,
    split_ws(cmd),
    work,
    timeout_ms,
  )
  let mut sig = "ok"
  if stage == "test" && r.rc != 0 {
    sig = test_sig(r.stdout, r.stderr)
  } else {
    for f in @stager.findings(stage, r) {
      if @judge.severity_name(f.severity) == "defect" {
        sig = @cluster.crash_signature(f.class, r.rc, r.stderr, r.stdout)
        break
      }
    }
  }
  (sig, r.rc, r.stdout, r.stderr)
}

///|
/// Signature for one run.  Uses the same stager signature the campaign writes,
/// so a candidate and its triage are comparable.
async fn run_signature(
  dir : String,
  stage : String,
  timeout_ms : Int32,
) -> (String, Int32, String) {
  let r = if stage == "syncheck" {
    @exec.run(
      @stager.tool_path("moonc"),
      ["syncheck", "-error-format", "json", "main.mbt"],
      dir,
      timeout_ms,
    )
  } else {
    @stager.run_stage(stage, "wasm-gc", dir, timeout_ms)
  }
  // The campaign stores cluster.crash_signature; the re-run must use the same
  // protocol or a real candidate looks like a different defect.
  let mut sig = "ok"
  for f in @stager.findings("build", r) {
    if @judge.severity_name(f.severity) == "defect" {
      sig = @cluster.crash_signature(f.class, r.rc, r.stderr, r.stdout)
      break
    }
  }
  (sig, r.rc, r.stderr)
}

///|

///|
/// Only crash-class signatures can be promoted.  A plain timeout is not a
/// compiler defect: a generated program can hang on its own, and "3x budget
/// still times out" does not distinguish that from a compiler bug.  Such
/// candidates are reported as timeout-only and stay inconclusive.
fn is_defect_sig(sig : String) -> Bool {
  sig.contains("crash|") || sig.has_prefix("test|")
}

///|
fn is_timeout_only(sig : String) -> Bool {
  !sig.contains("crash|") && (sig.contains("timeout") || sig.contains("hang"))
}

///|
fn manifest_intact(case_dir : String) -> Bool {
  let mpath = join(join(case_dir, "original"), "manifest.json")
  let m = @stager.read_text(mpath)
  if m == "" { return false }
  let pairs : Array[(String, String)] = [
    ("moon_mod", "moon.mod"), ("moon_pkg", "moon.pkg"),
    ("source", "source.mbt"), ("argv", "argv.json"),
    ("paths", "paths.json"), ("expected", "expected.json"),
    ("pin", "pin.json"), ("env", "env.json"),
  ]
  for (k, f) in pairs {
    let want = @cluster.json_get_string(m, k)
    let got = @corpus.sha1_hex(@stager.read_text(join(join(case_dir, "original"), f)))
    if want == "" || want != got { return false }
  }
  true
}

///|
fn triage_status(
  defect : Bool,
  timeout_only : Bool,
  reproduced : Int32,
  control_clean : Bool,
  known : Bool,
  minimise_required : Bool,
  minimised : Bool,
) -> String {
  if !defect {
    if timeout_only {
      "timeout-only"
    } else {
      "inconclusive"
    }
  } else if reproduced < 3 {
    "flaky"
  } else if !control_clean {
    "inconclusive"
  } else if known {
    "known"
  } else if minimise_required && !minimised {
    "flaky"
  } else {
    "confirmed"
  }
}

///|
async fn main {
  let args = @env.args()
  if args.contains("--help") || args.length() < 2 {
    usage()
    return
  }
  let case_dir = match arg_value(args, "--case") {
    Some(s) => s
    None => {
      usage()
      return
    }
  }
  let raw_stage = match arg_value(args, "--stage") {
    Some(s) => s
    None => "check"
  }
  // Campaign findings use t1/t2/t3; there is no `moon t1`.  Map them to the
  // real compiler stage: t1 is a syncheck, t2/t3 are builds.
  let stage = if raw_stage == "t1" {
    "syncheck"
  } else if raw_stage == "t2" || raw_stage == "t3" {
    "build"
  } else {
    raw_stage
  }
  let base_timeout = match arg_value(args, "--timeout-ms") {
    Some(s) => parse_num(s, 60000)
    None => 60000
  }
  // Relaxed budget: a hang must survive 3x the campaign limit.
  let relaxed = base_timeout * 3
  let minimize = arg_value(args, "--minimize")
  let mut src = ""
  for name in @stager.try_read_dir(case_dir) {
    if name == "meta.json" || name == "formatted.mbt" || name == "triage.jsonl" {
      continue
    }
    if name.has_prefix("in.") || name.has_prefix("main.") || src == "" {
      src = @stager.read_text(join(case_dir, name))
      if name.has_prefix("in.") || name.has_prefix("main.") {
        break
      }
    }
  }
  if src == "" {
    println("{\"ok\":false,\"error\":\"no in.mbt in " + case_dir + "\"}")
    @env.exit(2)
  }
  let capsule_json = join(case_dir, "capsule.json")
  let is_capsule = @fs.path_exists(capsule_json)
  let cap_moon = @cluster.json_get_string(@stager.read_text(capsule_json), "moon")
  let cap_cmd = @cluster.json_get_string(@stager.read_text(capsule_json), "cmd")
  let cap_file = @cluster.json_get_string(@stager.read_text(capsule_json), "file")
  let baseline_src = @stager.read_text(join(case_dir, "baseline.mbt"))
  let work = "/tmp/mbtfuzz_triage_" + @env.now().to_string()
  // create_dir is not recursive; without this every write_pkg failed and the
  // candidate was silently reported as "no signature".
  ensure_dir(work)
  let meta = @stager.read_text(join(case_dir, "meta.json"))
  // Escape-aware: signatures contain `Invalid_argument(\"Char.chr\")`.
  let original = @cluster.json_get_string(meta, "signature")
  let kind = @cluster.json_get_string(meta, "kind")
  let expected_json = @stager.read_text(join(join(case_dir, "original"), "expected.json"))
  let expected_out = @cluster.json_get_string(expected_json, "stdout")
  let expected_err = @cluster.json_get_string(expected_json, "stderr")
  let expected_rc = if expected_json.contains("255") { 255 } else if expected_json.contains("\"rc\": 2") || expected_json.contains("\"rc\":2") { 2 } else if expected_json.contains("1") { 1 } else { 0 }
  let expected_sig = test_sig(expected_out, expected_err)
  let sigs : Array[String] = []
  let mut reproducible = 0
  let mut exact = 0
  let mut first_err = ""
  for k in 0..<3 {
    let sig_err = if is_capsule {
      capsule_replay(
        join(work, "r" + k.to_string()),
        join(join(case_dir, "original"), "pkg"),
        cap_file,
        src,
        cap_moon,
        cap_cmd,
        stage,
        relaxed,
      )
    } else {
      let d = join(work, "r" + k.to_string())
      if !write_pkg(d, src, "mbt") {
        continue
      }
      let (s, rc, e) = run_signature(d, stage, relaxed)
      (s, rc, "", e)
    }
    let (sig, rrc, _out, err) = sig_err
    sigs.push(sig)
    if first_err == "" {
      first_err = err
    }
    // Same fingerprint as the candidate AND crash class; three different
    // crashes are not three reproductions of one defect.
    if kind == "TEST_FAIL" {
      if sig == expected_sig && sig != "test||" && rrc == expected_rc {
        exact += 1
        reproducible += 1
      }
    } else if original != "" && sig == original {
      reproducible += 1
    }
  }
  // Negative control: a benign package under the same stage and budget.
  let ctl = join(work, "control")
  let mut control_clean = false
  let ctl_ok = if is_capsule {
    if baseline_src == "" {
      false
    } else {
      let (ctl_sig, ctl_rc, _ctl_out, ctl_err) = capsule_replay(
        ctl,
        join(join(case_dir, "original"), "pkg"),
        cap_file,
        baseline_src,
        cap_moon,
        cap_cmd,
        stage,
        relaxed,
      )
      let obs = @judge.observation(
        stage, ctl_rc, false, 0L, 0L, 0, false, false, "", ctl_err,
      )
      control_clean = ctl_rc == 0 &&
        !is_defect_sig(ctl_sig) &&
        !@judge.has_diagnostic(obs)
      true
    }
  } else if write_pkg(ctl, "fn main {\n  println(\"ok\")\n}\n", "mbt") {
    let (ctl_sig, ctl_rc, ctl_err) = run_signature(ctl, stage, relaxed)
    // A clean control must actually complete (rc 0), avoid a crash signature
    // and carry no compiler diagnostic.
    let ctl_obs = @judge.observation(
      stage, ctl_rc, false, 0L, 0L, 0, false, false, "", ctl_err,
    )
    control_clean = ctl_rc == 0 &&
      !is_defect_sig(ctl_sig) &&
      !@judge.has_diagnostic(ctl_obs)
    true
  } else {
    false
  }
  ignore(ctl_ok)
  // Optional minimise: only "published" counts.
  let mut minimised = false
  let mut minimise_note = "not requested"
  let mut reduced_path = ""
  match (if is_capsule { None } else { minimize }) {
    Some(bin) =>
      if @fs.path_exists(bin) {
        let d = join(work, "min")
        if write_pkg(d, src, "mbt") {
          let out = join(work, "reduced.mbt")
          let r = @exec.run(
            bin,
            [
              "--dir", d, "--file", "main.mbt", "--stage", stage, "--target",
              "wasm-gc", "--out", out,
            ],
            work,
            600000,
          )
          minimised = r.rc == 0 && r.stdout.contains("\"published\":true")
          minimise_note = if minimised { "verified" } else { "not published" }
          if minimised {
            // The reduced file must still trigger the candidate's fingerprint
            // under the same stage/config; a published but different failure
            // is not a reduction of this defect.
            let vd = join(work, "verify")
            let reduced_src = @stager.read_text(out)
            if write_pkg(vd, reduced_src, "mbt") {
              let (vsig, vrc, verr) = run_signature(vd, stage, relaxed)
              let still = is_defect_sig(vsig) &&
                (original == "" || vsig == original) &&
                vrc != 0
              if still {
                reduced_path = out
              } else {
                minimised = false
                minimise_note = "reduced did not reproduce"
              }
              ignore(verr)
            } else {
              minimised = false
              minimise_note = "verify write failed"
            }
          }
        }
      } else {
        minimise_note = "minimise binary missing"
      }
    None => ()
  }
  let first = if sigs.length() > 0 { sigs[0] } else { "" }
  let known = known_match(first_err)
  let known_some = match known {
    Some(_) => true
    None => false
  }
  // Only check/build/test have a reducer that can replay the original defect.
  // t1 maps to syncheck (not minimisable) and capsule packages are not
  // single-file reducible; neither may become flaky merely because the caller
  // passed --minimize unconditionally.
  let minimise_supported = !is_capsule &&
    (stage == "check" || stage == "build" || stage == "test")
  let minimize_required = minimise_supported &&
    (match minimize {
      Some(_) => true
      None => false
    })
  if !minimise_supported && (match minimize {
    Some(_) => true
    None => false
  }) {
    minimise_note = "not supported for stage " + stage
  }
  let status0 = triage_status(
    is_defect_sig(first),
    is_timeout_only(first),
    reproducible,
    control_clean,
    known_some,
    minimize_required,
    minimised,
  )
  let status = if kind == "TEST_FAIL" && exact < 3 { "inconclusive" } else { status0 }
  // A confirmed witness must outlive the work directory.
  if status == "confirmed" {
    let cd = join(case_dir, "confirmed")
    ensure_dir(cd)
    ignore(@stager.write_text(join(cd, "in.mbt"), src))
    if reduced_path != "" {
      ignore(
        @stager.write_text(
          join(cd, "reduced.mbt"),
          @stager.read_text(reduced_path),
        ),
      )
    }
    ignore(
      @stager.write_text(
        join(cd, "status.json"),
        "{\"status\":\"confirmed\",\"signature\":\"" +
        @stager.escape(first) +
        "\",\"stage\":\"" +
        stage +
        "\"}",
      ),
    )
  }
  let b = StringBuilder()
  b.write_string("{\"case\":\"" + @stager.escape(case_dir) + "\"")
  b.write_string(",\"status\":\"" + status + "\"")
  b.write_string(",\"reproduced\":\"" + reproducible.to_string() + "/3\"")
  b.write_string(",\"stage\":\"" + stage + "\"")
  b.write_string(",\"signature\":\"" + @stager.escape(first) + "\"")
  b.write_string(",\"known\":")
  match known {
    Some(id) => b.write_string("\"" + id + "\"")
    None => b.write_string("null")
  }
  b.write_string(
    ",\"control_clean\":" + (if control_clean { "true" } else { "false" }),
  )
  b.write_string(",\"minimise\":\"" + minimise_note + "\"")
  b.write_string("}")
  println(b.to_string())
  @stager.rm_rf(work)
}
