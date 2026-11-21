///|
/// Terminal states for one target.  `COMPLETE` means the program was built,
/// linked and ran to a zero exit.  Every other state is a failed experiment
/// and must never be compared as if it were output: two timeouts, two
/// identical crashes or two identical compile errors are not agreement.
const ST_COMPLETE : String = "COMPLETE"

///|
const ST_BUILD_FAIL : String = "BUILD_FAIL"

///|
const ST_LINK_FAIL : String = "LINK_FAIL"

///|
const ST_TIMEOUT : String = "TIMEOUT"

///|
const ST_RUN_FAIL : String = "RUN_FAIL"

///|
/// One target's observation for a case.
struct Obs {
  target : String
  status : String
  rc : Int32
  /// Capped stdout (64 KiB).  `digest` and `full_len` describe the *full*
  /// output, which is why a truncated observation can never be compared as if
  /// its prefix were the whole thing.
  out : String
  err : String
  ms : Int64
  truncated : Bool
  digest : String
  full_len : Int64
}

///|
fn usage() -> Unit {
  println(
    "usage: semdiff --out FILE [--family f64|int|str] " +
    "[--targets wasm-gc,native] [--only ID[,ID]] [--timeout-ms N] [--keep]",
  )
}

///|
/// Diagnostics only: warnings dominate the head of stderr and would push the
/// actual compile error out of a fixed-length excerpt.
fn error_excerpt(err : String) -> String {
  let i = err.find("Error")
  let tail = match i {
    Some(k) => err[k:].to_owned()
    None => err
  }
  if tail.length() > 400 {
    tail[0:400].to_owned()
  } else {
    tail
  }
}

///|
/// A failed build is only classified as a link failure when the diagnostics
/// name the link stage.  Everything else (parse, type, package resolution)
/// is a build failure; the distinction matters because "link failed" is the
/// class the native/target-specific defects live in.
fn link_failure(err : String) -> Bool {
  err.contains("failed to link") ||
  err.contains("link-core") ||
  err.contains("Machine_error") ||
  err.contains("undefined symbol") ||
  err.contains("ld: ") ||
  err.contains("error: link")
}

///|
/// Explain the first divergence against the first live target.  The previous
/// version compared against whichever target happened to be last, so a
/// js-only difference printed "length N vs N" and looked like a formatting
/// artefact.
fn mismatch_hint(obs : Array[Obs]) -> String {
  if obs.length() < 2 {
    return ""
  }
  let first = obs[0]
  for k, o in obs {
    if k > 0 {
      if o.rc != first.rc {
        return "rc " +
          first.target +
          "=" +
          first.rc.to_string() +
          " vs " +
          o.target +
          "=" +
          o.rc.to_string()
      }
      if o.out != first.out {
        return first.target +
          " vs " +
          o.target +
          ": " +
          first_diff_line(first.out, o.out)
      }
    }
  }
  ""
}

///|
/// Compare normalized stdout across targets.
///
/// The rule the previous version got wrong: agreement requires that *every*
/// requested target reached `COMPLETE`.  A target that timed out, crashed or
/// failed to build contributes no output, so comparing the survivors can turn
/// "both runs hung" into "both runs agree".  Anything not fully observed is
/// `INCONCLUSIVE`, never `ALL_EQUAL`.
fn compare(obs : Array[Obs]) -> String {
  if obs.length() == 0 {
    return "NO_CASES"
  }
  for o in obs {
    if o.status != ST_COMPLETE {
      return "INCONCLUSIVE"
    }
    // A capped prefix is not the output.  Equality of the first 64 KiB says
    // nothing about the suffix, so truncation is INCONCLUSIVE even when the
    // prefixes match.
    if o.truncated {
      return "INCONCLUSIVE"
    }
  }
  let first = obs[0]
  for i, o in obs {
    if i > 0 {
      if o.rc != first.rc {
        return "MISMATCH"
      }
      if first.digest != "" && o.digest != "" {
        if o.digest != first.digest || o.full_len != first.full_len {
          return "MISMATCH"
        }
      } else if o.out != first.out {
        return "MISMATCH"
      }
    }
  }
  "ALL_EQUAL"
}

///|
/// A one-line human hint naming the first differing output line, so a
/// mismatch does not require opening the JSON.
fn first_diff_line(a : String, b : String) -> String {
  let la = a.split("\n").collect()
  let lb = b.split("\n").collect()
  let n = if la.length() < lb.length() { la.length() } else { lb.length() }
  let mut i = 0
  while i < n {
    if la[i].to_owned() != lb[i].to_owned() {
      return "line " +
        (i + 1).to_string() +
        ": `" +
        la[i].to_owned() +
        "` vs `" +
        lb[i].to_owned() +
        "`"
    }
    i += 1
  }
  "length " + la.length().to_string() + " vs " + lb.length().to_string()
}

///|
fn write_pkg(dir : String, src : String) -> Bool {
  @stager.rm_rf(dir)
  let created = try {
    @fs.create_dir(dir)
    true
  } catch {
    _ => false
  }
  if !created {
    return false
  }
  // `Float::from_double` lives on the builtin Float type, so the generated
  // package needs no imports at all - importing `moonbitlang/core/float` only
  // produces an unused-package warning.
  let pkg = "pkgtype(kind: \"executable\")\n"
  let a = @stager.write_text(
    @stager.join(dir, "moon.mod"),
    "name = \"repro/semdiff\"\nversion = \"0.1.0\"\n",
  )
  let b = @stager.write_text(@stager.join(dir, "moon.pkg"), pkg)
  let c = @stager.write_text(@stager.join(dir, "main.mbt"), src)
  a && b && c
}

///|
async fn run_one(dir : String, target : String, timeout_ms : Int32) -> Obs {
  let start = @env.now()
  // Build first, so a compile/link failure is never mistaken for a run.  A
  // single `moon run` conflates the two and leaves `timed_out` invisible,
  // which is exactly how two hangs used to compare equal.
  let b = @exec.run_isolated(
    @stager.moon_path(),
    ["build", "--target", target],
    dir,
    timeout_ms,
    max_output_bytes=4194304,
    mem_mb=2048,
  )
  let elapsed = fn() {
    if @env.now() > start {
      (@env.now() - start).to_int().to_int64()
    } else {
      0L
    }
  }
  if b.timed_out {
    return {
      target,
      status: ST_TIMEOUT,
      rc: -999,
      out: "",
      err: "build timed out",
      ms: elapsed(),
      truncated: false,
      digest: "",
      full_len: 0L,
    }
  }
  if b.rc != 0 {
    return {
      target,
      status: if link_failure(b.stderr) {
        ST_LINK_FAIL
      } else {
        ST_BUILD_FAIL
      },
      rc: b.rc,
      out: "",
      err: error_excerpt(b.stderr),
      ms: elapsed(),
      truncated: b.stdout_truncated,
      digest: b.stdout_digest,
      full_len: b.stdout_full_len,
    }
  }
  let r = @exec.run_isolated(
    @stager.moon_path(),
    ["run", "main.mbt", "--target", target],
    dir,
    timeout_ms,
    max_output_bytes=4194304,
    mem_mb=2048,
  )
  let status = if r.timed_out {
    ST_TIMEOUT
  } else if r.rc != 0 {
    ST_RUN_FAIL
  } else {
    ST_COMPLETE
  }
  {
    target,
    status,
    rc: r.rc,
    out: r.stdout.trim_end().to_owned(),
    err: error_excerpt(r.stderr),
    ms: elapsed(),
    truncated: r.stdout_truncated,
    digest: r.stdout_digest,
    full_len: r.stdout_full_len,
  }
}

///|
/// Table-driven counterexamples for `compare`.  Runs without a compiler and
/// is wired into `accept`, so a regression in the decision function fails the
/// gate rather than silently restoring the false pass.
fn self_test(verbose : Bool) -> Bool {
  let mk = fn(target : String, status : String, rc : Int32, out : String) {
    {
      target,
      status,
      rc,
      out,
      err: "",
      ms: 0L,
      truncated: false,
      digest: "",
      full_len: 0L,
    }
  }
  let checks : Array[(String, Array[Obs], String)] = [
    (
      "two-timeouts",
      [mk("a", ST_TIMEOUT, -999, ""), mk("b", ST_TIMEOUT, -999, "")],
      "INCONCLUSIVE",
    ),
    (
      "two-signals",
      [mk("a", ST_RUN_FAIL, -11, ""), mk("b", ST_RUN_FAIL, -11, "")],
      "INCONCLUSIVE",
    ),
    (
      "two-build-fails",
      [mk("a", ST_BUILD_FAIL, 1, ""), mk("b", ST_BUILD_FAIL, 1, "")],
      "INCONCLUSIVE",
    ),
    (
      "two-link-fails",
      [mk("a", ST_LINK_FAIL, 1, ""), mk("b", ST_LINK_FAIL, 1, "")],
      "INCONCLUSIVE",
    ),
    (
      "missing-target",
      [mk("a", ST_COMPLETE, 0, "x"), mk("b", ST_BUILD_FAIL, 1, "")],
      "INCONCLUSIVE",
    ),
    (
      "equal",
      [mk("a", ST_COMPLETE, 0, "x"), mk("b", ST_COMPLETE, 0, "x")],
      "ALL_EQUAL",
    ),
    (
      "three-equal",
      [
        mk("a", ST_COMPLETE, 0, "x"),
        mk("b", ST_COMPLETE, 0, "x"),
        mk("c", ST_COMPLETE, 0, "x"),
      ],
      "ALL_EQUAL",
    ),
    (
      "differ",
      [mk("a", ST_COMPLETE, 0, "x"), mk("b", ST_COMPLETE, 0, "y")],
      "MISMATCH",
    ),
    ("no-cases", [], "NO_CASES"),
  ]
  let mut ok = true
  for c in checks {
    let (name, obs, want) = c
    let got = compare(obs)
    if got != want {
      println("self-test failed: " + name + " got " + got + " want " + want)
      ok = false
    }
  }
  // link_failure must separate the two failure classes.
  if !link_failure("Error: failed to link foo") ||
    link_failure("Error: [4021] Value x not found") {
    println("self-test failed: link_failure classification")
    ok = false
  }
  if verbose {
    println(
      "{\"ok\":" +
      (if ok { "true" } else { "false" }) +
      ",\"checks\":" +
      checks.length().to_string() +
      "}",
    )
  }
  ok
}

///|
async fn main {
  let args = @env.args()
  let mut out = ""
  let mut family = ""
  let mut targets = "wasm-gc,native"
  let mut only = ""
  let mut timeout_ms = 60000
  let mut keep = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--family" && i + 1 < args.length() {
      family = args[i + 1]
    } else if a == "--targets" && i + 1 < args.length() {
      targets = args[i + 1]
    } else if a == "--only" && i + 1 < args.length() {
      only = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
    } else if a == "--keep" {
      keep = true
    } else if a == "--self-test" {
      let ok = self_test(true)
      @env.exit(if ok { 0 } else { 1 })
    }
  }
  if out == "" {
    usage()
    @env.exit(2)
  }
  let tlist : Array[String] = []
  for t in targets.split(",") {
    let s = t.trim().to_owned()
    if s != "" {
      tlist.push(s)
    }
  }
  if tlist.length() < 2 {
    usage()
    @env.exit(2)
  }
  let work = "/tmp/mbtfuzz_semdiff"
  @stager.rm_rf(work)
  let _ = try {
    @fs.create_dir(work)
    true
  } catch {
    _ => false
  }
  let start_ms = @env.now()
  let mut total = 0
  let mut all_equal = 0
  let mut mismatches = 0
  let mut inconclusive = 0
  // Cases that never reached a target because the work directory could not be
  // written.  Kept separate from INCONCLUSIVE: one is the corpus lying, the
  // other is the harness failing.
  let mut skipped = 0
  let rows : Array[String] = []
  for c in @numgen.select(family) {
    if only != "" {
      let mut hit = false
      for part in only.split(",") {
        if part.trim() == c.id {
          hit = true
        }
      }
      if !hit {
        continue
      }
    }
    total += 1
    let dir = @stager.join(work, c.id)
    if !write_pkg(dir, c.src) {
      skipped += 1
      continue
    }
    let obs : Array[Obs] = []
    for t in tlist {
      obs.push(run_one(dir, t, timeout_ms))
    }
    let verdict = compare(obs)
    if verdict == "ALL_EQUAL" {
      all_equal += 1
    } else if verdict == "MISMATCH" {
      mismatches += 1
    } else {
      inconclusive += 1
    }
    let b = StringBuilder()
    b.write_string("{\"case\":\"")
    b.write_string(c.id)
    b.write_string("\",\"family\":\"")
    b.write_string(c.family)
    b.write_string("\",\"verdict\":\"")
    b.write_string(verdict)
    b.write_string("\",\"targets\":[")
    for i, o in obs {
      if i > 0 {
        b.write_string(",")
      }
      b.write_string("{\"target\":\"")
      b.write_string(o.target)
      b.write_string("\",\"status\":\"")
      b.write_string(o.status)
      b.write_string("\"")
      b.write_string(",\"rc\":")
      b.write_string(o.rc.to_string())
      b.write_string(",\"lines\":")
      b.write_string(
        (if o.status == ST_COMPLETE { o.out.split("\n").count() } else { 0 }).to_string(),
      )
      b.write_string(",\"ms\":")
      b.write_string(o.ms.to_string())
      if o.status != ST_COMPLETE {
        b.write_string(",\"err\":\"")
        b.write_string(@stager.escape(o.err))
        b.write_string("\"")
      }
      b.write_string("}")
    }
    b.write_string("]")
    if verdict == "MISMATCH" {
      b.write_string(",\"detail\":\"")
      b.write_string(@stager.escape(mismatch_hint(obs)))
      b.write_string("\"")
    }
    b.write_string("}")
    rows.push(b.to_string())
    println(b.to_string())
  }
  let _ = @stager.write_text(
    out,
    {
      let b = StringBuilder()
      for row in rows {
        b.write_string(row)
        b.write_string("\n")
      }
      b.to_string()
    },
  )
  let proven = total > 0 &&
    all_equal == total &&
    mismatches == 0 &&
    inconclusive == 0 &&
    skipped == 0
  let summary = "{\"ok\":" +
    (if proven { "true" } else { "false" }) +
    ",\"cases\":" +
    total.to_string() +
    ",\"all_equal\":" +
    all_equal.to_string() +
    ",\"mismatch\":" +
    mismatches.to_string() +
    ",\"inconclusive\":" +
    inconclusive.to_string() +
    ",\"skipped\":" +
    skipped.to_string() +
    ",\"targets\":\"" +
    targets +
    "\",\"ms\":" +
    (@env.now() - start_ms).to_string() +
    ",\"out\":\"" +
    @stager.escape(out) +
    "\"}"
  println(summary)
  if !keep {
    @stager.rm_rf(work)
  }
  // Success means every requested case was fully observed and agreed.  A
  // mismatch, an unobserved case, an empty corpus or a materialisation failure
  // all leave the semantic claim unproven.
  if !proven {
    @env.exit(1)
  }
}
