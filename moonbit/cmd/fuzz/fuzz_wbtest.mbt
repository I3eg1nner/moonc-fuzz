///|
test "mode file names and suffixes" {
  assert_eq(fname_of("mbt"), "in.mbt")
  assert_eq(fname_of("pkg"), "moon.pkg")
  assert_eq(fname_of("mod"), "moon.mod")
  assert_eq(fname_of("mbtmd"), "in.mbt.md")
  assert_eq(fname_of("mbti"), "in.mbti")
  assert_eq(fname_of("mbtx"), "in.mbtx")
  assert_eq(suffixes_of("pkg"), ["moon.pkg"])
  assert_eq(suffixes_of("mbtmd"), [".mbt.md"])
}

///|
test "diagnostic code extraction is sorted and unique" {
  let codes = diag_codes("x [E3001] y [W0002] [E3001] [E123] [E1234]")
  assert_eq(codes, ["E1234", "E3001", "W0002"])
}

///|
test "behavior signature distinguishes accept and error codes" {
  let ok : @exec.RunResult = {
    rc: 0,
    stdout: "",
    stderr: "[E3001]",
    ms: 0,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  let err : @exec.RunResult = {
    rc: 2,
    stdout: "[E3001]",
    stderr: "",
    ms: 0,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  assert_eq(behavior_sig("t1", ok), "t1|ACC|E3001")
  assert_eq(behavior_sig("t1", err), "t1|ERR|E3001")
}

///|
test "with_main does not duplicate an existing main" {
  assert_eq(with_main("fn main { () }"), "fn main { () }")
  assert_true(with_main("fn f() { }").contains("fn main"))
}

///|
test "json diagnostics keep code, message and location" {
  let a = json_diag_sig(
    "{\"level\":\"error\",\"error_code\":3002,\"loc\":\"3:1-3:2\",\"message\":\"Parse error, unexpected token\"}",
  )
  let b = json_diag_sig(
    "{\"level\":\"error\",\"error_code\":3003,\"loc\":\"4:2-4:3\",\"message\":\"Unbound variable\"}",
  )
  assert_true(a is Some(_))
  assert_true(b is Some(_))
  assert_true(a != b)
  assert_true(a.unwrap().contains("E3002"))
  assert_true(a.unwrap().contains("3:1-3:2"))
}

///|
test "json diagnostics do not collapse into one ERR bucket" {
  let mk = fn(msg : String) -> @exec.RunResult {
    {
      rc: 2,
      stdout: "",
      stderr: "{\"level\":\"error\",\"error_code\":3002,\"loc\":\"1:1\",\"message\":\"" +
      msg +
      "\"}",
      ms: 0,
      timed_out: false,
      stdout_digest: "",
      stdout_full_len: 0L,
      stdout_truncated: false,
    }
  }
  let a = behavior_sig("t1", mk("unexpected token A"))
  let b = behavior_sig("t1", mk("unexpected token B"))
  assert_true(a != b)
  assert_true(a.contains("E3002"))
  assert_true(b.contains("E3002"))
}

///|
fn trace_test_cfg() -> Config {
  {
    root: "",
    out: "/tmp/mbtfuzz_trace_wbtest",
    workers: 1,
    duration_s: 1,
    p_deep: 0.0,
    p_run: 0.0,
    body_only: true,
    mode: "mbt",
    seed_dir: "",
    fmt_check: false,
    native_diff: false,
    seed: 1UL,
    run_id: "wbtest",
    campaign: "test",
    qemu: "",
    trace_t1: 0.0,
    trace_t2: 1.0,
    trace_t3: 0.0,
    trace_workers: 1,
    trace_queue: 8,
    trace_max_mb: 1,
    trace_cpu_pct: 25,
    baseline_seeds: 0,
    t1_timeout: 1000,
    t2_timeout: 1000,
  }
}

///|
fn trace_test_task(src : String) -> TraceTask {
  {
    stage: "t2",
    input_hash: @corpus.sha1_hex(src),
    config_hash: "cfg",
    src,
    compiled: src,
    fname: "in.mbt",
    core_path: "",
    baseline: false,
  }
}

///|
fn trace_test_result(functions : Array[String]) -> @trace.TraceResult {
  {
    input_hash: "ih",
    config_hash: "cfg",
    stage: "t2",
    outcome: @trace.Accepted,
    complete: true,
    functions,
    elapsed_ms: 1L,
    trace_bytes: 1L,
    detail: "",
  }
}

///|
test "trace coverage admits and rewards only real deltas" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  let task = trace_test_task("src")
  trace_apply(cfg, task, trace_test_result(["f1", "f2"]), cov, f, q)
  assert_eq(cov.coverage_adds, 2)
  assert_eq(f.entries.length(), 1)
  let rewarded = f.entries[0].energy
  trace_apply(cfg, task, trace_test_result(["f1", "f2"]), cov, f, q)
  assert_eq(cov.coverage_adds, 2)
  assert_eq(f.entries.length(), 1)
  assert_eq(f.entries[0].energy, rewarded)
  trace_apply(
    cfg,
    trace_test_task("src2"),
    trace_test_result(["f1", "f2", "f3"]),
    cov,
    f,
    q,
  )
  assert_eq(cov.coverage_adds, 3)
  assert_eq(f.entries.length(), 2)
}

///|
test "feedback parent selection returns a retained input" {
  let f = feedback_new()
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0))
  let cfg = trace_test_cfg()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  trace_apply(
    cfg,
    trace_test_task("new"),
    trace_test_result(["x", "y"]),
    cov,
    f,
    q,
  )
  let rng = @mutate.Rng::new(7UL)
  let mut saw_seed = false
  let mut saw_new = false
  for _ in 0..<50 {
    match feedback_pick(f, rng) {
      Some(s) =>
        if s == "seed" {
          saw_seed = true
        } else if s == "new" {
          saw_new = true
        }
      None => ()
    }
  }
  assert_true(saw_seed)
  assert_true(saw_new)
}

///|
test "zero coverage growth does not admit or reward a parent" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0))
  let cov = trace_universe_new()
  let q = trace_queue_new()
  trace_apply(
    cfg,
    trace_test_task("seed"),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  let before = f.entries[0].energy
  trace_apply(
    cfg,
    trace_test_task("other"),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  assert_eq(f.entries.length(), 1)
  assert_eq(f.entries[0].energy, before)
}
