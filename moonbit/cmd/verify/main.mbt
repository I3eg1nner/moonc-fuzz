///|
/// Fresh-directory candidate verifier.
///
/// Each repeat gets a pristine copy of the candidate package (build products,
/// dependency links and VCS metadata are excluded), then the standard
/// check/build/test pipeline is driven with a per-stage wall-clock timeout.
/// The result is a low-cardinality normalized signature plus a stability and
/// control verdict, so a one-off ICE is not mistaken for a reproducible one.
///
/// The verifier never edits the source package and never fuzzes.  It invokes
/// the pinned `moon` from PATH (or `MOON_BIN`) with `--frozen`, so the verifier
/// itself does not start a dependency download.
///
/// Usage:
///   verify --dir ABS_PACKAGE_DIR --target native|wasm|wasm-gc|js \
///          --mode debug|release --repeats N --timeout-ms N --out ABS_JSON \
///          [--control-dir ABS_PACKAGE_DIR]

///|
struct Config {
  dir : String
  target : String
  mode : String
  repeats : Int32
  timeout_ms : Int32
  out : String
  control : String?
}

///|
struct StageRun {
  name : String
  args : Array[String]
  rc : Int32
  ms : Int64
  timed_out : Bool
  signature : String
  diagnostics : Array[String]
}

///|
struct RepeatRun {
  repeat : Int32
  work_dir : String
  stages : Array[StageRun]
  terminal : String
  failing_stage : String
  signature : String
  rc : Int32
  rc_class : String
  ms : Int64
  diagnostics : Array[String]
}

///|
struct ControlReport {
  dir : String
  terminal : String
  stable : Bool
  runs : Array[RepeatRun]
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
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => if i == 0 { "/" } else { path[0:i].to_owned() }
    None => "."
  }
}

///|
fn is_abs(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// Trim trailing slashes so the basename of `/a/b/` is `b`, not the empty
/// string.  The filesystem root is left alone.
fn trim_dir(path : String) -> String {
  let mut p = path
  while p.length() > 1 && p.has_suffix("/") {
    p = p[0:p.length() - 1].to_owned()
  }
  p
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
    "usage: verify --dir ABS_PACKAGE_DIR --target native|wasm|wasm-gc|js --mode debug|release --repeats N --timeout-ms N --out ABS_JSON [--control-dir ABS_PACKAGE_DIR]",
  )
}

///|
fn default_config() -> Config {
  {
    dir: "",
    target: "native",
    mode: "debug",
    repeats: 3,
    timeout_ms: 120000,
    out: "",
    control: None,
  }
}

///|
fn parse_args(args : Array[String]) -> Config {
  let mut cfg = default_config()
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--dir" && i + 1 < args.length() {
      cfg = { ..cfg, dir: args[i + 1], }
      i += 2
    } else if a == "--target" && i + 1 < args.length() {
      cfg = { ..cfg, target: args[i + 1], }
      i += 2
    } else if a == "--mode" && i + 1 < args.length() {
      cfg = { ..cfg, mode: args[i + 1], }
      i += 2
    } else if a == "--repeats" && i + 1 < args.length() {
      cfg = { ..cfg, repeats: parse_int(args[i + 1], 0), }
      i += 2
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      cfg = { ..cfg, timeout_ms: parse_int(args[i + 1], 0), }
      i += 2
    } else if a == "--out" && i + 1 < args.length() {
      cfg = { ..cfg, out: args[i + 1], }
      i += 2
    } else if a == "--control-dir" && i + 1 < args.length() {
      cfg = { ..cfg, control: Some(args[i + 1]), }
      i += 2
    } else {
      // Unknown or incomplete option: leave the config invalid.
      cfg = { ..cfg, dir: "", out: "", }
      i += 1
    }
  }
  cfg
}

///|
fn config_error(cfg : Config) -> String {
  if cfg.dir == "" {
    return "--dir is required (absolute package directory)"
  }
  if cfg.out == "" {
    return "--out is required (absolute JSON path)"
  }
  if !is_abs(cfg.dir) {
    return "--dir must be absolute"
  }
  if !is_abs(cfg.out) {
    return "--out must be absolute"
  }
  match cfg.control {
    Some(c) => if !is_abs(c) { return "--control-dir must be absolute" }
    None => ()
  }
  if cfg.target != "native" &&
    cfg.target != "wasm" &&
    cfg.target != "wasm-gc" &&
    cfg.target != "js" {
    return "--target must be native, wasm, wasm-gc or js"
  }
  if cfg.mode != "debug" && cfg.mode != "release" {
    return "--mode must be debug or release"
  }
  if cfg.repeats < 1 || cfg.repeats > 50 {
    return "--repeats must be in 1..50"
  }
  if cfg.timeout_ms < 1000 || cfg.timeout_ms > 1800000 {
    return "--timeout-ms must be in 1000..1800000"
  }
  ""
}

///|
fn skip_name(name : String) -> Bool {
  name == "_build" || name == ".mooncakes" || name == ".git"
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
fn ensure_dir(path : String) -> Unit {
  if path == "" || path == "." || path == "/" || @fs.path_exists(path) {
    return
  }
  let parent = dirname(path)
  if parent != path {
    ensure_dir(parent)
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn is_dir_path(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
fn copy_tree(src : String, dst : String) -> Bool {
  let names = @fs.read_dir(src) catch { _ => return false }
  for n in names {
    if skip_name(n) {
      continue
    }
    let sp = join(src, n)
    let dp = join(dst, n)
    if is_dir_path(sp) {
      ensure_dir(dp)
      if !copy_tree(sp, dp) {
        return false
      }
    } else {
      let data = @fs.read_file_to_bytes(sp) catch { _ => return false }
      @fs.write_bytes_to_file(dp, data) catch {
        _ => return false
      }
    }
  }
  true
}

///|
/// Copy a package while excluding `_build`, `.mooncakes` and `.git`.
/// Returns false on any I/O error; a partially copied repeat directory is
/// never used by the caller.
fn copy_package(src : String, dst : String) -> Bool {
  if !@fs.path_exists(src) || !is_dir_path(src) {
    return false
  }
  rm_rf(dst)
  ensure_dir(dst)
  copy_tree(src, dst)
}

///|
fn sanitize_tag(s : String) -> String {
  let b = StringBuilder()
  let mut n = 0
  for c in s {
    if n >= 32 {
      break
    }
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' {
      b.write_char(c)
    } else {
      b.write_char('_')
    }
    n += 1
  }
  if n == 0 {
    "pkg"
  } else {
    b.to_string()
  }
}

///|
fn default_temp_base() -> String {
  match @env.get_env_var("MBTFUZZ_VERIFY_TMP") {
    Some(v) => if v == "" { "/tmp/mbtfuzz_verify" } else { v }
    None => "/tmp/mbtfuzz_verify"
  }
}

///|
/// Deterministic per-(package,target,mode,role) root.  The whole root is
/// removed at the start of a run, which cleans stale repeat copies.  The tool
/// is intentionally serialized: concurrent runs for the same tuple would
/// share this root.
fn temp_root(
  src : String,
  target : String,
  mode : String,
  role : String,
) -> String {
  let h = @corpus.short_hash(src + "|" + target + "|" + mode)
  let tag = sanitize_tag(basename(src)) + "-" + h[0:12].to_owned()
  join(join(default_temp_base(), tag + "-" + role), "repeats")
}

///|
fn resolve_moon() -> String {
  match @env.get_env_var("MOON_BIN") {
    Some(v) => if v != "" { v } else { default_moon() }
    None => default_moon()
  }
}

///|
fn default_moon() -> String {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let candidate = join(join(home, ".moon/bin"), "moon")
  if @fs.path_exists(candidate) {
    candidate
  } else {
    "moon"
  }
}

///|
fn stage_names() -> Array[String] {
  ["check", "build", "test_build_only", "test"]
}

///|
fn stage_args(name : String, target : String, mode : String) -> Array[String] {
  let a : Array[String] = ["--target", target, "--frozen"]
  if mode == "release" {
    a.push("--release")
  }
  if name == "check" {
    ["check"] + a
  } else if name == "build" {
    ["build"] + a
  } else if name == "test_build_only" {
    ["test"] + a + ["--build-only"]
  } else {
    ["test"] + a
  }
}

///|
fn collapse_ws(s : String) -> String {
  let b = StringBuilder()
  let mut prev_space = false
  for c in s {
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      if !prev_space {
        b.write_char(' ')
      }
      prev_space = true
    } else {
      b.write_char(c)
      prev_space = false
    }
  }
  b.to_string().trim().to_owned()
}

///|
fn replace_all(s : String, needle : String, repl : String) -> String {
  if needle == "" {
    return s
  }
  let b = StringBuilder()
  let mut rest = s
  while true {
    match rest.find(needle) {
      Some(i) => {
        b.write_string(rest[0:i].to_owned())
        b.write_string(repl)
        let next = i + needle.length()
        rest = rest[next:].to_owned()
      }
      None => {
        b.write_string(rest)
        break
      }
    }
  }
  b.to_string()
}

///|
/// Replace host paths so the signature is stable across repeats.  The source
/// directory and the fresh copy root both map to `<PKG>`.
fn sanitize_paths(text : String, roots : Array[String]) -> String {
  let mut s = text
  for r in roots {
    if r != "" {
      s = replace_all(s, r, "<PKG>")
    }
  }
  s
}

///|
fn cap_text(s : String, n : Int32) -> String {
  if s.length() <= n {
    s
  } else {
    s[0:n].to_owned() + "..."
  }
}

///|
/// Extract one `key=value` field from a `Machine_error` payload.  Values are
/// either quoted or bare up to the next `;`/`)`.
fn machine_field(inner : String, key : String) -> String {
  let needle = key + "="
  match inner.find(needle) {
    None => "?"
    Some(i) => {
      let rest = inner[i + needle.length():].to_owned().trim().to_owned()
      if rest.has_prefix("\"") {
        let body = rest[1:].to_owned()
        match body.find("\"") {
          Some(j) => body[0:j].to_owned()
          None => body
        }
      } else {
        let body = rest
        match body.find(";") {
          Some(j) => body[0:j].to_owned().trim().to_owned()
          None =>
            match body.find(")") {
              Some(j) => body[0:j].to_owned().trim().to_owned()
              None => body.trim().to_owned()
            }
        }
      }
    }
  }
}

///|
/// `Machine_error(kind=...; who=...; message=...)`, collapsed onto one line
/// and stripped of the diagnostic's line wrapping.
fn machine_error_sig(text : String) -> String? {
  let flat = collapse_ws(text)
  match flat.find("Machine_error(") {
    None => None
    Some(idx) => {
      let open = idx + "Machine_error".length()
      let mut depth = 0
      let mut end = -1
      for i in open..<flat.length() {
        match flat.get_char(i) {
          Some(c) =>
            if c == '(' {
              depth += 1
            } else if c == ')' {
              depth -= 1
              if depth == 0 {
                end = i
                break
              }
            }
          None => ()
        }
      }
      if end < 0 {
        Some("Machine_error(...)")
      } else {
        let inner = flat[open + 1:end].to_owned()
        Some(
          "Machine_error(kind=" +
          machine_field(inner, "kind") +
          "; who=" +
          machine_field(inner, "who") +
          "; message=" +
          machine_field(inner, "message") +
          ")",
        )
      }
    }
  }
}

///|
fn digits_at(s : String, start : Int32) -> String {
  let b = StringBuilder()
  let mut i = start
  while i < s.length() {
    match s.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          b.write_char(c)
          i += 1
        } else {
          break
        }
      None => break
    }
  }
  b.to_string()
}

///|
/// `moonc.ml` assertions are canonicalized to `moonc.ml:<line>:assertion`;
/// the character range and surrounding source context are not part of the
/// signature.
fn moonc_assertion_sig(text : String) -> String? {
  match text.find("moonc.ml") {
    None => None
    Some(idx) => {
      let tail = text[idx + "moonc.ml".length():].to_owned()
      let mut line = ""
      if tail.has_prefix(":") {
        line = digits_at(tail, 1)
      }
      if line == "" {
        match tail.find("line ") {
          Some(i) => line = digits_at(tail, i + "line ".length())
          None => ()
        }
      }
      if line == "" {
        match tail.find(":") {
          Some(i) => line = digits_at(tail, i + 1)
          None => ()
        }
      }
      if line == "" {
        Some("moonc.ml:?:assertion")
      } else {
        Some("moonc.ml:" + line + ":assertion")
      }
    }
  }
}

///|
fn oops_error_sig(text : String) -> String? {
  if !text.contains("Oops, the compiler") {
    return None
  }
  for line in text.split("\n") {
    let s = line.trim()
    if s.has_prefix("Error:") {
      let detail = collapse_ws(s["Error:".length():].to_owned())
      return Some("ICE: " + cap_text(detail, 300))
    }
  }
  Some("ICE: Oops, the compiler has encountered an unexpected situation")
}

///|
fn generic_error_sig(text : String) -> String? {
  for line in text.split("\n") {
    let s = line.trim()
    if s.has_prefix("Error:") {
      let detail = collapse_ws(s["Error:".length():].to_owned())
      return Some("Error: " + cap_text(detail, 300))
    }
    if s.has_prefix("error:") {
      let detail = collapse_ws(s["error:".length():].to_owned())
      return Some("error: " + cap_text(detail, 300))
    }
  }
  None
}

///|
fn signal_name(rc : Int32) -> String {
  let n = if rc < 0 { -rc } else if rc > 128 && rc < 160 { rc - 128 } else { 0 }
  if n == 11 {
    "SIGSEGV"
  } else if n == 6 {
    "SIGABRT"
  } else if n == 9 {
    "SIGKILL"
  } else if n == 4 {
    "SIGILL"
  } else if n == 8 {
    "SIGFPE"
  } else if n == 15 {
    "SIGTERM"
  } else if n == 13 {
    "SIGPIPE"
  } else {
    "signal"
  }
}

///|
fn fallback_sig(text : String, rc : Int32) -> String {
  for line in text.split("\n") {
    let s = collapse_ws(line.to_owned())
    if s != "" {
      return cap_text(s, 240)
    }
  }
  "rc:" + rc.to_string()
}

///|
fn run_signature(text : String, rc : Int32, timed_out : Bool) -> String {
  if timed_out {
    return "timeout"
  }
  if rc == 0 {
    return ""
  }
  match machine_error_sig(text) {
    Some(s) => s
    None =>
      match moonc_assertion_sig(text) {
        Some(s) => s
        None =>
          match oops_error_sig(text) {
            Some(s) => s
            None =>
              match generic_error_sig(text) {
                Some(s) => s
                None =>
                  if rc < 0 || (rc > 128 && rc < 160) {
                    "signal:" + signal_name(rc)
                  } else {
                    fallback_sig(text, rc)
                  }
              }
          }
      }
  }
}

///|
fn looks_ice(text : String) -> Bool {
  text.contains("Oops, the compiler has encountered") ||
  text.contains("Machine_error(") ||
  text.contains("Assertion_failure") ||
  text.contains("Assert_failure") ||
  text.contains("moonc.ml")
}

///|
fn looks_like_link_failure(text : String) -> Bool {
  text.contains("failed to link") || text.contains("link-core")
}

///|
/// Stage-aware classification.  `ice` dominates because a `Machine_error` in
/// `moon test --build-only` is a compiler ICE, not an ordinary link failure.
fn classify_stage(name : String, r : @exec.RunResult) -> String {
  if r.timed_out {
    return "timeout"
  }
  if r.rc == 0 {
    return "ok"
  }
  if r.rc == -999 && r.stderr == "" && r.stdout == "" {
    return "infra"
  }
  let blob = r.stderr + "\n" + r.stdout
  if looks_ice(blob) {
    return "ice"
  }
  if name == "check" {
    "check_fail"
  } else if name == "build" {
    "build_fail"
  } else if name == "test_build_only" {
    "test_link_fail"
  } else if name == "test" {
    if looks_like_link_failure(blob) {
      "test_link_fail"
    } else {
      "run_fail"
    }
  } else {
    "infra"
  }
}

///|
fn looks_diagnostic(s : String) -> Bool {
  s.contains("Error:") ||
  s.contains("error:") ||
  s.contains("Oops,") ||
  s.contains("This is a bug") ||
  s.contains("Assertion") ||
  s.contains("assertion") ||
  s.contains("panic") ||
  s.contains("failed") ||
  s.contains("FAILED") ||
  s.contains("Fatal")
}

///|
/// Prefer actual error lines over the compiler's ASCII-art banner and the
/// enormous `Compiler args:` replay.  Fall back to the first non-empty lines
/// when a stage emits an unrecognized diagnostic shape.
fn first_diagnostics(text : String, limit : Int32) -> Array[String] {
  let preferred : Array[String] = []
  let fallback : Array[String] = []
  for line in text.split("\n") {
    let s = collapse_ws(line.to_owned())
    if s == "" {
      continue
    }
    if s.has_prefix("Compiler args:") {
      continue
    }
    if fallback.length() < limit {
      fallback.push(cap_text(s, 240))
    }
    if looks_diagnostic(s) && preferred.length() < limit {
      preferred.push(cap_text(s, 240))
    }
  }
  if preferred.length() > 0 {
    preferred
  } else {
    fallback
  }
}

///|
fn rc_class(terminal : String, rc : Int32) -> String {
  if terminal == "timeout" {
    "timeout"
  } else if rc == 0 {
    "ok"
  } else if rc < 0 || (rc > 128 && rc < 160) {
    "signal"
  } else {
    "error"
  }
}

///|
fn infra_run(repeat : Int32, work : String, sig : String) -> RepeatRun {
  {
    repeat,
    work_dir: work,
    stages: [],
    terminal: "infra",
    failing_stage: "none",
    signature: sig,
    rc: 0,
    rc_class: "error",
    ms: 0L,
    diagnostics: [sig],
  }
}

///|
async fn run_stages(
  repeat : Int32,
  work : String,
  target : String,
  mode : String,
  timeout_ms : Int32,
  moon : String,
  roots : Array[String],
) -> RepeatRun {
  let stages : Array[StageRun] = []
  let mut terminal = "ok"
  let mut failing = "none"
  let mut signature = ""
  let mut rc = 0
  let mut total_ms = 0L
  let mut diags : Array[String] = []
  for name in stage_names() {
    let args = stage_args(name, target, mode)
    let r = @exec.run_isolated(
      moon,
      args,
      work,
      timeout_ms,
      max_output_bytes=1048576,
    )
    let blob = sanitize_paths(r.stderr + "\n" + r.stdout, roots)
    let term = classify_stage(name, r)
    let sig = if term == "ok" {
      ""
    } else {
      run_signature(blob, r.rc, r.timed_out)
    }
    let d = if term == "ok" { [] } else { first_diagnostics(blob, 5) }
    stages.push({
      name,
      args,
      rc: r.rc,
      ms: r.ms,
      timed_out: r.timed_out,
      signature: sig,
      diagnostics: d,
    })
    total_ms = total_ms + r.ms
    if term != "ok" {
      terminal = term
      failing = name
      signature = sig
      rc = r.rc
      diags = d
      break
    }
  }
  {
    repeat,
    work_dir: work,
    stages,
    terminal,
    failing_stage: failing,
    signature,
    rc,
    rc_class: rc_class(terminal, rc),
    ms: total_ms,
    diagnostics: diags,
  }
}

///|
async fn run_repeats(
  src : String,
  target : String,
  mode : String,
  repeats : Int32,
  timeout_ms : Int32,
  moon : String,
  role : String,
) -> Array[RepeatRun] {
  let root = temp_root(src, target, mode, role)
  rm_rf(root)
  ensure_dir(root)
  let runs : Array[RepeatRun] = []
  if !@fs.path_exists(src) || !is_dir_path(src) {
    for i in 0..<repeats {
      runs.push(
        infra_run(i, join(root, "repeat_" + i.to_string()), "missing_dir"),
      )
    }
    return runs
  }
  if !@fs.path_exists(join(src, "moon.mod")) {
    for i in 0..<repeats {
      runs.push(
        infra_run(i, join(root, "repeat_" + i.to_string()), "missing_moon_mod"),
      )
    }
    return runs
  }
  for i in 0..<repeats {
    let work = join(root, "repeat_" + i.to_string())
    rm_rf(work)
    if !copy_package(src, work) {
      runs.push(infra_run(i, work, "copy_failed"))
      continue
    }
    runs.push(run_stages(i, work, target, mode, timeout_ms, moon, [src, work]))
  }
  runs
}

///|
fn runs_stable(runs : Array[RepeatRun]) -> Bool {
  if runs.length() == 0 {
    return false
  }
  let first = runs[0]
  for r in runs {
    if r.terminal != first.terminal ||
      r.failing_stage != first.failing_stage ||
      r.signature != first.signature ||
      r.rc_class != first.rc_class {
      return false
    }
  }
  true
}

///|
fn common_terminal(runs : Array[RepeatRun]) -> String {
  if runs.length() == 0 {
    "infra"
  } else {
    let t = runs[0].terminal
    for r in runs {
      if r.terminal != t {
        return "mixed"
      }
    }
    t
  }
}

///|
fn decide_verdict(
  runs : Array[RepeatRun],
  stable : Bool,
  control : ControlReport?,
) -> String {
  let mut any_infra = false
  for r in runs {
    if r.terminal == "infra" {
      any_infra = true
    }
  }
  if any_infra {
    return "infra"
  }
  let terminal = common_terminal(runs)
  if !stable {
    return "not_reproduced"
  }
  if terminal == "ok" {
    return "not_reproduced"
  }
  match control {
    None => "reproduced"
    Some(c) =>
      if c.stable && c.terminal == "ok" {
        "reproduced"
      } else {
        "control_failed"
      }
  }
}

///|
fn bool_str(v : Bool) -> String {
  if v {
    "true"
  } else {
    "false"
  }
}

///|
fn json_strings(xs : Array[String]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  let mut first = true
  for x in xs {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string("\"")
    b.write_string(@corpus.json_escape(x))
    b.write_string("\"")
  }
  b.write_string("]")
  b.to_string()
}

///|
fn stage_json(s : StageRun) -> String {
  let b = StringBuilder()
  b.write_string("{\"stage\":\"")
  b.write_string(@corpus.json_escape(s.name))
  b.write_string("\",\"args\":")
  b.write_string(json_strings(s.args))
  b.write_string(",\"rc\":")
  b.write_string(s.rc.to_string())
  b.write_string(",\"ms\":")
  b.write_string(s.ms.to_string())
  b.write_string(",\"timed_out\":")
  b.write_string(bool_str(s.timed_out))
  b.write_string(",\"signature\":\"")
  b.write_string(@corpus.json_escape(s.signature))
  b.write_string("\",\"diagnostics\":")
  b.write_string(json_strings(s.diagnostics))
  b.write_string("}")
  b.to_string()
}

///|
fn run_json(r : RepeatRun) -> String {
  let b = StringBuilder()
  b.write_string("{\"repeat\":")
  b.write_string(r.repeat.to_string())
  b.write_string(",\"work_dir\":\"")
  b.write_string(@corpus.json_escape(r.work_dir))
  b.write_string("\",\"stages\":[")
  let mut first = true
  for s in r.stages {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string(stage_json(s))
  }
  b.write_string("],\"terminal\":\"")
  b.write_string(@corpus.json_escape(r.terminal))
  b.write_string("\",\"stage\":\"")
  b.write_string(@corpus.json_escape(r.failing_stage))
  b.write_string("\",\"signature\":\"")
  b.write_string(@corpus.json_escape(r.signature))
  b.write_string("\",\"rc\":")
  b.write_string(r.rc.to_string())
  b.write_string(",\"rc_class\":\"")
  b.write_string(@corpus.json_escape(r.rc_class))
  b.write_string("\",\"ms\":")
  b.write_string(r.ms.to_string())
  b.write_string(",\"diagnostics\":")
  b.write_string(json_strings(r.diagnostics))
  b.write_string("}")
  b.to_string()
}

///|
fn runs_json(runs : Array[RepeatRun]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  let mut first = true
  for r in runs {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string(run_json(r))
  }
  b.write_string("]")
  b.to_string()
}

///|
fn output_json(
  cfg : Config,
  runs : Array[RepeatRun],
  stable : Bool,
  control : ControlReport?,
  verdict : String,
) -> String {
  let b = StringBuilder()
  b.write_string("{\"candidate_dir\":\"")
  b.write_string(@corpus.json_escape(cfg.dir))
  b.write_string("\",\"target\":\"")
  b.write_string(@corpus.json_escape(cfg.target))
  b.write_string("\",\"mode\":\"")
  b.write_string(@corpus.json_escape(cfg.mode))
  b.write_string("\",\"repeats\":")
  b.write_string(cfg.repeats.to_string())
  b.write_string(",\"runs\":")
  b.write_string(runs_json(runs))
  b.write_string(",\"stable\":")
  b.write_string(bool_str(stable))
  b.write_string(",\"control\":")
  match control {
    Some(c) => {
      b.write_string("{\"dir\":\"")
      b.write_string(@corpus.json_escape(c.dir))
      b.write_string("\",\"terminal\":\"")
      b.write_string(@corpus.json_escape(c.terminal))
      b.write_string("\",\"stable\":")
      b.write_string(bool_str(c.stable))
      b.write_string(",\"runs\":")
      b.write_string(runs_json(c.runs))
      b.write_string("}")
    }
    None => b.write_string("null")
  }
  b.write_string(",\"verdict\":\"")
  b.write_string(@corpus.json_escape(verdict))
  b.write_string("\"}")
  b.to_string()
}

///|
fn short_sig(s : String) -> String {
  if s == "" {
    "-"
  } else {
    cap_text(s, 110)
  }
}

///|
fn print_summary(
  cfg : Config,
  runs : Array[RepeatRun],
  stable : Bool,
  control : ControlReport?,
  verdict : String,
  out_ok : Bool,
) -> Unit {
  println(
    "[verify] candidate=" +
    cfg.dir +
    " target=" +
    cfg.target +
    " mode=" +
    cfg.mode +
    " repeats=" +
    cfg.repeats.to_string(),
  )
  for r in runs {
    println(
      "  repeat " +
      r.repeat.to_string() +
      ": " +
      r.terminal +
      " at " +
      r.failing_stage +
      " rc=" +
      r.rc.to_string() +
      " ms=" +
      r.ms.to_string() +
      " sig=" +
      short_sig(r.signature),
    )
    if r.diagnostics.length() > 0 {
      println("    diag: " + cap_text(r.diagnostics[0], 160))
    }
  }
  println("[verify] stable=" + bool_str(stable) + " verdict=" + verdict)
  match control {
    Some(c) =>
      println(
        "[verify] control=" +
        c.dir +
        " terminal=" +
        c.terminal +
        " stable=" +
        bool_str(c.stable),
      )
    None => println("[verify] control=none")
  }
  if out_ok {
    println("[verify] json=" + cfg.out)
  } else {
    println("[verify] failed to write json=" + cfg.out)
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() >= 2 && (args[1] == "--help" || args[1] == "-h") {
    usage()
    return
  }
  let cfg = parse_args(args)
  let err = config_error(cfg)
  if err != "" {
    println("[verify] " + err)
    usage()
    @env.exit(2)
    return
  }
  let moon = resolve_moon()
  if !@fs.path_exists(moon) && moon.contains("/") {
    println("[verify] moon binary not found: " + moon)
    @env.exit(2)
    return
  }
  @corpus.ensure_dir(dirname(cfg.out))
  let runs = run_repeats(
    trim_dir(cfg.dir),
    cfg.target,
    cfg.mode,
    cfg.repeats,
    cfg.timeout_ms,
    moon,
    "cand",
  )
  let stable = runs_stable(runs)
  let control = match cfg.control {
    Some(d) => {
      let cruns = run_repeats(
        trim_dir(d),
        cfg.target,
        cfg.mode,
        cfg.repeats,
        cfg.timeout_ms,
        moon,
        "ctrl",
      )
      let cr : ControlReport = {
        dir: trim_dir(d),
        terminal: common_terminal(cruns),
        stable: runs_stable(cruns),
        runs: cruns,
      }
      Some(cr)
    }
    None => None
  }
  let verdict = decide_verdict(runs, stable, control)
  let text = output_json(cfg, runs, stable, control, verdict)
  let mut out_ok = true
  @fs.write_string_to_file(cfg.out, text + "\n") catch {
    _ => out_ok = false
  }
  print_summary(cfg, runs, stable, control, verdict, out_ok)
  if !out_ok || verdict == "infra" {
    @env.exit(2)
  }
}
