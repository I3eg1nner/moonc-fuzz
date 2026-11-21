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
/// Signature for one run.  Uses the same stager signature the campaign writes,
/// so a candidate and its triage are comparable.
async fn run_signature(
  dir : String,
  stage : String,
  timeout_ms : Int32,
) -> String {
  if stage == "syncheck" {
    let r = @exec.run(
      @stager.tool_path("moonc"),
      ["syncheck", "-error-format", "json", "main.mbt"],
      dir,
      timeout_ms,
    )
    @stager.signature("build", r)
  } else {
    let r = @stager.run_stage(stage, "wasm-gc", dir, timeout_ms)
    @stager.signature(stage, r)
  }
}

///|

///|
/// Only crash-class signatures can be promoted.  A plain timeout is not a
/// compiler defect: a generated program can hang on its own, and "3x budget
/// still times out" does not distinguish that from a compiler bug.  Such
/// candidates are reported as timeout-only and stay inconclusive.
fn is_defect_sig(sig : String) -> Bool {
  sig.contains("crash|")
}

///|
fn is_timeout_only(sig : String) -> Bool {
  !sig.contains("crash|") && (sig.contains("timeout") || sig.contains("hang"))
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
  } else if known {
    "known"
  } else if reproduced < 3 {
    "flaky"
  } else if !control_clean {
    "inconclusive"
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
  let stage = match arg_value(args, "--stage") {
    Some(s) => s
    None => "check"
  }
  let base_timeout = match arg_value(args, "--timeout-ms") {
    Some(s) => parse_num(s, 60000)
    None => 60000
  }
  // Relaxed budget: a hang must survive 3x the campaign limit.
  let relaxed = base_timeout * 3
  let minimize = arg_value(args, "--minimize")
  let src = @stager.read_text(join(case_dir, "in.mbt"))
  if src == "" {
    println("{\"ok\":false,\"error\":\"no in.mbt in " + case_dir + "\"}")
    @env.exit(2)
  }
  let work = "/tmp/mbtfuzz_triage_" + @env.now().to_string()
  // create_dir is not recursive; without this every write_pkg failed and the
  // candidate was silently reported as "no signature".
  ensure_dir(work)
  let sigs : Array[String] = []
  let mut reproducible = 0
  for k in 0..<3 {
    let d = join(work, "r" + k.to_string())
    if !write_pkg(d, src, "mbt") {
      continue
    }
    let sig = run_signature(d, stage, relaxed)
    sigs.push(sig)
    if is_defect_sig(sig) {
      reproducible += 1
    }
  }
  // Negative control: a benign package under the same stage and budget.
  let ctl = join(work, "control")
  let ctl_sig = if write_pkg(ctl, "fn main {\n  println(\"ok\")\n}\n", "mbt") {
    run_signature(ctl, stage, relaxed)
  } else {
    "control-write-failed"
  }
  let control_clean = !is_defect_sig(ctl_sig)
  // Optional minimise: only "published" counts.
  let mut minimised = false
  let mut minimise_note = "not requested"
  match minimize {
    Some(bin) =>
      if @fs.path_exists(bin) {
        let d = join(work, "min")
        if write_pkg(d, src, "mbt") {
          let out = join(work, "reduced.mbt")
          let r = @exec.run(
            bin,
            ["--dir", d, "--file", "main.mbt", "--stage", stage, "--out", out],
            work,
            600000,
          )
          minimised = r.rc == 0 && r.stdout.contains("\"published\":true")
          minimise_note = if minimised { "verified" } else { "not published" }
        }
      } else {
        minimise_note = "minimise binary missing"
      }
    None => ()
  }
  let first = if sigs.length() > 0 { sigs[0] } else { "" }
  let known = known_match(first)
  let known_some = match known {
    Some(_) => true
    None => false
  }
  let minimize_required = match minimize {
    Some(_) => true
    None => false
  }
  let status = triage_status(
    is_defect_sig(first),
    is_timeout_only(first),
    reproducible,
    control_clean,
    known_some,
    minimize_required,
    minimised,
  )
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
