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
fn write(path : String, text : String) -> Unit {
  @corpus.ensure_dir(@corpus.dirname(path))
  @fs.write_string_to_file(path, text) catch {
    _ => ()
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
    } else {
      println("usage: irprobe ROOT OUT [--random N] [--seed S] [--reduce]")
      @env.exit(2)
    }
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
    let wd = @corpus.join("/tmp/mbtfuzz_irprobe", "p" + tag)
    @corpus.ensure_dir(wd)
    let interpreter_events = Some(@ir.run(program, 10000)) catch { _ => None }
    let expected = match interpreter_events {
      Some(events) => join_events(events)
      None => ""
    }
    let before_stmts = @ir.statement_count(program)
    let used_program = if do_reduce {
      match interpreter_events {
        Some(events) =>
          @ir.reduce(program, events, 10000) catch {
            _ => program
          }
        None => program
      }
    } else {
      program
    }
    let after_stmts = @ir.statement_count(used_program)
    let src = @ir.emit_program(used_program)
    write(@corpus.join(wd, "in.mbt"), src)
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
      d.verdict == @oracle.Same &&
      d.wasm_rc == 0 &&
      d.js_rc == 0 &&
      !d.wasm_truncated &&
      !d.js_truncated &&
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
  write(@corpus.join(out, "rows.jsonl"), b.to_string())
  println("[irprobe] cases=\{programs.length()} errors=\{errors}")
  if errors > 0 {
    @env.exit(1)
  }
}
