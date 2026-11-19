///|
fn usage() -> Unit {
  println(
    "usage: scalefuzz --out FILE [--only PREFIX] [--timeout-ms N] [--keep]",
  )
}

///|
fn write_pkg(dir : String, c : @scalegen.Case) -> Bool {
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
  let a = @stager.write_text(
    @stager.join(dir, "moon.mod"),
    @scalegen.mod_source(),
  )
  let b = @stager.write_text(
    @stager.join(dir, "moon.pkg"),
    @scalegen.pkg_source(),
  )
  let d = @stager.write_text(
    @stager.join(dir, "lib.mbt"),
    @scalegen.lib_source(c),
  )
  let e = @stager.write_text(
    @stager.join(dir, "main.mbt"),
    @scalegen.main_source(),
  )
  a && b && d && e
}

///|
fn json_row(c : @scalegen.Case, stage : String, sig : String) -> String {
  "{\"case\":\"" +
  c.id +
  "\",\"shape\":\"" +
  @scalegen.shape_tag(c.shape) +
  "\",\"fields\":" +
  c.fields.to_string() +
  ",\"valtype\":" +
  (if c.valtype { "true" } else { "false" }) +
  ",\"stage\":\"" +
  stage +
  "\",\"signature\":\"" +
  @stager.escape(sig) +
  "\"}"
}

///|
async fn main {
  let args = @env.args()
  let mut out = ""
  let mut only = ""
  let mut timeout_ms = 90000
  let mut keep = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
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
  let work = "/tmp/mbtfuzz_scalefuzz"
  @stager.rm_rf(work)
  let _ = try {
    @fs.create_dir(work)
    true
  } catch {
    _ => false
  }
  let start_ms = @env.now()
  let rows : Array[String] = []
  let sigs : Map[String, Int32] = Map([])
  let mut total = 0
  let mut defect = 0
  let mut clean = 0
  let mut control_failures = 0
  for c in @scalegen.cases() {
    if only != "" && !c.id.has_prefix(only) {
      continue
    }
    total += 1
    let dir = @stager.join(work, c.id)
    if !write_pkg(dir, c) {
      control_failures += 1
      continue
    }
    let build = @stager.run_stage("build", "native", dir, timeout_ms)
    let mut stage = "build"
    let mut r = build
    if !@stager.is_defect("build", build) && build.rc == 0 {
      // The lowering passed; reach the linker, where F9-class defects live.
      stage = "test"
      r = @stager.run_stage("test", "native", dir, timeout_ms)
    }
    let sig = @stager.signature(stage, r)
    let is_defect = @stager.is_defect(stage, r)
    if is_defect {
      defect += 1
    } else if sig == "ok" || sig.has_prefix("fail/rc=") {
      clean += 1
      if !c.valtype {
        // A control must build; anything else means the generator is wrong,
        // not the compiler.
        if sig != "ok" {
          control_failures += 1
        }
      }
    } else {
      clean += 1
    }
    sigs.set(
      sig,
      match sigs.get(sig) {
        Some(n) => n + 1
        None => 1
      },
    )
    let row = json_row(c, stage, sig)
    rows.push(row)
    println(row)
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
  // One line per distinct signature: the whole point is whether size changes
  // the failure mode.
  let distinct : Array[String] = []
  for k, _ in sigs {
    distinct.push(k)
  }
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  b.write_string(if control_failures == 0 { "true" } else { "false" })
  b.write_string(",\"cases\":")
  b.write_string(total.to_string())
  b.write_string(",\"defects\":")
  b.write_string(defect.to_string())
  b.write_string(",\"clean\":")
  b.write_string(clean.to_string())
  b.write_string(",\"control_failures\":")
  b.write_string(control_failures.to_string())
  b.write_string(",\"distinct_signatures\":")
  b.write_string(distinct.length().to_string())
  b.write_string(",\"ms\":")
  b.write_string((@env.now() - start_ms).to_string())
  b.write_string(",\"out\":\"")
  b.write_string(@stager.escape(out))
  b.write_string("\"}")
  println(b.to_string())
  if !keep {
    @stager.rm_rf(work)
  }
  if control_failures != 0 {
    @env.exit(1)
  }
}
