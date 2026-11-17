///|
/// Case selection, rendering and per-target stage execution.

///|
fn select_layout(cfg : Config) -> Array[@featuregen.LayoutCase] {
  let all = @featuregen.layout_cases()
  let out : Array[@featuregen.LayoutCase] = []
  if cfg.only != "" {
    for c in all {
      if c.id == cfg.only {
        out.push(c)
      }
    }
    return out
  }
  let n = if cfg.limit > 0 && cfg.limit < all.length() {
    cfg.limit
  } else {
    all.length()
  }
  for i, c in all {
    if i < n {
      out.push(c)
    }
  }
  // F7 seed and its plain-struct control are calibration cases for the
  // known-ICE classifier.  They are always included, even when `--limit`
  // selects only the first few layout cases.
  for c in [@featuregen.f7_seed(), @featuregen.f7_control()] {
    let mut present = false
    for o in out {
      if o.id == c.id {
        present = true
      }
    }
    if !present {
      out.push(c)
    }
  }
  out
}

///|
fn select_async(cfg : Config) -> Array[@asyncgen.Case] {
  let all = @asyncgen.matrix()
  if cfg.only != "" {
    let out : Array[@asyncgen.Case] = []
    for c in all {
      if c.id == cfg.only {
        out.push(c)
      }
    }
    return out
  }
  @asyncgen.select_cases(cfg.limit)
}

///|
fn write_layout_case(dir : String, p : @featuregen.RenderedPackage) -> Bool {
  let a = write_one(join(dir, "moon.mod"), p.moon_mod)
  let b = write_one(join(dir, "moon.pkg"), p.moon_pkg)
  let c = write_one(join(dir, "lib.mbt"), p.lib_mbt)
  let d = write_one(join(dir, "main.mbt"), p.main_mbt)
  let e = write_one(join(dir, "main_test.mbt"), p.main_test_mbt)
  a && b && c && d && e
}

///|
fn write_async_case(dir : String, c : @asyncgen.Case) -> Bool {
  let mut ok = true
  for pair in @asyncgen.render_package(c) {
    let path = join(dir, pair.0)
    @corpus.ensure_dir(@corpus.dirname(path))
    if !write_one(path, pair.1) {
      ok = false
    }
  }
  ok
}

///|
fn mk_obs(
  target : String,
  stage : String,
  rc : Int32,
  executed : Bool,
  stdout : String,
  stderr : String,
  ms : Int64,
  klass : String,
  signature : String,
  artifact : String,
) -> TargetObs {
  {
    target,
    stage,
    rc,
    executed,
    stdout,
    stderr_short: short(stderr, 700),
    digest: output_digest(stdout),
    ms,
    klass,
    signature,
    artifact,
  }
}

///|
/// Build one target, then execute the artifact.  A failed build is terminal:
/// no output is compared for that target.
async fn run_target(cfg : Config, dir : String, target : String) -> TargetObs {
  let build = @exec.run_isolated(
    moon_path(),
    ["build", "--target", target],
    dir,
    cfg.timeout_ms,
    max_output_bytes=65536,
  )
  let bstderr = build.stderr
  if build.rc != 0 || build.timed_out {
    let (klass, sig) = classify_build_failure(
      "build",
      build.rc,
      build.timed_out,
      bstderr,
    )
    return mk_obs(
      target,
      "build",
      build.rc,
      false,
      "",
      bstderr,
      build.ms,
      klass,
      sig,
      "",
    )
  }
  let art = find_artifact(dir, target)
  if art == "" {
    return mk_obs(
      target,
      "build",
      0,
      false,
      "",
      "artifact-missing",
      build.ms,
      "NO_ARTIFACT",
      "no-artifact",
      "",
    )
  }
  let (cmd, args) = if target == "js" {
    (node_path(), [art])
  } else if target == "native" {
    (art, [])
  } else {
    (moonrun_path(), [art])
  }
  let r = @exec.run_isolated(
    cmd,
    args,
    dir,
    cfg.timeout_ms,
    max_output_bytes=1048576,
  )
  let run_klass = if r.timed_out {
    "TIMEOUT"
  } else if r.rc == 0 {
    "OK"
  } else {
    "RUN_RC"
  }
  let run_sig = if r.timed_out {
    "timeout:run"
  } else {
    "run:rc=" + r.rc.to_string()
  }
  mk_obs(
    target,
    "run",
    r.rc,
    !r.timed_out,
    r.stdout,
    r.stderr,
    build.ms + r.ms,
    run_klass,
    run_sig,
    art,
  )
}

///|
async fn run_layout_case(cfg : Config, c : @featuregen.LayoutCase) -> CaseRec {
  let dir = join(join(cfg.out, "cases"), c.id)
  rm_rf(dir)
  @corpus.ensure_dir(dir)
  let pkg = @featuregen.render_package(c)
  if !write_layout_case(dir, pkg) {
    let obs : Array[TargetObs] = []
    return {
      index: c.index,
      id: c.id,
      verdict: "INFRA",
      obs,
      dir,
      note: "write-failed",
    }
  }
  let obs : Array[TargetObs] = []
  for t in cfg.targets {
    obs.push(run_target(cfg, dir, t))
  }
  let verdict = verdict_of(obs)
  let keep = cfg.keep ||
    verdict == "OUTPUT_MISMATCH" ||
    verdict == "ICE" ||
    verdict == "KNOWN_LINK_ICE"
  if !keep {
    rm_rf(dir)
  }
  { index: c.index, id: c.id, verdict, obs, dir, note: "", }
}

///|
async fn run_async_case(cfg : Config, c : @asyncgen.Case) -> CaseRec {
  let dir = join(join(cfg.out, "cases"), c.id)
  rm_rf(dir)
  @corpus.ensure_dir(dir)
  if !write_async_case(dir, c) {
    let obs : Array[TargetObs] = []
    return {
      index: 0,
      id: c.id,
      verdict: "INFRA",
      obs,
      dir,
      note: "write-failed",
    }
  }
  let obs : Array[TargetObs] = []
  for t in cfg.targets {
    obs.push(run_target(cfg, dir, t))
  }
  // Async cases render only a library plus tests and have no `main`, so a
  // successful build yields no executable artifact; the driver records
  // NO_ARTIFACT rather than inventing an entry point.
  let verdict = verdict_of(obs)
  let keep = cfg.keep || verdict == "INFRA"
  if !keep {
    rm_rf(dir)
  }
  { index: 0, id: c.id, verdict, obs, dir, note: "async:no-main-generated", }
}
