///|
/// Defect-seeded mutation campaign.
///
/// Usage:
///   seedfuzz --out DIR [--seed DIR ...] [--mutants N] [--stage build|test]
///            [--timeout-ms N] [--start N]
///
/// The seed is a *package directory*, not a source file: a witness only
/// reproduces inside its own moon.mod/moon.pkg/native-stub configuration, and
/// flattening it into a skeleton silently turns every mutant into a type
/// error.  Each mutant copies the package, mutates one `.mbt` file, and runs
/// the stage.
///
/// Output: one JSON line per new defect signature, then a summary line.  Exit
/// 0 on a clean run (whether or not anything was found), 2 on bad usage.
fn usage() -> Unit {
  println(
    "usage: seedfuzz --out DIR [--seed DIR ...] [--mutants N] " +
    "[--stage build|test] [--timeout-ms N] [--start N]",
  )
}

///|
fn default_seeds() -> Array[String] {
  // Resolved against the current directory, not an absolute path: the gate
  // runs this from a checkout that is not at /data/audit/mbtfuzz.
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  [
    @stager.join(cwd, "poc/f2_lex_escape_ice"),
    @stager.join(cwd, "poc/f6_native_export_closure_min"),
    @stager.join(cwd, "poc/f9_native_v128_stub_ice"),
  ]
}

///|
fn write_jsonl(path : String, line : String) -> Unit {
  let existing = @stager.read_text(path)
  let _ = @stager.write_text(path, existing + line + "\n")
}

///|
/// Closed-loop formatter predicate.  A candidate is a defect only if:
///   1. the candidate itself is parse-accepted by `moonc syncheck`;
///   2. `moonfmt` output re-parses;
///   3. formatting is idempotent (second output == first);
///   4. if the candidate runs, the formatted file runs to the same stdout.
struct FmtCheck {
  ok : Bool
  kind : String
  detail : String
}

///|
fn pkg_files(dir : String) -> Array[String] {
  let out : Array[String] = []
  for name in @stager.try_read_dir(dir) {
    if name.has_suffix(".moon.pkg") || name == "moon.pkg" ||
      name.has_suffix(".moon.mod") || name == "moon.mod" {
      out.push(name)
    }
  }
  out
}

///|
async fn package_check(
  dir : String,
  rel : String,
  timeout_ms : Int32,
) -> FmtCheck {
  let moonc = @stager.tool_path("moonc")
  let target = @stager.join(dir, rel)
  let r = @exec.run(moonc, ["syncheck", target], dir, timeout_ms)
  if r.rc == -11 || r.rc == 139 {
    return { ok: true, kind: "pkg/sigsegv", detail: r.stderr }
  }
  if r.stderr.contains("Assertion failed") || r.stderr.contains("Invalid_argument") ||
    r.stderr.contains("Fatal error: exception") {
    return { ok: true, kind: "pkg/ice", detail: r.stderr }
  }
  if r.rc == 0 || r.rc == 2 {
    return { ok: false, kind: "pkg/invalid_or_clean", detail: "" }
  }
  { ok: false, kind: "pkg/other", detail: "rc=" + r.rc.to_string() }
}

///|
async fn format_check(
  dir : String,
  rel : String,
  timeout_ms : Int32,
) -> FmtCheck {
  let moonc = @stager.tool_path("moonc")
  let moonfmt = @stager.tool_path("moonfmt")
  let moon = @stager.moon_path()
  let target = @stager.join(dir, rel)
  let syn = @exec.run(moonc, ["syncheck", target], dir, timeout_ms)
  if syn.rc != 0 {
    return { ok: false, kind: "invalid", detail: "candidate syncheck rc=" + syn.rc.to_string() }
  }
  let f1 = @stager.join(dir, "__fmt_f1.mbt")
  let f2 = @stager.join(dir, "__fmt_f2.mbt")
  let fmt = @exec.run(moonfmt, [target, "-o", f1], dir, timeout_ms)
  if fmt.rc != 0 {
    return { ok: false, kind: "invalid", detail: "moonfmt rc=" + fmt.rc.to_string() }
  }
  let rsyn = @exec.run(moonc, ["syncheck", f1], dir, timeout_ms)
  if rsyn.rc != 0 {
    return {
      ok: true,
      kind: "fmt/reparse",
      detail: "reparse rc=" + rsyn.rc.to_string() + " " + rsyn.stderr,
    }
  }
  let fmt2 = @exec.run(moonfmt, [f1, "-o", f2], dir, timeout_ms)
  if fmt2.rc != 0 {
    return { ok: true, kind: "fmt/idem_fail", detail: "second moonfmt rc=" + fmt2.rc.to_string() }
  }
  if @stager.read_text(f1) != @stager.read_text(f2) {
    return { ok: true, kind: "fmt/not_idempotent", detail: "f1 != f2" }
  }
  let ro = @exec.run(moon, ["run", target, "--target", "wasm-gc", "-q"], dir, timeout_ms)
  if ro.rc == 0 {
    let rf = @exec.run(moon, ["run", f1, "--target", "wasm-gc", "-q"], dir, timeout_ms)
    if rf.rc != 0 || rf.stdout != ro.stdout {
      return {
        ok: true,
        kind: "fmt/semantic",
        detail: "original rc=0; formatted rc=" + rf.rc.to_string() +
          " stdout_equal=" + (rf.stdout == ro.stdout).to_string(),
      }
    }
  }
  { ok: true, kind: "fmt/clean", detail: "" }
}

///|
async fn main {
  let args = @env.args()
  let seeds : Array[String] = []
  let mut out = ""
  let mut mutants = 200
  let mut stage = "build"
  let mut timeout_ms = 20000
  let mut start_at = 0
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--seed" && i + 1 < args.length() {
      seeds.push(args[i + 1])
    } else if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--mutants" && i + 1 < args.length() {
      mutants = @stager.parse_int(args[i + 1], mutants)
    } else if a == "--stage" && i + 1 < args.length() {
      stage = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
    } else if a == "--start" && i + 1 < args.length() {
      start_at = @stager.parse_int(args[i + 1], start_at)
    }
  }
  if out == "" || (stage != "build" && stage != "test" && stage != "format" && stage != "package") {
    usage()
    @env.exit(2)
  }
  if seeds.length() == 0 {
    for s in default_seeds() {
      seeds.push(s)
    }
  }
  for s in seeds {
    if !@fs.path_exists(s) {
      println("missing seed package: " + s)
      @env.exit(2)
    }
  }
  let made = try {
    @fs.create_dir(out)
    true
  } catch {
    _ => @fs.path_exists(out)
  }
  if !made {
    println("cannot create " + out)
    @env.exit(2)
  }
  let jsonl = @stager.join(out, "findings.jsonl")
  let start_ms = @env.now()
  let rng = @mutate.Rng::new(start_ms)
  let mut runs = 0

  // Baseline per seed: reproducing a seed's own defect is `known`, not news.
  let seed_sigs : Array[String] = []
  let mut seed_defects = 0
  for s in seeds {
    // Same path as the mutant runs: the wrapper text embeds it, and a
    // different directory would make every mutant signature look new.
    let wd = "/tmp/mbtfuzz_seedfuzz_" + out.replace_all(old="/", new="_")
    @stager.rm_rf(wd)
    if !@stager.copy_pkg(s, wd) {
      seed_sigs.push("copy-failed")
      continue
    }
    if stage == "package" {
      let pf = pkg_files(wd)
      if pf.length() == 0 {
        seed_sigs.push("pkg/empty")
      } else {
        let pc = package_check(wd, pf[0], timeout_ms)
        runs += 1
        if pc.ok {
          seed_defects += 1
        }
        seed_sigs.push(if pc.ok { pc.kind } else { "pkg/clean" })
      }
    } else if stage == "format" {
      let files0 = @stager.mbt_files(wd)
      if files0.length() == 0 {
        seed_sigs.push("fmt/empty")
      } else {
        let fc = format_check(wd, files0[0], timeout_ms)
        runs += 1
        if fc.ok && fc.kind != "fmt/clean" {
          seed_defects += 1
        }
        seed_sigs.push(if fc.ok { fc.kind } else { "fmt/invalid" })
      }
    } else {
      let r = @stager.run_stage(stage, "native", wd, timeout_ms)
      runs += 1
      if @stager.is_defect(stage, r) {
        seed_defects += 1
      }
      seed_sigs.push(@stager.signature(stage, r))
    }
  }

  let mut defects = 0
  let mut known = 0
  let mut duplicates = 0
  let mut new_sigs = 0
  let mut ignored = 0
  let seen : Map[String, Unit] = Map([])
  let mut i = start_at
  while i < start_at + mutants {
    let idx = i % seeds.length()
    i += 1
    let seed = seeds[idx]
    let files = if stage == "package" { pkg_files(seed) } else { @stager.mbt_files(seed) }
    if files.length() == 0 {
      ignored += 1
      continue
    }
    let rel = files[rng.int_range(0, files.length() - 1)]
    let wd = "/tmp/mbtfuzz_seedfuzz_" + out.replace_all(old="/", new="_")
    @stager.rm_rf(wd)
    if !@stager.copy_pkg(seed, wd) {
      ignored += 1
      continue
    }
    let target = @stager.join(wd, rel)
    let original = @stager.read_text(target)
    let pool : Array[String] = [original]
    let candidate = @mutate.mutate(original, rng, pool, false)
    if candidate == original {
      ignored += 1
      continue
    }
    let _ = @stager.write_text(target, candidate)
    let mut sig = ""
    if stage == "package" {
      let pc = package_check(wd, rel, timeout_ms)
      runs += 1
      if !pc.ok {
        ignored += 1
        continue
      }
      defects += 1
      sig = pc.kind + "|" + @stager.normalize(pc.detail)
    } else if stage == "format" {
      let fc = format_check(wd, rel, timeout_ms)
      runs += 1
      if !fc.ok || fc.kind == "fmt/clean" {
        ignored += 1
        continue
      }
      defects += 1
      sig = fc.kind + "|" + @stager.normalize(fc.detail)
    } else {
      let r = @stager.run_stage(stage, "native", wd, timeout_ms)
      runs += 1
      if !@stager.is_defect(stage, r) {
        ignored += 1
        continue
      }
      defects += 1
      sig = @stager.signature(stage, r)
    }
    if sig == seed_sigs[idx] {
      known += 1
    } else if seen.contains(sig) {
      duplicates += 1
    } else {
      seen.set(sig, ())
      new_sigs += 1
      let dir = @stager.join(out, "cand_" + i.to_string())
      let _ = @stager.copy_pkg(wd, dir)
      let meta = "{\"seed\":\"" +
        @stager.escape(seed) +
        "\",\"file\":\"" +
        @stager.escape(rel) +
        "\",\"stage\":\"" +
        stage +
        "\",\"signature\":\"" +
        @stager.escape(sig) +
        "\"}"
      let _ = @stager.write_text(@stager.join(dir, "meta.json"), meta)
      println(meta)
      write_jsonl(jsonl, meta)
    }
  }

  let b = StringBuilder()
  b.write_string("{\"ok\":true,\"mutants\":")
  b.write_string(mutants.to_string())
  b.write_string(",\"runs\":")
  b.write_string(runs.to_string())
  b.write_string(",\"defects\":")
  b.write_string(defects.to_string())
  b.write_string(",\"seed_defects\":")
  b.write_string(seed_defects.to_string())
  b.write_string(",\"known\":")
  b.write_string(known.to_string())
  b.write_string(",\"new_signatures\":")
  b.write_string(new_sigs.to_string())
  b.write_string(",\"duplicates\":")
  b.write_string(duplicates.to_string())
  b.write_string(",\"ignored\":")
  b.write_string(ignored.to_string())
  b.write_string(",\"package_mode\":")
  b.write_string(if stage == "package" { "true" } else { "false" })
  b.write_string(",\"format_mode\":")
  b.write_string(if stage == "format" { "true" } else { "false" })
  b.write_string(",\"ms\":")
  b.write_string((@env.now() - start_ms).to_string())
  b.write_string(",\"out\":\"")
  b.write_string(@stager.escape(out))
  b.write_string("\"}")
  println(b.to_string())
  @stager.rm_rf("/tmp/mbtfuzz_seedfuzz_" + out.replace_all(old="/", new="_"))
  @stager.rm_rf("/tmp/mbtfuzz_seedbase")
}
