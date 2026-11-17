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
  mut trace_cpu_pct : Int32
  mut baseline_seeds : Int32
  mut edge_cap : Int32
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
struct Parent {
  src : String
  mut cov : @cov.FuncSet
  mut energy : Int32
}

///|
/// Shared corpus for the whole campaign.  With N workers this is the only
/// place parent selection reads from, so a discovery in worker 3 is visible to
/// worker 7 on its next iteration.
struct Feedback {
  entries : Array[Parent]
  index : Map[String, Int32]
}

///|
fn feedback_new() -> Feedback {
  { entries: [], index: Map([]), }
}

///|
/// `added` is the number of new `camlMoonc*` function names in this trace;
/// `new_edges` is the number of new exact TB edge keys from the **different,
/// wider** all-mapped scope.  The function term is unchanged and remains
/// primary; the edge term is additive and smaller.  Edge-only inputs get a
/// modest bump rather than the top-tier function bonus.
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
      e.cov = e.cov.union(cov)
      if e.energy < 64 {
        e.energy = e.energy + bonus
      }
      false
    }
    None => {
      let i = f.entries.length()
      f.index.set(h, i)
      f.entries.push({ src, cov, energy: bonus, })
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
  mut t1_reserved_ms : Int64
  mut t2_reserved_ms : Int64
  mut t3_reserved_ms : Int64
  mut inflight : Int32
  mut trace_ms : Int64
  mut trace_bytes : Int64
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
    t1_reserved_ms: 0L,
    t2_reserved_ms: 0L,
    t3_reserved_ms: 0L,
    inflight: 0,
    trace_ms: 0L,
    trace_bytes: 0L,
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
fn trace_submit(
  cfg : Config,
  q : TraceQueue,
  stage : @trace.TraceStage,
  src : String,
  compiled : String,
  fname : String,
  core_path : String,
  baseline : Bool,
  config_hash : String,
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
  if q.tasks.length() >= cfg.trace_queue {
    q.dropped += 1
    if baseline {
      // A seed that never entered the queue cannot be part of a complete U0.
      q.baseline_failed += 1
      q.baseline_complete = false
      q.baseline_settled = q.baseline_done + q.baseline_failed >=
        q.baseline_expected
    }
    return false
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
  mut observed_total : @cov.FuncSet
  mut coverage_adds : Int32
  edge_seen : Map[String, Unit]
  mut edge_cap : Int32
  mut edge_saturated : Bool
  mut new_edges : Int32
}

///|
fn trace_universe_new() -> TraceUniverse {
  {
    by_key: Map([]),
    evidence: Map([]),
    pending: [],
    rewarded: Map([]),
    baseline_total: @cov.FuncSet::new([]),
    observed_total: @cov.FuncSet::new([]),
    coverage_adds: 0,
    edge_seen: Map([]),
    edge_cap: EDGE_CAP_DEFAULT,
    edge_saturated: false,
    new_edges: 0,
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
fn edge_universe_add(cov : TraceUniverse, keys : Array[String]) -> Int32 {
  if cov.edge_saturated {
    return 0
  }
  let mut added = 0
  for k in keys {
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
  b.write_string(sig)
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
fn save_crash(
  cfg : Config,
  stage : String,
  r : @exec.RunResult,
  src : String,
  worker : Int32,
) -> Bool {
  let kind = @exec.classify(r)
  let detail = @exec.ice_detail(r)
  let sig = @corpus.short_hash(
    stage + "|" + kind + "|" + detail + "|rc=" + r.rc.to_string(),
  )
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
/// Source bytes are stored once per content hash.  Evidence records point at
/// this file instead of duplicating the source in every coverage record.
fn persist_source(cfg : Config, src : String) -> String {
  let h = @corpus.sha1_hex(src)
  let dir = join(cfg.out, "corpus")
  @corpus.ensure_dir(dir)
  ignore(write(join(dir, h + ".mbt"), src))
  h
}

///|
/// Behaviour evidence is intentionally separate from coverage evidence.  A
/// fast-path behaviour observation must never overwrite a later trace record
/// for the same source.
fn persist_behavior(cfg : Config, src : String, reason : String) -> Unit {
  let h = persist_source(cfg, src)
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
fn persist_coverage(
  cfg : Config,
  task : TraceTask,
  tr : @trace.TraceResult,
  funcs : Array[String],
  edge_novel : Bool,
) -> Unit {
  let source_hash = persist_source(cfg, task.src)
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
fn moonc_path(home : String) -> String {
  join(join(home, ".moon/bin"), "moonc")
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
  persist_coverage(cfg, task, tr, all.sorted(), edge_novel)
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
) -> Unit {
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
    if !cov.rewarded.contains(reward_key) {
      cov.rewarded.set(reward_key, ())
      ignore(feedback_upsert(feed, task.src, covset, delta.len(), edge_new))
    }
  }
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
  if q.baseline_failed == 0 {
    q.baseline_complete = true
    for p in cov.pending {
      trace_apply_delta(
        p.task,
        p.result,
        @cov.FuncSet::new(p.result.functions),
        p.edge_new,
        cov,
        feed,
      )
    }
    cov.pending.clear()
  } else {
    q.baseline_unresolved += cov.pending.length()
    cov.pending.clear()
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
  if !tr.complete {
    q.failed += 1
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
  let edge_new = edge_universe_add(cov, tr.edge_keys)
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
  trace_apply_delta(task, tr, covset, edge_new, cov, feed)
}

///|
fn trace_drop_remaining(q : TraceQueue) -> Unit {
  for t in q.tasks {
    if t.baseline {
      q.baseline_failed += 1
      q.baseline_complete = false
    }
  }
  q.dropped += q.tasks.length()
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
  let max_bytes = cfg.trace_max_mb.to_int64() * 1048576L
  let start = @async.now()
  let budget = if cfg.trace_cpu_pct > 0 {
    let b = cfg.duration_s.to_int64() * cfg.trace_cpu_pct.to_int64() * 10L
    if b < 2000L {
      2000L
    } else {
      b
    }
  } else {
    0L
  }
  let deadline = start + cfg.duration_s.to_int64() * 1000L + 10000L
  while @async.now() < deadline {
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
    if !task.baseline && budget > 0L && q.trace_ms - q.baseline_ms >= budget {
      trace_release(q, task)
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
      max_bytes,
    )
    let before = q.completed
    let failed_before = q.failed
    trace_apply(cfg, task, tr, cov, feed, q)
    if q.completed > before {
      prog.trace_completed += 1
    }
    if q.failed > failed_before {
      prog.trace_failed += 1
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
fn save_diff(
  cfg : Config,
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
  b.write_string(sig)
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
async fn worker(
  cfg : Config,
  id : Int32,
  seeds : Array[String],
  pool : Array[String],
  dict : Array[String],
  moonc : String,
  home : String,
  feed : Feedback,
  covctx : CovCtx,
  prog : Progress,
  q : TraceQueue,
) -> Stats {
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
  let bundle = join(join(home, ".moon/lib/core/_build/wasm/release/bundle"), "")
  let builtin = join(bundle, "builtin/builtin.mi")
  let prelude = join(bundle, "prelude/prelude.mi")
  let all_pkgs = join(join(cfg.root, "harness"), "all_pkgs.json")
  let pkg = "I3eg1nner/tpl/cmd/main"
  while @async.now() < end {
    s.it += 1
    prog.it += 1
    let base = match feedback_pick(feed, rng) {
      Some(v) => v
      None => rng.choice(seeds)
    }
    let src = @mutate.mutate(base, rng, local_pool, cfg.body_only, dict~)
    let src_hash = @corpus.sha1_hex(src)
    s.inputs.set(src_hash, ())
    let fname = fname_of(cfg.mode)
    if !write(join(wd, fname), src) {
      continue
    }
    let r1 = run_t1(
      moonc,
      wd,
      cfg.mode,
      fname,
      cfg.t1_timeout,
      builtin,
      prelude,
    )
    s.t1 += 1
    prog.t1 += 1
    if r1.timed_out {
      s.timeouts += 1
    }
    let k1 = @exec.classify(r1)
    let sig = behavior_sig("t1", r1)
    s.diag_families.set(behavior_family("t1", r1), ())
    let novel = !local_sigs.contains(sig)
    if covctx.enabled &&
      !r1.timed_out &&
      (k1 == "OK" || k1 == "ERR") &&
      q.tasks.length() < cfg.trace_queue / 2 &&
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
    if k1 != "OK" && k1 != "ERR" {
      s.crashes += 1
      prog.crashes += 1
      s.finding_candidates += 1
      prog.finding_candidates += 1
      if save_crash(cfg, "t1", r1, src, id) {
        s.witnesses += 1
        prog.witnesses += 1
      } else {
        s.finding_duplicates += 1
        prog.finding_duplicates += 1
      }
      continue
    }
    if cfg.fmt_check && cfg.mode == "mbt" && k1 == "OK" {
      let moonfmt = join(@corpus.dirname(moonc), "moonfmt")
      let fout = "fmt_" + fname
      let fr = @exec.run(moonfmt, [fname, "-o", fout], wd, cfg.t1_timeout)
      if fr.timed_out {
        let sig = @corpus.short_hash("fmt-hang|" + @corpus.short_hash(src))
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
        let fr2 = @exec.run(moonfmt, [fout, "-o", fout2], wd, cfg.t1_timeout)
        if fr2.rc != 0 {
          let d2 = @exec.ice_detail(fr2)
          let sig = @corpus.short_hash(
            "fmt2-err|" + d2 + "|" + @corpus.short_hash(src),
          )
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
          let sig = @corpus.short_hash(
            "fmt|" + detail + "|" + @corpus.short_hash(src),
          )
          let meta = "{\"stage\":\"fmt\",\"kind\":\"REPARSE\",\"fmt_rc\":" +
            fr.rc.to_string() +
            ",\"reparse_rc\":" +
            rr.rc.to_string() +
            ",\"detail\":\"" +
            @corpus.json_escape(detail) +
            "\"}"
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
            sig
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
      s.t2 += 1
      prog.t2 += 1
      s.t2_inputs.set(src_hash, ())
      if r2.timed_out {
        s.timeouts += 1
      }
      let k2 = @exec.classify(r2)
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
        if save_crash(cfg, "t2", r2, src, id) {
          s.witnesses += 1
          prog.witnesses += 1
        } else {
          s.finding_duplicates += 1
          prog.finding_duplicates += 1
        }
        continue
      }
      let sig2 = behavior_sig("t2", r2)
      s.sigs.set(sig2, ())
      s.diag_families.set(behavior_family("t2", r2), ())
      let novel2 = !local_t2_sigs.contains(sig2)
      if novel2 {
        local_t2_sigs.set(sig2, ())
        ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
        persist_behavior(cfg, src, "behavior_t2")
      }
      if covctx.enabled && (novel2 || rng.chance(cfg.trace_t2)) {
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
          ),
        )
      }
      if k2 == "OK" && covctx.enabled && rng.chance(cfg.trace_t3) {
        let core = join(wd, "out_wasm.core")
        if @fs.path_exists(core) {
          let snap_dir = join(cfg.out, "trace_cores")
          @corpus.ensure_dir(snap_dir)
          let core_path = join(snap_dir, @corpus.sha1_hex(src) + ".core")
          let bytes = @fs.read_file_to_bytes(core) catch { _ => Bytes::new(0) }
          if bytes.length() > 0 {
            @fs.write_bytes_to_file(core_path, bytes) catch {
              _ => ()
            }
            ignore(
              trace_submit(
                cfg,
                q,
                @trace.T3,
                src,
                "",
                "",
                core_path,
                false,
                covctx.config_hash,
              ),
            )
          }
        }
      }
      if k2 == "OK" && rng.chance(cfg.p_run) {
        s.diff_attempts += 1
        prog.diff_attempts += 1
        s.diff_inputs.set(src_hash, ())
        let d = if cfg.native_diff {
          @oracle.diff_native(
            moonc,
            join(join(home, ".moon/bin"), "moonrun"),
            join(join(home, ".moon/bin"), "moon"),
            wd,
            src,
            pkg,
            bundle,
            join(home, ".moon/lib/core"),
            join(join(cfg.root, "harness"), "moon.pkg"),
            all_pkgs,
            cfg.t2_timeout,
          )
        } else {
          @oracle.diff_program(
            moonc,
            join(join(home, ".moon/bin"), "moonrun"),
            "node",
            wd,
            src,
            pkg,
            bundle,
            join(join(home, ".moon/lib/core/_build/js/release/bundle"), ""),
            join(home, ".moon/lib/core"),
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
          if save_diff(cfg, d, src, id) {
            s.witnesses += 1
            prog.witnesses += 1
          } else {
            s.finding_duplicates += 1
            prog.finding_duplicates += 1
          }
        }
      }
    }
    s.sigs.set(sig, ())
    if novel {
      local_sigs.set(sig, ())
      // Only inputs that produced a new compiler behaviour enter the dynamic
      // corpus.  Coverage samples can also admit an input with a higher energy.
      ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
      persist_behavior(cfg, src, "behavior")
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
    q.closed = true
  }
  s
}

///|
async fn monitor(cfg : Config, prog : Progress, out : String) -> Stats {
  while prog.done < cfg.workers {
    @async.sleep(2000)
    let line = "{\"run_id\":\"" +
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
      ",\"trace_dropped\":" +
      prog.trace_dropped.to_string() +
      "}"
    @corpus.append_line(join(out, "stats.jsonl"), line)
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
    "            [--p-deep X] [--p-run X] [--body-only] [--seed N] [--mode mbt|pkg|mod|mbtmd|mbti|mbtx] [--seed-dir DIR] [--fmt-check] [--native-diff] [--run-id ID] [--campaign NAME] [--qemu PATH] [--trace-t1 P] [--trace-t2 P] [--trace-t3 P] [--trace-workers N] [--trace-queue N] [--trace-max-mb M] [--trace-cpu P] [--baseline-seeds N] [--edge-cap N]",
  )
}

///|
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let cfg : Config = {
    root: "/data/audit/mbtfuzz",
    out: "/data/audit/mbtfuzz/out/mb_fuzz",
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
    trace_cpu_pct: 25,
    baseline_seeds: 8,
    edge_cap: EDGE_CAP_DEFAULT,
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
      cfg.p_deep = parse_int(args[i + 1], 25).to_double() / 100.0
      i += 2
    } else if a == "--p-run" && i + 1 < args.length() {
      cfg.p_run = parse_int(args[i + 1], 0).to_double() / 100.0
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
      cfg.trace_t1 = parse_int(args[i + 1], 20).to_double() / 100.0
      i += 2
    } else if a == "--trace-t2" && i + 1 < args.length() {
      cfg.trace_t2 = parse_int(args[i + 1], 70).to_double() / 100.0
      i += 2
    } else if a == "--trace-t3" && i + 1 < args.length() {
      cfg.trace_t3 = parse_int(args[i + 1], 10).to_double() / 100.0
      i += 2
    } else if a == "--trace-workers" && i + 1 < args.length() {
      cfg.trace_workers = parse_int(args[i + 1], cfg.trace_workers)
      i += 2
    } else if a == "--trace-queue" && i + 1 < args.length() {
      cfg.trace_queue = parse_int(args[i + 1], cfg.trace_queue)
      i += 2
    } else if a == "--trace-max-mb" && i + 1 < args.length() {
      cfg.trace_max_mb = parse_int(args[i + 1], cfg.trace_max_mb)
      i += 2
    } else if a == "--trace-cpu" && i + 1 < args.length() {
      cfg.trace_cpu_pct = parse_int(args[i + 1], cfg.trace_cpu_pct)
      i += 2
    } else if a == "--baseline-seeds" && i + 1 < args.length() {
      cfg.baseline_seeds = parse_int(args[i + 1], cfg.baseline_seeds)
      i += 2
    } else if a == "--edge-cap" && i + 1 < args.length() {
      cfg.edge_cap = parse_int(args[i + 1], cfg.edge_cap)
      i += 2
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
  let moonc = moonc_path(home)
  let bundle = join(join(home, ".moon/lib/core/_build/wasm/release/bundle"), "")
  let builtin = join(bundle, "builtin/builtin.mi")
  let prelude = join(bundle, "prelude/prelude.mi")
  let all_pkgs = join(join(cfg.root, "harness"), "all_pkgs.json")
  let pkg = "I3eg1nner/tpl/cmd/main"
  let core_dir = join(home, ".moon/lib/core")
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
  for src in seeds {
    ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0, 0))
  }
  let q = trace_queue_new()
  let cov = trace_universe_new()
  cov.edge_cap = cfg.edge_cap
  if cov_on && cfg.baseline_seeds > 0 {
    let n = if cfg.baseline_seeds < seeds.length() {
      cfg.baseline_seeds
    } else {
      seeds.length()
    }
    for i in 0..<n {
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
      worker(cfg, w, seeds, seeds, dict, moonc, home, feed, covctx, prog, q)
    })
  }
  for id in 0..<cfg.trace_workers {
    let w = id
    tasks.push(() => trace_worker(cfg, w, q, feed, cov, covctx, prog))
  }
  tasks.push(() => monitor(cfg, prog, out))
  let results = @async.all(
    tasks,
    max_concurrent=cfg.workers + cfg.trace_workers + 1,
  )
  let total = stats_new()
  for r in results {
    total.it += r.it
    total.t1 += r.t1
    total.t2 += r.t2
    total.t2_ok += r.t2_ok
    total.t3_ok += r.t3_ok
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
    ",\"unique_witnesses\":" +
    total.witnesses.to_string() +
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
    ",\"trace_accepted\":" +
    q.accepted.to_string() +
    ",\"trace_rejected\":" +
    q.rejected.to_string() +
    ",\"trace_aborts\":" +
    q.aborts.to_string() +
    ",\"trace_dropped\":" +
    q.dropped.to_string() +
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
    "}"
  ignore(write(join(out, "summary.json"), summary))
  println("[mb-fuzz done] \{summary}")
}
