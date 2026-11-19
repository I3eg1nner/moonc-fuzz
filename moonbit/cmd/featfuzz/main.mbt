///|
/// Feature-directed staged oracle for native aggregate/layout cases.
///
/// For each generated package it runs, in order:
///   check -> build -> test --build-only -> test
///
/// The separate TestBuild stage is the point of this driver: `moon check` and
/// `moon build` can both succeed while the native test linker still ICEs
/// (F7/F9-style defects).  `moon build` is never used as a substitute for the
/// test link.
///
/// Usage:
///   featfuzz --out ABS_DIR [--family layout] [--target native]
///            [--mode debug|release] [--limit N] [--jobs N]
///            [--timeout-ms N] [--keep]
struct Config {
  mut out : String
  mut family : String
  mut target : String
  mut mode : String
  mut limit : Int32
  mut jobs : Int32
  mut timeout_ms : Int32
  mut keep : Bool
  mut cases_dir : String
}

///|
enum Stage {
  Check
  Build
  TestBuild
  Test
}

///|
fn stage_name(s : Stage) -> String {
  match s {
    Check => "check"
    Build => "build"
    TestBuild => "test-build"
    Test => "test"
  }
}

///|
struct CaseRecord {
  index : Int32
  id : String
  features : String
  stage : String
  rc : Int32
  klass : String
  signature : String
  dir : String
  stderr_short : String
  ms : Int64
  candidate : Bool
}

///|
fn join(a : String, b : String) -> String {
  @corpus.join(a, b)
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
fn write_one(path : String, text : String) -> Bool {
  let mut ok = true
  @fs.write_string_to_file(path, text) catch {
    _ => ok = false
  }
  ok
}

///|
fn write_package(dir : String, p : @featuregen.RenderedPackage) -> Bool {
  let a = write_one(join(dir, "moon.mod"), p.moon_mod)
  let b = write_one(join(dir, "moon.pkg"), p.moon_pkg)
  let c = write_one(join(dir, "lib.mbt"), p.lib_mbt)
  let d = write_one(join(dir, "main.mbt"), p.main_mbt)
  let e = write_one(join(dir, "main_test.mbt"), p.main_test_mbt)
  a && b && c && d && e
}

///|
fn moon_path() -> String {
  match @env.get_env_var("MOON") {
    Some(p) => p
    None => {
      let home = match @env.get_env_var("HOME") {
        Some(h) => h
        None => "/home/user"
      }
      home + "/.moon/bin/moon"
    }
  }
}

///|
fn stage_args(cfg : Config, stage : Stage) -> Array[String] {
  let cmd = match stage {
    Check => "check"
    Build => "build"
    TestBuild => "test"
    Test => "test"
  }
  let args : Array[String] = [cmd, "--target", cfg.target]
  if cfg.mode == "release" {
    args.push("--release")
  }
  if stage is TestBuild {
    args.push("--build-only")
  }
  args
}

///|
async fn run_stage(
  cfg : Config,
  dir : String,
  stage : Stage,
  timeout_ms : Int32,
) -> @exec.RunResult {
  @exec.run_isolated(
    moon_path(),
    stage_args(cfg, stage),
    dir,
    timeout_ms,
    max_output_bytes=65536,
  )
}

///|
fn has_compiler_crash(t : String) -> Bool {
  t.contains("Oops, the compiler has encountered") ||
  t.contains("Machine_error(") ||
  t.contains("Assert_failure") ||
  t.contains("Assertion failed") ||
  t.contains("Fatal error: exception") ||
  t.contains("SIGSEGV") ||
  t.contains("Segmentation fault") ||
  t.contains("internal error")
}

///|
fn infra_marker(t : String) -> String {
  let markers : Array[String] = [
    "No such file or directory", "no such file or directory", "ENOENT", "package not found",
    "Cannot find package", "cannot find package", "failed to download", "network error",
    "Network error", "Connection refused", "could not resolve", "Could not resolve",
    "not found in registry", "failed to read",
  ]
  for m in markers {
    if t.contains(m) {
      return m
    }
  }
  ""
}

///|
fn classify_stage(stage : Stage, r : @exec.RunResult) -> String {
  if r.timed_out {
    return "TIMEOUT"
  }
  let blob = r.stderr + "\n" + r.stdout
  if has_compiler_crash(blob) {
    return "ICE"
  }
  if r.rc == 0 {
    return "OK"
  }
  if infra_marker(blob) != "" {
    return "INFRA"
  }
  match stage {
    Check => "CHECK_FAIL"
    Build => "BUILD_FAIL"
    TestBuild => "TEST_LINK_FAIL"
    Test => "RUN_FAIL"
  }
}

///|
fn collapse_ws(s : String) -> String {
  let b = StringBuilder()
  let mut started = false
  let mut pending = false
  for c in s {
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      if started {
        pending = true
      }
    } else {
      if pending {
        b.write_char(' ')
        pending = false
      }
      b.write_char(c)
      started = true
    }
  }
  b.to_string()
}

///|
fn strip_quotes(s : String) -> String {
  let t = s.trim()
  if t.length() >= 2 && t.has_prefix("\"") && t.has_suffix("\"") {
    t[1:t.length() - 1].to_owned()
  } else {
    t.to_owned()
  }
}

///|
fn matching_paren(s : String, open : Int32) -> Int32 {
  let mut depth = 0
  let mut i = open
  while i < s.length() {
    let c = s[i]
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
      if depth == 0 {
        return i
      }
    }
    i += 1
  }
  -1
}

///|
fn kv(body : String, key : String) -> String {
  let needle = key + "="
  match body.find(needle) {
    None => ""
    Some(pos) => {
      let start = pos + needle.length()
      let mut i = start
      while i < body.length() && body[i] != ';' && body[i] != ')' {
        i += 1
      }
      collapse_ws(strip_quotes(body[start:i].to_owned()))
    }
  }
}

///|
/// Canonical `Machine_error(kind=...; who=...; message=...)`.  The `function`
/// field is intentionally dropped: it embeds case-specific symbols and would
/// defeat deduplication.
fn machine_error_detail(t : String) -> String {
  match t.find("Machine_error(") {
    None => ""
    Some(start) => {
      let open = start + 13
      let close = matching_paren(t, open)
      if close < 0 {
        return ""
      }
      let body = t[open:close].to_owned()
      let kind = kv(body, "kind")
      let who = kv(body, "who")
      let message = kv(body, "message")
      if kind == "" && who == "" && message == "" {
        ""
      } else {
        "Machine_error(kind=" +
        kind +
        "; who=" +
        who +
        "; message=" +
        message +
        ")"
      }
    }
  }
}

///|
fn parse_uint(s : String, start : Int32) -> Int32 {
  let mut i = start
  let mut v = 0
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      i += 1
    } else {
      break
    }
  }
  v
}

///|
/// Canonical `assert:<file>:<line>` for an OCaml/MoonBit assertion banner.
fn assertion_detail(t : String) -> String {
  for raw_line in t.split("\n") {
    let line = raw_line.to_owned()
    if line.contains("Assertion failed") ||
      line.contains("Assert_failure") ||
      line.contains("File \"moonc.ml\"") {
      let mut file = "unknown"
      match line.find("File \"") {
        Some(p) => {
          let tail = line[p + 6:].to_owned()
          match tail.find("\"") {
            Some(off) => {
              let q = p + 6 + off
              if q > p {
                file = @corpus.basename(line[p + 6:q].to_owned())
              }
            }
            None => ()
          }
        }
        None => ()
      }
      let mut line_no = 0
      match line.find("line ") {
        Some(p) => line_no = parse_uint(line, p + 5)
        None => ()
      }
      if line_no > 0 {
        return "assert:" + file + ":" + line_no.to_string()
      }
      return "assert:" + file
    }
  }
  ""
}

///|
fn signal_detail(rc : Int32, t : String) -> String {
  if rc < 0 {
    return "signal:" + (0 - rc).to_string()
  }
  if t.contains("SIGSEGV") || t.contains("Segmentation fault") {
    return "signal:11"
  }
  ""
}

///|
fn oops_detail(t : String) -> String {
  if !t.contains("Oops, the compiler has encountered") {
    return ""
  }
  for raw_line in t.split("\n") {
    let line = raw_line.to_owned()
    let s = line.trim()
    if s.has_prefix("Error: ") &&
      !s.contains("failed to link") &&
      !s.contains("failed to run build") {
      return "oops:" + collapse_ws(s[7:].to_owned())
    }
  }
  "oops:compiler"
}

///|
fn normalize_signature(
  klass : String,
  stage : String,
  rc : Int32,
  blob : String,
) -> String {
  if klass == "ICE" {
    let me = machine_error_detail(blob)
    if me != "" {
      return me
    }
    let sig = signal_detail(rc, blob)
    if sig != "" {
      return sig
    }
    let assert_sig = assertion_detail(blob)
    if assert_sig != "" {
      return assert_sig
    }
    let oo = oops_detail(blob)
    if oo != "" {
      return oo
    }
    return "ice:unknown"
  }
  if klass == "TIMEOUT" {
    return "timeout"
  }
  if klass == "INFRA" {
    let m = infra_marker(blob)
    return "infra:" + (if m == "" { "unknown" } else { m })
  }
  if klass == "OK" {
    return "ok"
  }
  stage + ":rc=" + rc.to_string()
}

///|
fn short(s : String, n : Int32) -> String {
  if s.length() <= n {
    s
  } else {
    s[0:n].to_owned() + "..."
  }
}

///|
async fn run_case(cfg : Config, c : @featuregen.LayoutCase) -> CaseRecord {
  let dir = join(cfg.cases_dir, c.id)
  rm_rf(dir)
  @corpus.ensure_dir(dir)
  let pkg = @featuregen.render_package(c)
  if !write_package(dir, pkg) {
    let rec : CaseRecord = {
      index: c.index,
      id: c.id,
      features: @featuregen.features_json(c),
      stage: "write",
      rc: -1,
      klass: "INFRA",
      signature: "infra:write-failed",
      dir,
      stderr_short: "failed to write generated package",
      ms: 0L,
      candidate: false,
    }
    println("[featfuzz] \{c.id} INFRA write rc=-1")
    return rec
  }
  let deadline = @async.now() + cfg.timeout_ms.to_int64()
  let stages : Array[Stage] = [Check, Build, TestBuild, Test]
  let mut stage = "write"
  let mut rc : Int32 = 0
  let mut blob = ""
  let mut klass = "OK"
  let mut elapsed : Int64 = 0
  for st in stages {
    let rem = deadline - @async.now()
    stage = stage_name(st)
    if rem <= 0L {
      klass = "TIMEOUT"
      rc = -999
      blob = "per-case timeout budget exhausted"
      break
    }
    let budget = if rem > cfg.timeout_ms.to_int64() {
      cfg.timeout_ms
    } else {
      rem.to_int()
    }
    let r = run_stage(cfg, dir, st, budget)
    elapsed += r.ms
    rc = r.rc
    blob = r.stderr + "\n" + r.stdout
    klass = classify_stage(st, r)
    if klass != "OK" {
      break
    }
  }
  let signature = normalize_signature(klass, stage, rc, blob)
  let candidate = klass == "ICE"
  if !cfg.keep && !candidate {
    rm_rf(dir)
  }
  let rec : CaseRecord = {
    index: c.index,
    id: c.id,
    features: @featuregen.features_json(c),
    stage,
    rc,
    klass,
    signature,
    dir,
    stderr_short: short(blob, 700),
    ms: elapsed,
    candidate,
  }
  println(
    "[featfuzz] \{c.id} \{klass} \{stage} rc=\{rc} sig=\{short(signature, 120)}",
  )
  rec
}

///|
fn record_json(r : CaseRecord) -> String {
  "{\"id\":\"" +
  @corpus.json_escape(r.id) +
  "\",\"features\":{" +
  r.features +
  "},\"stage\":\"" +
  @corpus.json_escape(r.stage) +
  "\",\"rc\":" +
  r.rc.to_string() +
  ",\"class\":\"" +
  @corpus.json_escape(r.klass) +
  "\",\"signature\":\"" +
  @corpus.json_escape(r.signature) +
  "\",\"dir\":\"" +
  @corpus.json_escape(r.dir) +
  "\",\"stderr_short\":\"" +
  @corpus.json_escape(r.stderr_short) +
  "\",\"candidate\":" +
  (if r.candidate { "true" } else { "false" }) +
  ",\"ms\":" +
  r.ms.to_string() +
  "}"
}

///|
fn sort_by_index(records : Array[CaseRecord]) -> Array[CaseRecord] {
  let out = records.copy()
  let n = out.length()
  for i in 1..<n {
    let cur = out[i]
    let mut j = i - 1
    while j >= 0 && out[j].index > cur.index {
      out[j + 1] = out[j]
      j -= 1
    }
    out[j + 1] = cur
  }
  out
}

///|
fn parse_int32(s : String, dflt : Int32) -> Int32 {
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
fn usage() -> Unit {
  println(
    "usage: featfuzz --out ABS_DIR [--family layout] [--target native] [--mode debug|release] [--limit N] [--jobs N] [--timeout-ms N] [--keep]",
  )
}

///|
async fn main {
  let args = @env.args()
  let cfg : Config = {
    out: "",
    family: "layout",
    target: "native",
    mode: "debug",
    limit: 0,
    jobs: 1,
    timeout_ms: 120000,
    keep: false,
    cases_dir: "",
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
    } else if a == "--target" && i + 1 < args.length() {
      cfg.target = args[i + 1]
      i += 2
    } else if a == "--mode" && i + 1 < args.length() {
      cfg.mode = args[i + 1]
      i += 2
    } else if a == "--limit" && i + 1 < args.length() {
      cfg.limit = parse_int(args[i + 1], 0)
      i += 2
    } else if a == "--jobs" && i + 1 < args.length() {
      cfg.jobs = parse_int(args[i + 1], 1)
      i += 2
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      cfg.timeout_ms = parse_int32(args[i + 1], 120000)
      i += 2
    } else if a == "--keep" {
      cfg.keep = true
      i += 1
    } else if a == "--help" || a == "-h" {
      usage()
      return
    } else {
      println("featfuzz: unknown or incomplete argument \{a}")
      usage()
      return
    }
  }
  if cfg.out == "" {
    usage()
    return
  }
  if !cfg.out.has_prefix("/") {
    println("featfuzz: --out must be an absolute path")
    return
  }
  if cfg.family != "layout" {
    println("featfuzz: unsupported family \{cfg.family} (MVP supports layout)")
    return
  }
  if cfg.mode != "debug" && cfg.mode != "release" {
    println("featfuzz: --mode must be debug or release")
    return
  }
  if cfg.jobs < 1 {
    cfg.jobs = 1
  }
  if cfg.timeout_ms < 1000 {
    cfg.timeout_ms = 1000
  }
  let all = @featuregen.layout_cases()
  let selected = if cfg.limit > 0 && cfg.limit < all.length() {
    all[0:cfg.limit].to_owned()
  } else {
    all
  }
  let cases_dir = join(cfg.out, "cases")
  cfg.cases_dir = cases_dir
  @corpus.ensure_dir(cases_dir)
  let results_path = join(cfg.out, "results.jsonl")
  let summary_path = join(cfg.out, "summary.json")
  ignore(write_one(results_path, ""))
  println(
    "[featfuzz] family=\{cfg.family} target=\{cfg.target} mode=\{cfg.mode} cases=\{selected.length()} jobs=\{cfg.jobs} timeout_ms=\{cfg.timeout_ms}",
  )
  let tasks : Array[async () -> CaseRecord] = []
  for c in selected {
    tasks.push(() => run_case(cfg, c))
  }
  let raw : Array[CaseRecord] = if tasks.length() == 0 {
    []
  } else {
    @conc.all_limited(tasks, cfg.jobs)
  }
  let records = sort_by_index(raw)
  let mut lines = ""
  let mut ok = 0
  let mut check_fail = 0
  let mut build_fail = 0
  let mut test_link_fail = 0
  let mut run_fail = 0
  let mut ice = 0
  let mut infra = 0
  let mut timeout = 0
  let sigs : Array[String] = []
  let sig_counts : Array[Int32] = []
  let sig_json : Array[String] = []
  let infra_json : Array[String] = []
  for r in records {
    lines = lines + record_json(r) + "\n"
    if r.klass == "OK" {
      ok += 1
    } else if r.klass == "CHECK_FAIL" {
      check_fail += 1
    } else if r.klass == "BUILD_FAIL" {
      build_fail += 1
    } else if r.klass == "TEST_LINK_FAIL" {
      test_link_fail += 1
    } else if r.klass == "RUN_FAIL" {
      run_fail += 1
    } else if r.klass == "ICE" {
      ice += 1
    } else if r.klass == "INFRA" {
      infra += 1
      infra_json.push(
        "{\"id\":\"" +
        @corpus.json_escape(r.id) +
        "\",\"signature\":\"" +
        @corpus.json_escape(r.signature) +
        "\"}",
      )
    } else if r.klass == "TIMEOUT" {
      timeout += 1
    }
    if r.candidate {
      let mut found = false
      for k, s in sigs {
        if s == r.signature {
          sig_counts[k] = sig_counts[k] + 1
          found = true
        }
      }
      if !found {
        sigs.push(r.signature)
        sig_counts.push(1)
        sig_json.push(
          "{\"signature\":\"" +
          @corpus.json_escape(r.signature) +
          "\",\"class\":\"" +
          @corpus.json_escape(r.klass) +
          "\",\"stage\":\"" +
          @corpus.json_escape(r.stage) +
          "\",\"rc\":" +
          r.rc.to_string() +
          ",\"first_id\":\"" +
          @corpus.json_escape(r.id) +
          "\",\"dir\":\"" +
          @corpus.json_escape(r.dir) +
          "\"}",
        )
      }
    }
  }
  ignore(write_one(results_path, lines))
  let mut candidates = ""
  for k, s in sig_json {
    if k > 0 {
      candidates = candidates + ","
    }
    let with_count = s[0:s.length() - 1].to_owned() +
      ",\"occurrences\":" +
      sig_counts[k].to_string() +
      "}"
    candidates = candidates + with_count
  }
  let mut infra_items = ""
  for k, s in infra_json {
    if k > 0 {
      infra_items = infra_items + ","
    }
    infra_items = infra_items + s
  }
  let summary = "{\"family\":\"" +
    @corpus.json_escape(cfg.family) +
    "\",\"target\":\"" +
    @corpus.json_escape(cfg.target) +
    "\",\"mode\":\"" +
    @corpus.json_escape(cfg.mode) +
    "\",\"matrix_size\":" +
    @featuregen.matrix_size().to_string() +
    ",\"selected\":" +
    records.length().to_string() +
    ",\"limit\":" +
    cfg.limit.to_string() +
    ",\"jobs\":" +
    cfg.jobs.to_string() +
    ",\"keep\":" +
    (if cfg.keep { "true" } else { "false" }) +
    ",\"counts\":{\"OK\":" +
    ok.to_string() +
    ",\"CHECK_FAIL\":" +
    check_fail.to_string() +
    ",\"BUILD_FAIL\":" +
    build_fail.to_string() +
    ",\"TEST_LINK_FAIL\":" +
    test_link_fail.to_string() +
    ",\"RUN_FAIL\":" +
    run_fail.to_string() +
    ",\"ICE\":" +
    ice.to_string() +
    ",\"INFRA\":" +
    infra.to_string() +
    ",\"TIMEOUT\":" +
    timeout.to_string() +
    "},\"distinct_candidate_signatures\":" +
    sigs.length().to_string() +
    ",\"candidates\":[" +
    candidates +
    "],\"infra_excluded\":[" +
    infra_items +
    "]}"
  ignore(write_one(summary_path, summary))
  println(
    "[featfuzz done] selected=\{records.length()} OK=\{ok} ICE=\{ice} BUILD_FAIL=\{build_fail} TEST_LINK_FAIL=\{test_link_fail} RUN_FAIL=\{run_fail} CHECK_FAIL=\{check_fail} INFRA=\{infra} TIMEOUT=\{timeout} sigs=\{sigs.length()}",
  )
  println("[featfuzz] results=\{results_path}")
  println("[featfuzz] summary=\{summary_path}")
}
