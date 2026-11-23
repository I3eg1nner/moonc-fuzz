///|
/// Reward weights for one feedback update.  Function novelty is the primary
/// signal and keeps its historical 32; edge novelty is additive and strictly
/// smaller.  An input that only adds edges therefore earns a modest bonus
/// (1 + 8 = 9 with no known functions, 6 + 8 = 14 with known functions), never
/// the top-tier 32/40 reserved for new functions.
const FUNC_NOVELTY_BONUS : Int32 = 32

///|
const KNOWN_FUNC_BONUS : Int32 = 6

///|
const EDGE_NOVELTY_BONUS : Int32 = 8

///|
/// Default campaign-wide cap on retained exact TB edge keys.  Each key is a
/// heap `String`, so an uncapped union over a long campaign would grow without
/// bound.  One real `moonc` T1 trace has ~28k mapped transitions and a T2 trace
/// ~36k, so a cap below one trace would saturate during the baseline and make
/// the signal meaningless.  200k keys is roughly 10-20 MB at worst and leaves
/// room for several traces of genuine novelty while still bounding memory.
const EDGE_CAP_DEFAULT : Int32 = 200000

///|
/// Default campaign-wide cap on retained parents.  Parent selection is a
/// linear scan over this array and the on-disk corpus is one source file per
/// retained parent, so the pool is the two costs that grew without bound in
/// the 60 s / 16-worker calibration (45,546 parents, 88,775 files).  20k keeps
/// a campaign's selection scan and its evidence set proportional to a fixed
/// number instead of to elapsed time.
const PARENT_CAP_DEFAULT : Int32 = 20000

///|
/// Default cap on distinct inputs whose evidence is written under
/// `<out>/corpus` in one campaign.  A persisted input owns at most one source
/// file, two behaviour records and one coverage sidecar per
/// `(stage, outcome)`, so this cap bounds total evidence files as well as
/// source bytes.  Candidate evidence (crash/ICE/diff) is exempt and counted
/// separately; it is never dropped.
const PERSIST_CAP_DEFAULT : Int32 = 2000

///|
/// Maximum number of failure lines kept in `<out>/trace_failures.jsonl`.
/// `trace_failed` in `summary.json` keeps counting every failure after the
/// log is full; only the per-event log is bounded (each line is hundreds of
/// bytes, and `append_line` rewrites the whole file, so an unbounded log is
/// also quadratic I/O).
const TRACE_FAILURE_LOG_MAX : Int32 = 2048

///|
/// Sidecar edge preview cap.  Larger than the old silent 2048, explicitly
/// flagged when truncated instead of looking complete.
const SIDECAR_EDGE_CAP : Int32 = 8192

///|
/// Bound on the edge-diagnostic maps; collision accounting is best-effort and
/// must not grow without limit.
const EDGE_DIAG_CAP : Int32 = 200000

///|
/// MoonBit-native fuzz driver.
///
/// The process model is deliberately the same as the Python driver:
///   T1  moonc syncheck          (~10 ms)  lexer/parser
///   T2  moonc build-package     (~30 ms)  typer/IR/wasm codegen
/// Crashes are classified with the same markers and persisted under
/// `<out>/findings/<stage>/<kind>/<signature>/`.
///
/// Parallelism is async child-process fan-out, not CPU threads.  MoonBit's
/// event loop can keep 100+ `moonc` children in flight; each worker owns its
/// own temp directory, so there is no shared mutable process state.
struct Config {
  mut root : String
  mut out : String
  mut workers : Int32
  mut duration_s : Int32
  mut p_deep : Double
  mut p_run : Double
  mut body_only : Bool
  mut mode : String
  mut seed_dir : String
  mut fmt_check : Bool
  mut native_diff : Bool
  mut seed : UInt64
  mut run_id : String
  mut campaign : String
  mut qemu : String
  mut trace_t1 : Double
  mut trace_t2 : Double
  mut trace_t3 : Double
  mut trace_workers : Int32
  mut trace_queue : Int32
  mut trace_max_mb : Int32
  mut trace_wait_ms : Int32
  mut trace_cpu_pct : Int32
  mut baseline_seeds : Int32
  mut edge_cap : Int32
  mut parent_cap : Int32
  mut persist_cap : Int32
  /// Independent budget for coverage witnesses.  Sharing the behaviour budget
  /// meant that a full behaviour corpus silently stopped writing new coverage
  /// evidence (P0-2).
  mut coverage_cap : Int32
  /// Cap on the per-campaign novelty bookkeeping maps (`inputs`, `sigs`,
  /// `diag_families`, T2/T3 input sets).  They are statistics, not scheduling
  /// state; a 30-minute soak showed RSS still growing with iteration count, and
  /// these maps are part of that growth.
  mut stats_cap : Int32
  /// When false, edge novelty still updates the universe but does not add the
  /// +8 parent reward.  This is the "function-only" arm of the feedback A/B.
  mut edge_reward : Bool
  /// Soft self-limit on harness RSS (MiB).  The monitor stops the campaign
  /// cleanly when the limit is crossed; 0 disables it.  This is the in-process
  /// half of the resource top; the outer half is prlimit in the soak script.
  mut rss_limit_mb : Int32
  /// Baseline traces may need a much larger log than mutation traces: U0 is
  /// built from real seed inputs, and a 64 MiB cap silently truncated them,
  /// leaving U0 incomplete and coverage learning off for the whole campaign.
  mut baseline_trace_max_mb : Int32
  /// Percentage of iterations seeded from a type-valid IR program instead of
  /// a byte mutation.  This is the "deep queue" wired into the main campaign.
  mut deep_p : Double
  /// Run cmd/triage rules over the saved candidates at campaign end.
  mut triage_after : Bool
  /// Triages an existing findings tree and exits (used by the acceptance
  /// control, and to re-triage a past run).
  mut triage_only : String
  /// Write one finding through the real `@corpus.save_finding` path and exit.
  /// Used by the triage positive control so the fixture is not hand-written.
  mut emit_finding : String
  /// Coverage state from a previous epoch: per-key function unions and the
  /// edge universe.  Without it, an epoch restart resets by_key and every
  /// carried input looks novel again.
  mut coverage_state : String
  mut coverage_write : String
  mut recover : Bool
  /// Package lane: a whole package (moon.pkg/deps/argv) instead of flat files.
  mut pkg_seed : String
  mut pkg_file : String
  mut pkg_argv : String
  mut pkg_run_argv : String
  mut pkg_run_argv_b : String
  mut pkg_run_cmd_b : String
  t1_timeout : Int32
  t2_timeout : Int32
}

///|
struct Stats {
  mut it : Int32
  mut t1 : Int32
  mut t2 : Int32
  mut t2_ok : Int32
  mut t3_ok : Int32
  mut t3_diff : Int32
  mut t3_runtime : Int32
  mut t3_inconclusive : Int32
  mut t3_semantic_diff : Int32
  mut t3_accept_diff : Int32
  /// Deep-lane semantic T3: reference interpreter output vs wasm-gc stdout.
  mut deep_t3_attempts : Int32
  mut deep_t3_matched : Int32
  mut deep_t3_distinct : Int32
  mut deep_t3_mismatch : Int32
  mut deep_t3_inconclusive : Int32
  /// Phase attribution for the edge-reward throughput question.
  mut ms_mutate : Int64
  mut ms_t1 : Int64
  mut ms_t2 : Int64
  /// Size accounting for the T1-cost question: mutated bytes vs parent bytes.
  mut bytes_src : Int64
  mut bytes_parent : Int64
  mut pkg_t3_attempts : Int32
  mut pkg_t3_ok : Int32
  mut pkg_t3_fail : Int32
  mut pkg_t3_distinct : Int32
  mut backend_attempts : Int32
  mut backend_witnesses : Int32
  mut backend_excluded : Int32
  mut t3_compiler_abort : Int32
  mut diff_attempts : Int32
  mut diff_nonempty : Int32
  mut finding_candidates : Int32
  mut finding_duplicates : Int32
  mut crashes : Int32
  mut witnesses : Int32
  mut timeouts : Int32
  sigs : Map[String, Unit]
  diag_families : Map[String, Unit]
  inputs : Map[String, Unit]
  t2_inputs : Map[String, Unit]
  t2_ok_inputs : Map[String, Unit]
  diff_inputs : Map[String, Unit]
}

///|

///|
/// Admission for the novelty-statistics maps.  Refusing a new key after the
/// cap keeps RSS bounded; the counters still increment, so `it`/`t1` stay
/// exact and only the distinct-set sizes stop growing.
fn stats_admit(cfg : Config, m : Map[String, Unit]) -> Bool {
  m.length() < cfg.stats_cap
}

///|
fn stats_new() -> Stats {
  {
    it: 0,
    t1: 0,
    t2: 0,
    t2_ok: 0,
    t3_ok: 0,
    t3_diff: 0,
    t3_runtime: 0,
    t3_inconclusive: 0,
    t3_semantic_diff: 0,
    t3_accept_diff: 0,
    deep_t3_attempts: 0,
    deep_t3_matched: 0,
    deep_t3_distinct: 0,
    deep_t3_mismatch: 0,
    deep_t3_inconclusive: 0,
    ms_mutate: 0L,
    ms_t1: 0L,
    ms_t2: 0L,
    bytes_src: 0L,
    bytes_parent: 0L,
    pkg_t3_attempts: 0,
    pkg_t3_ok: 0,
    pkg_t3_fail: 0,
    pkg_t3_distinct: 0,
    backend_attempts: 0,
    backend_witnesses: 0,
    backend_excluded: 0,
    t3_compiler_abort: 0,
    diff_attempts: 0,
    diff_nonempty: 0,
    finding_candidates: 0,
    finding_duplicates: 0,
    crashes: 0,
    witnesses: 0,
    timeouts: 0,
    sigs: Map([]),
    diag_families: Map([]),
    inputs: Map([]),
    t2_inputs: Map([]),
    t2_ok_inputs: Map([]),
    diff_inputs: Map([]),
  }
}

///|
/// Campaign-wide counters for periodic snapshots.  Updates happen in the
/// cooperative async event loop, so no lock is needed around these fields.
struct Progress {
  mut it : Int32
  mut t1 : Int32
  mut t2 : Int32
  mut t2_ok : Int32
  mut t3_ok : Int32
  mut t3_diff : Int32
  mut t3_runtime : Int32
  mut t3_inconclusive : Int32
  mut diff_attempts : Int32
  mut diff_nonempty : Int32
  mut finding_candidates : Int32
  mut finding_duplicates : Int32
  mut crashes : Int32
  mut witnesses : Int32
  /// Non-empty when the harness stopped itself before the duration expired.
  /// "memory" means it hit --rss-limit-mb; the summary is still written.
  deep_matched : Map[String, Unit]
  mut stop_reason : String
  mut trace_completed : Int32
  mut trace_failed : Int32
  mut trace_dropped : Int32
  mut done : Int32
}

///|
fn progress_new() -> Progress {
  {
    it: 0,
    t1: 0,
    t2: 0,
    t2_ok: 0,
    t3_ok: 0,
    t3_diff: 0,
    t3_runtime: 0,
    t3_inconclusive: 0,
    diff_attempts: 0,
    diff_nonempty: 0,
    finding_candidates: 0,
    finding_duplicates: 0,
    crashes: 0,
    witnesses: 0,
    deep_matched: Map([]),
    stop_reason: "",
    trace_completed: 0,
    trace_failed: 0,
    trace_dropped: 0,
    done: 0,
  }
}

///|
/// One retained input.  `energy` is the mutation budget: inputs that added
/// compiler functions get selected more often; ordinary seeds stay at 1.
/// Edge novelty is a strictly smaller additive bonus on top of these weights.
///
/// `hash` is the content SHA-1 used as the index key, cached so eviction does
/// not have to re-hash the victim.  `seq` is the admission counter, used only
/// to break equal-energy eviction ties in favour of the oldest parent, which
/// keeps the replacement policy independent of array slot history.
struct Parent {
  src : String
  hash : String
  mut cov : @cov.FuncSet
  mut energy : Int32
  seq : Int64
}

///|
/// Bounded shared corpus for the whole campaign.  With N workers this is the
/// only place parent selection reads from, so a discovery in worker 3 is
/// visible to worker 7 on its next iteration.
///
/// Growth policy: at `cap` entries a new input evicts the retained parent with
/// the lowest energy (ties: oldest `seq`).  Eviction is a pure function of the
/// current pool and the admission order, so it needs no RNG and is
/// deterministic for a fixed sequence of upserts.  The newcomer is always
/// admitted, so a saturated pool keeps turning over instead of freezing; the
/// energy ranking decides which parents survive over time.
///
/// Evicted hashes are remembered in a bounded ring (`tombstones` /
/// `tomb_ring`, at most `cap` entries).  A re-offered evicted input is
/// refused, so a replayed corpus/seed load cannot silently re-admit it in the
/// same campaign.  The ring forgets the oldest tombstones first, so memory
/// stays O(cap) over a multi-hour run; the guarantee therefore covers the most
/// recent `cap` evictions, which is the window in which the driver re-observes
/// a just-evicted content.  (The driver never scans its own `out/corpus` back
/// into `Feedback` at all — persisted sources are replay evidence, not a
/// resumed parent pool — so there is no older, silent re-entry path.)
struct Feedback {
  mut cap : Int32
  entries : Array[Parent]
  index : Map[String, Int32]
  mut seen : Int32
  mut evicted : Int32
  /// Number of evictions that had to take a parent owning a unique feature,
  /// because every retained parent owned at least one.
  mut protected_forced : Int32
  /// How many retained parents own each feature.  Updated incrementally so
  /// eviction can protect the last owner without a full rescan.
  feature_owners : Map[String, Int32]
  mut next_seq : Int64
  tombstones : Map[String, Unit]
  tomb_ring : Array[String]
  mut tomb_pos : Int32
}

///|
fn feedback_new() -> Feedback {
  {
    cap: PARENT_CAP_DEFAULT,
    entries: [],
    index: Map([]),
    seen: 0,
    evicted: 0,
    protected_forced: 0,
    feature_owners: Map([]),
    next_seq: 0L,
    tombstones: Map([]),
    tomb_ring: [],
    tomb_pos: 0,
  }
}

///|
/// Remember one evicted content hash.  The ring is capped at `cap`, matching
/// the parent pool, and overwrites the oldest tombstone first.
fn feedback_tombstone(f : Feedback, h : String) -> Unit {
  if f.cap <= 0 {
    return
  }
  f.tombstones.set(h, ())
  if f.tomb_ring.length() < f.cap {
    f.tomb_ring.push(h)
  } else if f.tomb_ring.length() > 0 {
    let old = f.tomb_ring[f.tomb_pos]
    f.tombstones.remove(old)
    f.tomb_ring[f.tomb_pos] = h
    f.tomb_pos = (f.tomb_pos + 1) % f.tomb_ring.length()
  }
}

///|
/// `added` is the number of new `camlMoonc*` function names in this trace;
/// `new_edges` is the number of new exact TB edge keys from the **different,
/// wider** all-mapped scope.  The function term is unchanged and remains
/// primary; the edge term is additive and smaller.  Edge-only inputs get a
/// modest bump rather than the top-tier function bonus.
///
/// The return value says whether a *new* parent was admitted; energy updates
/// to an already-retained parent return false.  Admission is capped (see
/// `Feedback`); a refused or evicted input is still executed and still counts
/// toward coverage, it just is not retained as a parent.
fn owner_add(m : Map[String, Int32], key : String) -> Unit {
  let n = match m.get(key) {
    Some(v) => v
    None => 0
  }
  m.set(key, n + 1)
}

///|
fn owner_sub(m : Map[String, Int32], key : String) -> Unit {
  match m.get(key) {
    Some(v) => if v <= 1 { m.remove(key) } else { m.set(key, v - 1) }
    None => ()
  }
}

///|
/// True when evicting this parent would drop the last copy of some feature.
fn owns_unique(f : Feedback, e : Parent) -> Bool {
  for k in e.cov.sorted() {
    match f.feature_owners.get(k) {
      Some(1) => return true
      _ => ()
    }
  }
  false
}

///|
fn feedback_upsert(
  f : Feedback,
  src : String,
  cov : @cov.FuncSet,
  added : Int32,
  new_edges : Int32,
) -> Bool {
  let h = @corpus.sha1_hex(src)
  let base = if added > 0 {
    FUNC_NOVELTY_BONUS
  } else if cov.len() > 0 {
    KNOWN_FUNC_BONUS
  } else {
    1
  }
  let bonus = if new_edges > 0 { base + EDGE_NOVELTY_BONUS } else { base }
  match f.index.get(h) {
    Some(i) => {
      let e = f.entries[i]
      for k in cov.difference(e.cov).sorted() {
        owner_add(f.feature_owners, k)
      }
      e.cov = e.cov.union(cov)
      if e.energy < 64 {
        e.energy = e.energy + bonus
      }
      false
    }
    None => {
      // Refuse content whose eviction tombstone is still remembered.
      if f.tombstones.contains(h) || f.cap <= 0 {
        return false
      }
      if f.entries.length() < f.cap {
        let i = f.entries.length()
        f.index.set(h, i)
        for k in cov.sorted() {
          owner_add(f.feature_owners, k)
        }
        f.entries.push({ src, hash: h, cov, energy: bonus, seq: f.next_seq, })
        f.next_seq = f.next_seq + 1L
        f.seen += 1
        return true
      }
      // Full: lowest-energy, oldest-first-on-tie, but never the last owner of
      // a feature unless every entry owns one (then the count is reported).
      let mut victim = -1
      let mut j = 0
      while j < f.entries.length() {
        let e = f.entries[j]
        if !owns_unique(f, e) {
          if victim < 0 {
            victim = j
          } else {
            let v = f.entries[victim]
            if e.energy < v.energy || (e.energy == v.energy && e.seq < v.seq) {
              victim = j
            }
          }
        }
        j += 1
      }
      if victim < 0 {
        // Every retained parent owns a feature that nobody else owns.
        // Evicting one would silently drop the last replayable owner, so the
        // admission is refused and counted instead.
        f.protected_forced += 1
        return false
      }
      let old = f.entries[victim]
      for k in old.cov.sorted() {
        owner_sub(f.feature_owners, k)
      }
      // The newcomer's features must be registered too; the replacement branch
      // used to skip this, leaving the ownership map short by one parent.
      for k in cov.sorted() {
        owner_add(f.feature_owners, k)
      }
      f.index.remove(old.hash)
      feedback_tombstone(f, old.hash)
      f.entries[victim] = { src, hash: h, cov, energy: bonus, seq: f.next_seq, }
      f.next_seq = f.next_seq + 1L
      f.index.set(h, victim)
      f.evicted += 1
      f.seen += 1
      true
    }
  }
}

///|
fn feedback_pick(f : Feedback, rng : @mutate.Rng) -> String? {
  if f.entries.length() == 0 {
    return None
  }
  let mut total = 0
  for e in f.entries {
    total = total + 1 + e.energy
  }
  if total <= 0 {
    return None
  }
  let mut r = rng.int(total)
  for e in f.entries {
    let w = 1 + e.energy
    if r < w {
      e.energy = if e.energy > 1 { e.energy - 1 } else { 1 }
      return Some(e.src)
    }
    r = r - w
  }
  Some(f.entries[f.entries.length() - 1].src)
}

///|
struct CovCtx {
  enabled : Bool
  qemu : String
  sym : @trace.SymTab
  config_hash : String
  moonc : String
  builtin : String
  prelude : String
  all_pkgs : String
  pkg : String
  bundle : String
  core_dir : String
  pkg_config : String
}

///|
struct TraceTask {
  stage : @trace.TraceStage
  input_hash : String
  config_hash : String
  src : String
  compiled : String
  fname : String
  core_path : String
  baseline : Bool
  /// "deep" for the IR lane; those tasks never reward ordinary parents.
  lane : String
  /// Time reserved at dequeue time.  In-flight work must count toward the
  /// stage share or several workers can all dequeue the same oversubscribed
  /// stage before any completion is recorded.
  reserved_ms : Int64
}

///|
struct TraceQueue {
  tasks : Array[TraceTask]
  seen : Map[String, Unit]
  mut closed : Bool
  mut dropped : Int32
  mut fast_done : Int32
  mut completed : Int32
  mut accepted : Int32
  mut rejected : Int32
  mut aborts : Int32
  mut failed : Int32
  mut fail_timeout : Int32
  mut fail_too_large : Int32
  mut fail_empty : Int32
  mut fail_collector : Int32
  mut fail_other : Int32
  /// Backpressure state.  Workers wait for room instead of dropping
  /// immediately; every wait ends on room, the wait cap, the campaign
  /// deadline, or q.stop.
  mut stop : Bool
  mut deadline : UInt64
  mut wait_events : Int32
  mut wait_ms_total : Int64
  mut deferred : Int32
  mut deferred_queue_full : Int32
  mut deferred_timeout : Int32
  mut deferred_close : Int32
  mut draining : Bool
  mut drain_deadline : UInt64
  mut q_len_sum : Int64
  mut q_len_samples : Int32
  mut baseline_expected : Int32
  mut baseline_done : Int32
  mut baseline_failed : Int32
  mut baseline_settled : Bool
  mut baseline_complete : Bool
  mut baseline_unresolved : Int32
  mut baseline_ms : Int64
  mut t1_ms : Int64
  mut t2_ms : Int64
  mut t3_ms : Int64
  mut t1_done : Int32
  mut t2_done : Int32
  mut t3_done : Int32
  /// Consecutive T1 traces with no new function and no new edge.  When the
  /// parser side is saturated, T1 keeps burning trace slots that T2/T3 could
  /// use on behaviourally novel inputs.
  mut t1_dry : Int32
  mut t1_trace_off : Bool
  mut t1_reserved_ms : Int64
  mut t2_reserved_ms : Int64
  mut t3_reserved_ms : Int64
  mut inflight : Int32
  mut trace_ms : Int64
  mut trace_bytes : Int64
  /// Failure log lines actually written / suppressed after
  /// `TRACE_FAILURE_LOG_MAX`.  `failed` keeps counting every failed trace.
  mut failure_logged : Int32
  mut failure_skipped : Int32
}

///|
fn trace_queue_new() -> TraceQueue {
  {
    tasks: [],
    seen: Map([]),
    closed: false,
    dropped: 0,
    fast_done: 0,
    completed: 0,
    accepted: 0,
    rejected: 0,
    aborts: 0,
    failed: 0,
    fail_timeout: 0,
    fail_too_large: 0,
    fail_empty: 0,
    fail_collector: 0,
    fail_other: 0,
    stop: false,
    deadline: 0UL,
    wait_events: 0,
    wait_ms_total: 0L,
    deferred: 0,
    deferred_queue_full: 0,
    deferred_timeout: 0,
    deferred_close: 0,
    draining: false,
    drain_deadline: 0UL,
    q_len_sum: 0L,
    q_len_samples: 0,
    baseline_expected: 0,
    baseline_done: 0,
    baseline_failed: 0,
    baseline_settled: true,
    baseline_complete: true,
    baseline_unresolved: 0,
    baseline_ms: 0L,
    t1_ms: 0L,
    t2_ms: 0L,
    t3_ms: 0L,
    t1_done: 0,
    t2_done: 0,
    t3_done: 0,
    t1_dry: 0,
    t1_trace_off: false,
    t1_reserved_ms: 0L,
    t2_reserved_ms: 0L,
    t3_reserved_ms: 0L,
    inflight: 0,
    trace_ms: 0L,
    trace_bytes: 0L,
    failure_logged: 0,
    failure_skipped: 0,
  }
}

///|
fn trace_priority(task : TraceTask) -> Int32 {
  if task.baseline {
    0
  } else {
    match task.stage {
      @trace.T2 => 1
      @trace.T3 => 2
      @trace.T1 => 3
    }
  }
}

///|
fn trace_stage_ms(q : TraceQueue, stage : @trace.TraceStage) -> Int64 {
  match stage {
    @trace.T1 => q.t1_ms
    @trace.T2 => q.t2_ms
    @trace.T3 => q.t3_ms
  }
}

///|
fn trace_stage_reserved_ms(q : TraceQueue, stage : @trace.TraceStage) -> Int64 {
  match stage {
    @trace.T1 => q.t1_reserved_ms
    @trace.T2 => q.t2_reserved_ms
    @trace.T3 => q.t3_reserved_ms
  }
}

///|
fn trace_stage_done(q : TraceQueue, stage : @trace.TraceStage) -> Int32 {
  match stage {
    @trace.T1 => q.t1_done
    @trace.T2 => q.t2_done
    @trace.T3 => q.t3_done
  }
}

///|
fn trace_stage_share(stage : @trace.TraceStage) -> Int64 {
  match stage {
    @trace.T2 => 70L
    @trace.T1 => 20L
    @trace.T3 => 10L
  }
}

///|
/// Reserve an estimated cost before the trace starts.  Once at least one
/// sample exists, use its observed average; otherwise use conservative
/// defaults.  The actual elapsed time replaces this reservation on completion.
fn trace_stage_estimate(q : TraceQueue, stage : @trace.TraceStage) -> Int64 {
  let done = trace_stage_done(q, stage)
  if done > 0 {
    let avg = trace_stage_ms(q, stage) / done.to_int64()
    if avg < 10L {
      10L
    } else {
      avg
    }
  } else {
    match stage {
      @trace.T1 => 20L
      @trace.T2 => 250L
      @trace.T3 => 4000L
    }
  }
}

///|
fn trace_stage_used(q : TraceQueue, stage : @trace.TraceStage) -> Int64 {
  trace_stage_ms(q, stage) + trace_stage_reserved_ms(q, stage)
}

///|
fn trace_reserve(q : TraceQueue, task : TraceTask) -> TraceTask {
  if task.baseline {
    return task
  }
  let ms = trace_stage_estimate(q, task.stage)
  match task.stage {
    @trace.T1 => q.t1_reserved_ms += ms
    @trace.T2 => q.t2_reserved_ms += ms
    @trace.T3 => q.t3_reserved_ms += ms
  }
  q.inflight += 1
  { ..task, reserved_ms: ms, }
}

///|
fn trace_release(q : TraceQueue, task : TraceTask) -> Unit {
  if task.baseline {
    return
  }
  match task.stage {
    @trace.T1 =>
      q.t1_reserved_ms = if q.t1_reserved_ms >= task.reserved_ms {
        q.t1_reserved_ms - task.reserved_ms
      } else {
        0L
      }
    @trace.T2 =>
      q.t2_reserved_ms = if q.t2_reserved_ms >= task.reserved_ms {
        q.t2_reserved_ms - task.reserved_ms
      } else {
        0L
      }
    @trace.T3 =>
      q.t3_reserved_ms = if q.t3_reserved_ms >= task.reserved_ms {
        q.t3_reserved_ms - task.reserved_ms
      } else {
        0L
      }
  }
  if q.inflight > 0 {
    q.inflight -= 1
  }
}

///|
/// Queue state is distinct from a temporary scheduling pause.  `Wait` is used
/// while another trace is in flight and every remaining stage is above its
/// share; the consumer must not clear the queue for `Wait`.
priv enum TracePick {
  Ready(TraceTask)
  Wait
  Closed
}

///|
/// Pop the highest-priority task whose stage is still below its trace-time
/// share.  In-flight estimates count toward the share.  If no stage is below
/// share and nothing is in flight, shares are mathematically unsatisfiable for
/// the current queue, so borrow the highest-priority task instead of stalling
/// forever.  If work is in flight, wait for its actual cost to replace the
/// estimate.
fn trace_pop(q : TraceQueue) -> TracePick {
  if q.tasks.length() == 0 {
    return if q.closed { Closed } else { Wait }
  }
  let total = trace_stage_used(q, @trace.T1) +
    trace_stage_used(q, @trace.T2) +
    trace_stage_used(q, @trace.T3)
  let mut best = -1
  let mut best_p = 99
  let mut any = -1
  let mut any_p = 99
  for i in 0..<q.tasks.length() {
    let task = q.tasks[i]
    if task.baseline {
      let picked = q.tasks.remove(i)
      return Ready(trace_reserve(q, picked))
    }
    let p = trace_priority(task)
    if p < any_p {
      any = i
      any_p = p
    }
    let used = trace_stage_used(q, task.stage)
    let over = total > 0L &&
      used * 100L >= total * trace_stage_share(task.stage)
    if !over && p < best_p {
      best = i
      best_p = p
    }
  }
  let choose = if best >= 0 {
    Some(best)
  } else if q.inflight > 0 {
    None
  } else if any >= 0 {
    Some(any)
  } else {
    None
  }
  match choose {
    Some(i) => Ready(trace_reserve(q, q.tasks.remove(i)))
    None => Wait
  }
}

///|
fn trace_key(task : TraceTask) -> String {
  @trace.trace_stage_name(task.stage) +
  "|" +
  task.input_hash +
  "|" +
  task.config_hash
}

///|
/// Deterministic spread sample: `k` indices over `total`, evenly spaced.
fn spread_indices(total : Int32, k : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  if total <= 0 || k <= 0 {
    return out
  }
  let n = if k < total { k } else { total }
  let mut i = 0
  while i < n {
    let idx = i * total / n
    out.push(idx)
    i += 1
  }
  out
}

///|
async fn trace_submit(
  cfg : Config,
  q : TraceQueue,
  stage : @trace.TraceStage,
  src : String,
  compiled : String,
  fname : String,
  core_path : String,
  baseline : Bool,
  config_hash : String,
  lane? : String = "",
) -> Bool {
  let task : TraceTask = {
    stage,
    input_hash: @corpus.sha1_hex(src),
    config_hash: config_hash + "|entry=" + @trace.trace_stage_name(stage),
    src,
    compiled,
    fname,
    core_path,
    baseline,
    lane,
    reserved_ms: 0L,
  }
  let key = trace_key(task)
  if q.seen.contains(key) {
    return false
  }
  if baseline {
    // Count every unique baseline attempt, including one that cannot enter
    // the queue.  Otherwise expected/done/failed would not describe the same
    // set and an incomplete U0 could look settled.
    q.baseline_expected += 1
  }
  // Track occupancy on every submit, not only when full.
  q.q_len_sum += q.tasks.length().to_int64()
  q.q_len_samples += 1
  // Baseline tasks bypass the capacity check: U0 must cover every seed, and
  // the queue is drained before the campaign starts anyway.  Dropping them
  // here was what kept `baseline_state=incomplete` on every run.
  if !baseline && q.tasks.length() >= cfg.trace_queue {
    // Bounded wait: give the trace workers room instead of dropping the
    // candidate immediately.  Waits end on room, the wait cap, the campaign
    // deadline, or q.stop (set by the monitor), so a worker can never block
    // shutdown.
    let wait_start = @env.now()
    q.wait_events += 1
    while q.tasks.length() >= cfg.trace_queue && !q.stop &&
      @env.now() < q.deadline {
      let waited = @env.now() - wait_start
      if waited >= cfg.trace_wait_ms.to_uint64() {
        break
      }
      @async.sleep(10)
    }
    q.wait_ms_total += (@env.now() - wait_start).to_int().to_int64()
    if q.tasks.length() >= cfg.trace_queue {
      q.dropped += 1
      q.deferred += 1
      let waited = @env.now() - wait_start
      if q.stop || @env.now() >= q.deadline ||
        waited >= cfg.trace_wait_ms.to_uint64() {
        q.deferred_timeout += 1
      } else {
        q.deferred_queue_full += 1
      }
      return false
    }
  }
  q.seen.set(key, ())
  q.tasks.push(task)
  if baseline {
    q.baseline_settled = false
    q.baseline_complete = false
  }
  true
}

///|
struct PendingTrace {
  task : TraceTask
  result : @trace.TraceResult
  /// Edge keys this trace contributed when it completed.  Stored because the
  /// campaign-wide edge universe is updated immediately, while the reward is
  /// deferred until the baseline settles.
  edge_new : Int32
}

///|
/// Campaign coverage universe.
///
/// `by_key` / `evidence` / `baseline_total` / `observed_total` remain the
/// historical `camlMoonc*` **function** scope.  `edge_seen` is a separate,
/// wider scope: exact `"<pc0>,<pc1>"` keys for TB transitions whose BOTH
/// endpoints map to any symbol.  The two scopes are deliberately not merged
/// and their counts are not comparable.
///
/// `edge_seen` is capped at `edge_cap` keys for the whole campaign.  Once an
/// insertion would exceed the cap the universe is marked `edge_saturated`,
/// stops adding, and reports `new_edges == 0` from then on.  Existing keys are
/// still recognized during that phase; nothing is silently evicted.
struct TraceUniverse {
  by_key : Map[String, @cov.FuncSet]
  evidence : Map[String, @cov.FuncSet]
  pending : Array[PendingTrace]
  rewarded : Map[String, Unit]
  mut baseline_total : @cov.FuncSet
  /// Per (stage|outcome|config) union of baseline functions.  Seeded into
  /// `by_key` when U0 settles, otherwise the first candidate trace per key
  /// counts every baseline function as novel and every input gets rewarded.
  baseline_by_key : Map[String, @cov.FuncSet]
  mut observed_total : @cov.FuncSet
  mut coverage_adds : Int32
  edge_seen : Map[String, Unit]
  mut edge_cap : Int32
  mut edge_saturated : Bool
  mut new_edges : Int32
  /// Edge-universe accounting by source: baseline vs mutation stages.  This is
  /// what a saturation diagnosis needs; `new_edges` alone cannot say when the
  /// cap was reached or which stage was still contributing.
  mut edge_new_baseline : Int32
  mut edge_new_t1 : Int32
  mut edge_new_t2 : Int32
  mut edge_new_t3 : Int32
  /// Universe size frozen when U0 settled (0 if baseline never settled).
  mut edge_at_settle : Int32
  /// Edges offered after the universe was already saturated (all refused).
  mut edge_refused : Int32
  /// Edge keys are namespaced by (binary, config, mode).  A raw key seen under
  /// two identities is a collision the old global namespace silently merged.
  edge_raw_owner : Map[String, String]
  edge_collided : Map[String, Unit]
  mut edge_collisions : Int32
  /// Shared budget for full-input evidence on disk (`--persist-cap`).  It is
  /// campaign-wide, so every worker and every trace path uses this object.
  persist : PersistBudget
  /// Checkpoint metadata written with the state: schema epoch, cumulative
  /// cases, parent owner count, and the last admitted input hash.
  mut state_epoch : Int32
  mut checkpoint_cases : Int32
  mut case_base : Int32
  mut adds_base : Int32
  mut owner_base : Int32
  mut checkpoint_owners : Int32
  mut last_input_hash : String
  mut checkpoint_adds : Int32
  mut state_config_hash : String
  mut state_pin_hash : String
  mut state_corpus_hash : String
}

///|
fn trace_universe_new() -> TraceUniverse {
  {
    by_key: Map([]),
    evidence: Map([]),
    pending: [],
    rewarded: Map([]),
    baseline_total: @cov.FuncSet::new([]),
    baseline_by_key: Map([]),
    observed_total: @cov.FuncSet::new([]),
    coverage_adds: 0,
    edge_seen: Map([]),
    edge_cap: EDGE_CAP_DEFAULT,
    edge_saturated: false,
    new_edges: 0,
    edge_new_baseline: 0,
    edge_new_t1: 0,
    edge_new_t2: 0,
    edge_new_t3: 0,
    edge_at_settle: 0,
    edge_refused: 0,
    edge_raw_owner: Map([]),
    edge_collided: Map([]),
    edge_collisions: 0,
    persist: persist_budget_new(PERSIST_CAP_DEFAULT, 4000),
    state_epoch: 1,
    checkpoint_cases: 0,
    case_base: 0,
    adds_base: 0,
    owner_base: 0,
    checkpoint_owners: 0,
    last_input_hash: "",
    checkpoint_adds: 0,
    state_config_hash: "",
    state_pin_hash: "",
    state_corpus_hash: "",
  }
}

///|
/// Insert one trace's exact mapped-edge keys and return the number of keys
/// that were genuinely new to the campaign universe.
///
/// This is a real set difference (membership test per key), never a constant.
/// The cap is checked before every insertion.  When the cap is reached the
/// universe saturates and later calls return 0 without adding anything, so a
/// saturated run cannot silently drop a subset of keys and still claim exact
/// novelty.
///
/// The return value is the delta for this trace; `TraceUniverse.new_edges`
/// only accumulates deltas from non-baseline traces (see `trace_apply`), so
/// baseline keys for U0 seed the universe without inflating the scheduler
/// novelty counter.
///|
/// Edge novelty in an identity-scoped namespace.  `identity` should contain
/// the compiler binary hash, the config id and the mode; the raw TB pair is
/// only unique inside that namespace.
fn edge_universe_add_scoped(
  cov : TraceUniverse,
  identity : String,
  keys : Array[String],
) -> Int32 {
  let mut added = 0
  for raw in keys {
    // Collision accounting first, even when the scoped key is new: this is
    // what the old one-namespace map was hiding.
    match cov.edge_raw_owner.get(raw) {
      Some(prev) =>
        if prev != identity && !cov.edge_collided.contains(raw) &&
          cov.edge_collided.length() < EDGE_DIAG_CAP {
          cov.edge_collided.set(raw, ())
          cov.edge_collisions += 1
        }
      None =>
        if cov.edge_raw_owner.length() < EDGE_DIAG_CAP {
          cov.edge_raw_owner.set(raw, identity)
        }
    }
  }
  if cov.edge_saturated {
    return 0
  }
  for raw in keys {
    let k = identity + "@" + raw
    if cov.edge_seen.contains(k) {
      continue
    }
    if cov.edge_seen.length() >= cov.edge_cap {
      cov.edge_saturated = true
      break
    }
    cov.edge_seen.set(k, ())
    added += 1
  }
  added
}

///|
fn edge_status(cov : TraceUniverse) -> String {
  if cov.edge_saturated {
    "degraded_cap"
  } else {
    "ok"
  }
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let isdir = @fs.is_dir(path) catch { _ => false }
  if isdir {
    let names = @fs.read_dir(path) catch { _ => [] }
    for n in names {
      rm_rf(join(path, n))
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn write(path : String, text : String) -> Bool {
  @corpus.ensure_dir(@corpus.dirname(path))
  @fs.write_string_to_file(path, text) catch {
    _ => return false
  }
  true
}

///|
fn has_main(src : String) -> Bool {
  src.find("fn main") is Some(_)
}

///|
fn with_main(src : String) -> String {
  if has_main(src) {
    src
  } else {
    src + "\n\nfn main { () }\n"
  }
}

///|
fn diag_codes(blob : String) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  let n = blob.length()
  let mut i = 0
  while i + 6 < n {
    let c0 = blob.get_char(i)
    let c1 = blob.get_char(i + 1)
    let c6 = blob.get_char(i + 6)
    if c0 == Some('[') &&
      c6 == Some(']') &&
      (c1 == Some('E') || c1 == Some('W')) {
      let mut digits = true
      for k in 2..<6 {
        match blob.get_char(i + k) {
          Some(c) => if c < '0' || c > '9' { digits = false }
          None => digits = false
        }
      }
      if digits {
        let code = blob.exact_view(start=i + 1, end=i + 6).to_owned()
        if !seen.contains(code) {
          seen.set(code, ())
          out.push(code)
        }
      }
    }
    i += 1
  }
  out.sort()
  out
}

///|
fn truncate_chars(s : StringView, n : Int32) -> String {
  if s.char_length() <= n {
    s.to_owned()
  } else {
    s.exact_view(start=0, end=n).to_owned()
  }
}

///|
/// Parse one `-error-format json` diagnostic line.  The compiler emits one
/// object per line:
///   {"$message_type":"diagnostic","level":"error","error_code":3002,...}
/// The old `[E3002]`-only extractor merged every parse error into `ERR`, which
/// made the fuzz feedback loop blind.  Keep the code *and* the low-cardinality
/// context (message/location) so distinct diagnostics remain distinguishable.
struct JsonDiagPart {
  tagged : String
  msg : String
  loc : String
}

///|
fn json_diag_part(line : StringView) -> JsonDiagPart? {
  let parsed = @json.parse(line) catch { _ => return None }
  match parsed {
    Object(obj) => {
      let level = match obj.get("level") {
        Some(String(s)) => s
        _ => "error"
      }
      let code = match obj.get("error_code") {
        Some(Number(n, ..)) => n.to_int().to_string()
        Some(String(s)) => s
        _ =>
          match obj.get("warning_code") {
            Some(Number(n, ..)) => n.to_int().to_string()
            Some(String(s)) => s
            _ => ""
          }
      }
      let loc = match obj.get("loc") {
        Some(String(s)) => s
        _ => ""
      }
      let msg = match obj.get("message") {
        Some(String(s)) => truncate_chars(s, 160)
        _ => ""
      }
      if code == "" && msg == "" {
        None
      } else {
        let prefix = if level == "warning" { "W" } else { "E" }
        let tagged = if code.has_prefix("E") || code.has_prefix("W") {
          code
        } else {
          prefix + code
        }
        Some({ tagged, msg, loc, })
      }
    }
    _ => None
  }
}

///|
fn json_diag_sig(line : StringView) -> String? {
  match json_diag_part(line) {
    Some(p) => Some(p.tagged + "|" + p.msg + "|" + p.loc)
    None => None
  }
}

///|
fn json_diag_family(line : StringView) -> String? {
  match json_diag_part(line) {
    Some(p) => Some(p.tagged + "|" + p.msg)
    None => None
  }
}

///|
/// Stable T1 behaviour signature.  JSON diagnostics are parsed structurally;
/// legacy bracket codes remain as a fallback for non-JSON tool output.
fn behavior_sig_impl(
  stage : String,
  r : @exec.RunResult,
  with_loc : Bool,
) -> String {
  let seen : Map[String, Unit] = Map([])
  let parts : Array[String] = []
  let blob = r.stderr + "\n" + r.stdout
  for line in blob.split("\n") {
    let t = line.trim()
    if t.has_prefix("{") {
      let detail = if with_loc { json_diag_sig(t) } else { json_diag_family(t) }
      match detail {
        Some(s) =>
          if !seen.contains(s) {
            seen.set(s, ())
            parts.push(s)
          }
        None => ()
      }
    }
  }
  if parts.length() == 0 {
    for c in diag_codes(blob) {
      if !seen.contains(c) {
        seen.set(c, ())
        parts.push(c)
      }
    }
  }
  parts.sort()
  let status = if r.timed_out {
    "HANG"
  } else if r.rc == 0 {
    "ACC"
  } else {
    "ERR"
  }
  let b = StringBuilder()
  b.write_string(stage)
  b.write_string("|")
  b.write_string(status)
  for p in parts {
    b.write_string("|")
    b.write_string(p)
  }
  if parts.length() == 0 && r.rc != 0 {
    b.write_string("|rc=")
    b.write_string(r.rc.to_string())
  }
  b.to_string()
}

///|
/// Stable T1 behaviour signature.  JSON diagnostics are parsed structurally;
/// legacy bracket codes remain as a fallback for non-JSON tool output.
fn behavior_sig(stage : String, r : @exec.RunResult) -> String {
  behavior_sig_impl(stage, r, true)
}

///|
/// Scheduler-facing family: same error code and message, location omitted.
/// Full signatures remain the evidence key; families prevent a moved token
/// from looking like a new exploration direction.
fn behavior_family(stage : String, r : @exec.RunResult) -> String {
  behavior_sig_impl(stage, r, false)
}

///|
fn tail_text(s : String, n : Int32) -> String {
  if s.length() <= n {
    s
  } else {
    s[s.length() - n:].to_owned()
  }
}

///|
fn meta_json(
  stage : String,
  kind : String,
  detail : String,
  r : @exec.RunResult,
  sig : String,
  worker : Int32,
) -> String {
  let b = StringBuilder()
  b.write_string("{\"stage\":\"")
  b.write_string(stage)
  b.write_string("\",\"kind\":\"")
  b.write_string(kind)
  b.write_string("\",\"detail\":\"")
  b.write_string(@corpus.json_escape(detail))
  b.write_string("\",\"signature\":\"")
  b.write_string(@corpus.json_escape(sig))
  // A saved finding is a candidate until `cmd/verify` re-runs it on a fresh
  // copy.  Nothing in the campaign may call it confirmed.
  b.write_string("\",\"status\":\"candidate")
  b.write_string("\",\"rc\":")
  b.write_string(r.rc.to_string())
  b.write_string(",\"ms\":")
  b.write_string(r.ms.to_string())
  b.write_string(",\"timed_out\":")
  b.write_string(if r.timed_out { "true" } else { "false" })
  b.write_string(",\"stderr_tail\":\"")
  b.write_string(@corpus.json_escape(tail_text(r.stderr, 4000)))
  b.write_string("\",\"stdout_tail\":\"")
  b.write_string(@corpus.json_escape(tail_text(r.stdout, 2000)))
  b.write_string("\",\"worker\":")
  b.write_string(worker.to_string())
  b.write_string("}")
  b.to_string()
}

///|
/// Crash evidence is a candidate and is never budget-gated: the input is
/// force-copied into the corpus, then the finding directory is written.

///|
/// Defect classification goes through the shared oracle layer (`@judge`), not
/// only the legacy marker matcher.  The legacy name is still returned for the
/// ordinary outcomes (`OK`, `ERR`, `HANG`) so the stage logic keeps working;
/// for a real defect the judge's class wins, because that is the vocabulary the
/// regression suite and the evidence documents use.
fn judged_kind(stage : String, r : @exec.RunResult) -> String {
  let obs = @stager.observation_of(stage, r)
  for f in @judge.check_all(@judge.registry(), obs) {
    if @judge.severity_name(f.severity) == "defect" {
      return f.class
    }
  }
  @exec.classify(r)
}

///|
fn save_crash(
  cfg : Config,
  pb : PersistBudget,
  stage : String,
  r : @exec.RunResult,
  src : String,
  worker : Int32,
) -> Bool {
  let kind = judged_kind(stage, r)
  let detail = @exec.ice_detail(r)
  // Root-cause bucket: normalised ICE text / top frame / known class, not a
  // hash of the stage and the volatile first error line.
  let sig = @cluster.crash_signature(kind, r.rc, r.stderr, r.stdout)
  force_persist_source(cfg, pb, src)
  @corpus.save_finding(
    cfg.out,
    stage,
    kind,
    sig,
    src,
    meta_json(stage, kind, detail, r, sig, worker),
    fname_of(cfg.mode),
  )
}

///|
/// Campaign-wide budget for full-input evidence under `<out>/corpus`.
///
/// The unit is one distinct input content hash.  A persisted input owns one
/// source file plus its behaviour/coverage sidecars, all keyed by that hash,
/// so bounding inputs bounds the whole evidence tree.
///
/// `written` counts every input written (budgeted and forced).  `forced` is
/// the candidate subset (crash/ICE/diff), which bypasses the cap.  `skipped`
/// counts non-candidate evidence requests refused after the budget filled;
/// the run keeps executing and counting, it just stops writing new evidence.
/// `saturated` makes that visible in `summary.json`.
struct PersistBudget {
  mut cap : Int32
  sources : Map[String, Unit]
  mut written : Int32
  mut forced : Int32
  mut skipped : Int32
  mut saturated : Bool
  /// Coverage witnesses have their own budget and their own hash set, so a
  /// full behaviour corpus can no longer starve coverage evidence.
  mut coverage_cap : Int32
  covered : Map[String, Unit]
  mut coverage_written : Int32
  mut coverage_skipped : Int32
}

///|
fn persist_budget_new(cap : Int32, coverage_cap : Int32) -> PersistBudget {
  {
    cap,
    sources: Map([]),
    written: 0,
    forced: 0,
    skipped: 0,
    saturated: false,
    coverage_cap,
    covered: Map([]),
    coverage_written: 0,
    coverage_skipped: 0,
  }
}

///|
/// True when the non-candidate budget is exhausted.  Candidate (forced)
/// writes never consume the budget, so they cannot starve real evidence.
fn persist_budget_full(pb : PersistBudget) -> Bool {
  pb.written - pb.forced >= pb.cap
}

///|
/// Source bytes are stored once per content hash.  Evidence records point at
/// this file instead of duplicating the source in every coverage record.
///
/// Returns the hash when the input's source is on disk, `None` when a
/// non-candidate write was skipped because the budget is full.  Re-persisting
/// an already-written input rewrites the same path and does not consume the
/// budget a second time.

///|
/// Canonical on-disk name for one stored input.  The extension follows the
/// mode so `--seed-dir` replay loads what the campaign wrote; every mode used
/// to be stored as `.mbt`, which made pkg/mod/mbtmd restarts silently load
/// nothing.
fn corpus_file_name(h : String, mode : String) -> String {
  if mode == "pkg" {
    h + ".moon.pkg"
  } else if mode == "mod" {
    h + ".moon.mod"
  } else if mode == "mbtmd" {
    h + ".mbt.md"
  } else if mode == "mbti" {
    h + ".mbti"
  } else if mode == "mbtx" {
    h + ".mbtx"
  } else {
    h + ".mbt"
  }
}

///|
fn persist_admit(
  cfg : Config,
  pb : PersistBudget,
  src : String,
  force : Bool,
) -> String? {
  let h = @corpus.sha1_hex(src)
  let path = join(join(cfg.out, "corpus"), corpus_file_name(h, cfg.mode))
  if pb.sources.contains(h) {
    ignore(write(path, src))
    return Some(h)
  }
  if !force && persist_budget_full(pb) {
    pb.skipped += 1
    pb.saturated = true
    return None
  }
  if !write(path, src) {
    return None
  }
  pb.sources.set(h, ())
  pb.written += 1
  if force {
    pb.forced += 1
  }
  Some(h)
}

///|
/// Coverage witnesses have a separate budget.  Returning `None` here only
/// stops the sidecar from being written; the trace still ran and still updated
/// the in-memory universe, and `coverage_skipped` says so.
fn persist_admit_coverage(
  cfg : Config,
  pb : PersistBudget,
  src : String,
) -> String? {
  let h = @corpus.sha1_hex(src)
  let path = join(join(cfg.out, "corpus"), corpus_file_name(h, cfg.mode))
  if pb.covered.contains(h) {
    ignore(write(path, src))
    return Some(h)
  }
  if pb.coverage_written >= pb.coverage_cap {
    pb.coverage_skipped += 1
    return None
  }
  if !write(path, src) {
    return None
  }
  pb.covered.set(h, ())
  pb.coverage_written += 1
  Some(h)
}

///|
/// Candidate evidence is never dropped: crashes, ICEs and diff witnesses are
/// copied into the corpus even after the budget is saturated.
fn force_persist_source(cfg : Config, pb : PersistBudget, src : String) -> Unit {
  ignore(persist_admit(cfg, pb, src, true))
}

///|
/// Behaviour evidence is intentionally separate from coverage evidence.  A
/// fast-path behaviour observation must never overwrite a later trace record
/// for the same source.
fn persist_behavior(
  cfg : Config,
  pb : PersistBudget,
  src : String,
  reason : String,
) -> Unit {
  let h = match persist_admit(cfg, pb, src, false) {
    Some(h) => h
    None => return
  }
  let dir = join(join(join(cfg.out, "corpus"), "behavior"), h)
  @corpus.ensure_dir(dir)
  let meta = "{\"sha1\":\"" +
    h +
    "\",\"reason\":\"" +
    @corpus.json_escape(reason) +
    "\",\"bytes\":" +
    src.length().to_string() +
    ",\"source\":\"corpus/" +
    h +
    ".mbt\"}"
  ignore(write(join(dir, reason + ".json"), meta))
}

///|
/// One record per `(input_hash, config_hash, stage, outcome)`.  The record
/// carries the full key, so a run can reconstruct per-config/stage/outcome
/// coverage subsets without relying on the short sidecar filename.
///
/// Two scopes coexist in this JSON and must not be conflated:
///   - `coverage_funcs` is the accumulated union of `camlMoonc*` function names
///     for this key across reruns;
///   - the TB counters (`unique_pc`, `mapped_unique_pc`, `edges`,
///     `mapped_edges`), `trace_edge_keys`, and `edge_novel` describe only the
///     latest trace that produced this record (`tb_counter_scope`).
/// `trace_edge_keys` is the per-trace key count (equal to `mapped_edges` by
/// construction); `edge_novel` says whether that trace added at least one key
/// to the campaign edge universe at the time it completed.  The key set itself
/// is not persisted.
///
/// Persistence is budgeted per input content hash: once `--persist-cap` is
/// reached, traces for inputs that are not already persisted are still
/// executed and still update the in-memory evidence map, but no new sidecar is
/// written and `persist_skipped` is incremented.
fn persist_coverage(
  cfg : Config,
  pb : PersistBudget,
  task : TraceTask,
  tr : @trace.TraceResult,
  funcs : Array[String],
  edge_novel : Bool,
) -> Unit {
  let source_hash = match persist_admit_coverage(cfg, pb, task.src) {
    Some(h) => h
    None => return
  }
  let stage = @trace.trace_stage_name(tr.stage)
  let outcome = @trace.trace_outcome_name(tr.outcome)
  let dir = join(
    join(join(join(cfg.out, "corpus"), "coverage"), stage),
    outcome,
  )
  @corpus.ensure_dir(dir)
  // The full config hash contains separators; hash it for a stable filename
  // while keeping the complete value in the JSON body.
  let config_name = @corpus.sha1_hex(tr.config_hash)
  // Persist a bounded prefix of the actual edge keys, not just their count, so
  // a restart can rebuild feature ownership for this (input, config).
  let capped_keys : Array[String] = []
  let mut ki = 0
  while ki < tr.edge_keys.length() && ki < SIDECAR_EDGE_CAP {
    capped_keys.push(tr.edge_keys[ki])
    ki += 1
  }
  let meta = "{\"input_hash\":\"" +
    tr.input_hash +
    "\",\"config_hash\":\"" +
    @corpus.json_escape(tr.config_hash) +
    "\",\"stage\":\"" +
    stage +
    "\",\"outcome\":\"" +
    outcome +
    "\",\"complete\":true,\"source_sha1\":\"" +
    source_hash +
    "\",\"source\":\"corpus/" +
    source_hash +
    ".mbt\",\"trace_rc\":" +
    tr.rc.to_string() +
    ",\"elapsed_ms\":" +
    tr.elapsed_ms.to_string() +
    ",\"trace_bytes\":" +
    tr.trace_bytes.to_string() +
    ",\"coverage_funcs\":" +
    @trace.json_string_array(funcs) +
    ",\"coverage_funcs_count\":" +
    funcs.length().to_string() +
    ",\"trace_func_count\":" +
    tr.functions.length().to_string() +
    ",\"unique_pc\":" +
    tr.unique_pc.to_string() +
    ",\"mapped_unique_pc\":" +
    tr.mapped_unique_pc.to_string() +
    ",\"edges\":" +
    tr.edges.to_string() +
    ",\"mapped_edges\":" +
    tr.mapped_edges.to_string() +
    ",\"trace_edge_keys\":" +
    tr.edge_keys.length().to_string() +
    ",\"edge_keys\":" +
    @trace.json_string_array(capped_keys) +
    ",\"edge_keys_truncated\":" +
    (if tr.edge_keys.length() > SIDECAR_EDGE_CAP { "true" } else { "false" }) +
    ",\"edge_novel\":" +
    (if edge_novel { "true" } else { "false" }) +
    ",\"tb_counter_scope\":\"latest_trace\"" +
    ",\"func_scope\":\"camlMoonc*\"" +
    ",\"edge_scope\":\"mapped_both_endpoints\"}"
  ignore(write(join(dir, tr.input_hash + "_" + config_name + ".json"), meta))
}

///|
fn file_sha1(path : String) -> String {
  let b = @fs.read_file_to_bytes(path) catch { _ => Bytes::new(0) }
  @crypto.bytes_to_hex_string(@crypto.sha1(b))
}

///|
fn moonc_path() -> String {
  @stager.tool_path("moonc")
}

///|
fn fname_of(mode : String) -> String {
  if mode == "pkg" {
    "moon.pkg"
  } else if mode == "mod" {
    "moon.mod"
  } else if mode == "mbtmd" {
    "in.mbt.md"
  } else if mode == "mbti" {
    "in.mbti"
  } else if mode == "mbtx" {
    "in.mbtx"
  } else {
    "in.mbt"
  }
}

///|
fn suffixes_of(mode : String) -> Array[String] {
  if mode == "pkg" {
    ["moon.pkg"]
  } else if mode == "mod" {
    ["moon.mod"]
  } else if mode == "mbtmd" {
    [".mbt.md"]
  } else if mode == "mbti" {
    [".mbti"]
  } else if mode == "mbtx" {
    [".mbtx"]
  } else {
    [".mbt"]
  }
}

///|
fn t1_args(
  mode : String,
  fname : String,
  builtin : String,
  prelude : String,
) -> Array[String] {
  if mode == "mbt" || mode == "pkg" || mode == "mod" || mode == "mbtmd" {
    ["syncheck", "-error-format", "json", fname]
  } else if mode == "mbti" {
    [
      "build-interface",
      fname,
      "-o",
      "out.mi",
      "-i",
      builtin + ":moonbitlang/core/builtin",
      "-i",
      prelude + ":prelude",
    ]
  } else {
    ["syncheck", "-mbtx-frontmatter", "true", fname]
  }
}

///|
fn t2_args(
  pkg : String,
  builtin : String,
  prelude : String,
  all_pkgs : String,
) -> Array[String] {
  [
    "build-package",
    "in.mbt",
    "-o",
    "out_wasm.core",
    "-pkg",
    pkg,
    "-pkg-type",
    "executable",
    "-i",
    builtin + ":moonbitlang/core/builtin",
    "-i",
    prelude + ":prelude",
    "-pkg-sources",
    pkg + ":.",
    "-target",
    "wasm",
    "-g",
    "-O0",
    "-workspace-path",
    ".",
    "-all-pkgs",
    all_pkgs,
  ]
}

///|
async fn run_t1(
  moonc : String,
  wd : String,
  mode : String,
  fname : String,
  timeout_ms : Int32,
  builtin : String,
  prelude : String,
) -> @exec.RunResult {
  @exec.run_isolated(
    moonc,
    t1_args(mode, fname, builtin, prelude),
    wd,
    timeout_ms,
    mem_mb=2048,
  )
}

///|
fn trace_baseline_state(q : TraceQueue) -> String {
  if q.baseline_expected == 0 && q.baseline_failed == 0 {
    "disabled"
  } else if !q.baseline_settled {
    "pending"
  } else if q.baseline_complete {
    "complete"
  } else {
    "incomplete"
  }
}

///|
/// `relative_new` is only meaningful against a frozen, complete U0.  A
/// disabled/pending/incomplete baseline keeps `observed_funcs` for diagnosis
/// but emits JSON null instead of a number that would look like coverage gain.
fn relative_new_json(q : TraceQueue, cov : TraceUniverse) -> String {
  if trace_baseline_state(q) == "complete" {
    cov.observed_total.difference(cov.baseline_total).len().to_string()
  } else {
    "null"
  }
}

///|
fn trace_record_evidence(
  cfg : Config,
  task : TraceTask,
  tr : @trace.TraceResult,
  covset : @cov.FuncSet,
  edge_novel : Bool,
  cov : TraceUniverse,
) -> Unit {
  let key = tr.input_hash +
    "|" +
    tr.config_hash +
    "|" +
    @trace.trace_stage_name(tr.stage) +
    "|" +
    @trace.trace_outcome_name(tr.outcome)
  let old = match cov.evidence.get(key) {
    Some(s) => s
    None => @cov.FuncSet::new([])
  }
  let all = old.union(covset)
  cov.evidence.set(key, all)
  persist_coverage(cfg, cov.persist, task, tr, all.sorted(), edge_novel)
}

///|
/// Apply one candidate trace to the function universe and, when it is novel in
/// either scope, admit/bump the parent.
///
/// `edge_new` was computed when the trace completed (the edge universe is
/// updated for every complete trace, including baseline seeds).  Function
/// novelty keeps its historical behaviour; edge-only novelty gets the small
/// additive bonus inside `feedback_upsert` instead of being ignored.
fn trace_apply_delta(
  task : TraceTask,
  tr : @trace.TraceResult,
  covset : @cov.FuncSet,
  edge_new : Int32,
  cov : TraceUniverse,
  feed : Feedback,
) -> Int32 {
  let key = @trace.trace_stage_name(tr.stage) +
    "|" +
    @trace.trace_outcome_name(tr.outcome) +
    "|" +
    tr.config_hash
  let old = match cov.by_key.get(key) {
    Some(s) => s
    None => @cov.FuncSet::new([])
  }
  let delta = covset.difference(old)
  if delta.len() > 0 {
    cov.by_key.set(key, old.union(covset))
    cov.coverage_adds += delta.len()
  }
  if delta.len() > 0 || edge_new > 0 {
    let reward_key = task.input_hash +
      "|" +
      task.config_hash +
      "|" +
      @trace.trace_stage_name(task.stage)
    if !cov.rewarded.contains(reward_key) && task.lane != "deep" {
      cov.rewarded.set(reward_key, ())
      ignore(feedback_upsert(feed, task.src, covset, delta.len(), edge_new))
    }
  }
  delta.len()
}

///|
/// Freeze U0 only after every submitted baseline task has completed or
/// failed.  Until then candidate results are buffered.  If any baseline
/// collection failed, U0 is incomplete and buffered candidates are not
/// rewarded; over-rewarding seed coverage is worse than losing that batch.
fn trace_maybe_settle_baseline(
  cov : TraceUniverse,
  feed : Feedback,
  q : TraceQueue,
) -> Unit {
  if q.baseline_settled ||
    q.baseline_done + q.baseline_failed < q.baseline_expected {
    return
  }
  q.baseline_settled = true
  cov.edge_at_settle = cov.edge_seen.length()
  if q.baseline_failed == 0 {
    q.baseline_complete = true
    // U0 becomes the initial value of every per-key universe; novelty is only
    // what a later trace adds beyond the seeds.
    for k, v in cov.baseline_by_key {
      let old = match cov.by_key.get(k) {
        Some(s) => s
        None => @cov.FuncSet::new([])
      }
      cov.by_key.set(k, old.union(v))
    }
    for p in cov.pending {
      ignore(
        trace_apply_delta(
          p.task,
          p.result,
          @cov.FuncSet::new(p.result.functions),
          p.edge_new,
          cov,
          feed,
        ),
      )
    }
    cov.pending.clear()
  } else {
    q.baseline_unresolved += cov.pending.length()
    cov.pending.clear()
  }
}

///|
/// T3 tracing links against a snapshotted `.core` copy of the worker's build
/// output.  The snapshot is only needed until `@trace.collect` has run, so it
/// is deleted as soon as the trace settles; live snapshots are therefore
/// bounded by the trace queue, not by campaign length.
fn trace_cleanup_core(task : TraceTask) -> Unit {
  if task.core_path == "" {
    return
  }
  @fs.remove_file(task.core_path) catch {
    _ => ()
  }
}

///|
fn trace_apply(
  cfg : Config,
  task : TraceTask,
  tr : @trace.TraceResult,
  cov : TraceUniverse,
  feed : Feedback,
  q : TraceQueue,
) -> Unit {
  q.trace_ms += tr.elapsed_ms
  q.trace_bytes += tr.trace_bytes
  trace_release(q, task)
  trace_cleanup_core(task)
  if !tr.complete {
    q.failed += 1
    if q.failure_logged < TRACE_FAILURE_LOG_MAX {
      q.failure_logged += 1
      @corpus.append_line(
        join(cfg.out, "trace_failures.jsonl"),
        "{\"input_hash\":\"" +
        tr.input_hash +
        "\",\"config_hash\":\"" +
        @corpus.json_escape(tr.config_hash) +
        "\",\"stage\":\"" +
        @trace.trace_stage_name(tr.stage) +
        "\",\"outcome\":\"" +
        @trace.trace_outcome_name(tr.outcome) +
        "\",\"rc\":" +
        tr.rc.to_string() +
        ",\"failure\":\"" +
        @corpus.json_escape(tr.failure) +
        "\",\"trace_bytes\":" +
        tr.trace_bytes.to_string() +
        ",\"elapsed_ms\":" +
        tr.elapsed_ms.to_string() +
        ",\"detail\":\"" +
        @corpus.json_escape(tr.detail) +
        "\"}",
      )
    } else {
      q.failure_skipped += 1
    }
    if task.baseline {
      q.baseline_failed += 1
      trace_maybe_settle_baseline(cov, feed, q)
    }
    return
  }
  q.completed += 1
  let covset = @cov.FuncSet::new(tr.functions)
  cov.observed_total = cov.observed_total.union(covset)
  // Edge keys live in the wider all-mapped scope.  Update the campaign
  // universe for every complete trace (baseline or candidate) exactly once,
  // and remember the delta so a deferred reward uses the same number.
  let identity = cfg.mode + "|" + tr.config_hash
  let edge_new = edge_universe_add_scoped(cov, identity, tr.edge_keys)
  if task.baseline {
    cov.edge_new_baseline += edge_new
  } else if task.stage == @trace.T1 {
    cov.edge_new_t1 += edge_new
  } else if task.stage == @trace.T2 {
    cov.edge_new_t2 += edge_new
  } else {
    cov.edge_new_t3 += edge_new
  }
  if cov.edge_saturated && edge_new == 0 && tr.edge_keys.length() > 0 {
    cov.edge_refused += 1
  }
  if !task.baseline {
    cov.new_edges += edge_new
  }
  trace_record_evidence(cfg, task, tr, covset, edge_new > 0, cov)
  if task.baseline {
    let key = @trace.trace_stage_name(tr.stage) +
      "|" +
      @trace.trace_outcome_name(tr.outcome) +
      "|" +
      tr.config_hash
    let old = match cov.by_key.get(key) {
      Some(s) => s
      None => @cov.FuncSet::new([])
    }
    cov.by_key.set(key, old.union(covset))
    cov.baseline_total = cov.baseline_total.union(covset)
    let bkey = @trace.trace_stage_name(tr.stage) +
      "|" +
      @trace.trace_outcome_name(tr.outcome) +
      "|" +
      tr.config_hash
    let prev = match cov.baseline_by_key.get(bkey) {
      Some(v) => v
      None => @cov.FuncSet::new([])
    }
    cov.baseline_by_key.set(bkey, prev.union(covset))
    q.baseline_done += 1
    q.baseline_ms += tr.elapsed_ms
    trace_maybe_settle_baseline(cov, feed, q)
    return
  }
  match tr.outcome {
    @trace.Accepted => q.accepted += 1
    @trace.Rejected => q.rejected += 1
    @trace.CompilerAbort => q.aborts += 1
    @trace.CollectorFailed => ()
  }
  match task.stage {
    @trace.T1 => {
      q.t1_ms += tr.elapsed_ms
      q.t1_done += 1
    }
    @trace.T2 => {
      q.t2_ms += tr.elapsed_ms
      q.t2_done += 1
    }
    @trace.T3 => {
      q.t3_ms += tr.elapsed_ms
      q.t3_done += 1
    }
  }
  if !q.baseline_settled {
    cov.pending.push({ task, result: tr, edge_new, })
    return
  }
  if !q.baseline_complete {
    q.baseline_unresolved += 1
    return
  }
  let reward_edges = if cfg.edge_reward { edge_new } else { 0 }
  let delta_len = trace_apply_delta(task, tr, covset, reward_edges, cov, feed)
  // Dryness is about the trace adding nothing NEW, not about the trace having
  // no functions at all (every T1 trace has functions).
  if task.stage == @trace.T1 && !task.baseline {
    if delta_len == 0 && reward_edges == 0 {
      q.t1_dry += 1
      if q.t1_dry >= 40 {
        q.t1_trace_off = true
      }
    } else {
      q.t1_dry = 0
    }
  }
}

///|
fn trace_drop_remaining(q : TraceQueue) -> Unit {
  for t in q.tasks {
    if t.baseline {
      q.baseline_failed += 1
      q.baseline_complete = false
    }
    trace_cleanup_core(t)
  }
  // Close-time abandonment is its own counter; `dropped` stays the
  // capacity/refusal metric so acceptance can require dropped ~ 0.
  q.deferred_close += q.tasks.length()
  q.tasks.clear()
}

///|
async fn trace_worker(
  cfg : Config,
  id : Int32,
  q : TraceQueue,
  feed : Feedback,
  cov : TraceUniverse,
  ctx : CovCtx,
  prog : Progress,
) -> Stats {
  let tag = @corpus.short_hash(cfg.run_id)
  let wd = join(join("/tmp/mbtfuzz_mb", tag), "tw" + id.to_string())
  rm_rf(wd)
  @corpus.ensure_dir(wd)
  let start = @async.now()
  let budget = if cfg.trace_cpu_pct > 0 {
    // Budget is campaign-wide trace CPU: duration * pct * trace workers.
    // The old duration*10*pct was per-worker and ignored the worker count, so
    // the 25% budget exhausted after a fraction of the wall-clock window.
    let b = cfg.duration_s.to_int64() *
      1000L *
      cfg.trace_cpu_pct.to_int64() /
      100L *
      cfg.trace_workers.to_int64()
    if b < 2000L {
      2000L
    } else {
      b
    }
  } else {
    0L
  }
  let deadline = start + cfg.duration_s.to_int64() * 1000L + 300000L
  while @async.now() < deadline {
    if q.draining &&
      (q.tasks.length() == 0 || @env.now() >= q.drain_deadline) {
      q.closed = true
      break
    }
    let task = match trace_pop(q) {
      Ready(t) => t
      Wait => {
        // Either the producer is still running, or all stages are above
        // share while another trace is in flight.  Neither is a reason to
        // discard queued work.
        @async.sleep(25)
        continue
      }
      Closed => break
    }
    // The candidate budget must never cut baseline collection: baseline is
    // the U0 and its cost is separate.
    if !task.baseline && q.baseline_complete && budget > 0L &&
      q.trace_ms - q.baseline_ms >= budget {
      trace_release(q, task)
      trace_cleanup_core(task)
      q.dropped += 1
      trace_drop_remaining(q)
      trace_maybe_settle_baseline(cov, feed, q)
      break
    }
    let args = match task.stage {
      @trace.T1 => {
        ignore(write(join(wd, task.fname), task.compiled))
        t1_args(cfg.mode, task.fname, ctx.builtin, ctx.prelude)
      }
      @trace.T2 => {
        ignore(write(join(wd, "in.mbt"), task.compiled))
        t2_args(ctx.pkg, ctx.builtin, ctx.prelude, ctx.all_pkgs)
      }
      @trace.T3 =>
        @oracle.link_args(
          "wasm",
          ctx.bundle,
          ctx.core_dir,
          ctx.pkg,
          ctx.pkg_config,
          task.core_path,
          "out_t3.wasm",
        )
    }
    let tr = @trace.collect(
      ctx.qemu,
      ctx.moonc,
      args,
      wd,
      @trace.trace_stage_name(task.stage) + "_" + id.to_string(),
      ctx.sym,
      task.input_hash,
      task.config_hash,
      task.stage,
      cfg.t2_timeout,
      (if task.baseline { cfg.baseline_trace_max_mb } else { cfg.trace_max_mb }).to_int64() *
      1048576L,
    )
    let before = q.completed
    let failed_before = q.failed
    trace_apply(cfg, task, tr, cov, feed, q)
    if q.completed > before {
      prog.trace_completed += 1
    }
    if q.failed > failed_before {
      prog.trace_failed += 1
      let f = tr.failure
      if f.has_prefix("timeout") {
        q.fail_timeout += 1
      } else if f.has_prefix("trace_too_large") {
        q.fail_too_large += 1
      } else if f.has_prefix("empty_trace") {
        q.fail_empty += 1
      } else if f.has_prefix("collector_exit") ||
        f.has_prefix("unclassified_exit") {
        q.fail_collector += 1
      } else {
        q.fail_other += 1
      }
    }
    prog.trace_dropped = q.dropped
  }
  if q.tasks.length() > 0 {
    trace_drop_remaining(q)
    trace_maybe_settle_baseline(cov, feed, q)
  }
  stats_new()
}

///|
/// A differential witness is a candidate too: force-persist the input before
/// the finding, regardless of the evidence budget.
fn save_diff(
  cfg : Config,
  pb : PersistBudget,
  r : @oracle.DiffResult,
  src : String,
  worker : Int32,
) -> Bool {
  let sig = @corpus.short_hash(
    "diff|" +
    @oracle.diff_class_name(r.verdict) +
    "|" +
    r.wasm_stage +
    "|" +
    r.js_stage +
    "|" +
    r.wasm_kind +
    "|" +
    r.js_kind +
    "|" +
    r.wasm_rc.to_string() +
    "|" +
    r.js_rc.to_string() +
    "|" +
    (if r.wasm_truncated { r.wasm_digest } else { r.wasm_out }) +
    "|" +
    (if r.js_truncated { r.js_digest } else { r.js_out }),
  )
  let b = StringBuilder()
  b.write_string("{\"stage\":\"diff\",\"kind\":\"DIFF\",\"verdict\":\"")
  b.write_string(@oracle.diff_class_name(r.verdict))
  b.write_string("\",\"signature\":\"")
  b.write_string(@corpus.json_escape(sig))
  // A saved finding is a candidate until `cmd/verify` re-runs it on a fresh
  // copy.  Nothing in the campaign may call it confirmed.
  b.write_string("\",\"status\":\"candidate")
  b.write_string("\",\"wasm_stage\":\"")
  b.write_string(r.wasm_stage)
  b.write_string("\",\"js_stage\":\"")
  b.write_string(r.js_stage)
  b.write_string("\",\"wasm_kind\":\"")
  b.write_string(r.wasm_kind)
  b.write_string("\",\"js_kind\":\"")
  b.write_string(r.js_kind)
  b.write_string("\",\"wasm_rc\":")
  b.write_string(r.wasm_rc.to_string())
  b.write_string(",\"js_rc\":")
  b.write_string(r.js_rc.to_string())
  b.write_string(",\"wasm_out\":\"")
  b.write_string(@corpus.json_escape(r.wasm_out))
  b.write_string("\",\"js_out\":\"")
  b.write_string(@corpus.json_escape(r.js_out))
  b.write_string("\",\"wasm_truncated\":")
  b.write_string(if r.wasm_truncated { "true" } else { "false" })
  b.write_string(",\"js_truncated\":")
  b.write_string(if r.js_truncated { "true" } else { "false" })
  b.write_string(",\"wasm_detail\":\"")
  b.write_string(@corpus.json_escape(tail_text(r.wasm_detail, 4000)))
  b.write_string("\",\"js_detail\":\"")
  b.write_string(@corpus.json_escape(tail_text(r.js_detail, 4000)))
  b.write_string("\",\"worker\":")
  b.write_string(worker.to_string())
  b.write_string("}")
  force_persist_source(cfg, pb, src)
  @corpus.save_finding(
    cfg.out,
    "diff",
    "DIFF",
    sig,
    src,
    b.to_string(),
    "in.mbt",
  )
}

///|
fn output_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  for line in s.split("\n") {
    out.push(line.to_owned())
  }
  while out.length() > 0 && out[out.length() - 1] == "" {
    out.pop() |> ignore
  }
  out
}

///|
fn lines_equal(a : String, expected : Array[String]) -> Bool {
  let got = output_lines(a)
  if got.length() != expected.length() {
    return false
  }
  for i, e in expected {
    if got[i] != e {
      return false
    }
  }
  true
}

///|
fn parse_after_int(s : String, marker : String) -> Int32 {
  match s.find(marker) {
    None => -1
    Some(i) => {
      let rest = s[i + marker.length():].to_owned()
      let mut n = 0
      let mut any = false
      for c in rest {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
          any = true
        } else if !any && (c == ' ' || c == '\t' || c == ':') {
          continue
        } else {
          break
        }
      }
      if any { n } else { -1 }
    }
  }
}

///|
fn failed_assertions(s : String) -> Array[String] {
  let out : Array[String] = []
  for line in s.split("\n") {
    if (line.contains("FAILED: `") || line.contains("failed:")) &&
      !line.contains("Total tests:") {
      let mut l = line.trim().to_owned()
      // Drop the backend tag ("[js] ...") so identities compare across targets.
      if l.has_prefix("[") {
        match l.find("]") {
          Some(i) => l = l[i + 1:].trim().to_owned()
          None => ()
        }
      }
      out.push(l)
    }
  }
  out.sort()
  out
}

///|
/// Cross-backend difference classification.  Test-harness metadata (headers,
/// ordering, backend name) is ignored; only pass/fail counts and failed
/// assertions are compared.  A backend that runs zero tests is excluded, not
/// reported as a difference.
fn backend_diff_class(a : String, b : String, rc_a : Int32, rc_b : Int32) -> String {
  let has_counts = a.contains("Total tests:") && b.contains("Total tests:")
  if has_counts {
    let ta = parse_after_int(a, "Total tests:")
    let tb = parse_after_int(b, "Total tests:")
    let fa = parse_after_int(a, ", failed:")
    let fb = parse_after_int(b, ", failed:")

    if ta == 0 || tb == 0 {
      return if ta == tb { "none" } else { "excluded" }
    }
    if ta != tb {
      return "excluded"
    }
    // Same failed count is not enough: A failing test X and B failing test Y
    // must be a divergence.  Compare the identities of failed tests.
    let la = failed_assertions(a)
    let lb = failed_assertions(b)
    if la.length() == lb.length() {
      let mut same = true
      for i, x in la {
        if lb[i] != x {
          same = false
        }
      }
      if same {
        return "none"
      }
    }
    return "witness"
  }
  if rc_a == rc_b && a.trim() == b.trim() {
    return "none"
  }
  let diff = a + "\n" + b

  for tok in [
    "Float", "Double", "Int64", "UInt64", "nan", "inf", "undefined",
    "timing", "GC", "debug", "elapsed", "ms)",
  ] {
    if diff.contains(tok) {
      return "excluded"
    }
  }
  "witness"
}

///|
///|
fn split_spaces(s : String) -> Array[String] {
  let out : Array[String] = []
  let b = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' {
      if b.to_string() != "" {
        out.push(b.to_string())
        b.reset()
      }
    } else {
      b.write_char(c)
    }
  }
  if b.to_string() != "" {
    out.push(b.to_string())
  }
  out
}

///|
/// Save a package-lane failure in the same layout triage's capsule mode reads.
///|
fn find_named(dir : String, name : String, prefix : String) -> String {
  let direct = join(dir, name)
  if @fs.path_exists(direct) {
    return prefix + name
  }
  for n in @stager.try_read_dir(dir) {
    let child = join(dir, n)
    let isdir = @fs.is_dir(child) catch { _ => false }
    if isdir {
      let got = find_named(child, name, prefix + n + "/")
      if got != "" {
        return got
      }
    }
  }
  ""
}

///|
fn save_pkg_witness(
  cfg : Config,
  moon : String,
  sig : String,
  kind : String,
  cmd : String,
  src : String,
  baseline : String,
  wd : String,
  file : String,
  rc : Int32,
  out : String,
  err : String,
) -> Bool {
  let fd = join(
    join(join(join(cfg.out, "findings"), "build"), kind),
    @corpus.dir_slug(sig),
  )
  if @fs.path_exists(join(fd, "meta.json")) {
    return false
  }
  @corpus.ensure_dir(fd)
  let orig = join(fd, "original")
  @corpus.ensure_dir(orig)
  // The failure scene is the working copy `wd`; `original/source.mbt` is the
  // mutant `src`, never the baseline.
  if !@stager.write_text(join(fd, "in.mbt"), src) ||
    !@stager.write_text(join(fd, "baseline.mbt"), baseline) {
    @stager.rm_rf(fd)
    return false
  }
  let copied_pkg = @stager.copy_tree(wd, join(orig, "pkg"))
  let copied_top = @stager.copy_tree(wd, join(fd, "pkg"))
  if !copied_pkg || !copied_top {
    @stager.rm_rf(fd)
    return false
  }
  let mod_rel = find_named(wd, "moon.mod", "")
  let pkg_rel = find_named(wd, "moon.pkg", "")
  if mod_rel == "" || pkg_rel == "" {
    @stager.rm_rf(fd)
    return false
  }
  let mod_src = @stager.read_text(join(wd, mod_rel))
  let pkg_src = @stager.read_text(join(wd, pkg_rel))
  let paths = "{\"moon_mod\":\"" + @stager.escape(mod_rel) +
    "\",\"moon_pkg\":\"" + @stager.escape(pkg_rel) +
    "\",\"source\":\"" + @stager.escape(file) + "\"}"
  let argv_parts = split_spaces(cmd)
  let argv_json = "[" + argv_parts.map(fn(x) { "\"" + @stager.escape(x) + "\"" }).join(",") + "]"
  let expected = "{\"rc\":" + rc.to_string() +
    ",\"stdout\":\"" + @stager.escape(out) +
    "\",\"stderr\":\"" + @stager.escape(err) + "\"}"
  // Every required file must exist and be non-empty; otherwise fail closed.
  let files : Array[(String, String)] = [
    (join(orig, "moon.mod"), mod_src),
    (join(orig, "moon.pkg"), pkg_src),
    (join(orig, "source.mbt"), src),
    (join(orig, "argv.txt"), cmd),
    (join(orig, "argv.json"), argv_json),
    (join(orig, "paths.json"), paths),
    (join(orig, "expected.json"), expected),
  ]
  for (path, text) in files {
    if text == "" || !@stager.write_text(path, text) {
      @stager.rm_rf(fd)
      return false
    }
  }
  let manifest = "{\"moon_mod\":\"" + @corpus.sha1_hex(mod_src) +
    "\",\"moon_pkg\":\"" + @corpus.sha1_hex(pkg_src) +
    "\",\"source\":\"" + @corpus.sha1_hex(src) +
    "\",\"argv\":\"" + @corpus.sha1_hex(argv_json) +
    "\",\"paths\":\"" + @corpus.sha1_hex(paths) +
    "\",\"expected\":\"" + @corpus.sha1_hex(expected) + "\"}"
  if !@stager.write_text(join(orig, "manifest.json"), manifest) {
    @stager.rm_rf(fd)
    return false
  }
  let capsule = "{\"moon\":\"" +
    @stager.escape(moon) +
    "\",\"cmd\":\"" +
    @stager.escape(cmd) +
    "\",\"build_cmd\":\"" +
    @stager.escape(cfg.pkg_argv) +
    "\",\"run_cmd\":\"" +
    @stager.escape(cfg.pkg_run_argv) +
    "\",\"file\":\"" +
    @stager.escape(file) +
    "\",\"original\":\"original\",\"stage\":\"build\",\"target\":\"\",\"signature\":\"" +
    @stager.escape(sig) +
    "\"}"
  if !@stager.write_text(join(fd, "capsule.json"), capsule) {
    @stager.rm_rf(fd)
    return false
  }
  let meta = "{\"stage\":\"build\",\"kind\":\"" +
    kind +
    "\",\"status\":\"candidate\",\"signature\":\"" +
    @stager.escape(sig) +
    "\"}"
  if !@stager.write_text(join(fd, "meta.json"), meta) {
    @stager.rm_rf(fd)
    return false
  }
  // Re-check the required files after write; a directory that merely exists
  // is not a saved witness.
  for (path, _) in files {
    if !@fs.path_exists(path) || @stager.read_text(path) == "" {
      @stager.rm_rf(fd)
      return false
    }
  }
  true
}

///|
async fn worker(
  cfg : Config,
  id : Int32,
  seeds : Array[String],
  pool : Array[String],
  dict : Array[String],
  moonc : String,
  feed : Feedback,
  covctx : CovCtx,
  prog : Progress,
  q : TraceQueue,
  pb : PersistBudget,
) -> Stats {
  if cfg.pkg_seed != "" {
    let ps = stats_new()
    let wd = join(cfg.out, "pkgwd_" + id.to_string())
    @stager.rm_rf(wd)
    if @stager.copy_tree(cfg.pkg_seed, wd) {
      @stager.rm_rf(join(wd, "_build"))
      let file = join(wd, cfg.pkg_file)
      let baseline = @stager.read_text(file)
      let argv = split_spaces(cfg.pkg_argv)
      let moon = @stager.moon_path()
      let pkg_t3_seen : Map[String, Unit] = Map([])
      let deadline = @env.now() + cfg.duration_s.to_uint64() * 1000UL
      let mut i = 0
      while @env.now() < deadline && prog.stop_reason == "" && baseline != "" {
        i += 1
        let rng = @mutate.Rng::new(
          0x9e3779b97f4a7c15UL + id.to_uint64() * 131UL + i.to_uint64(),
        )
        let src = @mutate.mutate(baseline, rng, [], true)
        if src == baseline || !@stager.write_text(file, src) {
          continue
        }
        ps.it += 1
        prog.it += 1
        ps.t2 += 1
        prog.t2 += 1
        let r = @exec.run_isolated(
          moon,
          argv,
          wd,
          cfg.t2_timeout,
          max_output_bytes=65536,
          mem_mb=6144,
        )
        if r.rc == 0 && !r.timed_out {
          ps.t2_ok += 1
          prog.t2_ok += 1
          if cfg.pkg_run_argv != "" {
            ps.pkg_t3_attempts += 1
            let rr = @exec.run_isolated(
              moon,
              split_spaces(cfg.pkg_run_argv),
              wd,
              cfg.t2_timeout,
              max_output_bytes=1048576,
              mem_mb=6144,
            )
            if rr.rc == 0 && !rr.timed_out {
              ps.pkg_t3_ok += 1
              let h = @corpus.sha1_hex(src)
              if !pkg_t3_seen.contains(h) {
                pkg_t3_seen.set(h, ())
                ps.pkg_t3_distinct += 1
              }
            }
            if cfg.pkg_run_argv_b != "" || cfg.pkg_run_cmd_b != "" {
              ps.backend_attempts += 1
              let rb = if cfg.pkg_run_cmd_b != "" {
                @exec.run(
                  "/bin/sh",
                  ["-c", cfg.pkg_run_cmd_b],
                  wd,
                  cfg.t2_timeout,
                  max_output_bytes=1048576,
                )
              } else {
                @exec.run_isolated(
                  moon,
                  split_spaces(cfg.pkg_run_argv_b),
                  wd,
                  cfg.t2_timeout,
                  max_output_bytes=1048576,
                  mem_mb=6144,
                )
              }
              let verdict = backend_diff_class(
                rr.stdout, rb.stdout, rr.rc, rb.rc,
              )
              if verdict == "witness" {
                ps.backend_witnesses += 1
                let bd = join(
                  join(cfg.out, "backend_diff"),
                  @corpus.short_hash(src),
                )
                @corpus.ensure_dir(bd)
                ignore(@stager.write_text(join(bd, "source.mbt"), src))
                ignore(@stager.write_text(join(bd, "baseline.mbt"), baseline))
                ignore(@stager.write_text(join(bd, "argv_a.txt"), cfg.pkg_run_argv))
                ignore(
                  @stager.write_text(
                    join(bd, "argv_b.txt"),
                    if cfg.pkg_run_cmd_b != "" {
                      cfg.pkg_run_cmd_b
                    } else {
                      cfg.pkg_run_argv_b
                    },
                  ),
                )
                ignore(@stager.write_text(join(bd, "out_a.txt"), rr.stdout))
                ignore(@stager.write_text(join(bd, "out_b.txt"), rb.stdout))
                ignore(
                  @stager.write_text(
                    join(bd, "rc.txt"),
                    "a=" +
                    rr.rc.to_string() +
                    " b=" +
                    rb.rc.to_string() +
                    "\n",
                  ),
                )
              } else if verdict == "excluded" {
                ps.backend_excluded += 1
              }
            }
            if rr.rc != 0 {
              ps.pkg_t3_fail += 1
              let ev = join(
                join(cfg.out, "pkg_mismatch"),
                @corpus.short_hash(src),
              )
              @corpus.ensure_dir(ev)
              ignore(@stager.write_text(join(ev, "source.mbt"), src))
              ignore(@stager.write_text(join(ev, "baseline.mbt"), baseline))
              ignore(@stager.write_text(join(ev, "stdout.txt"), rr.stdout))
              ignore(@stager.write_text(join(ev, "stderr.txt"), rr.stderr))
              ignore(
                @stager.write_text(
                  join(ev, "argv.txt"),
                  moon + " " + cfg.pkg_run_argv + " (cwd=" + wd + ")\n",
                ),
              )
              // Semantic (test) failures also enter the save -> triage chain;
              // they are not crash-class, so triage must keep them
              // inconclusive rather than promote them.
              let tsig = @cluster.crash_signature(
                "TEST_FAIL", rr.rc, rr.stderr, rr.stdout,
              )
              ignore(
                save_pkg_witness(
                  cfg, moon, tsig, "TEST_FAIL", cfg.pkg_run_argv, src,
                  baseline, wd, cfg.pkg_file, rr.rc, rr.stdout, rr.stderr,
                ),
              )
            }
          }
        } else {
          ps.crashes += 1
          prog.crashes += 1
          let kind = if r.stderr.contains("Oops, the compiler") ||
            r.stderr.contains("Machine_error") ||
            r.stderr.contains("Assertion failed") {
            "ICE"
          } else {
            "BUILD_FAIL"
          }
          let sig = @cluster.crash_signature(kind, r.rc, r.stderr, r.stdout)
          if save_pkg_witness(
            cfg, moon, sig, kind, cfg.pkg_argv, src, baseline, wd, cfg.pkg_file,
            r.rc, r.stdout, r.stderr,
          ) {
            ps.witnesses += 1
            prog.witnesses += 1
          }
          ignore(pb)
        }
        ignore(@stager.write_text(file, baseline))
      }
    }
    @stager.rm_rf(wd)
    prog.done += 1
    // Package lanes submit no traces; close the queue once all workers are
    // done so idle trace workers do not wait for the full drain grace.
    q.fast_done += 1
    if q.fast_done >= cfg.workers {
      q.closed = true
    }
    return ps
  }
  let s = stats_new()
  let tag = @corpus.short_hash(cfg.run_id)
  let wd = join(join("/tmp/mbtfuzz_mb", tag), "w" + id.to_string())
  rm_rf(wd)
  @corpus.ensure_dir(wd)
  let rng = @mutate.Rng::new(cfg.seed + id.to_uint64() * 0x9E3779B97F4A7C15UL)
  let local_pool : Array[String] = []
  for p in pool {
    local_pool.push(p)
  }
  let local_sigs : Map[String, Unit] = Map([])
  let local_t2_sigs : Map[String, Unit] = Map([])
  let end = @async.now() + cfg.duration_s.to_int64() * 1000L
  let bundle = join(
    join(@stager.moon_home(), "lib/core/_build/wasm/release/bundle"),
    "",
  )
  let builtin = join(bundle, "builtin/builtin.mi")
  let prelude = join(bundle, "prelude/prelude.mi")
  let all_pkgs = @stager.portable_all_pkgs(cfg.root)
  let pkg = "I3eg1nner/tpl/cmd/main"
  // U0 must be frozen before mutations count as rewards, so fast workers wait
  // for the baseline phase instead of racing it.  Without this, baseline tasks
  // were still queued when the duration ended and the summary said
  // "incomplete" even though every trace had succeeded.
  while !q.baseline_settled && @async.now() < end && prog.stop_reason == "" {
    @async.sleep(20)
  }
  while @async.now() < end && prog.stop_reason == "" {
    s.it += 1
    prog.it += 1
    let base = match feedback_pick(feed, rng) {
      Some(v) => v
      None => rng.choice(seeds)
    }
    // Deep queue: with probability --deep-p the iteration starts from a
    // type-valid IR program (the same generator cmd/deepfuzz measured) instead
    // of a byte mutation.  Everything downstream is the normal T1/T2/T3 path.
    let deep_seed = rng.int(1000000).to_uint64()
    // Deep programs are type-valid by construction; mutating them produces
    // many T1-OK/T2-fail inputs (small, syntactically robust sources), which
    // dragged the deep arm's T2 success rate below the byte-mutation arm.
    // They are used directly and deliberately not admitted as mutation parents.
    let ph0 = @env.now()
    let is_deep = cfg.deep_p > 0.0 && rng.chance(cfg.deep_p)
    let mut deep_expected : Array[String] = []
    let src = if is_deep {
      let prog_deep = @ir.generate(deep_seed, 12)
      deep_expected = try {
        @ir.run(prog_deep, 200000)
      } catch {
        _ => []
      }
      @ir.emit_program(prog_deep)
    } else {
      @mutate.mutate(base, rng, local_pool, cfg.body_only, dict~)
    }
    s.ms_mutate += (@env.now() - ph0).to_int().to_int64()
    s.bytes_src += src.length().to_int64()
    s.bytes_parent += base.length().to_int64()
    let src_hash = @corpus.sha1_hex(src)
    if stats_admit(cfg, s.inputs) {
      s.inputs.set(src_hash, ())
    }
    let fname = fname_of(cfg.mode)
    if !write(join(wd, fname), src) {
      continue
    }
    let pt1 = @env.now()
    let r1 = run_t1(
      moonc,
      wd,
      cfg.mode,
      fname,
      cfg.t1_timeout,
      builtin,
      prelude,
    )
    s.ms_t1 += (@env.now() - pt1).to_int().to_int64()
    s.t1 += 1
    prog.t1 += 1
    if r1.timed_out {
      s.timeouts += 1
    }
    let k1 = judged_kind("t1", r1)
    let sig = behavior_sig("t1", r1)
    if stats_admit(cfg, s.diag_families) {
      s.diag_families.set(behavior_family("t1", r1), ())
    }
    let novel = !local_sigs.contains(sig)
    if covctx.enabled &&
      !r1.timed_out &&
      (k1 == "OK" || k1 == "ERR") &&
      q.tasks.length() < cfg.trace_queue / 2 &&
      !q.t1_trace_off &&
      (novel || rng.chance(cfg.trace_t1)) {
      ignore(
        trace_submit(
          cfg,
          q,
          @trace.T1,
          src,
          src,
          fname,
          "",
          false,
          covctx.config_hash,
        ),
      )
    }
    // Deep lane's real T3: run the type-valid program and compare its stdout
    // with the reference interpreter.  t2_ok is not used as a substitute.
    if is_deep && k1 == "OK" {
      s.deep_t3_attempts += 1
      let rr = @exec.run_isolated(
        @stager.moon_path(),
        ["run", fname, "--target", "wasm-gc"],
        wd,
        cfg.t2_timeout,
        max_output_bytes=1048576,
        mem_mb=2048,
      )
      if !rr.timed_out && rr.rc == 0 && deep_expected.length() > 0 &&
        lines_equal(rr.stdout, deep_expected) {
        s.deep_t3_matched += 1
        let h = @corpus.sha1_hex(src)
        if !prog.deep_matched.contains(h) {
          prog.deep_matched.set(h, ())
          s.deep_t3_distinct += 1
        }
      } else if !rr.timed_out && rr.rc == 0 && deep_expected.length() > 0 {
        let truncated = rr.stdout_truncated
        if truncated {
          s.deep_t3_inconclusive += 1
        } else {
          s.deep_t3_mismatch += 1
        }
        // Keep the candidate before anything can clean it: emitted source,
        // expected/actual, the exact argv and the generator provenance.
        let ev = join(
          join(cfg.out, "deep_mismatch"),
          @corpus.short_hash(src),
        )
        @corpus.ensure_dir(ev)
        ignore(@stager.write_text(join(ev, "source.mbt"), src))
        ignore(@stager.write_text(join(ev, "expected.txt"), deep_expected.join("\n")))
        ignore(@stager.write_text(join(ev, "actual.txt"), rr.stdout))
        ignore(
          @stager.write_text(
            join(ev, "argv.txt"),
            @stager.moon_path() +
            " run " +
            fname +
            " --target wasm-gc (cwd=" +
            wd +
            ")\n",
          ),
        )
        ignore(
          @stager.write_text(
            join(ev, "ir_seed.txt"),
            "seed=" +
            deep_seed.to_string() +
            " size=12 truncated=" +
            (if truncated { "true" } else { "false" }) +
            " rc=" +
            rr.rc.to_string() +
            "\n",
          ),
        )
      }
    }
    if k1 != "OK" && k1 != "ERR" {
      s.crashes += 1
      prog.crashes += 1
      s.finding_candidates += 1
      prog.finding_candidates += 1
      if save_crash(cfg, pb, "t1", r1, src, id) {
        s.witnesses += 1
        prog.witnesses += 1
        // Re-feed the crashing input as a parent.  Saving the witness without
        // feeding it back leaves the campaign mutating away from the only
        // input known to reach the bug.
        ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
      } else {
        s.finding_duplicates += 1
        prog.finding_duplicates += 1
      }
      continue
    }
    if cfg.fmt_check && cfg.mode == "mbt" && k1 == "OK" {
      let moonfmt = join(@corpus.dirname(moonc), "moonfmt")
      let fout = "fmt_" + fname
      let fr = @exec.run_isolated(
        moonfmt,
        [fname, "-o", fout],
        wd,
        cfg.t1_timeout,
        max_output_bytes=65536,
        mem_mb=1024,
      )
      if fr.timed_out {
        // Formatter findings are bucketed by what the formatter reported, not
        // by the source hash: one defect must not create one directory per
        // input.
        let sig = @cluster.formatter_signature(fr.rc, fr.stderr, fr.stdout)
        force_persist_source(cfg, pb, src)
        ignore(
          @corpus.save_finding(
            cfg.out,
            "fmt",
            "HANG",
            sig,
            src,
            "{\"stage\":\"fmt\",\"kind\":\"HANG\"}",
            "in.mbt",
          ),
        )
        s.crashes += 1
      } else if fr.rc == 0 {
        let fout2 = "fmt2_" + fname
        let fr2 = @exec.run_isolated(
          moonfmt,
          [fout, "-o", fout2],
          wd,
          cfg.t1_timeout,
          max_output_bytes=65536,
          mem_mb=1024,
        )
        if fr2.rc != 0 {
          let d2 = @exec.ice_detail(fr2)
          let sig = @corpus.short_hash(
            "fmt2-err|" + d2 + "|" + @corpus.short_hash(src),
          )
          force_persist_source(cfg, pb, src)
          ignore(
            @corpus.save_finding(
              cfg.out,
              "fmt",
              "FMT_SECOND_ERR",
              sig,
              src,
              "{\"stage\":\"fmt\",\"kind\":\"FMT_SECOND_ERR\",\"rc\":" +
              fr2.rc.to_string() +
              ",\"detail\":\"" +
              @corpus.json_escape(d2) +
              "\"}",
              "in.mbt",
            ),
          )
          s.crashes += 1
        } else if fr.rc == 0 {
          let a = @fs.read_file_to_string(join(wd, fout)) catch { _ => "" }
          let b = @fs.read_file_to_string(join(wd, fout2)) catch { _ => "" }
          if a != b {
            let sig = @corpus.short_hash(
              "fmt-idem|" + @corpus.short_hash(a) + "|" + @corpus.short_hash(b),
            )
            force_persist_source(cfg, pb, src)
            ignore(
              @corpus.save_finding(
                cfg.out,
                "fmt",
                "NONIDEMPOTENT",
                sig,
                src,
                "{\"stage\":\"fmt\",\"kind\":\"NONIDEMPOTENT\"}",
                "in.mbt",
              ),
            )
            s.crashes += 1
          }
        }
        let rr = run_t1(
          moonc,
          wd,
          "mbt",
          fout,
          cfg.t1_timeout,
          builtin,
          prelude,
        )
        if rr.rc != 0 {
          let detail = @exec.ice_detail(rr)
          // Bucket by the *reparse* failure, not by the source: the same
          // formatter bug in three inputs must be one directory.
          let sig = @cluster.formatter_signature(rr.rc, rr.stderr, rr.stdout)
          let meta = "{\"stage\":\"fmt\",\"kind\":\"REPARSE\",\"fmt_rc\":" +
            fr.rc.to_string() +
            ",\"reparse_rc\":" +
            rr.rc.to_string() +
            ",\"detail\":\"" +
            @corpus.json_escape(detail) +
            "\"}"
          force_persist_source(cfg, pb, src)
          ignore(
            @corpus.save_finding(
              cfg.out,
              "fmt",
              "REPARSE",
              sig,
              src,
              meta,
              "in.mbt",
            ),
          )
          let fd = join(join(join(cfg.out, "findings"), "fmt"), "REPARSE") +
            "/" +
            @corpus.dir_slug(sig)
          @corpus.ensure_dir(fd)
          ignore(
            write(
              join(fd, "formatted.mbt"),
              @fs.read_file_to_string(join(wd, fout)) catch {
                _ => ""
              },
            ),
          )
          s.crashes += 1
        }
      } else {
        let de = @exec.ice_detail(fr)
        let sig = @corpus.short_hash(
          "fmt-err|" +
          de +
          "|" +
          fr.rc.to_string() +
          "|" +
          @corpus.short_hash(src),
        )
        force_persist_source(cfg, pb, src)
        ignore(
          @corpus.save_finding(
            cfg.out,
            "fmt",
            "FMT_ERR",
            sig,
            src,
            "{\"stage\":\"fmt\",\"kind\":\"FMT_ERR\",\"rc\":" +
            fr.rc.to_string() +
            ",\"detail\":\"" +
            @corpus.json_escape(de) +
            "\"}",
            "in.mbt",
          ),
        )
        s.crashes += 1
      }
    }
    if cfg.mode == "mbt" && k1 == "OK" && rng.chance(cfg.p_deep) {
      let pt2 = @env.now()
      let src2 = with_main(src)
      if !write(join(wd, "in.mbt"), src2) {
        continue
      }
      let r2 = @exec.run_isolated(
        moonc,
        t2_args(pkg, builtin, prelude, all_pkgs),
        wd,
        cfg.t2_timeout,
        mem_mb=6144,
      )
      s.ms_t2 += (@env.now() - pt2).to_int().to_int64()
      s.t2 += 1
      prog.t2 += 1
      if stats_admit(cfg, s.t2_inputs) {
        s.t2_inputs.set(src_hash, ())
      }
      if r2.timed_out {
        s.timeouts += 1
      }
      let k2 = judged_kind("t2", r2)
      if k2 == "OK" {
        s.t2_ok += 1
        prog.t2_ok += 1
        s.t2_ok_inputs.set(src_hash, ())
      }
      if k2 != "OK" && k2 != "ERR" {
        s.crashes += 1
        prog.crashes += 1
        s.finding_candidates += 1
        prog.finding_candidates += 1
        if save_crash(cfg, pb, "t2", r2, src, id) {
          s.witnesses += 1
          prog.witnesses += 1
        } else {
          s.finding_duplicates += 1
          prog.finding_duplicates += 1
        }
        continue
      }
      let sig2 = behavior_sig("t2", r2)
      if stats_admit(cfg, s.sigs) {
        s.sigs.set(sig2, ())
      }
      if stats_admit(cfg, s.diag_families) {
        s.diag_families.set(behavior_family("t2", r2), ())
      }
      let novel2 = !local_t2_sigs.contains(sig2)
      if novel2 {
        local_t2_sigs.set(sig2, ())
        // Deep programs are a separate lane: they must not become ordinary
        // mutation parents (https://... no URL, just the rule).
        if !is_deep {
          ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
          persist_behavior(cfg, pb, src, "behavior_t2")
        }
      }
      let t2_chance = if q.t1_trace_off {
        if cfg.trace_t2 > 0.95 {
          0.95
        } else {
          cfg.trace_t2 * 2.0
        }
      } else {
        cfg.trace_t2
      }
      if covctx.enabled && (novel2 || rng.chance(t2_chance)) {
        ignore(
          trace_submit(
            cfg,
            q,
            @trace.T2,
            src,
            src2,
            "in.mbt",
            "",
            false,
            covctx.config_hash,
            lane=(if is_deep { "deep" } else { "" }),
          ),
        )
      }
      if k2 == "OK" && covctx.enabled && rng.chance(cfg.trace_t3) {
        let core = join(wd, "out_wasm.core")
        if @fs.path_exists(core) {
          let snap_dir = join(cfg.out, "trace_cores")
          @corpus.ensure_dir(snap_dir)
          // Unique per submission: two workers holding the same source used to
          // compute the same path, so a refused duplicate deleted the snapshot
          // a queued task still referenced.  worker id + clock makes the file
          // owned by exactly one task, which is what trace_cleanup_core assumes.
          let core_path = join(
            snap_dir,
            @corpus.sha1_hex(
              src + "|" + id.to_string() + "|" + @env.now().to_string(),
            ) +
            ".core",
          )
          let bytes = @fs.read_file_to_bytes(core) catch { _ => Bytes::new(0) }
          if bytes.length() > 0 {
            @fs.write_bytes_to_file(core_path, bytes) catch {
              _ => ()
            }
            // The snapshot is ephemeral: if the task is refused (duplicate or
            // full queue) nothing will consume it, so remove it immediately.
            let queued = trace_submit(
              cfg,
              q,
              @trace.T3,
              src,
              "",
              "",
              core_path,
              false,
              covctx.config_hash,
            )
            if !queued {
              @fs.remove_file(core_path) catch {
                _ => ()
              }
            }
          }
        }
      }
      if k2 == "OK" && rng.chance(cfg.p_run) {
        s.diff_attempts += 1
        prog.diff_attempts += 1
        if stats_admit(cfg, s.diff_inputs) {
          s.diff_inputs.set(src_hash, ())
        }
        let d = if cfg.native_diff {
          @oracle.diff_native(
            moonc,
            @stager.tool_path("moonrun"),
            @stager.tool_path("moon"),
            wd,
            src,
            pkg,
            bundle,
            join(@stager.moon_home(), "lib/core"),
            join(join(cfg.root, "harness"), "moon.pkg"),
            all_pkgs,
            cfg.t2_timeout,
          )
        } else {
          @oracle.diff_program(
            moonc,
            @stager.tool_path("moonrun"),
            "node",
            wd,
            src,
            pkg,
            bundle,
            join(
              join(@stager.moon_home(), "lib/core/_build/js/release/bundle"),
              "",
            ),
            join(@stager.moon_home(), "lib/core"),
            join(join(cfg.root, "harness"), "moon.pkg"),
            all_pkgs,
            cfg.t2_timeout,
          )
        }
        if d.wasm_out.trim().char_length() > 0 ||
          d.js_out.trim().char_length() > 0 {
          s.diff_nonempty += 1
          prog.diff_nonempty += 1
        }
        if d.verdict == @oracle.Same {
          s.t3_ok += 1
          prog.t3_ok += 1
        } else if d.verdict == @oracle.RuntimeDiff {
          s.t3_runtime += 1
          prog.t3_runtime += 1
        } else if d.verdict == @oracle.Inconclusive {
          s.t3_inconclusive += 1
          prog.t3_inconclusive += 1
        } else {
          s.crashes += 1
          prog.crashes += 1
          s.t3_diff += 1
          prog.t3_diff += 1
          match d.verdict {
            @oracle.SemanticDiff => s.t3_semantic_diff += 1
            @oracle.AcceptDiff => s.t3_accept_diff += 1
            @oracle.CompilerAbort => s.t3_compiler_abort += 1
            _ => ()
          }
          s.finding_candidates += 1
          prog.finding_candidates += 1
          if save_diff(cfg, pb, d, src, id) {
            s.witnesses += 1
            prog.witnesses += 1
          } else {
            s.finding_duplicates += 1
            prog.finding_duplicates += 1
          }
        }
      }
    }
    if stats_admit(cfg, s.sigs) {
      s.sigs.set(sig, ())
    }
    if novel && !is_deep {
      // Per-worker novelty memory: without a cap this map grows with every
      // distinct behaviour the campaign ever sees, which is unbounded.
      if stats_admit(cfg, local_sigs) {
        local_sigs.set(sig, ())
      }
      // Only inputs that produced a new compiler behaviour enter the dynamic
      // corpus.  Coverage samples can also admit an input with a higher energy.
      ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
      persist_behavior(cfg, pb, src, "behavior")
      // Keep the splice pool fresh even after it reaches its cap.
      if local_pool.length() < 400 {
        local_pool.push(src)
      } else if local_pool.length() > 0 {
        local_pool[rng.int(local_pool.length())] = src
      }
    }
  }
  prog.done += 1
  q.fast_done += 1
  if q.fast_done >= cfg.workers {
    // Do not abandon the trace backlog: enter a bounded drain phase.  Trace
    // workers keep consuming and close the queue when it is empty or the
    // grace deadline passes.
    q.draining = true
    // Each trace takes seconds; 60 s left most of the backlog abandoned
    // (deferred_close 65-68).  Four minutes lets the queue actually drain.
    q.drain_deadline = @env.now() + 240000UL
  }
  s
}

///|
/// Harness RSS in MiB.  `x/fs` sizes the file with stat() and /proc files
/// report size 0, so reading /proc/self/status through it returns ""; a child
/// shell reads its parent's status instead ($PPID is the harness).
async fn rss_mb() -> Int64 {
  let r = @exec.run(
    "/bin/sh",
    ["-c", "grep VmRSS /proc/$PPID/status"],
    "/tmp",
    2000,
  )
  let text = r.stdout
  let digits = match text.find(":") {
    Some(i) => text[i + 1:].to_owned().trim()
    None => ""
  }
  let mut n = 0L
  for c in digits {
    if c >= '0' && c <= '9' {
      n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
    } else {
      break
    }
  }
  n / 1024L
}

///|
/// Stage recorded in a finding's meta.json.
fn triage_stage_of(dir : String) -> String {
  let meta = @stager.read_text(join(dir, "meta.json"))
  let key = "\"stage\":\""
  match meta.find(key) {
    Some(i) => {
      let rest = meta[i + key.length():].to_owned()
      match rest.find("\"") {
        Some(j) => rest[0:j].to_owned()
        None => "build"
      }
    }
    None => "build"
  }
}

///|

///|
/// Extract the value of `"<key>":"<value>"` from one JSON line.
fn json_str_field(line : String, key : String) -> String {
  let pat = "\"" + key + "\":\""
  match line.find(pat) {
    Some(i) => {
      let rest = line[i + pat.length():].to_owned()
      match rest.find("\"") {
        Some(j) => rest[0:j].to_owned()
        None => ""
      }
    }
    None => ""
  }
}

///|
fn json_str_array_field(line : String, key : String) -> Array[String] {
  let out : Array[String] = []
  let pat = "\"" + key + "\":["
  let i = match line.find(pat) {
    None => return out
    Some(i) => i + pat.length()
  }
  let mut j = i
  while j < line.length() {
    match line.get_char(j) {
      Some('"') => {
        let start = j + 1
        let mut k = start
        while k < line.length() && line.get_char(k) != Some('"') {
          k += 1
        }
        out.push(line[start:k].to_owned())
        j = k + 1
      }
      Some(']') => break
      Some(_) => j += 1
      None => break
    }
  }
  out
}

///|
fn json_int_field(line : String, key : String) -> Int32 {
  let pat = "\"" + key + "\":"
  let i = match line.find(pat) {
    None => return -1
    Some(i) => i + pat.length()
  }
  let mut j = i
  while j < line.length() && line.get_char(j) == Some(' ') {
    j += 1
  }
  let mut v = 0
  let mut any = false
  while j < line.length() {
    match line.get_char(j) {
      Some(c) => {
        if c >= '0' && c <= '9' {
          v = v * 10 + (c.to_int() - 48)
          any = true
          j += 1
        } else {
          break
        }
      }
      None => break
    }
  }
  if any { v } else { -1 }
}

///|
fn state_file_name(path : String) -> String {
  let mut i = path.length()
  while i > 0 {
    i -= 1
    if path.get_char(i) == Some('/') {
      return path[i + 1:].to_owned()
    }
  }
  path
}

///|
fn state_header_valid(cfg : Config, cov : TraceUniverse, text : String) -> Bool {
  let nl = match text.find("\n") { Some(i) => i; None => text.length() }
  let first = text[0:nl].to_owned()
  if !first.contains("\"schema\":\"coverage_state/v2\"") ||
    json_int_field(first, "version") != 1 {
    return false
  }
  let want = json_str_field(first, "checksum")
  if want == "" {
    return false
  }
  let payload_nl = if nl < text.length() { nl + 1 } else { text.length() }
  let payload = text[payload_nl:].to_owned()
  if @corpus.sha1_hex(payload) != want {
    return false
  }
  let ch = json_str_field(first, "config_hash")
  let ph = json_str_field(first, "pin_hash")
  let coh = json_str_field(first, "corpus_hash")
  if (ch != "" && ch != cov.state_config_hash) ||
    (ph != "" && ph != cov.state_pin_hash) ||
    (coh != "" && coh != cov.state_corpus_hash) {
    return false
  }
  true
}

///|
fn quarantine_state(cfg : Config, text : String, reason : String) -> Unit {
  let corrupt = cfg.coverage_state + ".corrupt." + reason + "." +
    @env.now().to_string()
  if @stager.write_text(corrupt, text) {
    @fs.remove_file(cfg.coverage_state) catch { _ => () }
    @fs.remove_file(cfg.coverage_state + ".sha256") catch { _ => () }
    println(
      "[state] quarantine " + cfg.coverage_state + " reclaimed=" + corrupt,
    )
  } else {
    println("[state] quarantine-write-failed " + cfg.coverage_state)
  }
}

///|
fn try_recover_state(cfg : Config, cov : TraceUniverse) -> String {
  let dir = parent_dir(cfg.coverage_state)
  let prefix = state_file_name(cfg.coverage_state) + ".corrupt."
  let names : Array[String] = []
  for n in @stager.try_read_dir(dir) {
    if n.has_prefix(prefix) {
      names.push(n)
    }
  }
  names.sort()
  for i in 0..<names.length() {
    let idx = names.length() - 1 - i
    let path = join(dir, names[idx])
    let text = @stager.read_text(path)
    if state_header_valid(cfg, cov, text) {
      if @stager.write_text(cfg.coverage_state, text) {
        println(
          "[state] recovered " + cfg.coverage_state + " from " + path,
        )
        return text
      }
    }
  }
  ""
}

///|
fn load_coverage_state(cfg : Config, cov : TraceUniverse) -> (Int32, Int32) {
  let mut text = @stager.read_text(cfg.coverage_state)
  if cfg.recover && (text == "" || !state_header_valid(cfg, cov, text)) {
    let recovered = try_recover_state(cfg, cov)
    if recovered != "" {
      text = recovered
    } else if text == "" {
      println("[state] fresh-start " + cfg.coverage_state)
    }
  }
  let mut keys = 0
  let mut edges = 0
  if text == "" {
    return (0, 0)
  }
  // Headerless legacy state: sidecar is authoritative.
  if !text.contains("\"schema\":") {
    let expected = @stager.read_text(cfg.coverage_state + ".sha256")
      .trim()
      .to_owned()
    if expected == "" || @corpus.sha1_hex(text) != expected {
      quarantine_state(cfg, text, "legacy")
      return (0, 0)
    }
  } else if !state_header_valid(cfg, cov, text) {
    quarantine_state(cfg, text, "header")
    return (0, 0)
  }
  for line in text.split("\n") {
    if line.contains("\"schema\":") {
      let e = json_int_field(line.to_owned(), "epoch")
      let c = json_int_field(line.to_owned(), "cases")
      let o = json_int_field(line.to_owned(), "owners")
      let a = json_int_field(line.to_owned(), "adds")
      if e >= 0 { cov.state_epoch = e + 1 }
      if a >= 0 { cov.adds_base = a; cov.checkpoint_adds = a }
      if c >= 0 { cov.case_base = c; cov.checkpoint_cases = c }
      if o >= 0 { cov.owner_base = o; cov.checkpoint_owners = o }
      let last = json_str_field(line.to_owned(), "last")
      if last != "" { cov.last_input_hash = last }
    } else if line.contains("\"key\":") {
      let key = json_str_field(line.to_owned(), "key")
      if key != "" {
        cov.by_key.set(
          key,
          @cov.FuncSet::new(json_str_array_field(line.to_owned(), "funcs")),
        )
        keys += 1
      }
    } else if line.contains("\"edges\":") {
      for e in json_str_array_field(line.to_owned(), "edges") {
        if cov.edge_seen.length() >= cov.edge_cap {
          cov.edge_saturated = true
          break
        }
        cov.edge_seen.set(e, ())
        edges += 1
      }
    }
  }
  (keys, edges)
}

///|
fn parent_dir(path : String) -> String {
  let mut i = path.length()
  while i > 0 {
    i -= 1
    if path.get_char(i) == Some('/') {
      return path[0:i].to_owned()
    }
  }
  "."
}

///|
async fn save_coverage_state(cfg : Config, cov : TraceUniverse, out : String) -> Bool {
  let lines : Array[String] = []
  for k, v in cov.by_key {
    lines.push(
      "{\"key\":\"" +
      @stager.escape(k) +
      "\",\"funcs\":" +
      @trace.json_string_array(v.sorted()) +
      "}",
    )
  }
  let edges : Array[String] = []
  for e in cov.edge_seen.keys() {
    edges.push(e)
  }
  edges.sort()
  lines.push("{\"edges\":" + @trace.json_string_array(edges) + "}")
  let payload = lines.join("\n") + "\n"
  let checksum = @corpus.sha1_hex(payload)
  let header = "{\"schema\":\"coverage_state/v2\",\"version\":1,\"epoch\":" +
    cov.state_epoch.to_string() +
    ",\"cases\":" + cov.checkpoint_cases.to_string() +
    ",\"owners\":" + cov.checkpoint_owners.to_string() +
    ",\"adds\":" + cov.checkpoint_adds.to_string() +
    ",\"config_hash\":\"" + @stager.escape(cov.state_config_hash) +
    "\",\"pin_hash\":\"" + @stager.escape(cov.state_pin_hash) +
    "\",\"corpus_hash\":\"" + @stager.escape(cov.state_corpus_hash) +
    "\",\"checksum\":\"" + checksum +
    "\",\"last\":\"" + @stager.escape(cov.last_input_hash) + "\"}"
  let body = header + "\n" + payload
  let target = if cfg.coverage_write != "" {
    cfg.coverage_write
  } else if cfg.coverage_state != "" {
    cfg.coverage_state
  } else {
    join(out, "coverage_state.jsonl")
  }
  @corpus.ensure_dir(parent_dir(target))
  let tmp = target + ".tmp"
  @fs.remove_file(tmp) catch { _ => () }
  let kill_mode = match @env.get_env_var("FUZZ_STATE_KILL") {
    Some(v) => v
    None => ""
  }
  if kill_mode == "mid_payload" {
    let half = body.length() / 2
    ignore(@stager.write_text(tmp, body[0:half].to_owned()))
    @env.exit(77)
  }
  if !@stager.write_text(tmp, body) {
    return false
  }
  if kill_mode == "after_tmp" {
    @env.exit(77)
  }
  // Flush before rename; no per-fd fsync API is exposed here.
  let _ = @exec.run("/bin/sh", ["-c", "sync"], out, 5000)
  // Atomic replace: header checksum is inside the renamed body.
  let mv = @exec.run(
    "/bin/sh",
    ["-c", "mv -f \"$1\" \"$2\"", "sh", tmp, target],
    out,
    5000,
  )
  if mv.rc != 0 {
    return false
  }
  if kill_mode == "after_rename" {
    @env.exit(77)
  }
  true
}

///|
/// Triage one finding by invoking `cmd/triage` -- the same implementation the
/// standalone command uses.  Keeping a second copy in the campaign is how the
/// two protocols drifted apart.
async fn triage_one(cfg : Config, dir : String) -> (String, String) {
  let triage = join(
    join(join(cfg.root, "moonbit/_build/native/debug/build"), "cmd/triage"),
    "triage.exe",
  )
  if !@fs.path_exists(triage) {
    return ("inconclusive", "")
  }
  let minimize = join(
    join(join(cfg.root, "moonbit/_build/native/debug/build"), "cmd/minimize"),
    "minimize.exe",
  )
  let r = @exec.run(
    triage,
    [
      "--case",
      dir,
      "--stage",
      triage_stage_of(dir),
      "--timeout-ms",
      cfg.t2_timeout.to_string(),
      "--minimize",
      minimize,
    ],
    cfg.root,
    600000,
  )
  let out = r.stdout.trim().to_owned()
  let status = json_str_field(out, "status")
  let known = json_str_field(out, "known")
  (
    if status == "" {
      "inconclusive"
    } else {
      status
    },
    if known == "null" {
      ""
    } else {
      known
    },
  )
}

///|

///|
/// Walk `<root>/findings/<stage>/<kind>/<sig>` and triage each.  Writes one
/// JSON line per case and returns counts (checked, confirmed, known, flaky,
/// inconclusive).
async fn triage_tree(
  cfg : Config,
  root : String,
  jsonl : String,
) -> (Int32, Int32, Int32, Int32, Int32) {
  let dirs : Array[String] = []
  for stage in @stager.try_read_dir(root) {
    let sd = join(root, stage)
    for kind in @stager.try_read_dir(sd) {
      let kd = join(sd, kind)
      for sig in @stager.try_read_dir(kd) {
        let d = join(kd, sig)
        if @fs.path_exists(join(d, "meta.json")) {
          dirs.push(d)
        }
      }
    }
  }
  dirs.sort()
  let mut checked = 0
  let mut confirmed = 0
  let mut known = 0
  let mut flaky = 0
  let mut inconclusive = 0
  let lines : Array[String] = []
  for d in dirs {
    if checked >= 50 {
      break
    }
    checked += 1
    let (status, kid) = triage_one(cfg, d)
    if status == "confirmed" {
      confirmed += 1
    } else if status == "known" {
      known += 1
    } else if status == "flaky" {
      flaky += 1
    } else {
      inconclusive += 1
    }
    lines.push(
      "{\"dir\":\"" +
      @stager.escape(d) +
      "\",\"status\":\"" +
      status +
      "\",\"known\":\"" +
      kid +
      "\"}",
    )
  }
  ignore(@stager.write_text(jsonl, lines.join("\n") + "\n"))
  (checked, confirmed, known, flaky, inconclusive)
}

///|
async fn monitor(
  cfg : Config,
  prog : Progress,
  cov : TraceUniverse,
  q : TraceQueue,
  out : String,
  feed : Feedback,
) -> Stats {
  let mon_start = @env.now()
  let mut last_ck = mon_start
  let mut last_cases = 0
  while prog.done < cfg.workers {
    @async.sleep(2000)
    if cfg.coverage_state != "" &&
      (prog.it - last_cases >= 100 || @env.now() - last_ck >= 5000UL) {
      cov.checkpoint_cases = cov.case_base + prog.it
      cov.checkpoint_owners = if feed.feature_owners.length() > cov.owner_base { feed.feature_owners.length() } else { cov.owner_base }
      cov.checkpoint_adds = cov.adds_base + cov.coverage_adds
      if feed.entries.length() > 0 {
        cov.last_input_hash = feed.entries[feed.entries.length() - 1].hash
      }
      let _ = save_coverage_state(cfg, cov, out)
      last_ck = @env.now()
      last_cases = prog.it
    }
    if cfg.rss_limit_mb > 0 && prog.stop_reason == "" {
      let now = rss_mb()
      if now > cfg.rss_limit_mb.to_int64() {
        prog.stop_reason = "memory"
      }
    }
    q.stop = prog.stop_reason != ""
    // Even with zero trace workers (or all of them stuck), the drain deadline
    // closes the queue; shutdown must never depend on a consumer existing.
    if q.draining && @env.now() >= q.drain_deadline {
      q.closed = true
    }
    let line = "{\"elapsed_ms\":" +
      (@env.now() - mon_start).to_string() +
      ",\"run_id\":\"" +
      @corpus.json_escape(cfg.run_id) +
      "\",\"it\":" +
      prog.it.to_string() +
      ",\"t1\":" +
      prog.t1.to_string() +
      ",\"t2\":" +
      prog.t2.to_string() +
      ",\"t2_ok\":" +
      prog.t2_ok.to_string() +
      ",\"t3_ok\":" +
      prog.t3_ok.to_string() +
      ",\"t3_diff\":" +
      prog.t3_diff.to_string() +
      ",\"t3_runtime\":" +
      prog.t3_runtime.to_string() +
      ",\"t3_inconclusive\":" +
      prog.t3_inconclusive.to_string() +
      ",\"diff_attempts\":" +
      prog.diff_attempts.to_string() +
      ",\"diff_nonempty\":" +
      prog.diff_nonempty.to_string() +
      ",\"finding_candidates\":" +
      prog.finding_candidates.to_string() +
      ",\"finding_duplicates\":" +
      prog.finding_duplicates.to_string() +
      ",\"crash_events\":" +
      prog.crashes.to_string() +
      ",\"unique_witnesses\":" +
      prog.witnesses.to_string() +
      ",\"trace_completed\":" +
      prog.trace_completed.to_string() +
      ",\"trace_failed\":" +
      prog.trace_failed.to_string() +
      ",\"coverage_adds\":" +
      cov.coverage_adds.to_string() +
      ",\"new_edges\":" +
      cov.new_edges.to_string() +
      ",\"edge_keys\":" +
      cov.edge_seen.length().to_string() +
      ",\"edge_saturated\":" +
      (if cov.edge_saturated { "true" } else { "false" }) +
      ",\"edge_new_baseline\":" +
      cov.edge_new_baseline.to_string() +
      ",\"edge_new_t1\":" +
      cov.edge_new_t1.to_string() +
      ",\"edge_new_t2\":" +
      cov.edge_new_t2.to_string() +
      ",\"edge_new_t3\":" +
      cov.edge_new_t3.to_string() +
      ",\"edge_at_settle\":" +
      cov.edge_at_settle.to_string() +
      ",\"edge_refused\":" +
      cov.edge_refused.to_string() +
      ",\"edge_status\":\"" +
      edge_status(cov) + "\"" +
      ",\"edge_collisions\":" +
      cov.edge_collisions.to_string() +
      ",\"trace_dropped\":" +
      prog.trace_dropped.to_string() +
      ",\"trace_wait_events\":" +
      q.wait_events.to_string() +
      ",\"trace_wait_ms_total\":" +
      q.wait_ms_total.to_string() +
      ",\"trace_deferred\":" +
      q.deferred.to_string() +
      ",\"trace_deferred_queue_full\":" +
      q.deferred_queue_full.to_string() +
      ",\"trace_deferred_timeout\":" +
      q.deferred_timeout.to_string() +
      ",\"trace_deferred_close\":" +
      q.deferred_close.to_string() +
      ",\"trace_queue_avg_x100\":" +
      (if q.q_len_samples > 0 { q.q_len_sum * 100L / q.q_len_samples.to_int64() } else { 0L }).to_string() +
      "}"
    @exec.append_line(join(out, "stats.jsonl"), line)
    println("[mb-fuzz progress] \{line}")
  }
  stats_new()
}

///|
fn count_corpus_files(out : String) -> Int32 {
  let mut n = 0
  let names = @fs.read_dir(join(out, "corpus")) catch { _ => [] }
  for name in names {
    if name.has_suffix(".mbt") {
      n += 1
    }
  }
  n
}

///|
fn parse_int(s : String, dflt : Int32) -> Int32 {
  let mut v = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      return dflt
    }
  }
  if any {
    v
  } else {
    dflt
  }
}

///|
fn main_usage() -> Unit {
  println("usage: fuzz [--root DIR] [--out DIR] [--workers N] [--duration S]")
  println(
    "            [--p-deep X] [--p-run X] [--body-only] [--seed N] [--mode mbt|pkg|mod|mbtmd|mbti|mbtx] [--seed-dir DIR] [--fmt-check] [--native-diff] [--run-id ID] [--campaign NAME] [--qemu PATH] [--trace-t1 P] [--trace-t2 P] [--trace-t3 P] [--trace-workers N] [--trace-queue N] [--trace-max-mb M] [--trace-cpu P] [--baseline-seeds N] [--baseline-trace-max-mb M] [--edge-cap N] [--parent-cap N] [--persist-cap N] [--coverage-cap N] [--stats-cap N] [--no-edge-reward] [--rss-limit-mb N]",
  )
}

///|
/// Percent-valued flags are integers in 0..100 and must not fall back to the
/// default on garbage: `--trace-t1 0.02` used to become 20 silently, which
/// made a "2%" campaign actually run at 20% (see findings/p1_feedback.md).
fn parse_percent(s : String) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  if n > 100 {
    None
  } else {
    Some(n)
  }
}

///|
fn percent_arg(args : Array[String], i : Int32, name : String) -> Int32 {
  match parse_percent(args[i + 1]) {
    Some(n) => n
    None => {
      println(
        "invalid value for " +
        name +
        ": `" +
        args[i + 1] +
        "` (expected integer 0..100)",
      )
      @env.exit(2)
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/data/audit/mbtfuzz"
  }
  let cfg : Config = {
    root: cwd,
    out: join(cwd, "out/mb_fuzz"),
    workers: 32,
    duration_s: 60,
    p_deep: 0.25,
    p_run: 0.0,
    body_only: false,
    mode: "mbt",
    seed_dir: "",
    fmt_check: false,
    native_diff: false,
    seed: 1UL,
    run_id: "",
    campaign: "default",
    qemu: "/tmp/AFLplusplus/afl-qemu-trace",
    trace_t1: 0.20,
    trace_t2: 0.70,
    trace_t3: 0.10,
    trace_workers: 3,
    trace_queue: 32,
    trace_max_mb: 256,
    trace_wait_ms: 30000,
    trace_cpu_pct: 25,
    baseline_seeds: 8,
    edge_cap: EDGE_CAP_DEFAULT,
    parent_cap: PARENT_CAP_DEFAULT,
    persist_cap: PERSIST_CAP_DEFAULT,
    coverage_cap: 4000,
    stats_cap: 100000,
    edge_reward: true,
    rss_limit_mb: 0,
    baseline_trace_max_mb: 256,
    deep_p: 0.0,
    triage_after: false,
    triage_only: "",
    emit_finding: "",
    coverage_state: "",
    coverage_write: "",
    recover: false,
    pkg_seed: "",
    pkg_file: "",
    pkg_argv: "build --target wasm-gc",
    pkg_run_argv: "",
    pkg_run_argv_b: "",
    pkg_run_cmd_b: "",
    t1_timeout: 8000,
    t2_timeout: 25000,
  }
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--root" && i + 1 < args.length() {
      cfg.root = args[i + 1]
      i += 2
    } else if a == "--out" && i + 1 < args.length() {
      cfg.out = args[i + 1]
      i += 2
    } else if a == "--workers" && i + 1 < args.length() {
      cfg.workers = parse_int(args[i + 1], cfg.workers)
      i += 2
    } else if a == "--duration" && i + 1 < args.length() {
      cfg.duration_s = parse_int(args[i + 1], cfg.duration_s)
      i += 2
    } else if a == "--p-deep" && i + 1 < args.length() {
      cfg.p_deep = percent_arg(args, i, "--p-deep").to_double() / 100.0
      i += 2
    } else if a == "--p-run" && i + 1 < args.length() {
      cfg.p_run = percent_arg(args, i, "--p-run").to_double() / 100.0
      i += 2
    } else if a == "--seed" && i + 1 < args.length() {
      cfg.seed = parse_int(args[i + 1], 1).to_uint64()
      i += 2
    } else if a == "--native-diff" {
      cfg.native_diff = true
      i += 1
    } else if a == "--fmt-check" {
      cfg.fmt_check = true
      i += 1
    } else if a == "--body-only" {
      cfg.body_only = true
      i += 1
    } else if a == "--seed-dir" && i + 1 < args.length() {
      cfg.seed_dir = args[i + 1]
      i += 2
    } else if a == "--mode" && i + 1 < args.length() {
      cfg.mode = args[i + 1]
      i += 2
    } else if a == "--run-id" && i + 1 < args.length() {
      cfg.run_id = args[i + 1]
      i += 2
    } else if a == "--campaign" && i + 1 < args.length() {
      cfg.campaign = args[i + 1]
      i += 2
    } else if a == "--qemu" && i + 1 < args.length() {
      cfg.qemu = args[i + 1]
      i += 2
    } else if a == "--trace-t1" && i + 1 < args.length() {
      cfg.trace_t1 = percent_arg(args, i, "--trace-t1").to_double() / 100.0
      i += 2
    } else if a == "--trace-t2" && i + 1 < args.length() {
      cfg.trace_t2 = percent_arg(args, i, "--trace-t2").to_double() / 100.0
      i += 2
    } else if a == "--trace-t3" && i + 1 < args.length() {
      cfg.trace_t3 = percent_arg(args, i, "--trace-t3").to_double() / 100.0
      i += 2
    } else if a == "--trace-workers" && i + 1 < args.length() {
      cfg.trace_workers = parse_int(args[i + 1], cfg.trace_workers)
      i += 2
    } else if a == "--trace-queue" && i + 1 < args.length() {
      cfg.trace_queue = parse_int(args[i + 1], cfg.trace_queue)
      i += 2
    } else if a == "--trace-wait-ms" && i + 1 < args.length() {
      cfg.trace_wait_ms = parse_int(args[i + 1], cfg.trace_wait_ms)
      i += 2
    } else if a == "--trace-max-mb" && i + 1 < args.length() {
      cfg.trace_max_mb = parse_int(args[i + 1], cfg.trace_max_mb)
      i += 2
    } else if a == "--trace-cpu" && i + 1 < args.length() {
      cfg.trace_cpu_pct = percent_arg(args, i, "--trace-cpu")
      i += 2
    } else if a == "--baseline-seeds" && i + 1 < args.length() {
      cfg.baseline_seeds = parse_int(args[i + 1], cfg.baseline_seeds)
      i += 2
    } else if a == "--edge-cap" && i + 1 < args.length() {
      cfg.edge_cap = parse_int(args[i + 1], cfg.edge_cap)
      i += 2
    } else if a == "--parent-cap" && i + 1 < args.length() {
      cfg.parent_cap = parse_int(args[i + 1], cfg.parent_cap)
      i += 2
    } else if a == "--persist-cap" && i + 1 < args.length() {
      cfg.persist_cap = parse_int(args[i + 1], cfg.persist_cap)
      i += 2
    } else if a == "--coverage-cap" && i + 1 < args.length() {
      cfg.coverage_cap = parse_int(args[i + 1], cfg.coverage_cap)
      i += 2
    } else if a == "--stats-cap" && i + 1 < args.length() {
      cfg.stats_cap = parse_int(args[i + 1], cfg.stats_cap)
      i += 2
    } else if a == "--no-edge-reward" {
      cfg.edge_reward = false
      i += 1
    } else if a == "--rss-limit-mb" && i + 1 < args.length() {
      cfg.rss_limit_mb = parse_int(args[i + 1], cfg.rss_limit_mb)
      i += 2
    } else if a == "--baseline-trace-max-mb" && i + 1 < args.length() {
      cfg.baseline_trace_max_mb = parse_int(
        args[i + 1],
        cfg.baseline_trace_max_mb,
      )
      i += 2
    } else if a == "--deep-p" && i + 1 < args.length() {
      cfg.deep_p = percent_arg(args, i, "--deep-p").to_double() / 100.0
      i += 2
    } else if a == "--triage" {
      cfg.triage_after = true
      i += 1
    } else if a == "--triage-only" && i + 1 < args.length() {
      cfg.triage_only = args[i + 1]
      i += 2
    } else if a == "--emit-selftest-finding" && i + 1 < args.length() {
      cfg.emit_finding = args[i + 1]
      i += 2
    } else if a == "--pkg-seed" && i + 1 < args.length() {
      cfg.pkg_seed = args[i + 1]
      i += 2
    } else if a == "--pkg-file" && i + 1 < args.length() {
      cfg.pkg_file = args[i + 1]
      i += 2
    } else if a == "--pkg-argv" && i + 1 < args.length() {
      cfg.pkg_argv = args[i + 1]
      i += 2
    } else if a == "--pkg-run-argv" && i + 1 < args.length() {
      cfg.pkg_run_argv = args[i + 1]
      i += 2
    } else if a == "--pkg-run-argv-b" && i + 1 < args.length() {
      cfg.pkg_run_argv_b = args[i + 1]
      i += 2
    } else if a == "--pkg-run-cmd-b" && i + 1 < args.length() {
      cfg.pkg_run_cmd_b = args[i + 1]
      i += 2
    } else if a == "--coverage-state" && i + 1 < args.length() {
      cfg.coverage_state = args[i + 1]
      i += 2
    } else if a == "--coverage-state-out" && i + 1 < args.length() {
      cfg.coverage_write = args[i + 1]
      i += 2
    } else if a == "--recover" {
      cfg.recover = true
      i += 1
    } else {
      main_usage()
      return
    }
  }
  let run_id = if cfg.run_id == "" {
    @async.now().to_string()
  } else {
    cfg.run_id
  }
  cfg.run_id = run_id
  if cfg.edge_cap < 0 {
    cfg.edge_cap = 0
  }
  if cfg.parent_cap < 0 {
    cfg.parent_cap = 0
  }
  if cfg.persist_cap < 0 {
    cfg.persist_cap = 0
  }
  if cfg.coverage_cap < 0 {
    cfg.coverage_cap = 0
  }
  if cfg.stats_cap < 0 {
    cfg.stats_cap = 0
  }
  if cfg.emit_finding != "" {
    let src = @stager.read_text(
      @stager.join(cfg.root, "poc/f2_lex_escape_ice/cmd/main.mbt"),
    )
    let sig = @cluster.crash_signature(
      "ICE", 199, "Error: Invalid_argument(\"Char.chr\")\n", "",
    )
    let meta = "{\"stage\":\"build\",\"kind\":\"ICE\",\"status\":\"candidate\",\"signature\":\"" +
      @stager.escape(sig) +
      "\"}"
    ignore(
      @corpus.save_finding(
        cfg.emit_finding,
        "build",
        "ICE",
        sig,
        src,
        meta,
        "in.mbt",
      ),
    )
    println("{\"emitted\":\"" + @stager.escape(sig) + "\"}")
    return
  }
  if cfg.triage_only != "" {
    let (checked, confirmed, known, flaky, inconclusive) = triage_tree(
      cfg,
      cfg.triage_only,
      join(cfg.triage_only, "triage.jsonl"),
    )
    println(
      "{\"triaged\":" +
      checked.to_string() +
      ",\"confirmed\":" +
      confirmed.to_string() +
      ",\"known\":" +
      known.to_string() +
      ",\"flaky\":" +
      flaky.to_string() +
      ",\"inconclusive\":" +
      inconclusive.to_string() +
      "}",
    )
    return
  }
  let out = join(cfg.out, run_id)
  cfg.out = out
  @corpus.ensure_dir(join(out, "findings"))
  @corpus.ensure_dir(join(out, "corpus"))
  let roots = if cfg.seed_dir != "" {
    [cfg.seed_dir]
  } else {
    [
      join(cfg.root, "seeds"),
      join(cfg.root, "seeds_real"),
      join(cfg.root, "seeds_real2"),
    ]
  }
  let seeds = @corpus.load_texts(roots, suffixes_of(cfg.mode), 12000, 2000)
  if seeds.length() == 0 {
    println("no seeds under \{cfg.root}")
    return
  }
  let dict_text = @fs.read_file_to_string(
    join(cfg.root, "harness/moonbit.dict"),
  ) catch {
    _ => ""
  }
  let dict = @mutate.parse_dict(dict_text)
  let moonc = moonc_path()
  let bundle = join(
    join(@stager.moon_home(), "lib/core/_build/wasm/release/bundle"),
    "",
  )
  let builtin = join(bundle, "builtin/builtin.mi")
  let prelude = join(bundle, "prelude/prelude.mi")
  let all_pkgs = @stager.portable_all_pkgs(cfg.root)
  let pkg = "I3eg1nner/tpl/cmd/main"
  let core_dir = join(@stager.moon_home(), "lib/core")
  let pkg_config = join(join(cfg.root, "harness"), "moon.pkg")
  let nm = @exec.run("nm", ["-n", moonc], cfg.root, 30000)
  let sym = @trace.SymTab::parse(nm.stdout)
  let cov_on = cfg.trace_t1 + cfg.trace_t2 + cfg.trace_t3 > 0.0 &&
    @fs.path_exists(cfg.qemu) &&
    nm.rc == 0 &&
    sym.len() > 0
  let config_hash = @corpus.short_hash(
    file_sha1(moonc) +
    "|" +
    file_sha1(all_pkgs) +
    "|" +
    file_sha1(builtin) +
    "|" +
    file_sha1(prelude) +
    "|" +
    file_sha1(pkg_config) +
    "|wasm|-g|-O0",
  )
  let covctx : CovCtx = {
    enabled: cov_on,
    qemu: cfg.qemu,
    sym,
    config_hash,
    moonc,
    builtin,
    prelude,
    all_pkgs,
    pkg,
    bundle,
    core_dir,
    pkg_config,
  }
  let feed = feedback_new()
  feed.cap = cfg.parent_cap
  for src in seeds {
    ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
  }
  let q = trace_queue_new()
  q.deadline = @env.now() + (cfg.duration_s.to_uint64() + 120UL) * 1000UL
  let cov = trace_universe_new()
  cov.edge_cap = cfg.edge_cap
  cov.state_config_hash = config_hash
  cov.state_pin_hash = @corpus.sha1_hex("moonc v0.10.20+65efd5b93")
  cov.state_corpus_hash = @corpus.sha1_hex(seeds.length().to_string())
  let (restored_keys, restored_edges) = if cfg.coverage_state != "" {
    load_coverage_state(cfg, cov)
  } else {
    (0, 0)
  }
  // One campaign-wide evidence budget shared by workers and trace paths.
  cov.persist.cap = cfg.persist_cap
  cov.persist.coverage_cap = cfg.coverage_cap
  let pb = cov.persist
  if cov_on && cfg.baseline_seeds > 0 {
    // Spread the baseline across the corpus instead of taking the first N
    // files after sort(): with --seed-dir the corpus grows every epoch, and a
    // fixed prefix made U0 describe the same eight files forever, so every new
    // epoch reported the carried corpus as "novel" (inflated coverage_adds).
    let picked = spread_indices(seeds.length(), cfg.baseline_seeds)
    for i in picked {
      let src = seeds[i]
      ignore(
        trace_submit(
          cfg,
          q,
          @trace.T1,
          src,
          src,
          fname_of(cfg.mode),
          "",
          true,
          config_hash,
        ),
      )
      if cfg.mode == "mbt" {
        ignore(
          trace_submit(
            cfg,
            q,
            @trace.T2,
            src,
            with_main(src),
            "in.mbt",
            "",
            true,
            config_hash,
          ),
        )
      }
    }
  }
  let plan = "{\"run_id\":\"" +
    @corpus.json_escape(run_id) +
    "\",\"campaign\":\"" +
    @corpus.json_escape(cfg.campaign) +
    "\",\"mode\":\"" +
    @corpus.json_escape(cfg.mode) +
    "\",\"workers\":" +
    cfg.workers.to_string() +
    ",\"duration_s\":" +
    cfg.duration_s.to_string() +
    ",\"p_deep\":" +
    cfg.p_deep.to_string() +
    ",\"p_run\":" +
    cfg.p_run.to_string() +
    ",\"seed\":" +
    cfg.seed.to_string() +
    ",\"body_only\":" +
    (if cfg.body_only { "true" } else { "false" }) +
    ",\"native_diff\":" +
    (if cfg.native_diff { "true" } else { "false" }) +
    ",\"trace_t1\":" +
    cfg.trace_t1.to_string() +
    ",\"trace_t2\":" +
    cfg.trace_t2.to_string() +
    ",\"trace_t3\":" +
    cfg.trace_t3.to_string() +
    ",\"trace_workers\":" +
    cfg.trace_workers.to_string() +
    ",\"trace_queue\":" +
    cfg.trace_queue.to_string() +
    ",\"trace_max_mb\":" +
    cfg.trace_max_mb.to_string() +
    ",\"trace_cpu_pct\":" +
    cfg.trace_cpu_pct.to_string() +
    ",\"baseline_seeds\":" +
    cfg.baseline_seeds.to_string() +
    ",\"edge_cap\":" +
    cfg.edge_cap.to_string() +
    ",\"parent_cap\":" +
    cfg.parent_cap.to_string() +
    ",\"persist_cap\":" +
    cfg.persist_cap.to_string() +
    ",\"coverage_cap\":" +
    cfg.coverage_cap.to_string() +
    ",\"stats_cap\":" +
    cfg.stats_cap.to_string() +
    ",\"config_hash\":\"" +
    @corpus.json_escape(config_hash) +
    "\",\"coverage\":" +
    (if cov_on { "true" } else { "false" }) +
    ",\"qemu\":\"" +
    @corpus.json_escape(cfg.qemu) +
    "\",\"moonc\":\"" +
    @corpus.json_escape(moonc) +
    "\",\"seeds\":" +
    seeds.length().to_string() +
    ",\"dict\":" +
    dict.length().to_string() +
    "}"
  ignore(write(join(out, "manifest.json"), plan))
  println("[mb-fuzz plan] \{plan}")
  let prog = progress_new()
  let tasks : Array[async () -> Stats] = []
  for id in 0..<cfg.workers {
    let w = id
    tasks.push(() => {
      worker(cfg, w, seeds, seeds, dict, moonc, feed, covctx, prog, q, pb)
    })
  }
  for id in 0..<cfg.trace_workers {
    let w = id
    tasks.push(() => trace_worker(cfg, w, q, feed, cov, covctx, prog))
  }
  tasks.push(() => monitor(cfg, prog, cov, q, out, feed))
  let results = @conc.all_limited(tasks, cfg.workers + cfg.trace_workers + 1)
  let total = stats_new()
  for r in results {
    total.it += r.it
    total.t1 += r.t1
    total.t2 += r.t2
    total.t2_ok += r.t2_ok
    total.t3_ok += r.t3_ok
    total.deep_t3_attempts += r.deep_t3_attempts
    total.deep_t3_matched += r.deep_t3_matched
    total.deep_t3_distinct += r.deep_t3_distinct
    total.deep_t3_mismatch += r.deep_t3_mismatch
    total.deep_t3_inconclusive += r.deep_t3_inconclusive
    total.ms_mutate += r.ms_mutate
    total.ms_t1 += r.ms_t1
    total.ms_t2 += r.ms_t2
    total.bytes_src += r.bytes_src
    total.bytes_parent += r.bytes_parent
    total.pkg_t3_attempts += r.pkg_t3_attempts
    total.pkg_t3_ok += r.pkg_t3_ok
    total.pkg_t3_fail += r.pkg_t3_fail
    total.pkg_t3_distinct += r.pkg_t3_distinct
    total.backend_attempts += r.backend_attempts
    total.backend_witnesses += r.backend_witnesses
    total.backend_excluded += r.backend_excluded
    total.t3_diff += r.t3_diff
    total.t3_runtime += r.t3_runtime
    total.t3_inconclusive += r.t3_inconclusive
    total.t3_semantic_diff += r.t3_semantic_diff
    total.t3_accept_diff += r.t3_accept_diff
    total.t3_compiler_abort += r.t3_compiler_abort
    total.diff_attempts += r.diff_attempts
    total.diff_nonempty += r.diff_nonempty
    total.finding_candidates += r.finding_candidates
    total.finding_duplicates += r.finding_duplicates
    total.crashes += r.crashes
    total.witnesses += r.witnesses
    total.timeouts += r.timeouts
    for k in r.sigs.keys() {
      total.sigs.set(k, ())
    }
    for k in r.diag_families.keys() {
      total.diag_families.set(k, ())
    }
    for k in r.inputs.keys() {
      total.inputs.set(k, ())
    }
    for k in r.t2_inputs.keys() {
      total.t2_inputs.set(k, ())
    }
    for k in r.t2_ok_inputs.keys() {
      total.t2_ok_inputs.set(k, ())
    }
    for k in r.diff_inputs.keys() {
      total.diff_inputs.set(k, ())
    }
  }
  let diff_complete = total.t3_ok +
    total.t3_runtime +
    total.t3_semantic_diff +
    total.t3_accept_diff +
    total.t3_compiler_abort
  // Diagnostic: how much of RSS is explained by the retained parent pool?
  // src bytes + one pointer-sized estimate per cov feature.
  let mut parent_bytes = 0L
  for e in feed.entries {
    parent_bytes += e.src.length().to_int64() + e.hash.length().to_int64()
    parent_bytes += e.cov.len().to_int64() * 32L
  }
  // Persist coverage for the next epoch: inputs alone are not enough.  A
  // failed write is an infrastructure error, not a silent empty state.
  cov.checkpoint_cases = cov.case_base + total.it
  cov.checkpoint_owners = if feed.feature_owners.length() > cov.owner_base { feed.feature_owners.length() } else { cov.owner_base }
  cov.checkpoint_adds = cov.adds_base + cov.coverage_adds
  if feed.entries.length() > 0 {
    cov.last_input_hash = feed.entries[feed.entries.length() - 1].hash
  }
  if !save_coverage_state(cfg, cov, out) {
    println(
      "{\"ok\":false,\"error\":\"coverage_state write failed\",\"out\":\"" +
      @stager.escape(out) +
      "\"}",
    )
    @env.exit(2)
  }
  let (tri_checked, tri_confirmed, tri_known, tri_flaky, tri_inconclusive) = if cfg.triage_after {
    let (checked, confirmed, known, flaky, inconclusive) = triage_tree(
      cfg,
      join(out, "findings"),
      join(out, "triage.jsonl"),
    )
    let reg : Array[String] = []
    for line in @stager.read_text(join(out, "triage.jsonl")).split("\n") {
      if line.contains("\"status\":\"confirmed\"") {
        reg.push(line.to_owned())
      }
    }
    ignore(
      @stager.write_text(join(out, "regression.txt"), reg.join("\n") + "\n"),
    )
    (checked, confirmed, known, flaky, inconclusive)
  } else {
    (0, 0, 0, 0, 0)
  }
  let rss_now = rss_mb()
  let summary = "{\"run_id\":\"" +
    @corpus.json_escape(run_id) +
    "\",\"it\":" +
    total.it.to_string() +
    ",\"t1\":" +
    total.t1.to_string() +
    ",\"t2\":" +
    total.t2.to_string() +
    ",\"t2_ok\":" +
    total.t2_ok.to_string() +
    ",\"t3_ok\":" +
    total.t3_ok.to_string() +
    ",\"deep_t3_attempts\":" +
    total.deep_t3_attempts.to_string() +
    ",\"deep_t3_matched\":" +
    total.deep_t3_matched.to_string() +
    ",\"deep_t3_distinct\":" +
    total.deep_t3_distinct.to_string() +
    ",\"deep_t3_mismatch\":" +
    total.deep_t3_mismatch.to_string() +
    ",\"deep_t3_inconclusive\":" +
    total.deep_t3_inconclusive.to_string() +
    ",\"deep_t3_distinct_global\":" +
    prog.deep_matched.length().to_string() +
    ",\"ms_mutate\":" +
    total.ms_mutate.to_string() +
    ",\"ms_t1\":" +
    total.ms_t1.to_string() +
    ",\"ms_t2\":" +
    total.ms_t2.to_string() +
    ",\"bytes_src\":" +
    total.bytes_src.to_string() +
    ",\"bytes_parent\":" +
    total.bytes_parent.to_string() +
    ",\"pkg_t3_attempts\":" +
    total.pkg_t3_attempts.to_string() +
    ",\"pkg_t3_ok\":" +
    total.pkg_t3_ok.to_string() +
    ",\"pkg_t3_fail\":" +
    total.pkg_t3_fail.to_string() +
    ",\"pkg_t3_distinct\":" +
    total.pkg_t3_distinct.to_string() +
    ",\"backend_attempts\":" +
    total.backend_attempts.to_string() +
    ",\"backend_witnesses\":" +
    total.backend_witnesses.to_string() +
    ",\"backend_excluded\":" +
    total.backend_excluded.to_string() +
    ",\"t3_diff\":" +
    total.t3_diff.to_string() +
    ",\"t3_runtime\":" +
    total.t3_runtime.to_string() +
    ",\"t3_inconclusive\":" +
    total.t3_inconclusive.to_string() +
    ",\"t3_semantic_diff\":" +
    total.t3_semantic_diff.to_string() +
    ",\"t3_accept_diff\":" +
    total.t3_accept_diff.to_string() +
    ",\"t3_compiler_abort\":" +
    total.t3_compiler_abort.to_string() +
    ",\"diff_attempts\":" +
    total.diff_attempts.to_string() +
    ",\"diff_complete\":" +
    diff_complete.to_string() +
    ",\"diff_nonempty\":" +
    total.diff_nonempty.to_string() +
    ",\"finding_candidates\":" +
    total.finding_candidates.to_string() +
    ",\"finding_duplicates\":" +
    total.finding_duplicates.to_string() +
    ",\"crash_events\":" +
    total.crashes.to_string() +
    ",\"candidate_witnesses\":" +
    total.witnesses.to_string() +
    ",\"confirmed_witnesses\":0" +
    ",\"behavior_sigs\":" +
    total.sigs.length().to_string() +
    ",\"diagnostic_families\":" +
    total.diag_families.length().to_string() +
    ",\"unique_inputs\":" +
    total.inputs.length().to_string() +
    ",\"unique_t2_inputs\":" +
    total.t2_inputs.length().to_string() +
    ",\"unique_t2_ok_inputs\":" +
    total.t2_ok_inputs.length().to_string() +
    ",\"unique_diff_inputs\":" +
    total.diff_inputs.length().to_string() +
    ",\"trace_completed\":" +
    q.completed.to_string() +
    ",\"trace_failed\":" +
    q.failed.to_string() +
    ",\"trace_fail_timeout\":" +
    q.fail_timeout.to_string() +
    ",\"trace_fail_too_large\":" +
    q.fail_too_large.to_string() +
    ",\"trace_fail_empty\":" +
    q.fail_empty.to_string() +
    ",\"trace_fail_collector\":" +
    q.fail_collector.to_string() +
    ",\"trace_fail_other\":" +
    q.fail_other.to_string() +
    ",\"trace_accepted\":" +
    q.accepted.to_string() +
    ",\"trace_rejected\":" +
    q.rejected.to_string() +
    ",\"trace_aborts\":" +
    q.aborts.to_string() +
    ",\"trace_dropped\":" +
    q.dropped.to_string() +
    ",\"trace_wait_events\":" +
    q.wait_events.to_string() +
    ",\"trace_wait_ms_total\":" +
    q.wait_ms_total.to_string() +
    ",\"trace_deferred\":" +
    q.deferred.to_string() +
    ",\"trace_deferred_queue_full\":" +
    q.deferred_queue_full.to_string() +
    ",\"trace_deferred_timeout\":" +
    q.deferred_timeout.to_string() +
    ",\"trace_deferred_close\":" +
    q.deferred_close.to_string() +
    ",\"trace_queue_avg_x100\":" +
    (if q.q_len_samples > 0 { q.q_len_sum * 100L / q.q_len_samples.to_int64() } else { 0L }).to_string() +
    ",\"trace_ms\":" +
    q.trace_ms.to_string() +
    ",\"trace_bytes\":" +
    q.trace_bytes.to_string() +
    ",\"baseline_done\":" +
    q.baseline_done.to_string() +
    ",\"baseline_failed\":" +
    q.baseline_failed.to_string() +
    ",\"baseline_expected\":" +
    q.baseline_expected.to_string() +
    ",\"baseline_state\":\"" +
    trace_baseline_state(q) +
    "\",\"baseline_complete\":" +
    (if q.baseline_complete && q.baseline_expected > 0 {
      "true"
    } else {
      "false"
    }) +
    ",\"baseline_pending\":" +
    cov.pending.length().to_string() +
    ",\"baseline_unresolved\":" +
    q.baseline_unresolved.to_string() +
    ",\"baseline_ms\":" +
    q.baseline_ms.to_string() +
    ",\"baseline_funcs\":" +
    cov.baseline_total.len().to_string() +
    ",\"observed_funcs\":" +
    cov.observed_total.len().to_string() +
    ",\"relative_new\":" +
    relative_new_json(q, cov) +
    ",\"coverage_adds\":" +
    cov.coverage_adds.to_string() +
    ",\"coverage_keys\":" +
    cov.by_key.length().to_string() +
    ",\"edge_keys\":" +
    cov.edge_seen.length().to_string() +
    ",\"edge_new_baseline\":" +
    cov.edge_new_baseline.to_string() +
    ",\"edge_new_t1\":" +
    cov.edge_new_t1.to_string() +
    ",\"edge_new_t2\":" +
    cov.edge_new_t2.to_string() +
    ",\"edge_new_t3\":" +
    cov.edge_new_t3.to_string() +
    ",\"edge_at_settle\":" +
    cov.edge_at_settle.to_string() +
    ",\"edge_refused\":" +
    cov.edge_refused.to_string() +
    ",\"edge_status\":\"" +
    edge_status(cov) + "\"" +
    ",\"edge_collisions\":" +
    cov.edge_collisions.to_string() +
    ",\"t1_dry\":" +
    q.t1_dry.to_string() +
    ",\"t1_trace_off\":" +
    (if q.t1_trace_off { "true" } else { "false" }) +
    ",\"edge_reward\":" +
    (if cfg.edge_reward { "true" } else { "false" }) +
    ",\"stop_reason\":\"" +
    @corpus.json_escape(prog.stop_reason) +
    "\"" +
    ",\"restored_keys\":" +
    restored_keys.to_string() +
    ",\"restored_edges\":" +
    restored_edges.to_string() +
    ",\"triage_checked\":" +
    tri_checked.to_string() +
    ",\"triage_confirmed\":" +
    tri_confirmed.to_string() +
    ",\"triage_known\":" +
    tri_known.to_string() +
    ",\"triage_flaky\":" +
    tri_flaky.to_string() +
    ",\"triage_inconclusive\":" +
    tri_inconclusive.to_string() +
    ",\"rss_mb\":" +
    rss_now.to_string() +
    ",\"parent_bytes\":" +
    parent_bytes.to_string() +
    ",\"parents\":" +
    feed.entries.length().to_string() +
    ",\"edge_cap\":" +
    cov.edge_cap.to_string() +
    ",\"edge_saturated\":" +
    (if cov.edge_saturated { "true" } else { "false" }) +
    ",\"new_edges\":" +
    cov.new_edges.to_string() +
    ",\"coverage_records\":" +
    cov.evidence.length().to_string() +
    ",\"corpus\":" +
    feed.entries.length().to_string() +
    ",\"persisted\":" +
    count_corpus_files(out).to_string() +
    ",\"parent_cap\":" +
    feed.cap.to_string() +
    ",\"parents_seen\":" +
    feed.seen.to_string() +
    ",\"parents_retained\":" +
    feed.entries.length().to_string() +
    ",\"parents_protected_forced\":" +
    feed.protected_forced.to_string() +
    ",\"parents_evicted\":" +
    feed.evicted.to_string() +
    ",\"persist_cap\":" +
    pb.cap.to_string() +
    ",\"persist_written\":" +
    pb.written.to_string() +
    ",\"persist_skipped\":" +
    pb.skipped.to_string() +
    ",\"persist_candidates\":" +
    pb.forced.to_string() +
    ",\"persist_saturated\":" +
    (if pb.saturated { "true" } else { "false" }) +
    ",\"coverage_cap\":" +
    pb.coverage_cap.to_string() +
    ",\"coverage_written\":" +
    pb.coverage_written.to_string() +
    ",\"coverage_skipped\":" +
    pb.coverage_skipped.to_string() +
    ",\"trace_failures_logged\":" +
    q.failure_logged.to_string() +
    ",\"trace_failures_skipped\":" +
    q.failure_skipped.to_string() +
    "}"
  ignore(write(join(out, "summary.json"), summary))
  println("[mb-fuzz done] \{summary}")
}
