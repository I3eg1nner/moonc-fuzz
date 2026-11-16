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
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let root = if args.length() >= 2 { args[1] } else { "/data/audit/mbtfuzz" }
  let out = if args.length() >= 3 { args[2] } else { "/tmp/mbtfuzz_irprobe" }
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
  let programs = @ir.sample_programs()
  let rows : Array[String] = []
  let mut errors = 0
  for i, program in programs {
    let tag = i.to_string()
    let wd = @corpus.join("/tmp/mbtfuzz_irprobe", "p" + tag)
    @corpus.ensure_dir(wd)
    let interpreter_ok = Some(join_events(@ir.run(program, 10000))) catch {
      _ => None
    }
    let expected = match interpreter_ok {
      Some(e) => e
      None => ""
    }
    let src = @ir.emit_program(program)
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
    let ok = interpreter_ok is Some(_) &&
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
      ",\"ok\":" +
      (if ok { "true" } else { "false" }) +
      ",\"verdict\":\"" +
      @oracle.diff_class_name(d.verdict) +
      "\",\"interpreter_ok\":" +
      (if interpreter_ok is Some(_) { "true" } else { "false" }) +
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
