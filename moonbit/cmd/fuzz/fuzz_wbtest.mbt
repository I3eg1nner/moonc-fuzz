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
fn trace_test_task_stage(
  src : String,
  stage : @trace.TraceStage,
  baseline : Bool,
) -> TraceTask {
  {
    stage,
    input_hash: @corpus.sha1_hex(src),
    config_hash: "cfg",
    src,
    compiled: src,
    fname: "in.mbt",
    core_path: "",
    baseline,
    reserved_ms: 0L,
  }
}

///|
fn trace_test_task(src : String) -> TraceTask {
  trace_test_task_stage(src, @trace.T2, false)
}

///|
fn trace_test_result_full(
  functions : Array[String],
  stage : @trace.TraceStage,
  outcome : @trace.TraceOutcome,
  complete : Bool,
) -> @trace.TraceResult {
  {
    input_hash: "ih",
    config_hash: "cfg",
    stage,
    outcome,
    complete,
    functions,
    // The scheduling tests do not read TB counters; exact values are covered
    // by the trace-package tests and the sidecar-shape test below.
    unique_pc: 0,
    mapped_unique_pc: 0,
    edges: 0,
    mapped_edges: 0,
    elapsed_ms: 1L,
    trace_bytes: 1L,
    rc: if outcome == @trace.Accepted {
      0
    } else {
      2
    },
    failure: if complete {
      ""
    } else {
      "injected"
    },
    detail: "",
  }
}

///|
fn trace_test_result(functions : Array[String]) -> @trace.TraceResult {
  trace_test_result_full(functions, @trace.T2, @trace.Accepted, true)
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

///|
test "trace scheduler borrows a share instead of closing the queue" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  assert_true(
    trace_submit(cfg, q, @trace.T1, "a", "a", "in.mbt", "", false, "cfg"),
  )
  let first = match trace_pop(q) {
    Ready(t) => t
    _ => {
      assert_true(false)
      trace_test_task("fallback")
    }
  }
  trace_apply(
    cfg,
    first,
    trace_test_result_full(["f1"], @trace.T1, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  assert_true(
    trace_submit(cfg, q, @trace.T1, "b", "b", "in.mbt", "", false, "cfg"),
  )
  match trace_pop(q) {
    Ready(t) => assert_true(t.stage == @trace.T1)
    _ => assert_true(false)
  }
}

///|
test "trace scheduler counts in-flight reservations" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  assert_true(
    trace_submit(cfg, q, @trace.T2, "a", "a", "in.mbt", "", false, "cfg"),
  )
  assert_true(
    trace_submit(cfg, q, @trace.T2, "b", "b", "in.mbt", "", false, "cfg"),
  )
  let first = match trace_pop(q) {
    Ready(t) => t
    _ => {
      assert_true(false)
      trace_test_task("fallback")
    }
  }
  assert_eq(q.t2_reserved_ms, 250L)
  assert_eq(q.inflight, 1)
  match trace_pop(q) {
    Wait => ()
    _ => assert_true(false)
  }
  trace_apply(
    cfg,
    first,
    trace_test_result_full(["f1"], @trace.T2, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  assert_eq(q.t2_reserved_ms, 0L)
  assert_eq(q.inflight, 0)
  match trace_pop(q) {
    Ready(t) => assert_true(t.stage == @trace.T2)
    _ => assert_true(false)
  }
}

///|
test "candidate waits for baseline and gains no seed coverage" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  q.baseline_expected = 1
  q.baseline_settled = false
  q.baseline_complete = false
  trace_apply(
    cfg,
    trace_test_task("candidate"),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  assert_eq(cov.coverage_adds, 0)
  assert_eq(cov.pending.length(), 1)
  assert_eq(f.entries.length(), 0)
  trace_apply(
    cfg,
    trace_test_task_stage("seed", @trace.T2, true),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  assert_eq(q.baseline_complete, true)
  assert_eq(cov.pending.length(), 0)
  assert_eq(cov.coverage_adds, 0)
  assert_eq(f.entries.length(), 0)
}

///|
test "failed baseline marks candidates unresolved and unrewarded" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  q.baseline_expected = 1
  q.baseline_settled = false
  q.baseline_complete = false
  trace_apply(
    cfg,
    trace_test_task("candidate"),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  trace_apply(
    cfg,
    trace_test_task_stage("seed", @trace.T2, true),
    trace_test_result_full([], @trace.T2, @trace.CollectorFailed, false),
    cov,
    f,
    q,
  )
  assert_eq(q.baseline_complete, false)
  assert_eq(q.baseline_unresolved, 1)
  assert_eq(cov.coverage_adds, 0)
  assert_eq(f.entries.length(), 0)
}

///|
test "coverage evidence is keyed by stage and behavior cannot erase it" {
  let cfg = trace_test_cfg()
  cfg.out = "/tmp/mbtfuzz_sidecar_wbtest"
  rm_rf(cfg.out)
  let src = "fn f() { () }"
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  trace_apply(
    cfg,
    trace_test_task_stage(src, @trace.T1, false),
    trace_test_result_full(["f1"], @trace.T1, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  trace_apply(
    cfg,
    trace_test_task_stage(src, @trace.T2, false),
    trace_test_result_full(["f2"], @trace.T2, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  persist_behavior(cfg, src, "behavior")
  assert_eq(cov.evidence.length(), 2)
  let corpus = join(cfg.out, "corpus")
  assert_true(@fs.path_exists(join(corpus, @corpus.sha1_hex(src) + ".mbt")))
  let cov_root = join(corpus, "coverage")
  let t1dir = join(join(cov_root, "t1"), "accepted")
  let t2dir = join(join(cov_root, "t2"), "accepted")
  let t1files = @fs.read_dir(t1dir) catch { _ => [] }
  let t2files = @fs.read_dir(t2dir) catch { _ => [] }
  assert_eq(t1files.length(), 1)
  assert_eq(t2files.length(), 1)
  let t1meta = @fs.read_file_to_string(join(t1dir, t1files[0])) catch {
    _ => ""
  }
  let t2meta = @fs.read_file_to_string(join(t2dir, t2files[0])) catch {
    _ => ""
  }
  assert_true(t1meta.contains("\"stage\":\"t1\""))
  assert_true(t1meta.contains("f1"))
  assert_true(t2meta.contains("\"stage\":\"t2\""))
  assert_true(t2meta.contains("f2"))
  let behavior = join(join(corpus, "behavior"), @corpus.sha1_hex(src))
  assert_true(@fs.path_exists(join(behavior, "behavior.json")))
}

///|
test "a dropped baseline task makes U0 incomplete" {
  let cfg = trace_test_cfg()
  cfg.trace_queue = 1
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  assert_true(
    trace_submit(cfg, q, @trace.T2, "seed1", "seed1", "in.mbt", "", true, "cfg"),
  )
  assert_true(
    !trace_submit(
      cfg,
      q,
      @trace.T2,
      "seed2",
      "seed2",
      "in.mbt",
      "",
      true,
      "cfg",
    ),
  )
  assert_eq(q.baseline_expected, 2)
  assert_eq(q.baseline_failed, 1)
  trace_apply(
    cfg,
    trace_test_task_stage("seed1", @trace.T2, true),
    trace_test_result_full([], @trace.T2, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  assert_eq(trace_baseline_state(q), "incomplete")
  assert_eq(q.baseline_complete, false)
}

///|
test "relative_new is null unless baseline is complete" {
  let cov = trace_universe_new()
  let q = trace_queue_new()
  cov.baseline_total = @cov.FuncSet::new(["f1"])
  cov.observed_total = @cov.FuncSet::new(["f1", "f2"])
  assert_eq(relative_new_json(q, cov), "null")
  q.baseline_expected = 1
  q.baseline_settled = true
  q.baseline_complete = true
  assert_eq(relative_new_json(q, cov), "1")
  q.baseline_complete = false
  assert_eq(relative_new_json(q, cov), "null")
}

///|
test "diagnostic family ignores location while signature keeps it" {
  let mk = fn(loc : String) -> @exec.RunResult {
    {
      rc: 2,
      stdout: "",
      stderr: "{\"level\":\"error\",\"error_code\":3002,\"loc\":\"" +
      loc +
      "\",\"message\":\"Parse error\"}",
      ms: 0,
      timed_out: false,
      stdout_digest: "",
      stdout_full_len: 0L,
      stdout_truncated: false,
    }
  }
  let a = mk("1:1")
  let b = mk("2:8")
  assert_true(behavior_sig("t1", a) != behavior_sig("t1", b))
  assert_eq(behavior_family("t1", a), behavior_family("t1", b))
}

///|
test "coverage sidecar persists exact TB counters" {
  let cfg = trace_test_cfg()
  let task = trace_test_task_stage("src-tb", @trace.T2, false)
  let tr : @trace.TraceResult = {
    ..trace_test_result_full(["camlMoonc__A"], @trace.T2, @trace.Accepted, true),
    unique_pc: 7,
    mapped_unique_pc: 5,
    edges: 9,
    mapped_edges: 3,
  }
  // 7 > 5 and 9 > 3 on purpose: the sidecar must keep both the mapped and the
  // total numbers instead of collapsing them into one.
  persist_coverage(cfg, task, tr, ["camlMoonc__A", "camlMoonc__B"])
  let dir = join(
    join(join(join(cfg.out, "corpus"), "coverage"), "t2"),
    "accepted",
  )
  let path = join(
    dir,
    tr.input_hash + "_" + @corpus.sha1_hex(tr.config_hash) + ".json",
  )
  let meta = @fs.read_file_to_string(path) catch { _ => "" }
  assert_true(meta.contains("\"unique_pc\":7"))
  assert_true(meta.contains("\"mapped_unique_pc\":5"))
  assert_true(meta.contains("\"edges\":9"))
  assert_true(meta.contains("\"mapped_edges\":3"))
  assert_true(meta.contains("\"coverage_funcs_count\":2"))
  assert_true(meta.contains("\"trace_func_count\":1"))
  assert_true(meta.contains("\"tb_counter_scope\":\"latest_trace\""))
  assert_true(meta.contains("\"edge_scope\":\"mapped_both_endpoints\""))
}
