///|
/// Differential wasm-vs-js pipeline.
///
/// The Python harness compared stdout and rc after a full `build-package` +
/// `link-core` + execute cycle.  This package ports that exact sequence, with
/// the same flags and the same `strip()` comparison rule.  It is intentionally
/// separate from the fuzz driver so the oracle can be tested on fixed inputs.
pub struct DiffResult {
  same : Bool
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
  let args : Array[String] = ["link-core"]
  for c in core_files(bundle) {
    args.push(c)
  }
  args.push("out_" + target + ".core")
  args.push("-main")
  args.push(pkg)
  args.push("-o")
  args.push(out)
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
  @exec.run(moonc, args, wd, timeout_ms)
}

///|
fn strip(s : String) -> String {
  // Python's .strip() over ASCII output.  Child stdout in these tests is
  // ASCII; trim() covers the whitespace that matters here.
  s.trim().to_owned()
}

///|
/// Pure agreement predicate so fault injection can test the oracle without a
/// compiler.  A successful run is compared by rc and stdout; two failures are
/// compared by failure class (native abort vs wasm trap is not a miscompile).
pub fn outcomes_agree(
  wasm_kind : String,
  wasm_rc : Int32,
  wasm_out : String,
  js_kind : String,
  js_rc : Int32,
  js_out : String,
) -> Bool {
  if wasm_kind == "OK" && js_kind == "OK" {
    wasm_rc == js_rc && strip(wasm_out) == strip(js_out)
  } else {
    wasm_kind == js_kind
  }
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
  let mut wasm_stage = "build"
  let mut js_stage = "build"
  let mut wasm_detail = @exec.ice_detail(bwasm) + bwasm.stderr
  let mut js_detail = @exec.ice_detail(bjs) + bjs.stderr
  if bwasm.rc == 0 {
    let l = link(
      moonc, wd, "wasm", wasm_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    wasm_kind = @exec.classify(l)
    wasm_stage = "link"
    wasm_rc = l.rc
    wasm_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run(moonrun, ["out_wasm.wasm"], wd, timeout_ms)
      wasm_rc = r.rc
      wasm_out = r.stdout
      wasm_kind = @exec.classify(r)
      wasm_stage = "run"
      wasm_detail = r.stderr
    }
  }
  if bjs.rc == 0 {
    let l = link(
      moonc, wd, "js", js_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    js_kind = @exec.classify(l)
    js_stage = "link"
    js_rc = l.rc
    js_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run(node, ["out_js.js"], wd, timeout_ms)
      js_rc = r.rc
      js_out = r.stdout
      js_kind = @exec.classify(r)
      js_stage = "run"
      js_detail = r.stderr
    }
  }
  {
    same: wasm_rc == js_rc &&
    strip(wasm_out) == strip(js_out) &&
    wasm_kind == js_kind,
    wasm_rc,
    js_rc,
    wasm_out,
    js_out,
    wasm_kind,
    js_kind,
    wasm_stage,
    js_stage,
    wasm_detail,
    js_detail,
  }
}

///|
/// Native-vs-wasm differential.  `moon run in.mbt --target native` delegates
/// the C link step to the build system (link-core alone produces a relocatable
/// object, not an executable), which is exactly what a user sees.
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
  let mut wasm_stage = "build"
  let mut wasm_detail = @exec.ice_detail(bwasm) + bwasm.stderr
  if bwasm.rc == 0 {
    let l = link(
      moonc, wd, "wasm", wasm_bundle, core_dir, pkg, pkg_config, timeout_ms,
    )
    wasm_kind = @exec.classify(l)
    wasm_stage = "link"
    wasm_rc = l.rc
    wasm_detail = @exec.ice_detail(l) + l.stderr
    if l.rc == 0 {
      let r = @exec.run(moonrun, ["out_wasm.wasm"], wd, timeout_ms)
      wasm_rc = r.rc
      wasm_out = r.stdout
      wasm_kind = @exec.classify(r)
      wasm_stage = "run"
      wasm_detail = r.stderr
    }
  }
  let n = @exec.run(
    moon,
    ["run", "in.mbt", "--target", "native"],
    wd,
    timeout_ms,
  )
  let js_kind = @exec.classify(n)
  {
    same: wasm_rc == n.rc &&
    strip(wasm_out) == strip(n.stdout) &&
    wasm_kind == js_kind,
    wasm_rc,
    js_rc: n.rc,
    wasm_out,
    js_out: n.stdout,
    wasm_kind,
    js_kind,
    wasm_stage,
    js_stage: "native-run",
    wasm_detail,
    js_detail: @exec.ice_detail(n) + n.stderr,
  }
}
