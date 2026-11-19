///|
/// One target's observation for a case.
struct Obs {
  target : String
  built : Bool
  rc : Int32
  out : String
  err : String
  ms : Int64
}

///|
fn usage() -> Unit {
  println(
    "usage: semdiff --out FILE [--family f64|int|str] " +
    "[--targets wasm-gc,native] [--only ID[,ID]] [--timeout-ms N] [--keep]",
  )
}

///|
/// Diagnostics only: warnings dominate the head of stderr and would push the
/// actual compile error out of a fixed-length excerpt.
fn error_excerpt(err : String) -> String {
  let i = err.find("Error")
  let tail = match i {
    Some(k) => err[k:].to_owned()
    None => err
  }
  if tail.length() > 400 {
    tail[0:400].to_owned()
  } else {
    tail
  }
}

///|
/// `moon run` reports a compile failure as a nonzero exit with diagnostics on
/// stderr.  A program that legitimately exits nonzero (a panic) also does, but
/// it still printed its earlier lines; the diagnostics are what separate them.
fn looks_like_build_failure(err : String) -> Bool {
  err.contains("failed to build") ||
  err.contains("Failed to run build") ||
  err.contains("failed when building project") ||
  err.contains("Error: [")
}

///|
/// Targets that actually produced a runnable program.
fn live_of(obs : Array[Obs]) -> Array[Obs] {
  let live : Array[Obs] = []
  for o in obs {
    if o.built {
      live.push(o)
    }
  }
  live
}

///|
/// Explain the first divergence against the first live target.  The previous
/// version compared against whichever target happened to be last, so a
/// js-only difference printed "length N vs N" and looked like a formatting
/// artefact.
fn mismatch_hint(obs : Array[Obs]) -> String {
  let live = live_of(obs)
  if live.length() < 2 {
    return ""
  }
  let first = live[0]
  for k, o in live {
    if k > 0 {
      if o.rc != first.rc {
        return "rc " +
          first.target +
          "=" +
          first.rc.to_string() +
          " vs " +
          o.target +
          "=" +
          o.rc.to_string()
      }
      if o.out != first.out {
        return first.target +
          " vs " +
          o.target +
          ": " +
          first_diff_line(first.out, o.out)
      }
    }
  }
  ""
}

///|
/// Compare normalized stdout and exit status across targets that built.
fn compare(obs : Array[Obs]) -> String {
  let live = live_of(obs)
  if live.length() < 2 {
    return "SKIP"
  }
  let first = live[0]
  for i, o in live {
    if i > 0 {
      if o.rc != first.rc || o.out != first.out {
        return "MISMATCH"
      }
    }
  }
  "ALL_EQUAL"
}

///|
/// A one-line human hint naming the first differing output line, so a
/// mismatch does not require opening the JSON.
fn first_diff_line(a : String, b : String) -> String {
  let la = a.split("\n").collect()
  let lb = b.split("\n").collect()
  let n = if la.length() < lb.length() { la.length() } else { lb.length() }
  let mut i = 0
  while i < n {
    if la[i].to_owned() != lb[i].to_owned() {
      return "line " +
        (i + 1).to_string() +
        ": `" +
        la[i].to_owned() +
        "` vs `" +
        lb[i].to_owned() +
        "`"
    }
    i += 1
  }
  "length " + la.length().to_string() + " vs " + lb.length().to_string()
}

///|
fn write_pkg(dir : String, src : String) -> Bool {
  @stager.rm_rf(dir)
  let created = try {
    @fs.create_dir(dir)
    true
  } catch {
    _ => false
  }
  if !created {
    return false
  }
  @stager.write_text(
    @stager.join(dir, "moon.mod"),
    "name = \"repro/semdiff\"\nversion = \"0.1.0\"\n",
  ) &&
  @stager.write_text(
    @stager.join(dir, "moon.pkg"),
    "pkgtype(kind: \"executable\")\n",
  ) &&
  @stager.write_text(@stager.join(dir, "main.mbt"), src)
}

///|
async fn run_one(dir : String, target : String, timeout_ms : Int32) -> Obs {
  let start = @env.now()
  let r = @exec.run(
    @stager.moon_path(),
    ["run", "main.mbt", "--target", target],
    dir,
    timeout_ms,
  )
  let ms = if @env.now() > start {
    (@env.now() - start).to_int().to_int64()
  } else {
    0L
  }
  let built = !looks_like_build_failure(r.stderr)
  {
    target,
    built,
    rc: r.rc,
    out: r.stdout.trim_end().to_owned(),
    err: error_excerpt(r.stderr),
    ms,
  }
}

///|
async fn main {
  let args = @env.args()
  let mut out = ""
  let mut family = ""
  let mut targets = "wasm-gc,native"
  let mut only = ""
  let mut timeout_ms = 60000
  let mut keep = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--family" && i + 1 < args.length() {
      family = args[i + 1]
    } else if a == "--targets" && i + 1 < args.length() {
      targets = args[i + 1]
    } else if a == "--only" && i + 1 < args.length() {
      only = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
    } else if a == "--keep" {
      keep = true
    }
  }
  if out == "" {
    usage()
    @env.exit(2)
  }
  let tlist : Array[String] = []
  for t in targets.split(",") {
    let s = t.trim().to_owned()
    if s != "" {
      tlist.push(s)
    }
  }
  if tlist.length() < 2 {
    usage()
    @env.exit(2)
  }
  let work = "/tmp/mbtfuzz_semdiff"
  @stager.rm_rf(work)
  let _ = try {
    @fs.create_dir(work)
    true
  } catch {
    _ => false
  }
  let start_ms = @env.now()
  let mut total = 0
  let mut all_equal = 0
  let mut mismatches = 0
  let mut skipped = 0
  let rows : Array[String] = []
  for c in @numgen.select(family) {
    if only != "" {
      let mut hit = false
      for part in only.split(",") {
        if part.trim() == c.id {
          hit = true
        }
      }
      if !hit {
        continue
      }
    }
    total += 1
    let dir = @stager.join(work, c.id)
    if !write_pkg(dir, c.src) {
      skipped += 1
      continue
    }
    let obs : Array[Obs] = []
    for t in tlist {
      obs.push(run_one(dir, t, timeout_ms))
    }
    let verdict = compare(obs)
    if verdict == "ALL_EQUAL" {
      all_equal += 1
    } else if verdict == "MISMATCH" {
      mismatches += 1
    } else {
      skipped += 1
    }
    let b = StringBuilder()
    b.write_string("{\"case\":\"")
    b.write_string(c.id)
    b.write_string("\",\"family\":\"")
    b.write_string(c.family)
    b.write_string("\",\"verdict\":\"")
    b.write_string(verdict)
    b.write_string("\",\"targets\":[")
    for i, o in obs {
      if i > 0 {
        b.write_string(",")
      }
      b.write_string("{\"target\":\"")
      b.write_string(o.target)
      b.write_string("\",\"built\":")
      b.write_string(if o.built { "true" } else { "false" })
      b.write_string(",\"rc\":")
      b.write_string(o.rc.to_string())
      b.write_string(",\"lines\":")
      b.write_string(o.out.split("\n").count().to_string())
      b.write_string(",\"ms\":")
      b.write_string(o.ms.to_string())
      if !o.built {
        b.write_string(",\"err\":\"")
        b.write_string(@stager.escape(o.err))
        b.write_string("\"")
      }
      b.write_string("}")
    }
    b.write_string("]")
    if verdict == "MISMATCH" {
      b.write_string(",\"detail\":\"")
      b.write_string(@stager.escape(mismatch_hint(obs)))
      b.write_string("\"")
    }
    b.write_string("}")
    rows.push(b.to_string())
    println(b.to_string())
  }
  let _ = @stager.write_text(
    out,
    {
      let b = StringBuilder()
      for row in rows {
        b.write_string(row)
        b.write_string("\n")
      }
      b.to_string()
    },
  )
  let summary = "{\"ok\":" +
    (if mismatches == 0 { "true" } else { "false" }) +
    ",\"cases\":" +
    total.to_string() +
    ",\"all_equal\":" +
    all_equal.to_string() +
    ",\"mismatch\":" +
    mismatches.to_string() +
    ",\"skipped\":" +
    skipped.to_string() +
    ",\"targets\":\"" +
    targets +
    "\",\"ms\":" +
    (@env.now() - start_ms).to_string() +
    ",\"out\":\"" +
    @stager.escape(out) +
    "\"}"
  println(summary)
  if !keep {
    @stager.rm_rf(work)
  }
  if mismatches != 0 {
    @env.exit(1)
  }
}
