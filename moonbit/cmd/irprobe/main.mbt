///|
/// Compile the small IR samples to MoonBit and compare the generated wasm/js
/// executions against the independent IR interpreter.  This is deliberately a
/// prototype oracle: it covers only the subset implemented by `ir/`.

///|
fn join_events(events : Array[String]) -> String {
  let b = StringBuilder()
  for i, e in events {
    if i > 0 {
      b.write_string("\n")
    }
    b.write_string(e)
  }
  b.to_string()
}

///|
fn write(path : String, text : String) -> Bool {
  @corpus.ensure_dir(@corpus.dirname(path))
  @fs.write_string_to_file(path, text) catch {
    _ => return false
  }
  true
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
fn strip_flag(argv : Array[String], flag : String) -> Array[String] {
  let out : Array[String] = []
  for a in argv {
    if a != flag {
      out.push(a)
    }
  }
  out
}

///|
fn build_args(
  target : String,
  bundle : String,
  pkg : String,
  all_pkgs : String,
  out : String,
  with_o0 : Bool,
) -> Array[String] {
  let args : Array[String] = [
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
  ]
  if with_o0 {
    args.push("-O0")
  }
  args.push("-workspace-path")
  args.push(".")
  args.push("-all-pkgs")
  args.push(all_pkgs)
  args.push("-i")
  args.push(
    @corpus.join(bundle, "builtin/builtin.mi") + ":moonbitlang/core/builtin",
  )
  args.push("-i")
  args.push(@corpus.join(bundle, "prelude/prelude.mi") + ":prelude")
  args
}

///|
async fn four_cell_case(
  program : @ir.Program,
  case_id : String,
  wd : String,
  moonc : String,
  moonrun : String,
  target : String,
  bundle : String,
  core_dir : String,
  pkg : String,
  pkg_config : String,
  all_pkgs : String,
  timeout_ms : Int32,
  inject_arm : String,
) -> String {
  let events = Some(@ir.run(program, 10000)) catch { _ => None }
  let expected = match events {
    Some(e) => join_events(e)
    None => ""
  }
  let target_text = if expected == "" { "" } else { expected + "\n" }
  let src = @ir.emit_program(program)
  let wrote = write(@corpus.join(wd, "in.mbt"), src)
  let b0 = @exec.run(
    moonc,
    build_args(target, bundle, pkg, all_pkgs, "out_O0.core", true),
    wd,
    timeout_ms,
    max_output_bytes=8 * 1024 * 1024,
  )
  let bd = @exec.run(
    moonc,
    build_args(target, bundle, pkg, all_pkgs, "out_default.core", false),
    wd,
    timeout_ms,
    max_output_bytes=8 * 1024 * 1024,
  )
  let base_reason = if events is None {
    "interpreter"
  } else if !wrote {
    "write"
  } else if b0.rc != 0 {
    "build_O0"
  } else if bd.rc != 0 {
    "build_default"
  } else {
    ""
  }
  let mut ok = base_reason == ""
  let arm_text = StringBuilder()
  let reason_text = StringBuilder()
  for arm in ["B0L0", "B0Ld", "BdL0", "BdLd"] {
    let build_o0 = arm == "B0L0" || arm == "B0Ld"
    let link_o0 = arm == "B0L0" || arm == "BdL0"
    let core = if build_o0 { "out_O0.core" } else { "out_default.core" }
    let wasm = arm + ".wasm"
    let largs = @oracle.link_args(
      target, bundle, core_dir, pkg, pkg_config, core, wasm,
    )
    let largs = if link_o0 { largs } else { strip_flag(largs, "-O0") }
    let lr = @exec.run(
      moonc,
      largs,
      wd,
      timeout_ms,
      max_output_bytes=8 * 1024 * 1024,
    )
    let rr = if lr.rc == 0 {
      @exec.run(
        moonrun,
        [wasm],
        wd,
        timeout_ms,
        max_output_bytes=8 * 1024 * 1024,
      )
    } else {
      @corpus.ensure_dir(wd)
      {
        rc: -1,
        stdout: "",
        stderr: "link failed",
        ms: 0L,
        timed_out: false,
        stdout_digest: "",
        stdout_full_len: 0L,
        stdout_truncated: false,
      }
    }
    let actual = if inject_arm == arm || inject_arm == "all" {
      rr.stdout + "Emit(999, -1)\n"
    } else {
      rr.stdout
    }
    let reason = if base_reason != "" {
      base_reason
    } else if lr.rc != 0 {
      "link"
    } else if rr.timed_out {
      "timeout"
    } else if rr.stdout_truncated {
      "truncated"
    } else if rr.rc != 0 {
      "run"
    } else if actual != target_text {
      "mismatch"
    } else {
      "ok"
    }
    let arm_ok = reason == "ok"
    if !arm_ok {
      ok = false
    }
    arm_text.write_string(",\"")
    arm_text.write_string(arm)
    arm_text.write_string("\":")
    arm_text.write_string(if arm_ok { "true" } else { "false" })
    reason_text.write_string(",\"")
    reason_text.write_string(arm)
    reason_text.write_string("_reason\":\"")
    reason_text.write_string(@corpus.json_escape(reason))
    reason_text.write_string("\"")
  }
  "{\"case\":\"" +
  @corpus.json_escape(case_id) +
  "\",\"four_cell\":true,\"ok\":" +
  (if ok { "true" } else { "false" }) +
  ",\"build_O0_rc\":" +
  b0.rc.to_string() +
  ",\"build_default_rc\":" +
  bd.rc.to_string() +
  ",\"inject_arm\":\"" +
  @corpus.json_escape(inject_arm) +
  "\"" +
  arm_text.to_string() +
  reason_text.to_string() +
  "}"
}

///|
fn reason_field(row : String, key : String) -> String {
  let needle = "\"" + key + "\":\""
  match row.find(needle) {
    Some(i) => {
      let rest = row[i + needle.length():].to_owned()
      match rest.find("\"") {
        Some(j) => rest[0:j].to_owned()
        None => ""
      }
    }
    None => ""
  }
}

///|
fn reason_vector(row : String) -> Array[String] {
  [
    reason_field(row, "B0L0_reason"),
    reason_field(row, "B0Ld_reason"),
    reason_field(row, "BdL0_reason"),
    reason_field(row, "BdLd_reason"),
  ]
}

///|
fn vectors_equal(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, x in a {
    if x != b[i] {
      return false
    }
  }
  true
}

///|
fn main_body(program : @ir.Program) -> Array[@ir.Stmt] {
  for f in program.funcs {
    if f.name == "main" {
      return f.body
    }
  }
  []
}

///|
fn with_main_body(program : @ir.Program, body : Array[@ir.Stmt]) -> @ir.Program {
  let funcs : Array[@ir.Func] = []
  for f in program.funcs {
    if f.name == "main" {
      funcs.push({ ..f, body, })
    } else {
      funcs.push(f)
    }
  }
  { funcs, }
}

///|
fn without_stmt(body : Array[@ir.Stmt], index : Int32) -> Array[@ir.Stmt] {
  let out : Array[@ir.Stmt] = []
  for i, s in body {
    if i != index {
      out.push(s)
    }
  }
  out
}

///|
fn events_equal(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, x in a {
    if x != b[i] {
      return false
    }
  }
  true
}

///|
async fn reduce_failure_case(
  program : @ir.Program,
  case_id : String,
  wd : String,
  moonc : String,
  moonrun : String,
  target : String,
  bundle : String,
  core_dir : String,
  pkg : String,
  pkg_config : String,
  all_pkgs : String,
  timeout_ms : Int32,
  inject_arm : String,
) -> String {
  let baseline_row = four_cell_case(
    program, case_id, wd, moonc, moonrun, target, bundle, core_dir, pkg, pkg_config,
    all_pkgs, timeout_ms, inject_arm,
  )
  let baseline = reason_vector(baseline_row)
  let baseline_events_opt = Some(@ir.run(program, 10000)) catch { _ => None }
  if baseline_events_opt is None {
    return "{\"case\":\"" +
      @corpus.json_escape(case_id) +
      "\",\"reduce_failure\":true,\"ok\":false,\"error\":\"interpreter\"}"
  }
  let baseline_events = baseline_events_opt.unwrap()
  let has_failure = reason_field(baseline_row, "B0L0_reason") != "ok" ||
    reason_field(baseline_row, "B0Ld_reason") != "ok" ||
    reason_field(baseline_row, "BdL0_reason") != "ok" ||
    reason_field(baseline_row, "BdLd_reason") != "ok"
  if !has_failure {
    return "{\"case\":\"" +
      @corpus.json_escape(case_id) +
      "\",\"reduce_failure\":true,\"ok\":false,\"error\":\"no_failure\"}"
  }
  let before_stmts = @ir.statement_count(program)
  let mut current = program
  let mut changed = true
  while changed {
    changed = false
    let body = main_body(current)
    let mut i = body.length() - 1
    while i >= 0 {
      let candidate = with_main_body(current, without_stmt(body, i))
      let valid = try {
        @ir.check_program(candidate)
        events_equal(@ir.run(candidate, 10000), baseline_events)
      } catch {
        _ => false
      }
      if valid {
        let row = four_cell_case(
          candidate,
          case_id + "_cand",
          wd,
          moonc,
          moonrun,
          target,
          bundle,
          core_dir,
          pkg,
          pkg_config,
          all_pkgs,
          timeout_ms,
          inject_arm,
        )
        if vectors_equal(reason_vector(row), baseline) {
          current = candidate
          changed = true
        }
      }
      i -= 1
    }
  }
  let final_row = four_cell_case(
    current,
    case_id + "_final",
    wd,
    moonc,
    moonrun,
    target,
    bundle,
    core_dir,
    pkg,
    pkg_config,
    all_pkgs,
    timeout_ms,
    inject_arm,
  )
  let after_stmts = @ir.statement_count(current)
  "{\"case\":\"" +
  @corpus.json_escape(case_id) +
  "\",\"four_cell\":true,\"reduce_failure\":true,\"baseline_reasons\":[\"" +
  @corpus.json_escape(baseline[0]) +
  "\",\"" +
  @corpus.json_escape(baseline[1]) +
  "\",\"" +
  @corpus.json_escape(baseline[2]) +
  "\",\"" +
  @corpus.json_escape(baseline[3]) +
  "\"],\"before_stmts\":" +
  before_stmts.to_string() +
  ",\"after_stmts\":" +
  after_stmts.to_string() +
  ",\"preserved\":" +
  (if vectors_equal(reason_vector(final_row), baseline) {
    "true"
  } else {
    "false"
  }) +
  ",\"ok\":" +
  (if vectors_equal(reason_vector(final_row), baseline) && has_failure {
    "true"
  } else {
    "false"
  }) +
  "}"
}

///|
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let root = if args.length() >= 2 { args[1] } else { "/data/audit/mbtfuzz" }
  let out = if args.length() >= 3 { args[2] } else { "/tmp/mbtfuzz_irprobe" }
  let mut random_n = 0
  let mut seed = 1
  let mut do_reduce = false
  let mut four_cell = false
  let mut reduce_failure = false
  let mut inject_arm = ""
  let mut ai = 3
  while ai < args.length() {
    if args[ai] == "--random" && ai + 1 < args.length() {
      random_n = parse_int(args[ai + 1], 0)
      ai += 2
    } else if args[ai] == "--seed" && ai + 1 < args.length() {
      seed = parse_int(args[ai + 1], 1)
      ai += 2
    } else if args[ai] == "--reduce" {
      do_reduce = true
      ai += 1
    } else if args[ai] == "--four-cell" {
      four_cell = true
      ai += 1
    } else if args[ai] == "--inject-arm" && ai + 1 < args.length() {
      inject_arm = args[ai + 1]
      ai += 2
    } else if args[ai] == "--reduce-failure" {
      reduce_failure = true
      ai += 1
    } else {
      println(
        "usage: irprobe ROOT OUT [--random N] [--seed S] [--reduce] [--four-cell]",
      )
      @env.exit(2)
    }
  }
  if inject_arm != "" &&
    inject_arm != "all" &&
    inject_arm != "B0L0" &&
    inject_arm != "B0Ld" &&
    inject_arm != "BdL0" &&
    inject_arm != "BdLd" {
    println("[irprobe] unknown injection arm")
    @env.exit(2)
  }
  if inject_arm != "" && !four_cell {
    println("[irprobe] --inject-arm requires --four-cell")
    @env.exit(2)
  }
  if reduce_failure && !four_cell {
    println("[irprobe] --reduce-failure requires --four-cell")
    @env.exit(2)
  }
  @corpus.ensure_dir(out)
  let moonc = @corpus.join(@corpus.join(home, ".moon/bin"), "moonc")
  let moonrun = @corpus.join(@corpus.join(home, ".moon/bin"), "moonrun")
  let node = "node"
  let core = @corpus.join(home, ".moon/lib/core")
  let wasm_bundle = @corpus.join(core, "_build/wasm/release/bundle")
  let js_bundle = @corpus.join(core, "_build/js/release/bundle")
  let pkg = "I3eg1nner/tpl/cmd/main"
  let pkg_config = @corpus.join(@corpus.join(root, "harness"), "moon.pkg")
  let all_pkgs = @corpus.join(@corpus.join(root, "harness"), "all_pkgs.json")
  let programs : Array[@ir.Program] = []
  for p in @ir.sample_programs() {
    programs.push(p)
  }
  for i in 0..<random_n {
    programs.push(
      @ir.generate((seed.to_int64() + i.to_int64()).reinterpret_as_uint64(), 8),
    )
  }
  let rows : Array[String] = []
  let mut errors = 0
  for i, program in programs {
    let tag = i.to_string()
    let wd = @corpus.join(@corpus.join(out, "work"), "p" + tag)
    @corpus.ensure_dir(wd)
    if four_cell {
      let row = if reduce_failure {
        reduce_failure_case(
          program, tag, wd, moonc, moonrun, "wasm-gc", wasm_bundle, core, pkg, pkg_config,
          all_pkgs, 30000, inject_arm,
        )
      } else {
        four_cell_case(
          program, tag, wd, moonc, moonrun, "wasm-gc", wasm_bundle, core, pkg, pkg_config,
          all_pkgs, 30000, inject_arm,
        )
      }
      if !row.contains("\"ok\":true") {
        errors += 1
      }
      rows.push(row)
      continue
    }
    let interpreter_events = Some(@ir.run(program, 10000)) catch { _ => None }
    let expected = match interpreter_events {
      Some(events) => join_events(events)
      None => ""
    }
    let before_stmts = @ir.statement_count(program)
    let mut reduce_ok = true
    let used_program = if do_reduce {
      match interpreter_events {
        Some(events) =>
          @ir.reduce(program, events, 10000) catch {
            _ => {
              reduce_ok = false
              program
            }
          }
        None => {
          reduce_ok = false
          program
        }
      }
    } else {
      program
    }
    let after_stmts = @ir.statement_count(used_program)
    let src = @ir.emit_program(used_program)
    let wrote = write(@corpus.join(wd, "in.mbt"), src)
    let d = @oracle.diff_program(
      moonc,
      moonrun,
      node,
      wd,
      src,
      pkg,
      wasm_bundle + "/",
      js_bundle + "/",
      core,
      pkg_config,
      all_pkgs,
      30000,
    )
    let target = if expected == "" { "" } else { expected + "\n" }
    let wasm_ok = d.wasm_out == target
    let js_ok = d.js_out == target
    let ok = interpreter_events is Some(_) &&
      wrote &&
      d.verdict == @oracle.Same &&
      d.wasm_rc == 0 &&
      d.js_rc == 0 &&
      !d.wasm_truncated &&
      !d.js_truncated &&
      (!do_reduce || reduce_ok) &&
      wasm_ok &&
      js_ok
    if !ok {
      errors += 1
    }
    rows.push(
      "{\"case\":" +
      tag +
      ",\"before_stmts\":" +
      before_stmts.to_string() +
      ",\"after_stmts\":" +
      after_stmts.to_string() +
      ",\"reduced\":" +
      (if do_reduce { "true" } else { "false" }) +
      ",\"reduce_ok\":" +
      (if reduce_ok { "true" } else { "false" }) +
      ",\"ok\":" +
      (if ok { "true" } else { "false" }) +
      ",\"verdict\":\"" +
      @oracle.diff_class_name(d.verdict) +
      "\",\"interpreter_ok\":" +
      (if interpreter_events is Some(_) { "true" } else { "false" }) +
      ",\"wasm_rc\":" +
      d.wasm_rc.to_string() +
      ",\"js_rc\":" +
      d.js_rc.to_string() +
      ",\"wasm_ok\":" +
      (if wasm_ok { "true" } else { "false" }) +
      ",\"js_ok\":" +
      (if js_ok { "true" } else { "false" }) +
      ",\"expected\":\"" +
      @corpus.json_escape(expected) +
      "\",\"wasm\":\"" +
      @corpus.json_escape(d.wasm_out) +
      "\",\"js\":\"" +
      @corpus.json_escape(d.js_out) +
      "\"}",
    )
  }
  let b = StringBuilder()
  for row in rows {
    b.write_string(row)
    b.write_string("\n")
  }
  if !write(@corpus.join(out, "rows.jsonl"), b.to_string()) {
    errors += 1
  }
  println("[irprobe] cases=\{programs.length()} errors=\{errors}")
  if errors > 0 {
    @env.exit(1)
  }
}
