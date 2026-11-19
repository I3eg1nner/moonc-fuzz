///|
/// Script-mode trigger surface mapper.
///
/// Usage:
///   scriptfuzz --out FILE [--family grid|boundary|all] [--timeout-ms N]
///              [--only PREFIX] [--keep]
///
/// Two families:
///   grid     - the 36-point cross product around the F7 shape (payload kind x
///              container x construction x `#valtype`).
///   boundary - ten fixed probes that each separate two competing explanations
///              of the trigger; each has an expected outcome on this pin.
///
/// Writes one JSON line per case, then a summary line.  Exit 0 when every
/// negative control compiled and ran, 1 when a control failed (the renderer is
/// broken and no row can be trusted), 2 on usage.
fn usage() -> Unit {
  println(
    "usage: scriptfuzz --out FILE [--family grid|boundary|all] " +
    "[--timeout-ms N] [--only PREFIX] [--keep]",
  )
}

///|
/// Run one script and return (rc, defect, signature).
async fn run_script(
  workdir : String,
  id : String,
  src : String,
  timeout_ms : Int32,
) -> (Int32, Bool, String) {
  let path = @stager.join(workdir, id + ".mbt")
  let _ = @stager.write_text(path, src)
  let r = @exec.run_isolated(
    @stager.moon_path(),
    ["run", path, "--target", "native"],
    workdir,
    timeout_ms,
    max_output_bytes=32768,
  )
  (r.rc, @stager.is_defect("run", r), @stager.signature("run", r))
}

///|
async fn main {
  let args = @env.args()
  let mut out = ""
  let mut timeout_ms = 30000
  let mut only = ""
  let mut family = "grid"
  let mut keep = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--out" && i + 1 < args.length() {
      out = args[i + 1]
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
    } else if a == "--only" && i + 1 < args.length() {
      only = args[i + 1]
    } else if a == "--family" && i + 1 < args.length() {
      family = args[i + 1]
    } else if a == "--keep" {
      keep = true
    }
  }
  if out == "" {
    usage()
    @env.exit(2)
  }
  let workdir = "/tmp/mbtfuzz_scriptfuzz"
  @stager.rm_rf(workdir)
  let made = try {
    @fs.create_dir(workdir)
    true
  } catch {
    _ => false
  }
  if !made {
    println("cannot create " + workdir)
    @env.exit(2)
  }
  let start_ms = @env.now()
  let mut total = 0
  let mut ok_cases = 0
  let mut defects = 0
  let mut invalid = 0
  let mut controls = 0
  let mut control_failures = 0
  let mut mismatches = 0
  let sigs : Map[String, Int32] = Map([])
  let rows : Array[String] = []

  if family == "boundary" || family == "all" {
    for c in @scriptgen.boundary_cases() {
      total += 1
      let (_, hit, _) = run_script(workdir, c.id, c.src, timeout_ms)
      controls += 1
      if hit != c.expect_defect {
        mismatches += 1
      }
      if hit {
        defects += 1
      } else {
        ok_cases += 1
      }
      if !c.expect_defect && hit {
        control_failures += 1
      }
      let row = "{\"case\":\"" +
        c.id +
        "\",\"expect_defect\":" +
        (if c.expect_defect { "true" } else { "false" }) +
        ",\"defect\":" +
        (if hit { "true" } else { "false" }) +
        ",\"matches\":" +
        (if hit == c.expect_defect { "true" } else { "false" }) +
        ",\"why\":\"" +
        @stager.escape(c.why) +
        "\"}"
      rows.push(row)
      println(row)
    }
  }

  if family == "grid" || family == "all" {
    for c in @scriptgen.cases() {
      if only != "" && !c.id.has_prefix(only) {
        continue
      }
      total += 1
      let (rc, hit, sig) = run_script(
        workdir,
        c.id,
        @scriptgen.render(c),
        timeout_ms,
      )
      if hit {
        defects += 1
      } else if sig == "ok" {
        ok_cases += 1
      } else {
        // A plain failure means the case did not compile: an invalid
        // experiment, not a result.
        invalid += 1
      }
      if !c.valtype {
        controls += 1
        if sig != "ok" {
          control_failures += 1
        }
      }
      sigs.set(
        sig,
        match sigs.get(sig) {
          Some(n) => n + 1
          None => 1
        },
      )
      let row = "{\"case\":\"" +
        c.id +
        "\",\"valtype\":" +
        (if c.valtype { "true" } else { "false" }) +
        ",\"rc\":" +
        rc.to_string() +
        ",\"defect\":" +
        (if hit { "true" } else { "false" }) +
        ",\"signature\":\"" +
        @stager.escape(sig) +
        "\"}"
      rows.push(row)
      println(row)
    }
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
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  b.write_string(if control_failures == 0 { "true" } else { "false" })
  b.write_string(",\"family\":\"")
  b.write_string(family)
  b.write_string("\",\"cases\":")
  b.write_string(total.to_string())
  b.write_string(",\"ok_cases\":")
  b.write_string(ok_cases.to_string())
  b.write_string(",\"defects\":")
  b.write_string(defects.to_string())
  b.write_string(",\"invalid\":")
  b.write_string(invalid.to_string())
  b.write_string(",\"controls\":")
  b.write_string(controls.to_string())
  b.write_string(",\"control_failures\":")
  b.write_string(control_failures.to_string())
  b.write_string(",\"mismatches\":")
  b.write_string(mismatches.to_string())
  b.write_string(",\"distinct_signatures\":")
  b.write_string(sigs.length().to_string())
  b.write_string(",\"ms\":")
  b.write_string((@env.now() - start_ms).to_string())
  b.write_string(",\"out\":\"")
  b.write_string(@stager.escape(out))
  b.write_string("\"}")
  println(b.to_string())
  if !keep {
    @stager.rm_rf(workdir)
  }
  if control_failures != 0 {
    @env.exit(1)
  }
}
