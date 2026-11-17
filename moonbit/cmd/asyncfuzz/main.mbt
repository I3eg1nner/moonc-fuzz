///|
/// Async state-machine feature driver.
///
/// One generated module per case.  The stage order is check, build,
/// test-build-only, test; the first non-zero stage is recorded with its raw
/// signature.  A compiler assertion/ICE/SIGSEGV is a candidate; dependency and
/// network failures are INFRA and never counted as evidence.  The F8 known
/// positive is run first as a calibration control and labelled separately.

///|
struct Config {
  mut out : String
  mut target : String
  mut limit : Int32
  mut timeout_ms : Int32
  mut keep : Bool
}

///|
struct StageResult {
  rc : Int32
  ms : Int64
  sig : String
  blob : String
  infra : Bool
  timed_out : Bool
}

///|
struct CaseOutcome {
  case : @asyncgen.Case
  dir : String
  mut status : String
  mut stage : String
  mut rc : Int32
  mut sig : String
  mut ms : Int64
  mut evidence : String
  reruns : Array[String]
  controls : Array[(String, String, String)]
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
fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let isdir = @fs.is_dir(path) catch { _ => false }
  if isdir {
    let names = @fs.read_dir(path) catch { _ => [] }
    for n in names {
      rm_rf(join(path, n))
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn parse_int(s : String, dflt : Int32) -> Int32 {
  let mut v = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      return dflt
    }
  }
  if any {
    v
  } else {
    dflt
  }
}

///|
fn usage() -> Unit {
  println(
    "usage: moon run cmd/asyncfuzz -- --out ABS_DIR [--target js|wasm|native] [--limit N] [--timeout-ms N] [--keep]",
  )
}

///|
fn valid_target(t : String) -> Bool {
  t == "js" || t == "wasm" || t == "native"
}

///|
fn jstr(s : String) -> String {
  "\"" + @corpus.json_escape(s) + "\""
}

///|
fn jbool(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
fn tail_text(s : String, n : Int32) -> String {
  let start = if s.length() > n { s.length() - n } else { 0 }
  let b = StringBuilder()
  let mut i = start
  while i < s.length() {
    match s.get_char(i) {
      Some(c) => b.write_char(c)
      None => ()
    }
    i += 1
  }
  b.to_string()
}

///|
fn write_case_files(dir : String, c : @asyncgen.Case) -> Bool {
  @corpus.ensure_dir(join(dir, "lib"))
  for pair in @asyncgen.render_package(c) {
    let path = join(dir, pair.0)
    @corpus.ensure_dir(@corpus.dirname(path))
    @fs.write_string_to_file(path, pair.1) catch {
      _ => return false
    }
  }
  true
}

///|
async fn run_stage(
  moon : String,
  dir : String,
  args : Array[String],
  timeout_ms : Int32,
) -> StageResult {
  let r = @exec.run(
    moon,
    args,
    dir,
    timeout_ms,
    max_output_bytes=4 * 1024 * 1024,
  )
  let blob = r.stderr + "\n" + r.stdout
  {
    rc: r.rc,
    ms: r.ms,
    sig: @asyncgen.normalize_signature(blob, r.rc),
    blob,
    infra: @asyncgen.is_infra(blob),
    timed_out: r.timed_out,
  }
}

///|
fn stage_plan(target : String) -> Array[(String, Array[String])] {
  [
    ("check", ["check", "--target", target]),
    ("build", ["build", "--target", target]),
    ("test-build-only", ["test", "--target", target, "--build-only"]),
    ("test", ["test", "--target", target]),
  ]
}

///|
async fn run_case(
  cfg : Config,
  c : @asyncgen.Case,
  root : String,
  tag : String,
) -> CaseOutcome {
  let dir = join(root, tag)
  rm_rf(dir)
  @corpus.ensure_dir(dir)
  let out : CaseOutcome = {
    case: c,
    dir,
    status: "not_run",
    stage: "",
    rc: 0,
    sig: "",
    ms: 0L,
    evidence: "",
    reruns: [],
    controls: [],
  }
  if !write_case_files(dir, c) {
    out.status = "write_error"
    out.stage = "write"
    return out
  }
  let moon = "/home/user/.moon/bin/moon"
  let mut finished = false
  for pair in stage_plan(cfg.target) {
    let stage = pair.0
    let r = run_stage(moon, dir, pair.1, cfg.timeout_ms)
    out.stage = stage
    out.rc = r.rc
    out.ms = out.ms + r.ms
    if r.timed_out {
      out.status = "timeout"
      out.sig = r.sig
      out.evidence = tail_text(r.blob, 2000)
      finished = true
    } else if r.infra {
      out.status = "infra"
      out.sig = r.sig
      out.evidence = tail_text(r.blob, 2000)
      finished = true
    } else if @asyncgen.is_crash_signature(r.sig) {
      out.status = if @asyncgen.is_known_f8(r.sig) {
        "known_f8"
      } else {
        "new_candidate"
      }
      out.sig = r.sig
      out.evidence = tail_text(r.blob, 4000)
      finished = true
    } else if r.rc != 0 {
      out.status = if stage == "test" { "test_fail" } else { "invalid" }
      out.sig = r.sig
      out.evidence = tail_text(r.blob, 2000)
      finished = true
    }
    if finished {
      break
    }
  }
  if !finished {
    out.status = "ok"
    out.stage = "test"
  }
  out
}

///|
fn outcome_json(o : CaseOutcome) -> String {
  let c = o.case
  let b = StringBuilder()
  b.write_string("{")
  b.write_string("\"id\":" + jstr(c.id) + ",")
  b.write_string(
    "\"kind\":" + jstr(if c.f8_control { "f8_control" } else { "case" }) + ",",
  )
  b.write_string("\"shape\":" + jstr(@asyncgen.shape_slug(c.shape)) + ",")
  b.write_string(
    "\"suspension\":" + jstr(@asyncgen.suspension_slug(c.suspension)) + ",",
  )
  b.write_string("\"control\":" + jstr(@asyncgen.control_slug(c.control)) + ",")
  b.write_string("\"ty\":" + jstr(@asyncgen.ty_slug(c.ty)) + ",")
  b.write_string("\"entry\":" + jstr(@asyncgen.entry_slug(c.entry)) + ",")
  b.write_string("\"status\":" + jstr(o.status) + ",")
  b.write_string("\"stage\":" + jstr(o.stage) + ",")
  b.write_string("\"rc\":" + o.rc.to_string() + ",")
  b.write_string("\"signature\":" + jstr(o.sig) + ",")
  b.write_string("\"ms\":" + o.ms.to_string() + ",")
  b.write_string("\"dir\":" + jstr(o.dir) + ",")
  b.write_string("\"reruns\":[")
  for i, r in o.reruns {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(jstr(r))
  }
  b.write_string("],\"controls\":[")
  for i, ctl in o.controls {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(
      "{\"name\":" +
      jstr(ctl.0) +
      ",\"status\":" +
      jstr(ctl.1) +
      ",\"signature\":" +
      jstr(ctl.2) +
      "}",
    )
  }
  b.write_string("],")
  b.write_string("\"lib\":" + jstr(@asyncgen.render_lib(c)) + ",")
  b.write_string("\"test\":" + jstr(@asyncgen.render_test(c)) + ",")
  b.write_string("\"evidence\":" + jstr(o.evidence))
  b.write_string("}")
  b.to_string()
}

///|
fn count_add(m : Map[String, Int32], key : String) -> Unit {
  m.set(key, m.get_or_default(key, 0) + 1)
}

///|
fn summary_json(
  cfg : Config,
  matrix_size : Int32,
  selected : Int32,
  ran : Int32,
  counts : Map[String, Int32],
  sigs : Map[String, Int32],
  new_sigs : Array[String],
  f8 : CaseOutcome,
  duration_ms : Int64,
) -> String {
  let b = StringBuilder()
  b.write_string("{")
  b.write_string("\"schema\":\"asyncfuzz/1\",")
  b.write_string("\"out\":" + jstr(cfg.out) + ",")
  b.write_string("\"target\":" + jstr(cfg.target) + ",")
  b.write_string("\"limit\":" + cfg.limit.to_string() + ",")
  b.write_string("\"timeout_ms\":" + cfg.timeout_ms.to_string() + ",")
  b.write_string("\"matrix_size\":" + matrix_size.to_string() + ",")
  b.write_string("\"selected\":" + selected.to_string() + ",")
  b.write_string("\"ran\":" + ran.to_string() + ",")
  b.write_string("\"duration_ms\":" + duration_ms.to_string() + ",")
  b.write_string("\"f8_control\":{")
  b.write_string("\"id\":" + jstr(f8.case.id) + ",")
  b.write_string("\"status\":" + jstr(f8.status) + ",")
  b.write_string("\"stage\":" + jstr(f8.stage) + ",")
  b.write_string("\"rc\":" + f8.rc.to_string() + ",")
  b.write_string("\"signature\":" + jstr(f8.sig) + ",")
  b.write_string("\"reproduced\":" + jbool(f8.status == "known_f8"))
  b.write_string("},")
  b.write_string("\"counts\":{")
  let mut first = true
  for pair in counts.to_array() {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string(jstr(pair.0) + ":" + pair.1.to_string())
  }
  b.write_string("},")
  b.write_string("\"signatures\":{")
  first = true
  for pair in sigs.to_array() {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string(jstr(pair.0) + ":" + pair.1.to_string())
  }
  b.write_string("},")
  b.write_string("\"new_signatures\":[")
  for i, s in new_sigs {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(jstr(s))
  }
  b.write_string("],")
  b.write_string(
    "\"known_f8_signature\":" + jstr(@asyncgen.known_f8_signature()),
  )
  b.write_string("}")
  b.to_string()
}

///|
async fn run_control(
  cfg : Config,
  c : @asyncgen.Case,
  root : String,
  name : String,
) -> (String, String, String) {
  let outcome = run_case(cfg, c, root, c.id + "-" + name)
  (name, outcome.status, outcome.sig)
}

///|
async fn main {
  let args = @env.args()
  let cfg : Config = {
    out: "",
    target: "native",
    limit: 40,
    timeout_ms: 120000,
    keep: false,
  }
  let mut i = 1
  let mut bad = false
  while i < args.length() {
    let a = args[i]
    if a == "--out" && i + 1 < args.length() {
      cfg.out = args[i + 1]
      i += 2
    } else if a == "--target" && i + 1 < args.length() {
      cfg.target = args[i + 1]
      i += 2
    } else if a == "--limit" && i + 1 < args.length() {
      let v = parse_int(args[i + 1], cfg.limit)
      if v > 0 {
        cfg.limit = v
      }
      i += 2
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      cfg.timeout_ms = parse_int(args[i + 1], cfg.timeout_ms)
      i += 2
    } else if a == "--keep" {
      cfg.keep = true
      i += 1
    } else {
      println("bad arg: " + a)
      bad = true
      i += 1
    }
  }
  if bad ||
    cfg.out == "" ||
    !cfg.out.has_prefix("/") ||
    !valid_target(cfg.target) {
    usage()
    return
  }
  let t0 = @async.now()
  rm_rf(cfg.out)
  @corpus.ensure_dir(cfg.out)
  let results_path = join(cfg.out, "results.jsonl")
  let summary_path = join(cfg.out, "summary.json")
  let all = @asyncgen.matrix()
  let selected = @asyncgen.select_cases(cfg.limit.to_int64().to_int())
  let mut f8 : CaseOutcome = {
    case: all[0],
    dir: "",
    status: "missing",
    stage: "",
    rc: 0,
    sig: "",
    ms: 0L,
    evidence: "",
    reruns: [],
    controls: [],
  }
  let mut have_f8 = false
  for c in all {
    if c.f8_control {
      f8 = run_case(cfg, c, join(cfg.out, "cases"), "f8-control")
      have_f8 = true
    }
  }
  if !have_f8 {
    println("[asyncfuzz] ERROR: matrix has no F8 control")
    return
  }
  @corpus.append_line(results_path, outcome_json(f8))
  println(
    "[asyncfuzz] F8 control -> " +
    f8.status +
    " stage=" +
    f8.stage +
    " rc=" +
    f8.rc.to_string() +
    " sig=" +
    f8.sig,
  )
  let counts : Map[String, Int32] = Map([])
  let sigs : Map[String, Int32] = Map([])
  let new_sigs : Array[String] = []
  let mut ran = 0
  let mut stop = false
  for c in selected {
    let outcome = run_case(cfg, c, join(cfg.out, "cases"), c.id)
    ran = ran + 1
    if outcome.status == "new_candidate" {
      // Reproduce three times in fresh directories.
      for n in 1..<=3 {
        let rr = run_case(
          cfg,
          c,
          join(cfg.out, "cases"),
          c.id + "-rerun-" + n.to_string(),
        )
        outcome.reruns.push(rr.status + ":" + rr.sig)
      }
      // Controls: drop the pause, and drop `raise?` when applicable.
      let no_pause : @asyncgen.Case = {
        id: c.id + "-ctrl-nopause",
        shape: c.shape,
        suspension: @asyncgen.SuspNone,
        control: c.control,
        ty: c.ty,
        entry: c.entry,
        f8_control: false,
      }
      outcome.controls.push(
        run_control(cfg, no_pause, join(cfg.out, "cases"), "ctrl-nopause"),
      )
      if c.shape == @asyncgen.OptRaiseOpt {
        let no_raise : @asyncgen.Case = {
          id: c.id + "-ctrl-noraise",
          shape: @asyncgen.OptRaise,
          suspension: c.suspension,
          control: c.control,
          ty: c.ty,
          entry: c.entry,
          f8_control: false,
        }
        outcome.controls.push(
          run_control(cfg, no_raise, join(cfg.out, "cases"), "ctrl-noraise"),
        )
      }
      new_sigs.push(outcome.sig)
      stop = true
    }
    count_add(counts, outcome.status)
    if outcome.sig != "" {
      count_add(sigs, outcome.sig)
    }
    println(
      "[asyncfuzz] " +
      outcome.case.id +
      " -> " +
      outcome.status +
      " stage=" +
      outcome.stage +
      " rc=" +
      outcome.rc.to_string() +
      " sig=" +
      outcome.sig,
    )
    @corpus.append_line(results_path, outcome_json(outcome))
    if !cfg.keep &&
      (
        outcome.status == "ok" ||
        outcome.status == "invalid" ||
        outcome.status == "test_fail"
      ) {
      rm_rf(outcome.dir)
    }
    if stop {
      break
    }
  }
  let duration = @async.now() - t0
  let summary = summary_json(
    cfg,
    all.length(),
    selected.length(),
    ran,
    counts,
    sigs,
    new_sigs,
    f8,
    duration,
  )
  @fs.write_string_to_file(summary_path, summary) catch {
    _ => println("[asyncfuzz] failed to write summary")
  }
  println(
    "[asyncfuzz] target=" +
    cfg.target +
    " matrix=" +
    all.length().to_string() +
    " selected=" +
    selected.length().to_string() +
    " ran=" +
    ran.to_string() +
    " duration_ms=" +
    duration.to_string(),
  )
  let cb = StringBuilder()
  for pair in counts.to_array() {
    cb.write_string(" " + pair.0 + "=" + pair.1.to_string())
  }
  println("[asyncfuzz] counts:" + cb.to_string())
  if new_sigs.length() > 0 {
    println("[asyncfuzz] NEW SIGNATURE(S):")
    for s in new_sigs {
      println("  " + s)
    }
  } else {
    println("[asyncfuzz] no new signature")
  }
  println("[asyncfuzz] results=" + results_path + " summary=" + summary_path)
  if f8.status != "known_f8" {
    println("[asyncfuzz] WARNING: F8 calibration did not reproduce")
  }
}
