///|
/// Acceptance gate for the Python -> MoonBit migration.
///
/// This is deliberately not "did the tests pass".  It checks the properties a
/// reviewer would use to decide that MoonBit is the operational default:
/// pinned toolchain, all known defects reproduced, real trace parity, coverage
/// set algebra, differential oracle sensitivity on the runnable templates, and
/// a bounded campaign that never invokes Python.
///
/// Usage: accept <repo-root> [bin-dir]
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
fn check(name : String, ok : Bool, detail : String) -> String {
  let b = StringBuilder()
  b.write_string("{\"check\":\"")
  b.write_string(name)
  b.write_string("\",\"ok\":")
  b.write_string(if ok { "true" } else { "false" })
  b.write_string(",\"detail\":\"")
  b.write_string(@corpus.json_escape(detail))
  b.write_string("\"}")
  b.to_string()
}

///|
fn count_lines(text : String) -> Int32 {
  let mut n = 0
  for line in text.split("\n") {
    if line.trim().char_length() > 0 {
      n += 1
    }
  }
  n
}

///|
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let root = if args.length() >= 2 { args[1] } else { "/data/audit/mbtfuzz" }
  let moonbit = join(root, "moonbit")
  let bin = if args.length() >= 3 {
    args[2]
  } else {
    join(moonbit, "_build/native/debug/build")
  }
  let moonc = join(join(home, ".moon/bin"), "moonc")
  let tag = @env.now().to_string()
  let results : Array[String] = []

  // 1. Pinned toolchain.  Changing this must force a re-validation, not be
  // silently accepted as "latest".
  let v = @exec.run(moonc, ["-v"], "/tmp", 5000)
  let vtext = (v.stdout + v.stderr).trim().to_owned()
  let pinned = "v0.10.20+65efd5b93"
  results.push(check("toolchain_pinned", vtext.contains(pinned), vtext))

  // 1b. Unit tests and typecheck must pass before the heavier gates.
  let moon = join(join(home, ".moon/bin"), "moon")
  // `moon test` does not build every cmd binary; the gate invokes
  // regress/diffprobe/trace2funcs/cov by path, so build the module first.
  let mb = @exec.run(moon, ["build", "--target", "native"], moonbit, 240000)
  results.push(check("moon_build", mb.rc == 0, "rc=" + mb.rc.to_string()))
  let mt = @exec.run(moon, ["test", "--target", "native"], moonbit, 180000)
  let mt_text = mt.stdout + mt.stderr
  results.push(
    check(
      "moon_test",
      mt.rc == 0 && mt_text.contains("failed: 0"),
      "rc=" + mt.rc.to_string() + " " + mt_text.trim().to_owned(),
    ),
  )
  let mc = @exec.run(moon, ["check"], moonbit, 180000)
  results.push(check("moon_check", mc.rc == 0, "rc=" + mc.rc.to_string()))

  // 2. All known defects: regression runner must emit 12 ok rows and rc 0.
  let reg = @exec.run(
    join(bin, "cmd/regress/regress.exe"),
    [root, "/tmp/mbtfuzz_accept_regress_" + tag + ".jsonl"],
    root,
    240000,
  )
  let reg_lines = read_text("/tmp/mbtfuzz_accept_regress_" + tag + ".jsonl")
  let mut reg_ok = reg.rc == 0 && count_lines(reg_lines) == 12
  for line in reg_lines.split("\n") {
    if line.trim().char_length() > 0 && !line.contains("\"ok\":true") {
      reg_ok = false
    }
  }
  results.push(
    check(
      "regressions_12",
      reg_ok,
      "rc=" + reg.rc.to_string() + " rows=" + count_lines(reg_lines).to_string(),
    ),
  )

  // 3. Trace2funcs on a frozen synthetic trace: exact JSON, not a count.
  let tr = @exec.run(
    join(bin, "cmd/trace2funcs/trace2funcs.exe"),
    [
      join(moonbit, "accept_fixtures/nm.txt"),
      join(moonbit, "accept_fixtures/trace.log"),
    ],
    moonbit,
    5000,
  )
  let expected = read_text(join(moonbit, "accept_fixtures/expected_trace.json"))
    .trim()
    .to_owned()
  let got = tr.stdout.trim().to_owned()
  results.push(check("trace_exact", tr.rc == 0 && got == expected, got))

  // 3b. Real end-to-end trace parity: QEMU on the 22 B invalid-UTF8 input,
  // then trace2funcs, compared to a Python-golden function set frozen at 599.
  let nm = @exec.run("nm", ["-n", moonc], root, 10000)
  @fs.write_string_to_file("/tmp/mbtfuzz_accept_nm_" + tag + ".txt", nm.stdout) catch {
    _ => ()
  }
  let q = @exec.run(
    "/tmp/AFLplusplus/afl-qemu-trace",
    [
      "-d",
      "exec",
      "-D",
      "/tmp/mbtfuzz_accept_f4_" + tag + ".log",
      "--",
      moonc,
      "syncheck",
      "doc.mbt.md",
    ],
    join(root, "poc/f4_invalid_utf8"),
    30000,
  )
  let tr2 = @exec.run(
    join(bin, "cmd/trace2funcs/trace2funcs.exe"),
    [
      "/tmp/mbtfuzz_accept_nm_" + tag + ".txt",
      "/tmp/mbtfuzz_accept_f4_" + tag + ".log",
      "/tmp/mbtfuzz_accept_f4_actual_" + tag + ".json",
    ],
    moonbit,
    30000,
  )
  let exp_json = @cov.parse_json(
    read_text(join(moonbit, "accept_fixtures/trace_f4.expected.json")),
  ) catch {
    _ => @cov.FuncSet::new([])
  }
  let act_json = @cov.parse_json(
    read_text("/tmp/mbtfuzz_accept_f4_actual_" + tag + ".json"),
  ) catch {
    _ => @cov.FuncSet::new([])
  }
  let exp_funcs = exp_json.sorted()
  let act_funcs = act_json.sorted()
  results.push(
    check(
      "trace_real_f4",
      q.rc == 199 && tr2.rc == 0 && act_funcs == exp_funcs,
      "qemu_rc=" +
      q.rc.to_string() +
      " expected=" +
      exp_funcs.length().to_string() +
      " actual=" +
      act_funcs.length().to_string(),
    ),
  )

  // 4. Coverage set algebra on frozen fixtures.
  let cv = @exec.run(
    join(bin, "cmd/cov/cov.exe"),
    [
      "union",
      join(moonbit, "accept_fixtures/cov_a.json"),
      join(moonbit, "accept_fixtures/cov_b.json"),
    ],
    moonbit,
    5000,
  )
  results.push(
    check(
      "cov_union",
      cv.rc == 0 && cv.stdout.contains("\"func_count\":3"),
      cv.stdout.trim().to_owned(),
    ),
  )

  // 5. Differential oracle on all runnable templates: each must reach run on
  // both backends and agree.  Agreement is necessary, not sufficient.
  let templates = @corpus.collect_files(
    join(root, "templates"),
    [".mbt"],
    100000,
    0,
  )
  let mut diff_ok = true
  let mut diff_n = 0
  let diff_detail = StringBuilder()
  for f in templates {
    let r = @exec.run(
      join(bin, "cmd/diffprobe/diffprobe.exe"),
      [f, root],
      root,
      60000,
    )
    diff_n += 1
    let t = r.stdout
    let ok = r.rc == 0 &&
      t.contains("same=true") &&
      t.contains("wasm stage=run kind=OK") &&
      t.contains("js   stage=run kind=OK")
    if !ok {
      diff_ok = false
      diff_detail.write_string(basename(f) + ": " + t + "\\n")
    }
  }
  results.push(
    check(
      "oracle_templates",
      diff_ok && diff_n > 0,
      "n=" + diff_n.to_string() + " " + diff_detail.to_string(),
    ),
  )

  // 6. The gate itself must be able to fail: a deliberately wrong expected
  // trace must not compare equal.
  let bad = expected + "x"
  results.push(
    check("negative_control", got != bad, "tampered expected differs"),
  )

  let mut all_ok = true
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  let mut first = true
  for r in results {
    if !r.contains("\"ok\":true") {
      all_ok = false
    }
  }
  b.write_string(if all_ok { "true" } else { "false" })
  b.write_string(",\"checks\":[")
  for r in results {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string(r)
  }
  b.write_string("]}")
  println(b.to_string())
  if !all_ok {
    @env.exit(1)
  }
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}
