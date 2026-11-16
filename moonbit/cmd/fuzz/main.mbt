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
  mut cov_every : Int32
  mut qemu : String
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
  mut crashes : Int32
  mut witnesses : Int32
  mut timeouts : Int32
  mut cov_samples : Int32
  mut cov_funcs : Int32
  sigs : Map[String, Unit]
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
    crashes: 0,
    witnesses: 0,
    timeouts: 0,
    cov_samples: 0,
    cov_funcs: 0,
    sigs: Map([]),
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
  mut crashes : Int32
  mut witnesses : Int32
  mut cov_samples : Int32
  mut cov_funcs : Int32
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
    crashes: 0,
    witnesses: 0,
    cov_samples: 0,
    cov_funcs: 0,
    done: 0,
  }
}

///|
/// One retained input.  `energy` is the mutation budget: inputs that added
/// compiler functions get selected more often; ordinary seeds stay at 1.
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
  mut total_cov : @cov.FuncSet
  mut coverage_adds : Int32
}

///|
fn feedback_new() -> Feedback {
  {
    entries: [],
    index: Map([]),
    total_cov: @cov.FuncSet::new([]),
    coverage_adds: 0,
  }
}

///|
fn feedback_upsert(
  f : Feedback,
  src : String,
  cov : @cov.FuncSet,
  added : Int32,
) -> Bool {
  let h = @corpus.sha1_hex(src)
  let bonus = if added > 0 { 32 } else if cov.len() > 0 { 6 } else { 1 }
  if added > 0 {
    f.coverage_adds += added
  }
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
/// Observe a real compiler-function cover set.  Returns the number of functions
/// this input added to the campaign union.
fn feedback_cover(f : Feedback, src : String, funcs : Array[String]) -> Int32 {
  let cov = @cov.FuncSet::new(funcs)
  let added = cov.difference(f.total_cov).len()
  if added > 0 {
    f.total_cov = f.total_cov.union(cov)
    ignore(feedback_upsert(f, src, cov, added))
  } else {
    // Record the observation on an already-admitted parent, but do not admit a
    // new input and do not grant energy when the campaign union did not grow.
    let h = @corpus.sha1_hex(src)
    match f.index.get(h) {
      Some(i) => f.entries[i].cov = f.entries[i].cov.union(cov)
      None => ()
    }
  }
  added
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
fn json_diag_sig(line : StringView) -> String? {
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
        Some(tagged + "|" + msg + "|" + loc)
      }
    }
    _ => None
  }
}

///|
/// Stable T1 behaviour signature.  JSON diagnostics are parsed structurally;
/// legacy bracket codes remain as a fallback for non-JSON tool output.
fn behavior_sig(stage : String, r : @exec.RunResult) -> String {
  let seen : Map[String, Unit] = Map([])
  let parts : Array[String] = []
  let blob = r.stderr + "\n" + r.stdout
  for line in blob.split("\n") {
    let t = line.trim()
    if t.has_prefix("{") {
      match json_diag_sig(t) {
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
/// Persist one admitted parent and the evidence that justified admission.
/// Source and sidecar share a content-derived name; `--seed-dir <run>/corpus`
/// can therefore replay or resume from a previous run.
fn persist_parent(
  cfg : Config,
  src : String,
  reason : String,
  funcs : Array[String],
) -> Unit {
  let h = @corpus.short_hash(src)
  let dir = join(cfg.out, "corpus")
  @corpus.ensure_dir(dir)
  ignore(write(join(dir, h + ".mbt"), src))
  let meta = "{\"sha1\":\"" +
    @corpus.sha1_hex(src) +
    "\",\"reason\":\"" +
    @corpus.json_escape(reason) +
    "\",\"bytes\":" +
    src.length().to_string() +
    ",\"coverage_funcs\":" +
    @trace.json_string_array(funcs) +
    "}"
  ignore(write(join(dir, h + ".json"), meta))
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
/// Run T1 under QEMU, then symbolize the executed PCs with the campaign's nm
/// table.  This is the real coverage source used by the feedback loop; it is
/// sampled (default: every 64th input) because tracing costs about one second
/// and writes ~17 MiB even for a tiny input.
async fn trace_t1(
  ctx : CovCtx,
  moonc : String,
  wd : String,
  mode : String,
  fname : String,
  builtin : String,
  prelude : String,
  tag : String,
  timeout_ms : Int32,
) -> Array[String] {
  if !ctx.enabled {
    return []
  }
  let trace_path = join(wd, "qemu_" + tag + ".log")
  @fs.remove_file(trace_path) catch {
    _ => ()
  }
  let args = ["-d", "exec", "-D", trace_path, "--", moonc] +
    t1_args(mode, fname, builtin, prelude)
  let r = @exec.run_isolated(ctx.qemu, args, wd, timeout_ms, mem_mb=4096)
  if r.timed_out {
    return []
  }
  let trace = @fs.read_file_to_string(trace_path) catch { _ => "" }
  @fs.remove_file(trace_path) catch {
    _ => ()
  }
  // A runaway log is a sign the sample is not representative; skip it rather
  // than pinning the worker's heap.
  if trace.length() == 0 || trace.length() > 134217728 {
    return []
  }
  let all = @trace.summarize_trace(trace, ctx.sym).funcs
  // Keep the same denominator as the frozen coverage report: camlMoonc*
  // symbols only, not OCaml runtime/CRT startup.
  let funcs : Array[String] = []
  for f in all {
    if f.has_prefix("camlMoonc") {
      funcs.push(f)
    }
  }
  funcs
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
    let mut cov_funcs : Array[String] = []
    let mut cov_admitted = false
    if cfg.cov_every > 0 && !r1.timed_out && s.it % cfg.cov_every == 0 {
      let funcs = trace_t1(
        covctx,
        moonc,
        wd,
        cfg.mode,
        fname,
        builtin,
        prelude,
        "w" + id.to_string(),
        cfg.t2_timeout,
      )
      if funcs.length() > 0 {
        s.cov_samples += 1
        prog.cov_samples += 1
        let added = feedback_cover(feed, src, funcs)
        if added > 0 {
          cov_funcs = funcs
          cov_admitted = true
          persist_parent(cfg, src, "coverage", funcs)
        }
        s.cov_funcs = feed.total_cov.len()
        prog.cov_funcs = feed.total_cov.len()
      }
    }
    if k1 != "OK" && k1 != "ERR" {
      s.crashes += 1
      prog.crashes += 1
      if save_crash(cfg, "t1", r1, src, id) {
        s.witnesses += 1
        prog.witnesses += 1
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
        ],
        wd,
        cfg.t2_timeout,
        mem_mb=6144,
      )
      s.t2 += 1
      prog.t2 += 1
      if r2.timed_out {
        s.timeouts += 1
      }
      let k2 = @exec.classify(r2)
      if k2 == "OK" {
        s.t2_ok += 1
        prog.t2_ok += 1
      }
      if k2 != "OK" && k2 != "ERR" {
        s.crashes += 1
        prog.crashes += 1
        if save_crash(cfg, "t2", r2, src, id) {
          s.witnesses += 1
          prog.witnesses += 1
        }
        continue
      }
      if k2 == "OK" && rng.chance(cfg.p_run) {
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
          if save_diff(cfg, d, src, id) {
            s.witnesses += 1
            prog.witnesses += 1
          }
        }
      }
    }
    let sig = behavior_sig("t1", r1)
    s.sigs.set(sig, ())
    let novel = !local_sigs.contains(sig)
    if novel {
      local_sigs.set(sig, ())
      // Only inputs that produced a new compiler behaviour enter the dynamic
      // corpus.  Coverage samples can also admit an input with a higher energy.
      ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0))
      let reason = if cov_admitted { "behavior+coverage" } else { "behavior" }
      if cov_admitted {
        persist_parent(cfg, src, reason, cov_funcs)
      } else {
        persist_parent(cfg, src, reason, [])
      }
      // Keep the splice pool fresh even after it reaches its cap.
      if local_pool.length() < 400 {
        local_pool.push(src)
      } else if local_pool.length() > 0 {
        local_pool[rng.int(local_pool.length())] = src
      }
    }
  }
  prog.done += 1
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
      ",\"crash_events\":" +
      prog.crashes.to_string() +
      ",\"unique_witnesses\":" +
      prog.witnesses.to_string() +
      ",\"cov_samples\":" +
      prog.cov_samples.to_string() +
      ",\"cov_funcs\":" +
      prog.cov_funcs.to_string() +
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
    "            [--p-deep X] [--p-run X] [--body-only] [--seed N] [--mode mbt|pkg|mod|mbtmd|mbti|mbtx] [--seed-dir DIR] [--fmt-check] [--native-diff] [--run-id ID] [--campaign NAME] [--cov-every N] [--qemu PATH]",
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
    cov_every: 64,
    qemu: "/tmp/AFLplusplus/afl-qemu-trace",
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
    } else if a == "--cov-every" && i + 1 < args.length() {
      cfg.cov_every = parse_int(args[i + 1], cfg.cov_every)
      i += 2
    } else if a == "--qemu" && i + 1 < args.length() {
      cfg.qemu = args[i + 1]
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
  let nm = @exec.run("nm", ["-n", moonc], cfg.root, 30000)
  let sym = @trace.SymTab::parse(nm.stdout)
  let cov_on = cfg.cov_every > 0 &&
    @fs.path_exists(cfg.qemu) &&
    nm.rc == 0 &&
    sym.len() > 0
  let covctx : CovCtx = { enabled: cov_on, qemu: cfg.qemu, sym, }
  let feed = feedback_new()
  for src in seeds {
    ignore(feedback_upsert(feed, src, @cov.FuncSet::new([]), 0))
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
    ",\"cov_every\":" +
    cfg.cov_every.to_string() +
    ",\"coverage\":" +
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
      worker(cfg, w, seeds, seeds, dict, moonc, home, feed, covctx, prog)
    })
  }
  tasks.push(() => monitor(cfg, prog, out))
  let results = @async.all(tasks, max_concurrent=cfg.workers + 1)
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
    total.crashes += r.crashes
    total.witnesses += r.witnesses
    total.timeouts += r.timeouts
    total.cov_samples += r.cov_samples
    if r.cov_funcs > total.cov_funcs {
      total.cov_funcs = r.cov_funcs
    }
    for k in r.sigs.keys() {
      total.sigs.set(k, ())
    }
  }
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
    ",\"crash_events\":" +
    total.crashes.to_string() +
    ",\"unique_witnesses\":" +
    total.witnesses.to_string() +
    ",\"behavior_sigs\":" +
    total.sigs.length().to_string() +
    ",\"cov_samples\":" +
    total.cov_samples.to_string() +
    ",\"cov_funcs\":" +
    feed.total_cov.len().to_string() +
    ",\"coverage_adds\":" +
    feed.coverage_adds.to_string() +
    ",\"corpus\":" +
    feed.entries.length().to_string() +
    ",\"persisted\":" +
    count_corpus_files(out).to_string() +
    "}"
  ignore(write(join(out, "summary.json"), summary))
  println("[mb-fuzz done] \{summary}")
}
