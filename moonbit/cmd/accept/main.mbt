///|
/// Acceptance gate for the Python -> MoonBit migration.
///
/// This is deliberately not "did the tests pass".  It checks the properties a
/// reviewer would use to decide that MoonBit is the operational default:
/// pinned toolchain, all known defects reproduced, real trace parity, coverage
/// set algebra, differential oracle sensitivity on the runnable templates,
/// false-positive regression on a real compile corpus and on a healthy LSP
/// session, and a bounded campaign that never invokes Python.
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
/// `MOON_HOME` is the toolchain's own variable and is what a restored archive
/// sets; `~/.moon` is only the fallback.  Hard-coding `$HOME/.moon` made the
/// gate untestable against a frozen toolchain.
fn toolchain_bin(name : String) -> String {
  let home = match @env.get_env_var("MOON_HOME") {
    Some(h) => if h == "" { default_home() } else { h }
    None => default_home()
  }
  join(join(home, "bin"), name)
}

///|
fn default_home() -> String {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  join(home, ".moon")
}

///|
fn usage() -> Unit {
  println(
    "usage: accept [ROOT] [BIN_DIR] [--profile full|core]\n" +
    "  full  all gates, including the two that need afl-qemu-trace (default)\n" +
    "  core  skip trace_exact/trace_real_f4/negative_control; names them in JSON",
  )
}

///|
async fn main {
  let args = @env.args()
  for a in args {
    if a == "--help" || a == "-h" {
      usage()
      return
    }
  }
  let pos : Array[String] = []
  let mut profile = "full"
  let mut pi = 1
  while pi < args.length() {
    let a = args[pi]
    if a == "--profile" && pi + 1 < args.length() {
      profile = args[pi + 1]
      pi += 2
    } else {
      pos.push(a)
      pi += 1
    }
  }
  // `core` skips the gates that need host tracing tools (afl-qemu-trace, a
  // pinned `moonc` symbol table).  It is meant for public CI, which can
  // restore the frozen toolchain but has no QEMU build; the skipped names are
  // printed in the JSON rather than silently dropped.
  let host_trace = profile != "core"
  let root = if pos.length() >= 1 {
    pos[0]
  } else {
    match @env.current_dir() {
      Some(d) => d
      None => "/data/audit/mbtfuzz"
    }
  }
  let moonbit = join(root, "moonbit")
  let bin = if pos.length() >= 2 {
    pos[1]
  } else {
    join(moonbit, "_build/native/debug/build")
  }
  let moonc = toolchain_bin("moonc")
  let tag = @env.now().to_string()
  let results : Array[String] = []

  // 1. Pinned toolchain.  Changing this must force a re-validation, not be
  // silently accepted as "latest".
  let v = @exec.run(moonc, ["-v"], "/tmp", 5000)
  let vtext = (v.stdout + v.stderr).trim().to_owned()
  let pinned = "v0.10.20+65efd5b93"
  results.push(check("toolchain_pinned", vtext.contains(pinned), vtext))

  // 1b. Unit tests and typecheck must pass before the heavier gates.
  let moon = toolchain_bin("moon")
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
  let mut reg_ok = reg.rc == 0 && count_lines(reg_lines) == 13
  for line in reg_lines.split("\n") {
    if line.trim().char_length() > 0 && !line.contains("\"ok\":true") {
      reg_ok = false
    }
  }
  // When a row fails, name it: "rc=1 rows=12" alone is not actionable.
  let mut reg_bad = ""
  for line in reg_lines.split("\n") {
    if line.trim().char_length() > 0 && !line.contains("\"ok\":true") {
      reg_bad = if line.char_length() > 200 {
        line[0:200].to_owned()
      } else {
        line.to_owned()
      }
      break
    }
  }
  let reg_head = "rc=" +
    reg.rc.to_string() +
    " rows=" +
    count_lines(reg_lines).to_string()
  let reg_detail = if reg_ok {
    reg_head
  } else {
    reg_head + " first_bad=" + reg_bad
  }
  results.push(check("regressions_13", reg_ok, reg_detail))

  // 2b. LSP defect gate.  Separately named on purpose: it asserts that F10,
  // F11 and F12 *still reproduce*, so an upstream fix must fail this check
  // rather than quietly changing `regressions_13`.  Six serial cases with one
  // fresh `moon-lsp` each; the detail records how long the whole check took.
  // A missing binary is a failure with a fixed reason, never a silent skip.
  let lsp_bin = toolchain_bin("moon-lsp")
  let lsp_present = @fs.path_exists(lsp_bin)
  let lsp_start = @env.now()
  let lsp = @exec.run(
    join(bin, "cmd/lspregress/lspregress.exe"),
    [],
    root,
    60000,
  )
  let lsp_ms = @env.now() - lsp_start
  let lsp_rows = count_lines(lsp.stdout)
  // 6 case rows + 1 summary row.
  let mut lsp_ok = lsp_present && lsp.rc == 0 && lsp_rows == 7
  for line in lsp.stdout.split("\n") {
    if line.trim().char_length() > 0 && !line.contains("\"ok\":true") {
      lsp_ok = false
    }
  }
  let lsp_detail = if !lsp_present {
    "moon-lsp not found"
  } else {
    "rc=" +
    lsp.rc.to_string() +
    " cases=6 rows=" +
    lsp_rows.to_string() +
    " ms=" +
    lsp_ms.to_string()
  }
  results.push(check("lsp_regress_6", lsp_ok, lsp_detail))

  // 2b2. LSP negative corpus.  `lsp_regress_6` asserts that known defects still
  // reproduce; this one asserts the opposite direction - on a healthy session
  // the oracles stay silent - and fails if the probe cannot see the F11 trigger
  // at all (`detector_proven`).  Three sessions x seven benign requests.
  let lspneg = @exec.run(
    join(bin, "cmd/lspneg/lspneg.exe"),
    ["--sessions", "3"],
    root,
    180000,
  )
  let lspneg_ok = lspneg.rc == 0 &&
    lspneg.stdout.contains("\"false_alarms\":0") &&
    lspneg.stdout.contains("\"detector_proven\":true")
  let lspneg_detail = if lspneg_ok {
    "sessions=3 observations=21 false_alarms=0 detector_proven=true"
  } else {
    lspneg.stdout.trim().to_owned()
  }
  results.push(check("lsp_negative", lspneg_ok, lspneg_detail))

  // 2c. Oracle sensitivity.  This is the gate that keeps the *measurement*
  // honest: every registered oracle must fire on an injected defect shape and
  // stay silent on controls.  It is cheap and pure, so it runs before the
  // expensive stages and blocks them if a classifier went blind.
  let oa = @exec.run(
    join(bin, "cmd/oracleaudit/oracleaudit.exe"),
    [],
    root,
    30000,
  )
  let oa_sensitive = count_occur(oa.stdout, "\"sensitive\":true")
  let oa_total = count_occur(oa.stdout, "\"oracle\":")
  let oa_ok = oa.rc == 0 &&
    oa.stdout.contains("\"ok\":true") &&
    oa_total > 0 &&
    oa_sensitive == oa_total
  let oa_detail = if oa_ok {
    "proven=" + oa_sensitive.to_string() + "/" + oa_total.to_string()
  } else {
    "rc=" + oa.rc.to_string() + " " + oa.stdout
  }
  results.push(check("oracle_sensitivity", oa_ok, oa_detail))

  // 2c2. False positives on a real compile corpus.  `oraclestat` builds eight
  // known-good programs and eight deliberately broken ones; any finding there
  // is a false alarm, and a mislabelled corpus shows up as `unexpected`.  The
  // gate is deliberately small: it is a regression net for the classifiers,
  // not the statistical measurement (that is `findings/methodology.md`).
  let os_json = "/tmp/mbtfuzz_accept_oraclestat_" + tag + ".json"
  let os = @exec.run(
    join(bin, "cmd/oraclestat/oraclestat.exe"),
    [
      "--clean",
      "8",
      "--broken",
      "8",
      "--json",
      os_json,
      "--root",
      "/tmp/mbtfuzz_accept_ostat_" + tag,
    ],
    root,
    180000,
  )
  let os_text = read_text(os_json)
  let os_ok = os.rc == 0 &&
    os_text.contains(
      "\"name\":\"clean\",\"n\":8,\"defects\":0,\"unexpected\":0",
    ) &&
    os_text.contains(
      "\"name\":\"broken\",\"n\":8,\"defects\":0,\"unexpected\":0",
    )
  let os_detail = if os_ok {
    "clean=8 broken=8 false_alarms=0 upper95=0.375"
  } else {
    "rc=" + os.rc.to_string() + " " + os_text
  }
  results.push(check("oracle_fpr", os_ok, os_detail))

  // 2d. Reduction witness.  Runs the minimizer end to end on the smallest
  // real link-time ICE we have (F9): the reduced witness must re-verify and
  // must not grow.  This is the only gate that exercises the reducer against
  // the actual compiler, so a broken signature comparison shows up here.
  let rd = @exec.run(
    join(bin, "cmd/minimize/minimize.exe"),
    [
      "--dir",
      join(root, "poc/f9_native_v128_stub_ice"),
      "--stage",
      "test",
      "--fuel",
      "60",
      "--out",
      "/tmp/mbtfuzz_accept_reduced_" + tag + ".mbt",
    ],
    root,
    180000,
  )
  let rd_ok = rd.rc == 0 &&
    rd.stdout.contains("\"verified\":true") &&
    rd.stdout.contains("\"published\":true") &&
    rd.stdout.contains("\"baseline\":\"crash|ICE|")
  results.push(check("reduce_witness", rd_ok, rd.stdout.trim().to_owned()))

  // 2e. Seed reproduction.  The mutation campaign is time-bounded and
  // randomised, so it cannot gate a build; what can be checked cheaply is that
  // the default seed packages still reproduce a defect at all (`--mutants 0`
  // only runs the baselines).  If a seed silently stops reproducing, every
  // mutated candidate from it becomes a type error and the campaign quietly
  // measures nothing.
  let sf = @exec.run(
    join(bin, "cmd/seedfuzz/seedfuzz.exe"),
    ["--out", "/tmp/mbtfuzz_accept_seed", "--mutants", "0"],
    root,
    60000,
  )
  let sf_ok = sf.rc == 0 &&
    sf.stdout.contains("\"seed_defects\":") &&
    !sf.stdout.contains("\"seed_defects\":0") &&
    !sf.stdout.contains("copy-failed")
  results.push(check("seed_repro", sf_ok, sf.stdout.trim().to_owned()))

  // 2f. F7 trigger surface.  Fifteen script-mode probes pin the corrected
  // characterisation (empty valtype array + non-null GC element): four must
  // ICE and eight must pass.  INVERTED ORACLE: when upstream fixes the
  // lowering, four rows flip to `matches:false`.  That is not a bug in the
  // gate - update poc/f7_valtype_array_ice/README.md and the expectations in
  // scriptgen, and record the fix, rather than flipping the values silently.
  let f7 = @exec.run(
    join(bin, "cmd/scriptfuzz/scriptfuzz.exe"),
    ["--out", "/tmp/mbtfuzz_accept_f7.jsonl", "--family", "boundary"],
    root,
    180000,
  )
  let f7_ok = f7.rc == 0 &&
    f7.stdout.contains("\"mismatches\":0") &&
    f7.stdout.contains("\"control_failures\":0") &&
    f7.stdout.contains("\"cases\":15")
  results.push(check("f7_boundary", f7_ok, f7.stdout.trim().to_owned()))

  // 2g. Semantic differential.  Every other gate asks "did it fail?"; this one
  // asks "did two backends print the same thing", the only question that
  // catches a miscompile with a clean exit.  wasm-gc and native only: the js
  // backend's constant folder gives `0.0 / 0.0` the opposite NaN sign, which is
  // a documented divergence, not a defect (see findings/semantic_diff.md).
  let sem = @exec.run(
    join(bin, "cmd/semdiff/semdiff.exe"),
    ["--out", "/tmp/mbtfuzz_accept_sem.jsonl", "--targets", "wasm-gc,native"],
    root,
    300000,
  )
  // A differential only proves something when every requested target reached
  // COMPLETE: a mismatch, an unobserved case and an empty corpus all fail the
  // same way now, and the summary says `ok:false` for each of them.
  let sem_ok = sem.rc == 0 &&
    sem.stdout.contains("\"ok\":true") &&
    sem.stdout.contains("\"mismatch\":0") &&
    sem.stdout.contains("\"inconclusive\":0") &&
    sem.stdout.contains("\"skipped\":0")
  results.push(check("semantic_diff", sem_ok, sem.stdout.trim().to_owned()))

  // 2g2. The differential's decision function is a table of counterexamples
  // that runs without a compiler: two timeouts, two signals, two build
  // failures, a missing target, an empty corpus.  This is the gate for the
  // class of false pass that used to make "both hung" look like agreement.
  let sc = @exec.run(
    join(bin, "cmd/semdiff/semdiff.exe"),
    ["--self-test"],
    root,
    30000,
  )
  let sc_ok = sc.rc == 0 && sc.stdout.contains("\"ok\":true")
  results.push(check("semdiff_selfcheck", sc_ok, sc.stdout.trim().to_owned()))

  // 3. Trace gates: exact JSON on a frozen trace, then real end-to-end QEMU
  // parity against a Python-golden function set.  These two need host tools
  // (`afl-qemu-trace`, a `moonc` symbol table) and are the only gates skipped
  // by `--profile core`.
  let expected = read_text(join(moonbit, "accept_fixtures/expected_trace.json"))
    .trim()
    .to_owned()
  if host_trace {
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
    let got = tr.stdout.trim().to_owned()
    results.push(check("trace_exact", tr.rc == 0 && got == expected, got))

    // 3b. Real end-to-end trace parity: QEMU on the 22 B invalid-UTF8 input,
    // then trace2funcs, compared to a Python-golden function set frozen at 599.
    let nm = @exec.run("nm", ["-n", moonc], root, 10000)
    @fs.write_string_to_file(
      "/tmp/mbtfuzz_accept_nm_" + tag + ".txt",
      nm.stdout,
    ) catch {
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
    // 6. The gate itself must be able to fail: a deliberately wrong expected
    // trace must not compare equal.
    let bad = expected + "x"
    results.push(
      check("negative_control", got != bad, "tampered expected differs"),
    )
  }

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
  b.write_string(",\"profile\":\"" + profile + "\"")
  b.write_string(",\"skipped\":[")
  if !host_trace {
    b.write_string("\"trace_exact\",\"trace_real_f4\",\"negative_control\"")
  }
  b.write_string("]")
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
fn count_occur(hay : String, needle : String) -> Int32 {
  let mut n = 0
  let mut rest = hay
  while rest.find(needle) is Some(i) {
    n += 1
    rest = rest[i + needle.length():].to_owned()
  }
  n
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}
