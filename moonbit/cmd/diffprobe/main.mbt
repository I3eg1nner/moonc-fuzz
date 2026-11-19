///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn be(
  kind : String,
  rc : Int32,
  out : String,
  stage : @oracle.Stage,
) -> @oracle.BackendResult {
  {
    kind,
    rc,
    out,
    stage,
    detail: "",
    truncated: false,
    out_digest: "",
    out_len: 0L,
  }
}

///|
fn bt(kind : String, rc : Int32, digest : String) -> @oracle.BackendResult {
  {
    kind,
    rc,
    out: "prefix\n[output truncated]",
    stage: @oracle.Run,
    detail: "",
    truncated: true,
    out_digest: digest,
    out_len: 2000000L,
  }
}

///|
///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("usage: diffprobe <file.mbt> [repo-root] [--native]")
    println("       diffprobe --inject wasm-link-vs-js-build")
    return
  }
  if args[1] == "--inject" {
    let case = if args.length() >= 3 { args[2] } else { "" }
    let r = if case == "wasm-link-vs-js-build" {
      @oracle.classify_diff(
        be("ERR", 2, "", @oracle.Link),
        be("ERR", 2, "", @oracle.Build),
      )
    } else if case == "wasm-run-vs-js-build" {
      @oracle.classify_diff(
        be("OK", 0, "x", @oracle.Run),
        be("ERR", 2, "", @oracle.Build),
      )
    } else if case == "wasm-ice-vs-js-build" {
      @oracle.classify_diff(
        be("ICE", 199, "", @oracle.Build),
        be("ERR", 2, "", @oracle.Build),
      )
    } else if case == "native-abort" {
      @oracle.classify_diff(
        be("ERR", 1, "", @oracle.Run),
        be("ERR", 134, "", @oracle.NativeRun),
      )
    } else if case == "truncated-suffix" {
      @oracle.classify_diff(
        bt("OK", 0, "wasm-full-digest"),
        bt("OK", 0, "js-full-digest"),
      )
    } else if case == "truncated-same" {
      @oracle.classify_diff(
        bt("OK", 0, "same-full-digest"),
        bt("OK", 0, "same-full-digest"),
      )
    } else if case == "same-run" {
      @oracle.classify_diff(
        be("OK", 0, "x", @oracle.Run),
        be("OK", 0, "x", @oracle.Run),
      )
    } else {
      println("unknown injection")
      return
    }
    println("verdict=\{@oracle.diff_class_name(r)}")
    println("same=\{r == @oracle.Same}")
    return
  }
  let root = if args.length() >= 3 { args[2] } else {
    match @env.current_dir() {
      Some(d) => d
      None => "/data/audit/mbtfuzz"
    }
  }
  let src = @fs.read_file_to_string(args[1]) catch {
    _ => {
      println("cannot read input")
      return
    }
  }
  let core = join(@stager.moon_home(), "lib/core")
  let wd = "/tmp/mbtfuzz_diffprobe_" + @env.now().to_string()
  @fs.create_dir(wd) catch {
    _ => ()
  }
  let native = args.length() >= 4 && args[3] == "--native"
  let r = if native {
    @oracle.diff_native(
      @stager.tool_path("moonc"),
      @stager.tool_path("moonrun"),
      @stager.tool_path("moon"),
      wd,
      src,
      "I3eg1nner/tpl/cmd/main",
      join(core, "_build/wasm/release/bundle"),
      core,
      join(join(root, "harness"), "moon.pkg"),
      @stager.portable_all_pkgs(root),
      25000,
    )
  } else {
    @oracle.diff_program(
      @stager.tool_path("moonc"),
      @stager.tool_path("moonrun"),
      "node",
      wd,
      src,
      "I3eg1nner/tpl/cmd/main",
      join(core, "_build/wasm/release/bundle"),
      join(core, "_build/js/release/bundle"),
      core,
      join(join(root, "harness"), "moon.pkg"),
      @stager.portable_all_pkgs(root),
      25000,
    )
  }
  println("verdict=\{@oracle.diff_class_name(r.verdict)}")
  println("same=\{r.same}")
  println(
    "wasm stage=\{r.wasm_stage} kind=\{r.wasm_kind} rc=\{r.wasm_rc} out=\{r.wasm_out}",
  )
  println("wasm detail=\{r.wasm_detail}")
  println(
    "js   stage=\{r.js_stage} kind=\{r.js_kind} rc=\{r.js_rc} out=\{r.js_out}",
  )
}
