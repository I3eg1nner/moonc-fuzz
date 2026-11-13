///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("usage: diffprobe <file.mbt> [repo-root]")
    return
  }
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let root = if args.length() >= 3 { args[2] } else { "/data/audit/mbtfuzz" }
  let src = @fs.read_file_to_string(args[1]) catch {
    _ => {
      println("cannot read input")
      return
    }
  }
  let core = join(home, ".moon/lib/core")
  let wd = "/tmp/mbtfuzz_diffprobe_" + @env.now().to_string()
  @fs.create_dir(wd) catch {
    _ => ()
  }
  let native = args.length() >= 4 && args[3] == "--native"
  let r = if native {
    @oracle.diff_native(
      join(join(home, ".moon/bin"), "moonc"),
      join(join(home, ".moon/bin"), "moonrun"),
      join(join(home, ".moon/bin"), "moon"),
      wd,
      src,
      "minie135/tpl/cmd/main",
      join(core, "_build/wasm/release/bundle"),
      core,
      join(join(root, "harness"), "moon.pkg"),
      join(join(root, "harness"), "all_pkgs.json"),
      25000,
    )
  } else {
    @oracle.diff_program(
      join(join(home, ".moon/bin"), "moonc"),
      join(join(home, ".moon/bin"), "moonrun"),
      "node",
      wd,
      src,
      "minie135/tpl/cmd/main",
      join(core, "_build/wasm/release/bundle"),
      join(core, "_build/js/release/bundle"),
      core,
      join(join(root, "harness"), "moon.pkg"),
      join(join(root, "harness"), "all_pkgs.json"),
      25000,
    )
  }
  println("same=\{r.same}")
  println(
    "wasm stage=\{r.wasm_stage} kind=\{r.wasm_kind} rc=\{r.wasm_rc} out=\{r.wasm_out}",
  )
  println("wasm detail=\{r.wasm_detail}")
  println(
    "js   stage=\{r.js_stage} kind=\{r.js_kind} rc=\{r.js_rc} out=\{r.js_out}",
  )
}
