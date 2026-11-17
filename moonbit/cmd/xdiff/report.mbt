///|
/// JSONL / summary rendering and the executable entry point.

///|
fn jstr(s : String) -> String {
  @corpus.json_escape(s)
}

///|
fn bool_json(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
fn obs_json(o : TargetObs, out_cap : Int32) -> String {
  "{\"target\":\"" +
  jstr(o.target) +
  "\",\"stage\":\"" +
  jstr(o.stage) +
  "\",\"rc\":" +
  o.rc.to_string() +
  ",\"executed\":" +
  bool_json(o.executed) +
  ",\"class\":\"" +
  jstr(o.klass) +
  "\",\"signature\":\"" +
  jstr(o.signature) +
  "\",\"digest\":\"" +
  jstr(o.digest) +
  "\",\"stdout_short\":\"" +
  jstr(short(o.stdout, out_cap)) +
  "\",\"stderr_short\":\"" +
  jstr(o.stderr_short) +
  "\",\"artifact\":\"" +
  jstr(o.artifact) +
  "\",\"ms\":" +
  o.ms.to_string() +
  "}"
}

///|
fn record_json(r : CaseRec) -> String {
  let mut obs = ""
  for i, o in r.obs {
    if i > 0 {
      obs = obs + ","
    }
    obs = obs + obs_json(o, 700)
  }
  "{\"id\":\"" +
  jstr(r.id) +
  "\",\"index\":" +
  r.index.to_string() +
  ",\"verdict\":\"" +
  jstr(r.verdict) +
  "\",\"note\":\"" +
  jstr(r.note) +
  "\",\"dir\":\"" +
  jstr(r.dir) +
  "\",\"observations\":[" +
  obs +
  "]}"
}

///|
fn find_sig(sigs : Array[String], s : String) -> Int32 {
  for i, x in sigs {
    if x == s {
      return i
    }
  }
  -1
}

///|
fn count_class(records : Array[CaseRec], klass : String) -> Int32 {
  let mut n = 0
  for r in records {
    if r.verdict == klass {
      n += 1
    }
  }
  n
}

///|
fn class_counts_json(records : Array[CaseRec]) -> String {
  let classes : Array[String] = [
    "ALL_EQUAL", "OUTPUT_MISMATCH", "KNOWN_LINK_ICE", "ICE", "BUILD_FAIL", "TIMEOUT",
    "INFRA", "SINGLE_TARGET", "NO_RUN",
  ]
  let mut out = ""
  for i, k in classes {
    if i > 0 {
      out = out + ","
    }
    out = out + "\"" + k + "\":" + count_class(records, k).to_string()
  }
  out
}

///|
fn target_exec_counts(cfg : Config, records : Array[CaseRec]) -> String {
  let mut out = ""
  for i, t in cfg.targets {
    let mut n = 0
    for r in records {
      for o in r.obs {
        if o.target == t && o.executed {
          n += 1
        }
      }
    }
    if i > 0 {
      out = out + ","
    }
    out = out + "\"" + jstr(t) + "\":" + n.to_string()
  }
  out
}

///|
fn targets_json(cfg : Config) -> String {
  let mut out = ""
  for i, t in cfg.targets {
    if i > 0 {
      out = out + ","
    }
    out = out + "\"" + jstr(t) + "\""
  }
  out
}

///|
fn summary_json(cfg : Config, records : Array[CaseRec]) -> String {
  let sigs : Array[String] = []
  let sig_counts : Array[Int32] = []
  let sig_classes : Array[String] = []
  let sig_targets : Array[String] = []
  let sig_first : Array[String] = []
  let mut known_ice = ""
  let mut known_n = 0
  let mut mismatches = ""
  let mut mismatch_n = 0
  for r in records {
    for o in r.obs {
      let failed = o.klass == "ICE" ||
        o.klass == "KNOWN_LINK_ICE" ||
        o.klass == "BUILD_FAIL" ||
        o.klass == "TIMEOUT" ||
        o.klass == "INFRA"
      if failed {
        let k = find_sig(sigs, o.signature)
        if k < 0 {
          sigs.push(o.signature)
          sig_counts.push(1)
          sig_classes.push(o.klass)
          sig_targets.push(o.target)
          sig_first.push(r.id)
        } else {
          sig_counts[k] = sig_counts[k] + 1
        }
      }
      if o.klass == "KNOWN_LINK_ICE" {
        if known_n > 0 {
          known_ice = known_ice + ","
        }
        known_ice = known_ice +
          "{\"id\":\"" +
          jstr(r.id) +
          "\",\"target\":\"" +
          jstr(o.target) +
          "\",\"signature\":\"" +
          jstr(o.signature) +
          "\",\"stage\":\"" +
          jstr(o.stage) +
          "\"}"
        known_n += 1
      }
    }
    if r.verdict == "OUTPUT_MISMATCH" {
      if mismatch_n > 0 {
        mismatches = mismatches + ","
      }
      let mut obs = ""
      for i, o in r.obs {
        if i > 0 {
          obs = obs + ","
        }
        obs = obs + obs_json(o, 2000)
      }
      mismatches = mismatches +
        "{\"id\":\"" +
        jstr(r.id) +
        "\",\"note\":\"" +
        jstr(r.note) +
        "\",\"observations\":[" +
        obs +
        "]}"
      mismatch_n += 1
    }
  }
  let mut sig_json = ""
  for i, s in sigs {
    if i > 0 {
      sig_json = sig_json + ","
    }
    sig_json = sig_json +
      "{\"signature\":\"" +
      jstr(s) +
      "\",\"class\":\"" +
      jstr(sig_classes[i]) +
      "\",\"target\":\"" +
      jstr(sig_targets[i]) +
      "\",\"first_id\":\"" +
      jstr(sig_first[i]) +
      "\",\"occurrences\":" +
      sig_counts[i].to_string() +
      "}"
  }
  "{\"schema\":\"xdiff/1\",\"family\":\"" +
  jstr(cfg.family) +
  "\",\"targets\":[" +
  targets_json(cfg) +
  "],\"limit\":" +
  cfg.limit.to_string() +
  ",\"only\":\"" +
  jstr(cfg.only) +
  "\",\"timeout_ms\":" +
  cfg.timeout_ms.to_string() +
  ",\"jobs\":" +
  cfg.jobs.to_string() +
  ",\"serial\":true,\"keep\":" +
  bool_json(cfg.keep) +
  ",\"selected\":" +
  records.length().to_string() +
  ",\"comparison\":{\"rc_compared\":true,\"trailing_whitespace\":\"trimmed\",\"only_built_targets_compared\":true}" +
  ",\"counts\":{" +
  class_counts_json(records) +
  "},\"executed_by_target\":{" +
  target_exec_counts(cfg, records) +
  "},\"distinct_signatures\":" +
  sigs.length().to_string() +
  ",\"signatures\":[" +
  sig_json +
  "],\"known_ice\":[" +
  known_ice +
  "],\"mismatches\":[" +
  mismatches +
  "]}"
}

///|
fn parse_int(s : String, dflt : Int32) -> Int32 {
  if s == "" {
    return dflt
  }
  let mut v = 0
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
    } else {
      return dflt
    }
  }
  v
}

///|
fn parse_targets(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = StringBuilder()
  for c in s {
    if c == ',' {
      let t = cur.to_string().trim().to_owned()
      if t != "" {
        out.push(t)
      }
      cur = StringBuilder()
    } else {
      cur.write_char(c)
    }
  }
  let t = cur.to_string().trim().to_owned()
  if t != "" {
    out.push(t)
  }
  out
}

///|
fn usage() -> Unit {
  println(
    "usage: xdiff --out ABS_DIR [--family layout|async] [--targets wasm-gc,wasm,js,native] [--limit N] [--timeout-ms N] [--jobs N] [--only ID] [--keep]",
  )
}

///|
fn obs_line(o : TargetObs) -> String {
  o.target + ":" + o.klass + ":rc=" + o.rc.to_string()
}

///|
async fn main {
  let args = @env.args()
  let cfg : Config = {
    out: "",
    family: "layout",
    targets: ["wasm-gc", "wasm", "js"],
    limit: 0,
    timeout_ms: 120000,
    jobs: 1,
    keep: false,
    only: "",
  }
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--out" && i + 1 < args.length() {
      cfg.out = args[i + 1]
      i += 2
    } else if a == "--family" && i + 1 < args.length() {
      cfg.family = args[i + 1]
      i += 2
    } else if a == "--targets" && i + 1 < args.length() {
      cfg.targets = parse_targets(args[i + 1])
      i += 2
    } else if a == "--limit" && i + 1 < args.length() {
      cfg.limit = parse_int(args[i + 1], 0)
      i += 2
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      cfg.timeout_ms = parse_int(args[i + 1], 120000)
      i += 2
    } else if a == "--jobs" && i + 1 < args.length() {
      cfg.jobs = parse_int(args[i + 1], 1)
      i += 2
    } else if a == "--only" && i + 1 < args.length() {
      cfg.only = args[i + 1]
      i += 2
    } else if a == "--keep" {
      cfg.keep = true
      i += 1
    } else if a == "--help" || a == "-h" {
      usage()
      return
    } else {
      println("xdiff: unknown or incomplete argument \{a}")
      usage()
      return
    }
  }
  if cfg.out == "" {
    usage()
    return
  }
  if !cfg.out.has_prefix("/") {
    println("xdiff: --out must be an absolute path")
    return
  }
  if cfg.family != "layout" && cfg.family != "async" {
    println("xdiff: --family must be layout or async")
    return
  }
  if cfg.targets.length() == 0 {
    println("xdiff: --targets must not be empty")
    return
  }
  for t in cfg.targets {
    if !target_is_known(t) {
      println("xdiff: unsupported target \{t}")
      return
    }
  }
  if cfg.timeout_ms < 1000 {
    cfg.timeout_ms = 1000
  }
  // Serial by construction.  `--jobs` is accepted for CLI symmetry and is
  // clamped to at most 2, but the loop below never overlaps builds: the host
  // this runs on was overloaded by concurrent moon processes before.
  if cfg.jobs < 1 {
    cfg.jobs = 1
  }
  if cfg.jobs > 2 {
    cfg.jobs = 2
  }
  @corpus.ensure_dir(cfg.out)
  let results_path = join(cfg.out, "results.jsonl")
  let summary_path = join(cfg.out, "summary.json")
  @corpus.ensure_dir(join(cfg.out, "cases"))
  let mut lines = ""
  let records : Array[CaseRec] = []
  if cfg.family == "layout" {
    let selected = select_layout(cfg)
    if selected.length() == 0 {
      println("xdiff: no layout case matched --only \{cfg.only}")
      return
    }
    println(
      "[xdiff] family=layout targets=\{cfg.targets.length()} cases=\{selected.length()} limit=\{cfg.limit} only=\{cfg.only} timeout_ms=\{cfg.timeout_ms} serial=true",
    )
    for c in selected {
      let r = run_layout_case(cfg, c)
      records.push(r)
    }
  } else {
    let selected = select_async(cfg)
    if selected.length() == 0 {
      println("xdiff: no async case matched --only \{cfg.only}")
      return
    }
    println(
      "[xdiff] family=async targets=\{cfg.targets.length()} cases=\{selected.length()} limit=\{cfg.limit} only=\{cfg.only} timeout_ms=\{cfg.timeout_ms} serial=true",
    )
    for c in selected {
      let r = run_async_case(cfg, c)
      records.push(r)
    }
  }
  for r in records {
    let mut obs = ""
    for i, o in r.obs {
      if i > 0 {
        obs = obs + ","
      }
      obs = obs + obs_line(o)
    }
    println("[xdiff] \{r.id} \{r.verdict} [\{obs}]")
    lines = lines + record_json(r) + "\n"
  }
  ignore(write_one(results_path, lines))
  ignore(write_one(summary_path, summary_json(cfg, records)))
  let mut all_equal = 0
  let mut mismatch = 0
  let mut known = 0
  let mut ice = 0
  let mut build_fail = 0
  let mut timeout = 0
  let mut infra = 0
  let mut single = 0
  let mut no_run = 0
  for r in records {
    if r.verdict == "ALL_EQUAL" {
      all_equal += 1
    } else if r.verdict == "OUTPUT_MISMATCH" {
      mismatch += 1
    } else if r.verdict == "KNOWN_LINK_ICE" {
      known += 1
    } else if r.verdict == "ICE" {
      ice += 1
    } else if r.verdict == "BUILD_FAIL" {
      build_fail += 1
    } else if r.verdict == "TIMEOUT" {
      timeout += 1
    } else if r.verdict == "INFRA" {
      infra += 1
    } else if r.verdict == "SINGLE_TARGET" {
      single += 1
    } else if r.verdict == "NO_RUN" {
      no_run += 1
    }
  }
  println(
    "[xdiff done] selected=\{records.length()} ALL_EQUAL=\{all_equal} OUTPUT_MISMATCH=\{mismatch} KNOWN_LINK_ICE=\{known} ICE=\{ice} BUILD_FAIL=\{build_fail} TIMEOUT=\{timeout} INFRA=\{infra} SINGLE_TARGET=\{single} NO_RUN=\{no_run}",
  )
  println("[xdiff] results=\{results_path}")
  println("[xdiff] summary=\{summary_path}")
}
