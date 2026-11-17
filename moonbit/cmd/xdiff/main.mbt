///|
/// Cross-backend execution differential for generated feature cases.
///
/// The existing staged oracles (`featfuzz`, `asyncfuzz`) stop at build/link
/// and never compare what a program *prints* on different backends.  This
/// driver renders the same generated source once per case, builds it per
/// target, executes the produced artifact, and compares stdout plus exit
/// status across every target that actually built.
///
/// Known upstream link/ICE signatures (F7/F8/F9) are labelled as
/// `KNOWN_LINK_ICE` and are never counted as output mismatches.  Targets that
/// failed to build are excluded from the comparison rather than compared as
/// empty output.
///
/// Usage:
///   xdiff --out ABS_DIR [--family layout|async]
///         [--targets wasm-gc,wasm,js,native] [--limit N]
///         [--timeout-ms N] [--jobs N] [--only ID] [--keep]
struct Config {
  mut out : String
  mut family : String
  mut targets : Array[String]
  mut limit : Int32
  mut timeout_ms : Int32
  mut jobs : Int32
  mut keep : Bool
  mut only : String
}

///|
/// One target's complete observation.  `executed` is false for build/link
/// failures and for a run that timed out; such records never take part in the
/// cross-target stdout comparison.
struct TargetObs {
  target : String
  stage : String
  rc : Int32
  executed : Bool
  stdout : String
  stderr_short : String
  digest : String
  ms : Int64
  klass : String
  signature : String
  artifact : String
}

///|
struct CaseRec {
  index : Int32
  id : String
  verdict : String
  obs : Array[TargetObs]
  dir : String
  note : String
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
fn short(s : String, n : Int32) -> String {
  if s.length() <= n {
    s
  } else {
    s[0:n].to_owned() + "..."
  }
}

///|
/// Normalize stdout for comparison: strip only trailing spaces, tabs, CR and
/// LF at the very end of the captured text.  Interior whitespace, leading
/// whitespace and every line break inside the payload are preserved, so a
/// program that prints two lines can never be confused with one line.
fn strip_trailing_ws(s : String) -> String {
  let mut end = s.length()
  while end > 0 {
    let c = s[end - 1]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      end -= 1
    } else {
      break
    }
  }
  s[0:end].to_owned()
}

///|
/// Digest of the raw captured stdout, before normalization.  Two runs that
/// differ only in a trailing newline still have equal *normalized* text but
/// distinct raw digests, which keeps the JSONL evidence unambiguous.
fn output_digest(s : String) -> String {
  @corpus.sha1_hex(s)
}

///|
/// Exact comparison rule: same normalized stdout AND same exit code.
fn obs_equal(a : TargetObs, b : TargetObs) -> Bool {
  a.rc == b.rc && strip_trailing_ws(a.stdout) == strip_trailing_ws(b.stdout)
}

///|
fn has_class(obs : Array[TargetObs], klass : String) -> Bool {
  for o in obs {
    if o.klass == klass {
      return true
    }
  }
  false
}

///|
fn executed(obs : Array[TargetObs]) -> Array[TargetObs] {
  let out : Array[TargetObs] = []
  for o in obs {
    if o.executed {
      out.push(o)
    }
  }
  out
}

///|
/// Case-level verdict from per-target observations.
///
/// Precedence: a real output divergence between two executed targets is the
/// most important result (`OUTPUT_MISMATCH`).  Only when no divergence exists
/// do compiler failures classify the case, and known upstream ICE signatures
/// are separated from unknown crashes.  A single executed target can never
/// produce a divergence, so it becomes `SINGLE_TARGET`; if one target built
/// and the rest failed with a *known* ICE, the known-ICE label wins because it
/// names the actual upstream blocker.
fn verdict_of(obs : Array[TargetObs]) -> String {
  let ex = executed(obs)
  let mut mismatch = false
  if ex.length() >= 2 {
    for i in 1..<ex.length() {
      if !obs_equal(ex[0], ex[i]) {
        mismatch = true
      }
    }
  }
  if mismatch {
    return "OUTPUT_MISMATCH"
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
  if ex.length() == 0 {
    if has_class(obs, "BUILD_FAIL") {
      return "BUILD_FAIL"
    }
    if has_class(obs, "INFRA") {
      return "INFRA"
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

///|
/// The three upstream signatures that this repo already tracks.  Matching is
/// textual because the compiler reports them as a banner plus a source
/// location; the label is the stable key.
fn known_ice_label(blob : String) -> String {
  if blob.contains("lower_array_make") {
    "known_f7:lower_array_make"
  } else if blob.contains("finish_stub_wrapper_shell") {
    "known_f9:finish_stub_wrapper_shell"
  } else if blob.contains("moonc.ml:125623") ||
    blob.contains("line 125623") {
    "known_f8:moonc.ml:125623"
  } else {
    ""
  }
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
fn infra_marker(t : String) -> String {
  let markers : Array[String] = [
    "module was not found in the registry", "failed to download",
    "download failed", "network error", "Network error", "Connection refused",
    "Could not resolve host", "registry index", "failed to fetch", "TLS error",
    "HTTP error", "No such file or directory", "package not found",
    "Cannot find package", "cannot find package",
  ]
  for m in markers {
    if t.contains(m) {
      return m
    }
  }
  ""
}

///|
/// Stable, low-cardinality signature for an unknown compiler crash.
fn normalize_ice(stage : String, rc : Int32, blob : String) -> String {
  if rc == -999 {
    return "spawn_error"
  }
  for raw_line in blob.split("\n") {
    let line = raw_line.trim()
    if line.has_prefix("Error: ") {
      return stage + ":error:" + collapse_ws(line[7:].to_owned())
    }
  }
  if blob.contains("Machine_error(") {
    return "Machine_error"
  }
  if blob.contains("Assert_failure") || blob.contains("Assertion failed") {
    return "assert_failure"
  }
  if blob.contains("Fatal error: exception") {
    return "ocaml_exception"
  }
  if blob.contains("Stack overflow") || blob.contains("Stack_overflow") {
    return "stack_overflow"
  }
  if rc < 0 {
    return "signal:" + rc.to_string()
  }
  "ice:unknown"
}

///|
/// Classify a failed build/link stage.  Known upstream signatures win over the
/// generic ICE bucket so the report can separate them downstream.
fn classify_build_failure(
  stage : String,
  rc : Int32,
  timed_out : Bool,
  stderr : String,
) -> (String, String) {
  if timed_out {
    return ("TIMEOUT", "timeout:" + stage)
  }
  let known = known_ice_label(stderr)
  if known != "" {
    return ("KNOWN_LINK_ICE", known)
  }
  if has_compiler_crash(stderr) {
    return ("ICE", normalize_ice(stage, rc, stderr))
  }
  let infra = infra_marker(stderr)
  if infra != "" {
    return ("INFRA", "infra:" + infra)
  }
  ("BUILD_FAIL", stage + ":rc=" + rc.to_string())
}

///|
fn target_ext(target : String) -> String {
  if target == "js" {
    ".js"
  } else if target == "native" {
    ".exe"
  } else {
    ".wasm"
  }
}

///|
/// Locate the artifact `moon build` produced.  The module basename is fixed by
/// the renderer (`generated`), but scanning the build directory avoids
/// duplicating that assumption and skips `.wasm.map` siblings.
fn find_artifact(dir : String, target : String) -> String {
  let bdir = join(dir, "_build/" + target + "/debug/build")
  let names = @fs.read_dir(bdir) catch { _ => [] }
  let ext = target_ext(target)
  for n in names {
    if n.has_suffix(ext) && !n.has_suffix(".map") {
      return join(bdir, n)
    }
  }
  ""
}

///|
fn moon_path() -> String {
  match @env.get_env_var("MOON") {
    Some(p) => p
    None => home_path() + "/.moon/bin/moon"
  }
}

///|
fn home_path() -> String {
  match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
}

///|
fn moonrun_path() -> String {
  match @env.get_env_var("MOONRUN") {
    Some(p) => p
    None => home_path() + "/.moon/bin/moonrun"
  }
}

///|
fn node_path() -> String {
  match @env.get_env_var("NODE") {
    Some(p) => p
    None => "node"
  }
}

///|
fn target_is_known(t : String) -> Bool {
  t == "wasm-gc" || t == "wasm" || t == "js" || t == "native"
}
