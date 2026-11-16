///|
/// Differential wasm-vs-js pipeline.
///
/// The Python harness compared stdout and rc after a full `build-package` +
/// `link-core` + execute cycle.  This package ports that exact sequence, with
/// the same flags and the same `strip()` comparison rule.  It is intentionally
/// separate from the fuzz driver so the oracle can be tested on fixed inputs.

///|
/// Outcome of a differential run.  `Same` is the only class that means the two
/// backends completed comparable executions and agreed; build/link failures are
/// deliberately not folded into `same=true`.
pub(all) enum DiffClass {
  Same
  SemanticDiff
  RuntimeDiff
  AcceptDiff
  CompilerAbort
  Inconclusive
}

///|
pub impl Eq for DiffClass with fn equal(a, b) {
  match (a, b) {
    (Same, Same)
    | (SemanticDiff, SemanticDiff)
    | (RuntimeDiff, RuntimeDiff)
    | (AcceptDiff, AcceptDiff)
    | (CompilerAbort, CompilerAbort)
    | (Inconclusive, Inconclusive) => true
    _ => false
  }
}

///|
pub extend DiffClass with Eq::{not_equal, equal}

///|

///|
/// Explicit lifecycle stage.  Native and wasm use the same enum so a build
/// failure cannot be mistaken for a program exit.
pub(all) enum Stage {
  Build
  Link
  Run
  NativeRun
}

///|
pub impl Eq for Stage with fn equal(a, b) {
  match (a, b) {
    (Build, Build) | (Link, Link) | (Run, Run) | (NativeRun, NativeRun) => true
    _ => false
  }
}

///|
pub extend Stage with Eq::{not_equal, equal}

///|
pub fn stage_name(s : Stage) -> String {
  match s {
    Build => "build"
    Link => "link"
    Run => "run"
    NativeRun => "native-run"
  }
}

///|
/// One backend's complete observation.  Grouping the fields avoids the
/// positional string/Int32 argument mix-up in the old classifier.
pub(all) struct BackendResult {
  kind : String
  rc : Int32
  out : String
  stage : Stage
  detail : String
  truncated : Bool
  out_digest : String
  out_len : Int64
}

///|
pub fn diff_class_name(c : DiffClass) -> String {
  match c {
    Same => "SAME"
    SemanticDiff => "SEMANTIC_DIFF"
    RuntimeDiff => "RUNTIME_DIFF"
    AcceptDiff => "ACCEPT_DIFF"
    CompilerAbort => "COMPILER_ABORT"
    Inconclusive => "INCONCLUSIVE"
  }
}

///|
pub struct DiffResult {
  same : Bool
  verdict : DiffClass
  wasm_rc : Int32
  js_rc : Int32
  wasm_out : String
  js_out : String
  wasm_kind : String
  js_kind : String
  wasm_stage : String
  js_stage : String
  wasm_detail : String
  js_detail : String
  wasm_truncated : Bool
  js_truncated : Bool
  wasm_digest : String
  js_digest : String
  wasm_len : Int64
  js_len : Int64
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
fn write(path : String, text : String) -> Unit {
  @fs.write_string_to_file(path, text) catch {
    _ => ()
  }
}

///|
fn std_flags(bundle : String) -> Array[String] {
  [
    "-i",
    join(bundle, "builtin/builtin.mi") + ":moonbitlang/core/builtin",
    "-i",
    join(bundle, "prelude/prelude.mi") + ":prelude",
  ]
}

///|
pub async fn build_package(
  moonc : String,
  wd : String,
  target : String,
  bundle : String,
  pkg : String,
  all_pkgs : String,
  timeout_ms : Int32,
) -> @exec.RunResult {
  let out = "out_" + target + ".core"
  @exec.run(
    moonc,
    [
      "build-package",
      "in.mbt",
      "-o",
      out,
      "-pkg",
      pkg,
      "-pkg-type",
      "executable",
      "-pkg-sources",
      pkg + ":.",
      "-target",
      target,
      "-g",
      "-O0",
      "-workspace-path",
      ".",
      "-all-pkgs",
      all_pkgs,
    ] +
    std_flags(bundle),
    wd,
    timeout_ms,
  )
}

///|
fn core_files(bundle : String) -> Array[String] {
  // Match Python's `glob(bundle/*/*.core)` exactly: one package level, not a
  // recursive walk.  Adding nested cores causes duplicate runtime symbols and
  // a link-time Key_not_found("$moonbit.incref") ICE.
  let out : Array[String] = []
  let dirs = @fs.read_dir(bundle) catch { _ => [] }
  for d in dirs {
    let p = join(bundle, d)
    let isdir = @fs.is_dir(p) catch { _ => false }
    if isdir {
      let names = @fs.read_dir(p) catch { _ => [] }
      for n in names {
        if n.has_suffix(".core") {
          out.push(join(p, n))
        }
      }
    }
  }
  out.sort()
  out
}

///|
pub fn link_args(
  target : String,
  bundle : String,
  core_dir : String,
  pkg : String,
  pkg_config : String,
  core_path : String,
  out_path : String,
) -> Array[String] {
  let args : Array[String] = ["link-core"]
  for c in core_files(bundle) {
    args.push(c)
  }
  args.push(core_path)
  args.push("-main")
  args.push(pkg)
  args.push("-o")
  args.push(out_path)
  args.push("-pkg-config-path")
  args.push(pkg_config)
  args.push("-pkg-sources")
  args.push(pkg + ":.")
  args.push("-pkg-sources")
  args.push("moonbitlang/core:" + core_dir)
  args.push("-target")
  args.push(target)
  args.push("-g")
  args.push("-O0")
  if target == "wasm" {
    args.push("-wasi")
  }
  args
}

///|
pub async fn link(
  moonc : String,
  wd : String,
  target : String,
  bundle : String,
  core_dir : String,
  pkg : String,
  pkg_config : String,
  timeout_ms : Int32,
) -> @exec.RunResult {
  let out = "out_" + target + (if target == "js" { ".js" } else { ".wasm" })
  @exec.run(
    moonc,
    link_args(
      target,
      bundle,
      core_dir,
      pkg,
      pkg_config,
      "out_" + target + ".core",
      out,
    ),
    wd,
    timeout_ms,
  )
}

///|
fn strip(s : String) -> String {
  // Python's .strip() over ASCII output.  Child stdout in these tests is
  // ASCII; trim() covers the whitespace that matters here.
  s.trim().to_owned()
}

///|
fn is_compiler_abort(kind : String, stage : Stage) -> Bool {
  (stage == Build || stage == Link) &&
  (
    kind == "ICE" ||
    kind == "OOM" ||
    kind == "OCAML_EXN" ||
    kind == "STACK" ||
    kind == "ASSERT" ||
    kind == "SIG"
  )
}

///|
priv enum OutputCmp {
  Equal
  Different
  Unknown
}

///|
/// Truncated output never causes a false SAME.  When both sides kept a digest
/// of the complete trimmed stdout, the digest is authoritative; otherwise the
/// comparison is unknown and the caller must return INCONCLUSIVE.
fn compare_outputs(a : BackendResult, b : BackendResult) -> OutputCmp {
  if !a.truncated && !b.truncated {
    if strip(a.out) == strip(b.out) {
      Equal
    } else {
      Different
    }
  } else if a.truncated &&
    b.truncated &&
    a.out_digest != "" &&
    b.out_digest != "" {
    if a.out_digest == b.out_digest {
      Equal
    } else {
      Different
    }
  } else {
    Unknown
  }
}

///|
/// Single decision function used by both real differential runs and fault
/// injection tests.  It first establishes whether both sides produced a
/// comparable execution; only then does it compare rc/stdout.  A build/link
/// failure on both sides is *inconclusive*, not equal.
pub fn classify_diff(wasm : BackendResult, js : BackendResult) -> DiffClass {
  if wasm.kind == "HANG" || js.kind == "HANG" {
    return Inconclusive
  }
  if wasm.rc == -999 || js.rc == -999 {
    return Inconclusive
  }
  if is_compiler_abort(wasm.kind, wasm.stage) ||
    is_compiler_abort(js.kind, js.stage) {
    return CompilerAbort
  }
  let wasm_ran = wasm.stage == Run
  let js_ran = js.stage == Run || js.stage == NativeRun
  if wasm_ran && js_ran {
    if wasm.kind != js.kind || wasm.rc != js.rc {
      if wasm.kind != "OK" && js.kind != "OK" {
        RuntimeDiff
      } else {
        SemanticDiff
      }
    } else {
      match compare_outputs(wasm, js) {
        Equal => Same
        Different => SemanticDiff
        Unknown => Inconclusive
      }
    }
  } else if wasm_ran || js_ran {
    AcceptDiff
  } else {
    // Neither side reached execution.  Normal diagnostics on both sides, or a
    // mixture of reject/link-error, cannot establish semantic equality.
    Inconclusive
  }
}

///|
/// Backwards-compatible run-stage predicate.  New code should call
/// `classify_diff` with explicit backend results.
pub fn outcomes_agree(
  wasm_kind : String,
  wasm_rc : Int32,
  wasm_out : String,
  js_kind : String,
  js_rc : Int32,
  js_out : String,
) -> Bool {
  classify_diff(
    {
      kind: wasm_kind,
      rc: wasm_rc,
      out: wasm_out,
      stage: Run,
      detail: "",
      truncated: false,
      out_digest: "",
      out_len: 0L,
    },
    {
      kind: js_kind,
      rc: js_rc,
      out: js_out,
      stage: Run,
      detail: "",
      truncated: false,
      out_digest: "",
      out_len: 0L,
    },
  ) ==
  Same
}

///|
/// Build, link and execute one program on wasm and js.  `src` must not already
/// contain a main; this function appends one exactly like mbtfuzz.py.
pub async fn diff_program(
  moonc : String,
  moonrun : String,
  node : String,
  wd : String,
  src : String,
  pkg : String,
  wasm_bundle : String,
  js_bundle : String,
  core_dir : String,
  pkg_config : String,
  all_pkgs : String,
  timeout_ms : Int32,
) -> DiffResult {
  let with_main = if src.find("fn main") is Some(_) {
    src
  } else {
    src + "\n\nfn main { () }\n"
  }
  write(join(wd, "in.mbt"), with_main)
  let bwasm = build_package(
    moonc, wd, "wasm", wasm_bundle, pkg, all_pkgs, timeout_ms,
  )
  let bjs = build_package(moonc, wd, "js", js_bundle, pkg, all_pkgs, timeout_ms)
  let mut wasm_rc = bwasm.rc
  let mut js_rc = bjs.rc
  let mut wasm_out = ""
  let mut js_out = ""
  let mut wasm_kind = @exec.classify(bwasm)
  let mut js_kind = @exec.classify(bjs)
  let mut wasm_stage : Stage = Build
  let mut js_stage : Stage = Build
  let mut wasm_detail = @exec.ice_detail(bwasm) + bwasm.stderr
  let mut js_detail = @exec.ice_detail(bjs) + bjs.stderr
  let mut wasm_truncated = false
  let mut js_truncated = false
  let mut wasm_digest = ""
  let mut js_digest = ""
  let mut wasm_len = 0L
  let mut js_len = 0L
  if bwasm.rc == 0 {
    let l = link(
      moonc, wd, "wasm", wasm_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    wasm_kind = @exec.classify(l)
    wasm_stage = Link
    wasm_rc = l.rc
    wasm_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run_isolated(
        moonrun,
        ["out_wasm.wasm"],
        wd,
        timeout_ms,
        max_output_bytes=1048576,
        mem_mb=4096,
      )
      wasm_rc = r.rc
      wasm_out = r.stdout
      wasm_kind = @exec.classify(r)
      wasm_stage = Run
      wasm_detail = r.stderr
      wasm_truncated = r.stdout_truncated
      wasm_digest = r.stdout_digest
      wasm_len = r.stdout_full_len
    }
  }
  if bjs.rc == 0 {
    let l = link(
      moonc, wd, "js", js_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    js_kind = @exec.classify(l)
    js_stage = Link
    js_rc = l.rc
    js_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run_isolated(
        node,
        ["out_js.js"],
        wd,
        timeout_ms,
        max_output_bytes=1048576,
        mem_mb=4096,
      )
      js_rc = r.rc
      js_out = r.stdout
      js_kind = @exec.classify(r)
      js_stage = Run
      js_detail = r.stderr
      js_truncated = r.stdout_truncated
      js_digest = r.stdout_digest
      js_len = r.stdout_full_len
    }
  }
  let wb : BackendResult = {
    kind: wasm_kind,
    rc: wasm_rc,
    out: wasm_out,
    stage: wasm_stage,
    detail: wasm_detail,
    truncated: wasm_truncated,
    out_digest: wasm_digest,
    out_len: wasm_len,
  }
  let jb : BackendResult = {
    kind: js_kind,
    rc: js_rc,
    out: js_out,
    stage: js_stage,
    detail: js_detail,
    truncated: js_truncated,
    out_digest: js_digest,
    out_len: js_len,
  }
  let verdict = classify_diff(wb, jb)
  {
    same: verdict == Same,
    verdict,
    wasm_rc,
    js_rc,
    wasm_out,
    js_out,
    wasm_kind,
    js_kind,
    wasm_stage: stage_name(wasm_stage),
    js_stage: stage_name(js_stage),
    wasm_detail,
    js_detail,
    wasm_truncated,
    js_truncated,
    wasm_digest,
    js_digest,
    wasm_len,
    js_len,
  }
}

///|
/// `moon run --build-only` prints `{"artifacts_path":[...]}`.  Return the
/// first executable path, or None if the build produced no artifact.
fn native_artifact(blob : String) -> String? {
  for line in blob.split("\n") {
    let t = line.trim()
    if t.has_prefix("{") {
      let parsed = @json.parse(t) catch { _ => continue }
      match parsed {
        Object(o) =>
          match o.get("artifacts_path") {
            Some(Array(a)) =>
              match a.get(0) {
                Some(String(path)) => return Some(path)
                _ => ()
              }
            _ => ()
          }
        _ => ()
      }
    }
  }
  None
}

///|
/// Native-vs-wasm differential.  The native side is split into:
///   `moon run --build-only`  -> build stage
///   <artifact path>          -> native-run stage
/// so an abort with rc 134 is a completed run, not a build failure.
pub async fn diff_native(
  moonc : String,
  moonrun : String,
  moon : String,
  wd : String,
  src : String,
  pkg : String,
  wasm_bundle : String,
  core_dir : String,
  pkg_config : String,
  all_pkgs : String,
  timeout_ms : Int32,
) -> DiffResult {
  let with_main = if src.find("fn main") is Some(_) {
    src
  } else {
    src + "\n\nfn main { () }\n"
  }
  write(join(wd, "in.mbt"), with_main)
  let bwasm = build_package(
    moonc, wd, "wasm", wasm_bundle, pkg, all_pkgs, timeout_ms,
  )
  let mut wasm_rc = bwasm.rc
  let mut wasm_out = ""
  let mut wasm_kind = @exec.classify(bwasm)
  let mut wasm_stage : Stage = Build
  let mut wasm_detail = @exec.ice_detail(bwasm) + bwasm.stderr
  let mut wasm_truncated = false
  let mut wasm_digest = ""
  let mut wasm_len = 0L
  if bwasm.rc == 0 {
    let l = link(
      moonc, wd, "wasm", wasm_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    wasm_kind = @exec.classify(l)
    wasm_stage = Link
    wasm_rc = l.rc
    wasm_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run_isolated(
        moonrun,
        ["out_wasm.wasm"],
        wd,
        timeout_ms,
        max_output_bytes=1048576,
        mem_mb=4096,
      )
      wasm_rc = r.rc
      wasm_out = r.stdout
      wasm_kind = @exec.classify(r)
      wasm_stage = Run
      wasm_detail = r.stderr
      wasm_truncated = r.stdout_truncated
      wasm_digest = r.stdout_digest
      wasm_len = r.stdout_full_len
    }
  }
  let nb = @exec.run_isolated(
    moon,
    ["run", "in.mbt", "--target", "native", "--build-only"],
    wd,
    timeout_ms,
    max_output_bytes=1048576,
    mem_mb=6144,
  )
  let mut js_kind = @exec.classify(nb)
  let mut js_stage : Stage = Build
  let mut js_rc = nb.rc
  let mut js_out = ""
  let mut js_detail = @exec.ice_detail(nb) + nb.stderr
  let mut js_truncated = false
  let mut js_digest = ""
  let mut js_len = 0L
  if nb.rc == 0 {
    match native_artifact(nb.stdout) {
      Some(path) => {
        let exe = if path.has_prefix("/") { path } else { join(wd, path) }
        let r = @exec.run_isolated(
          exe,
          [],
          wd,
          timeout_ms,
          max_output_bytes=1048576,
          mem_mb=4096,
        )
        js_rc = r.rc
        js_out = r.stdout
        js_kind = @exec.classify(r)
        js_stage = NativeRun
        js_detail = r.stderr
        js_truncated = r.stdout_truncated
        js_digest = r.stdout_digest
        js_len = r.stdout_full_len
      }
      None => {
        js_kind = "INFRA"
        js_detail = "build-only produced no artifact path\n" + nb.stdout
      }
    }
  }
  let wb : BackendResult = {
    kind: wasm_kind,
    rc: wasm_rc,
    out: wasm_out,
    stage: wasm_stage,
    detail: wasm_detail,
    truncated: wasm_truncated,
    out_digest: wasm_digest,
    out_len: wasm_len,
  }
  let jb : BackendResult = {
    kind: js_kind,
    rc: js_rc,
    out: js_out,
    stage: js_stage,
    detail: js_detail,
    truncated: js_truncated,
    out_digest: js_digest,
    out_len: js_len,
  }
  let verdict = classify_diff(wb, jb)
  {
    same: verdict == Same,
    verdict,
    wasm_rc,
    js_rc,
    wasm_out,
    js_out,
    wasm_kind,
    js_kind,
    wasm_stage: stage_name(wasm_stage),
    js_stage: stage_name(js_stage),
    wasm_detail,
    js_detail,
    wasm_truncated,
    js_truncated,
    wasm_digest,
    js_digest,
    wasm_len,
    js_len,
  }
}
