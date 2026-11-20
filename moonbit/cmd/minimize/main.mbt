///|

///|
/// Where a reduction may be published.  Empty means "do not publish": the
/// final verification did not match the baseline, so `--out` must stay
/// untouched and the caller learns about it from the exit code and the
/// `published` field.
fn publish_path(out : String, verified : Bool) -> String {
  if verified {
    out
  } else {
    ""
  }
}

///|
/// Compiler-driven reducer.
///
/// One rule shapes the whole file: never trust an unverified reduction.  The
/// final text is re-run, and a mismatch falls back to the original rather than
/// shipping a witness that does not reproduce.
fn usage() -> Unit {
  println(
    "usage: minimize --dir PATH [--file lib.mbt] [--stage build|check|test] " +
    "[--timeout-ms N] [--fuel N] [--out PATH] [--target native] " +
    "[--keep-workdir]",
  )
}

///|
/// Write one candidate and run one stage in the disposable work directory.
async fn run_once(
  target_path : String,
  stage : String,
  target : String,
  workdir : String,
  timeout_ms : Int32,
  text : String,
) -> String {
  if !@stager.write_text(target_path, text) {
    return "write-error"
  }
  let r = @stager.run_stage(stage, target, workdir, timeout_ms)
  @stager.signature(stage, r)
}

///|
async fn main {
  let args = @env.args()
  let mut dir = ""
  let mut file = "lib.mbt"
  let mut stage = "build"
  let mut timeout_ms = 120000
  let mut fuel = 300
  let mut out = ""
  let mut target = "native"
  let mut keep_workdir = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--dir" && i + 1 < args.length() {
      dir = args[i + 1]
    } else if a == "--file" && i + 1 < args.length() {
      file = args[i + 1]
    } else if a == "--stage" && i + 1 < args.length() {
      stage = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
    } else if a == "--fuel" && i + 1 < args.length() {
      fuel = @stager.parse_int(args[i + 1], fuel)
    } else if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--target" && i + 1 < args.length() {
      target = args[i + 1]
    } else if a == "--keep-workdir" {
      keep_workdir = true
    }
  }
  if dir == "" || !@fs.path_exists(@stager.join(dir, file)) {
    usage()
    @env.exit(2)
  }
  if stage != "check" && stage != "build" && stage != "test" {
    usage()
    @env.exit(2)
  }

  let start_ms = @env.now()
  let workdir = "/tmp/mbtfuzz_reduce_" + start_ms.to_string()
  @stager.rm_rf(workdir)
  if !@stager.copy_tree(dir, workdir) {
    println("{\"ok\":false,\"error\":\"copy failed\"}")
    @env.exit(2)
  }
  let target_path = @stager.join(workdir, file)
  let original = @stager.read_text(target_path)
  let before_lines = @stager.count_lines(original)

  let baseline = run_once(
    target_path, stage, target, workdir, timeout_ms, original,
  )
  if baseline == "ok" {
    println(
      "{\"ok\":false,\"error\":\"baseline passes; nothing to reduce\"," +
      "\"stage\":\"" +
      stage +
      "\"}",
    )
    @stager.rm_rf(workdir)
    @env.exit(1)
  }

  let r = @reduce.start(original, fuel)
  let mut go = true
  while go {
    match @reduce.next_text(r) {
      Some(cand) => {
        let sig = run_once(
          target_path, stage, target, workdir, timeout_ms, cand,
        )
        @reduce.verdict(r, sig == baseline)
      }
      None => go = false
    }
  }
  let reduced = @reduce.result(r)
  let final_sig = run_once(
    target_path, stage, target, workdir, timeout_ms, reduced,
  )
  let verified = final_sig == baseline
  let published = publish_path(out, verified)
  if !verified {
    let _ = @stager.write_text(target_path, original)
    // Keep the unverified candidate for inspection, but never at `--out`:
    // a caller that ignores the exit code would otherwise ship a witness that
    // does not reproduce.
    if out != "" {
      let _ = @stager.write_text(publish_path(out + ".rejected", true), reduced)
    }
  } else if published != "" {
    let _ = @stager.write_text(published, reduced)
  }
  let after_lines = @stager.count_lines(reduced)
  let ms = @env.now() - start_ms
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  b.write_string(if verified { "true" } else { "false" })
  b.write_string(",\"stage\":\"")
  b.write_string(stage)
  b.write_string("\",\"baseline\":\"")
  b.write_string(@stager.escape(baseline))
  b.write_string("\",\"before_lines\":")
  b.write_string(before_lines.to_string())
  b.write_string(",\"after_lines\":")
  b.write_string(after_lines.to_string())
  b.write_string(",\"calls\":")
  b.write_string(@reduce.test_calls(r).to_string())
  b.write_string(",\"exhausted\":")
  b.write_string(if @reduce.was_exhausted(r) { "true" } else { "false" })
  b.write_string(",\"verified\":")
  b.write_string(if verified { "true" } else { "false" })
  b.write_string(",\"published\":")
  b.write_string(if published != "" { "true" } else { "false" })
  b.write_string(",\"ms\":")
  b.write_string(ms.to_string())
  b.write_string(",\"workdir\":\"")
  b.write_string(@stager.escape(if keep_workdir { workdir } else { "" }))
  b.write_string("\",\"out\":\"")
  b.write_string(@stager.escape(out))
  b.write_string("\"}")
  println(b.to_string())
  if !keep_workdir {
    @stager.rm_rf(workdir)
  }
  if !verified {
    @env.exit(1)
  }
}
