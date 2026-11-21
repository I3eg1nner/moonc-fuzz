///|
/// Usage: capsule --pkg DIR --file REL [--target js] [--stage test]
///               [--duration S] [--iterations N] [--out DIR] [--seed N]
///
/// Step a/b of the capsule plan: copy the whole package, record
/// moon.mod/moon.pkg hashes and the exact argv, prove the baseline builds,
/// then mutate only `--file` in place and replay the same argv.
fn usage() -> Unit {
  println(
    "usage: capsule --pkg DIR --file REL [--target js] [--stage test] " +
    "[--duration S] [--iterations N] [--out DIR] [--seed N]",
  )
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
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn num_arg(args : Array[String], name : String, dflt : Int) -> Int {
  match arg_value(args, name) {
    Some(s) => {
      let mut n = 0
      let mut any = false
      for c in s {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
          any = true
        } else {
          return dflt
        }
      }
      if any { n } else { dflt }
    }
    None => dflt
  }
}

///|
fn is_crash(err : String, rc : Int32) -> Bool {
  rc < 0 ||
  err.contains("Oops, the compiler has encountered") ||
  err.contains("Assert_failure") ||
  err.contains("Machine_error")
}

///|
async fn main {
  let args = @env.args()
  let pkg = match arg_value(args, "--pkg") {
    Some(s) => s
    None => {
      usage()
      return
    }
  }
  let file = match arg_value(args, "--file") {
    Some(s) => s
    None => {
      usage()
      return
    }
  }
  let target = match arg_value(args, "--target") {
    Some(s) => s
    None => "js"
  }
  let stage = match arg_value(args, "--stage") {
    Some(s) => s
    None => "test"
  }
  let duration = num_arg(args, "--duration", 0)
  let max_iters = num_arg(args, "--iterations", 200)
  let seed0 = num_arg(args, "--seed", 1).to_uint64()
  let release = args.contains("--release")
  let out = match arg_value(args, "--out") {
    Some(s) => s
    None => "/tmp/mbtfuzz_capsule"
  }
  let work = join(out, "work")
  let src_path = join(pkg, file)
  let original = @stager.read_text(src_path)
  if original == "" {
    println("{\"ok\":false,\"error\":\"missing " + file + "\"}")
    @env.exit(2)
  }
  @stager.rm_rf(out)
  let made = try {
    @fs.create_dir(out)
    true
  } catch {
    _ => false
  }
  if !made {
    println("{\"ok\":false,\"error\":\"cannot create out\"}")
    @env.exit(2)
  }
  if !@stager.copy_tree(pkg, work) {
    println("{\"ok\":false,\"error\":\"copy failed\"}")
    @env.exit(2)
  }
  @stager.rm_rf(join(work, "_build"))
  let argv : Array[String] = if stage == "test" {
    ["test", "--target", target, "--build-only"]
  } else if stage == "check" {
    ["check", "--target", target]
  } else {
    ["build", "--target", target]
  }
  if release {
    argv.push("--release")
  }
  let moon = @stager.moon_path()
  let t0 = @env.now()
  let base = @exec.run_isolated(moon, argv, work, 120000, max_output_bytes=65536)
  // The package's moon.pkg may live next to the mutated file (f8: repro/),
  // not at the module root; record the one that actually governs the build.
  let pkg_pkg_path = {
    let next_to = join(@corpus.dirname(file), "moon.pkg")
    if @fs.path_exists(join(pkg, next_to)) {
      next_to
    } else {
      "moon.pkg"
    }
  }
  let av = StringBuilder()
  for i, a in argv {
    if i > 0 {
      av.write_string(",")
    }
    av.write_string("\"" + @stager.escape(a) + "\"")
  }
  let capsule = "{\"pkg\":\"" +
    @stager.escape(pkg) +
    "\",\"file\":\"" +
    @stager.escape(file) +
    "\",\"target\":\"" +
    target +
    "\",\"stage\":\"" +
    stage +
    "\",\"argv\":[" +
    "\"" + @stager.escape(moon) + "\"" +
    "," +
    av.to_string() +
    "],\"moon_mod_sha1\":\"" +
    @corpus.sha1_hex(@stager.read_text(join(pkg, "moon.mod"))) +
    "\",\"moon_pkg_path\":\"" +
    @stager.escape(pkg_pkg_path) +
    "\",\"moon_pkg_sha1\":\"" +
    @corpus.sha1_hex(@stager.read_text(join(pkg, pkg_pkg_path))) +
    "\",\"baseline_rc\":" +
    base.rc.to_string() +
    "}"
  ignore(@stager.write_text(join(out, "capsule.json"), capsule))
  if base.rc != 0 {
    println(
      "{\"ok\":false,\"error\":\"baseline build failed\",\"rc\":" +
      base.rc.to_string() +
      ",\"stderr\":\"" +
      @stager.escape(base.stderr) +
      "\"}",
    )
    @env.exit(1)
  }
  let deadline = @env.now() + duration.to_uint64() * 1000UL
  let mut attempts = 0
  let mut ok = 0
  let mut failed = 0
  let mut crashes = 0
  let sigs : Map[String, Unit] = Map([])
  let mut i = 0
  while i < max_iters && (duration == 0 || @env.now() < deadline) {
    i += 1
    let rng = @mutate.Rng::new(seed0 + i.to_uint64())
    let mutated = @mutate.mutate(original, rng, [], false)
    if mutated == original {
      continue
    }
    attempts += 1
    ignore(@stager.write_text(join(work, file), mutated))
    let r = @exec.run_isolated(
      moon,
      argv,
      work,
      120000,
      max_output_bytes=65536,
    )
    if r.rc == 0 {
      ok += 1
    } else {
      failed += 1
      if is_crash(r.stderr, r.rc) {
        crashes += 1
        sigs.set(
          @judge.error_line(@judge.observation(
            stage,
            r.rc,
            r.timed_out,
            r.ms,
            r.ms,
            0,
            false,
            false,
            r.stdout,
            r.stderr,
          )),
          (),
        )
      }
    }
    ignore(@stager.write_text(join(work, file), original))
  }
  // Replay consistency: the restored package must build exactly like baseline.
  let replay = @exec.run_isolated(moon, argv, work, 120000, max_output_bytes=65536)
  let b = StringBuilder()
  b.write_string("{\"attempts\":" + attempts.to_string())
  b.write_string(",\"ok\":" + ok.to_string())
  b.write_string(",\"failed\":" + failed.to_string())
  b.write_string(",\"crashes\":" + crashes.to_string())
  b.write_string(",\"distinct_crash_lines\":" + sigs.length().to_string())
  b.write_string(",\"baseline_rc\":" + base.rc.to_string())
  b.write_string(",\"replay_rc\":" + replay.rc.to_string())
  b.write_string(",\"replay_matches\":" +
    (if replay.rc == base.rc { "true" } else { "false" }))
  b.write_string(",\"ms\":" + (@env.now() - t0).to_string())
  b.write_string(",\"coverage_skipped\":\"n/a (capsule lane has no coverage budget)\"")
  b.write_string("}")
  println(b.to_string())
  ignore(@stager.write_text(join(out, "summary.json"), b.to_string()))
}
