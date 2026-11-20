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
    edge_cap: 1000,
    parent_cap: 20000,
    persist_cap: 2000,
    coverage_cap: 4000,
    stats_cap: 100000,
    edge_reward: true,
    rss_limit_mb: 0,
    baseline_trace_max_mb: 256,
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
    edge_keys: [],
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
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0, 0))
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
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0, 0))
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
  let pb = persist_budget_new(1000, 1000)
  persist_behavior(cfg, pb, src, "behavior")
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
test "baseline bypasses the queue cap, but a lost baseline still blocks U0" {
  let cfg = trace_test_cfg()
  cfg.trace_queue = 1
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  assert_true(
    trace_submit(cfg, q, @trace.T2, "seed1", "seed1", "in.mbt", "", true, "cfg"),
  )
  // Capacity used to refuse this one, which made every campaign's U0
  // incomplete.  Baseline tasks are now allowed past the cap.
  assert_true(
    trace_submit(cfg, q, @trace.T2, "seed2", "seed2", "in.mbt", "", true, "cfg"),
  )
  assert_eq(q.tasks.length(), 2)
  assert_eq(q.baseline_expected, 2)
  assert_eq(q.baseline_failed, 0)
  trace_apply(
    cfg,
    trace_test_task_stage("seed1", @trace.T2, true),
    trace_test_result_full([], @trace.T2, @trace.Accepted, true),
    cov,
    f,
    q,
  )
  assert_eq(q.baseline_done, 1)
  // The second seed never returns: U0 must not be reported complete.
  q.baseline_failed += 1
  trace_maybe_settle_baseline(cov, f, q)
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
    edge_keys: ["16,32", "32,48"],
  }
  // 7 > 5 and 9 > 3 on purpose: the sidecar must keep both the mapped and the
  // total numbers instead of collapsing them into one.
  let pb = persist_budget_new(1000, 1000)
  persist_coverage(cfg, pb, task, tr, ["camlMoonc__A", "camlMoonc__B"], true)
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
  assert_true(meta.contains("\"trace_edge_keys\":2"))
  assert_true(meta.contains("\"edge_novel\":true"))
}

///|
fn trace_test_result_edges(
  functions : Array[String],
  keys : Array[String],
) -> @trace.TraceResult {
  {
    ..trace_test_result(functions),
    edges: keys.length(),
    mapped_edges: keys.length(),
    edge_keys: keys,
  }
}

///|
test "edge universe dedups, caps, and saturates without evicting" {
  let cov = trace_universe_new()
  cov.edge_cap = 2
  let mut added_total = 0
  added_total += edge_universe_add(cov, ["1,2"])
  added_total += edge_universe_add(cov, ["1,2"])
  assert_eq(added_total, 1)
  added_total += edge_universe_add(cov, ["2,3", "2,3"])
  assert_eq(added_total, 2)
  assert_eq(cov.edge_seen.length(), 2)
  // Exactly at capacity but nothing has been refused yet.
  assert_false(cov.edge_saturated)
  // The next genuinely new key would exceed the cap: refuse, record, and stop.
  added_total += edge_universe_add(cov, ["3,4"])
  assert_true(cov.edge_saturated)
  assert_eq(added_total, 2)
  // Saturation is sticky; later calls cannot add and still report zero.
  added_total += edge_universe_add(cov, ["5,6"])
  assert_eq(cov.edge_seen.length(), 2)
  assert_eq(added_total, 2)
  // Keys already retained are still recognized after saturation.
  assert_eq(edge_universe_add(cov, ["1,2"]), 0)
}

///|
test "edge-only novelty earns a smaller bonus than function novelty" {
  let f = feedback_new()
  ignore(feedback_upsert(f, "edge-only", @cov.FuncSet::new([]), 0, 2))
  ignore(feedback_upsert(f, "func-only", @cov.FuncSet::new(["f1"]), 1, 0))
  ignore(feedback_upsert(f, "both", @cov.FuncSet::new(["f2"]), 1, 2))
  let ei = f.index.get(@corpus.sha1_hex("edge-only")).unwrap()
  let fi = f.index.get(@corpus.sha1_hex("func-only")).unwrap()
  let bi = f.index.get(@corpus.sha1_hex("both")).unwrap()
  assert_eq(f.entries[ei].energy, 1 + EDGE_NOVELTY_BONUS)
  assert_eq(f.entries[fi].energy, FUNC_NOVELTY_BONUS)
  assert_eq(f.entries[bi].energy, FUNC_NOVELTY_BONUS + EDGE_NOVELTY_BONUS)
  assert_true(f.entries[ei].energy < f.entries[fi].energy)
  assert_true(EDGE_NOVELTY_BONUS < FUNC_NOVELTY_BONUS)
}

///|
test "an edge-only trace is admitted and rewarded small, exactly once" {
  let cfg = trace_test_cfg()
  let f = feedback_new()
  ignore(feedback_upsert(f, "seed", @cov.FuncSet::new([]), 0, 0))
  let cov = trace_universe_new()
  let q = trace_queue_new()
  trace_apply(
    cfg,
    trace_test_task("edge"),
    trace_test_result_edges([], ["1,2", "2,3"]),
    cov,
    f,
    q,
  )
  assert_eq(cov.new_edges, 2)
  assert_eq(cov.coverage_adds, 0)
  assert_eq(f.entries.length(), 2)
  let ei = f.index.get(@corpus.sha1_hex("edge")).unwrap()
  let edge_energy = f.entries[ei].energy
  assert_eq(edge_energy, 1 + EDGE_NOVELTY_BONUS)
  let sidecar = join(
    join(join(join(cfg.out, "corpus"), "coverage"), "t2"),
    "accepted",
  )
  let path = join(sidecar, "ih" + "_" + @corpus.sha1_hex("cfg") + ".json")
  let first = @fs.read_file_to_string(path) catch { _ => "" }
  assert_true(first.contains("\"trace_edge_keys\":2"))
  assert_true(first.contains("\"edge_novel\":true"))
  // Replaying the same trace adds no edges and must not bump energy again.
  trace_apply(
    cfg,
    trace_test_task("edge"),
    trace_test_result_edges([], ["1,2", "2,3"]),
    cov,
    f,
    q,
  )
  assert_eq(cov.new_edges, 2)
  assert_eq(f.entries[ei].energy, edge_energy)
  let second = @fs.read_file_to_string(path) catch { _ => "" }
  assert_true(second.contains("\"edge_novel\":false"))
}

///|
test "edgeless traces keep edge counters at zero and do not panic" {
  let cfg = trace_test_cfg()
  cfg.out = "/tmp/mbtfuzz_edgeless_wbtest"
  rm_rf(cfg.out)
  let f = feedback_new()
  let cov = trace_universe_new()
  let q = trace_queue_new()
  q.baseline_expected = 1
  q.baseline_settled = false
  q.baseline_complete = false
  // Candidate with functions but no mapped transitions: buffered, no reward.
  trace_apply(
    cfg,
    trace_test_task("candidate"),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  assert_eq(cov.pending.length(), 1)
  assert_eq(cov.new_edges, 0)
  // Baseline is edgeless too; settling must not touch edge state.
  trace_apply(
    cfg,
    trace_test_task_stage("seed", @trace.T2, true),
    trace_test_result(["f1"]),
    cov,
    f,
    q,
  )
  assert_true(q.baseline_complete)
  assert_eq(cov.pending.length(), 0)
  assert_eq(cov.edge_seen.length(), 0)
  assert_eq(cov.new_edges, 0)
  assert_false(cov.edge_saturated)
  assert_eq(cov.coverage_adds, 0)
}

///|
fn feedback_index_consistent(f : Feedback) -> Bool {
  let mut ok = f.index.length() == f.entries.length()
  let mut i = 0
  while i < f.entries.length() && ok {
    match f.index.get(f.entries[i].hash) {
      Some(j) => if j != i { ok = false }
      None => ok = false
    }
    i += 1
  }
  ok
}

///|
fn feedback_src_set(f : Feedback) -> Map[String, Unit] {
  let m : Map[String, Unit] = Map([])
  for e in f.entries {
    m.set(e.src, ())
  }
  m
}

///|
test "parent pool cap evicts and keeps the index consistent" {
  let f = feedback_new()
  f.cap = 8
  for i in 0..<108 {
    ignore(
      feedback_upsert(f, "parent-" + i.to_string(), @cov.FuncSet::new([]), 0, 0),
    )
  }
  assert_eq(f.entries.length(), 8)
  assert_eq(f.seen, 108)
  assert_eq(f.evicted, 100)
  assert_true(feedback_index_consistent(f))
  let kept = feedback_src_set(f)
  // Equal energy: the replacement policy evicts the oldest admission first,
  // so exactly the last eight admitted inputs survive.
  for i in 0..<100 {
    assert_false(kept.contains("parent-" + i.to_string()))
  }
  for i in 100..<108 {
    assert_true(kept.contains("parent-" + i.to_string()))
  }
  // An evicted input whose tombstone is still remembered cannot silently
  // re-enter through a replayed load in the same campaign.
  ignore(feedback_upsert(f, "parent-99", @cov.FuncSet::new([]), 0, 0))
  assert_eq(f.entries.length(), 8)
  assert_eq(f.seen, 108)
  assert_eq(f.evicted, 100)
  assert_true(feedback_index_consistent(f))
}

///|
test "parent pool cap evicts the lowest-energy parent" {
  let f = feedback_new()
  f.cap = 3
  ignore(feedback_upsert(f, "high", @cov.FuncSet::new(["f"]), 1, 0))
  ignore(feedback_upsert(f, "mid", @cov.FuncSet::new(["f"]), 0, 0))
  ignore(feedback_upsert(f, "low", @cov.FuncSet::new([]), 0, 0))
  ignore(feedback_upsert(f, "new", @cov.FuncSet::new([]), 0, 0))
  assert_eq(f.entries.length(), 3)
  assert_eq(f.evicted, 1)
  let kept = feedback_src_set(f)
  assert_true(kept.contains("high"))
  assert_true(kept.contains("mid"))
  assert_true(kept.contains("new"))
  assert_false(kept.contains("low"))
  assert_true(feedback_index_consistent(f))
}

///|
test "parent pool survivors are deterministic for a seed and input stream" {
  let run = fn(seed : UInt64) -> Array[String] {
    let f = feedback_new()
    f.cap = 32
    let rng = @mutate.Rng::new(seed)
    for i in 0..<200 {
      let edges = if i % 7 == 0 { 1 } else { 0 }
      ignore(
        feedback_upsert(
          f,
          "in-" + i.to_string(),
          @cov.FuncSet::new([]),
          0,
          edges,
        ),
      )
      // Selection decays energy, so the RNG stream participates in the
      // survivor set; the same seed must reproduce it exactly.
      if i % 3 == 0 {
        ignore(feedback_pick(f, rng))
      }
    }
    let out : Array[String] = []
    for e in f.entries {
      out.push(e.src)
    }
    out.sort()
    out
  }
  let a = run(99UL)
  let b = run(99UL)
  assert_eq(a.length(), 32)
  assert_eq(a, b)
}

///|
test "evidence cap skips non-candidates but never candidates" {
  let cfg = trace_test_cfg()
  cfg.out = "/tmp/mbtfuzz_caps_persist_wbtest"
  rm_rf(cfg.out)
  let pb = persist_budget_new(2, 2)
  persist_behavior(cfg, pb, "alpha", "behavior")
  persist_behavior(cfg, pb, "beta", "behavior")
  assert_eq(pb.written, 2)
  assert_eq(pb.skipped, 0)
  assert_false(pb.saturated)
  persist_behavior(cfg, pb, "gamma", "behavior")
  assert_eq(pb.written, 2)
  assert_eq(pb.skipped, 1)
  assert_true(pb.saturated)
  let corpus = join(cfg.out, "corpus")
  assert_false(
    @fs.path_exists(join(corpus, @corpus.sha1_hex("gamma") + ".mbt")),
  )
  let src = "fn main { let _ = 1 }"
  let r : @exec.RunResult = {
    rc: 2,
    stdout: "",
    stderr: "Oops, the compiler has encountered a bug",
    ms: 1,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  assert_true(save_crash(cfg, pb, "t1", r, src, 0))
  assert_eq(pb.written, 3)
  assert_eq(pb.forced, 1)
  assert_true(@fs.path_exists(join(corpus, @corpus.sha1_hex(src) + ".mbt")))
  // Re-persisting an admitted input neither skips nor double-counts.
  persist_behavior(cfg, pb, "alpha", "behavior")
  assert_eq(pb.written, 3)
  assert_eq(pb.skipped, 1)
}

///|
test "coverage witnesses have their own budget" {
  let cfg = trace_test_cfg()
  cfg.out = "/tmp/mbtfuzz_caps_covcap_wbtest"
  rm_rf(cfg.out)
  let cov = trace_universe_new()
  // The behaviour budget is irrelevant to coverage: setting it to zero must
  // not stop coverage evidence from being written.
  cov.persist.cap = 0
  cov.persist.coverage_cap = 1
  let pb = cov.persist
  let f = feedback_new()
  let q = trace_queue_new()
  let tr1 : @trace.TraceResult = {
    ..trace_test_result(["f1"]),
    input_hash: @corpus.sha1_hex("first"),
  }
  let tr2 : @trace.TraceResult = {
    ..trace_test_result(["f2"]),
    input_hash: @corpus.sha1_hex("second"),
  }
  trace_apply(cfg, trace_test_task("first"), tr1, cov, f, q)
  trace_apply(cfg, trace_test_task("second"), tr2, cov, f, q)
  assert_eq(pb.coverage_written, 1)
  assert_eq(pb.coverage_skipped, 1)
  // Both traces are still counted in memory; only the second sidecar is gone.
  assert_eq(cov.evidence.length(), 2)
  let dir = join(
    join(join(join(cfg.out, "corpus"), "coverage"), "t2"),
    "accepted",
  )
  let suffix = "_" + @corpus.sha1_hex(tr1.config_hash) + ".json"
  assert_true(@fs.path_exists(join(dir, tr1.input_hash + suffix)))
  assert_false(@fs.path_exists(join(dir, tr2.input_hash + suffix)))
}

///|
test "corpus file names follow the mode" {
  assert_eq(corpus_file_name("h", "mbt"), "h.mbt")
  assert_eq(corpus_file_name("h", "pkg"), "h.moon.pkg")
  assert_eq(corpus_file_name("h", "mod"), "h.moon.mod")
  assert_eq(corpus_file_name("h", "mbtmd"), "h.mbt.md")
  assert_eq(corpus_file_name("h", "mbti"), "h.mbti")
  assert_eq(corpus_file_name("h", "mbtx"), "h.mbtx")
}

///|
/// A restart with `--seed-dir` uses the same suffix table as the mode loader;
/// the names above must therefore be loadable by it.
test "a persisted pkg witness is loadable by the pkg suffix" {
  let dir = "/tmp/mbtfuzz_wbtest_seeddir"
  rm_rf(dir)
  @corpus.ensure_dir(dir)
  let _ = @stager.write_text(
    join(dir, corpus_file_name("abc", "pkg")),
    "pkgtype(kind: \"executable\")\n",
  )
  let got = @corpus.load_texts([dir], ["moon.pkg"], 4096, 10)
  assert_eq(got.length(), 1)
}

///|
test "eviction never drops the last owner of a feature" {
  let f = feedback_new()
  f.cap = 2
  let _ = feedback_upsert(f, "one", @cov.FuncSet::new(["A", "B"]), 2, 0)
  let _ = feedback_upsert(f, "two", @cov.FuncSet::new(["B"]), 0, 0)
  // "one" owns A uniquely, "two" owns only B which "one" also owns.
  let _ = feedback_upsert(f, "three", @cov.FuncSet::new(["C"]), 1, 0)
  assert_eq(f.entries.length(), 2)
  let mut kept_one = false
  let mut kept_three = false
  for e in f.entries {
    if e.src == "one" {
      kept_one = true
    }
    if e.src == "three" {
      kept_three = true
    }
  }
  assert_true(kept_one)
  assert_true(kept_three)
  assert_eq(f.protected_forced, 0)
}

///|
test "if every parent owns a unique feature the eviction is forced and counted" {
  let f = feedback_new()
  f.cap = 2
  let _ = feedback_upsert(f, "a", @cov.FuncSet::new(["A"]), 1, 0)
  let _ = feedback_upsert(f, "b", @cov.FuncSet::new(["B"]), 1, 0)
  let _ = feedback_upsert(f, "c", @cov.FuncSet::new(["C"]), 1, 0)
  assert_eq(f.entries.length(), 2)
  assert_eq(f.protected_forced, 1)
}

///|
/// The finding metadata is JSON consumed by `cmd/verify` and by humans.  A
/// status field that leaves an extra quote makes every saved witness
/// unparseable, which is exactly the kind of bug a string-building writer
/// produces.
test "finding metadata is valid JSON and marked candidate" {
  let r : @exec.RunResult = {
    rc: -6,
    stdout: "",
    stderr: "Fatal error: out of memory\n",
    ms: 5600L,
    timed_out: false,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
  let m = meta_json("t1", "OOM", "", r, "abc", 1)
  assert_true(m.contains("\"status\":\"candidate\""))
  assert_false(
    m.has_prefix(
      "{\"stage\":\"t1\",\"kind\":\"OOM\",\"detail\":\"\",\"signature\":\"abc\",\"status\":\"candidate\"\"",
    ),
  )
}

///|
test "percent flags accept integers only" {
  assert_eq(parse_percent("0"), Some(0))
  assert_eq(parse_percent("20"), Some(20))
  assert_eq(parse_percent("100"), Some(100))
  assert_eq(parse_percent("0.02"), None)
  assert_eq(parse_percent("101"), None)
  assert_eq(parse_percent("-1"), None)
  assert_eq(parse_percent(""), None)
  assert_eq(parse_percent("2x"), None)
}
