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
  t1_timeout : Int32
  t2_timeout : Int32
}

///|
struct Stats {
  mut it : Int32
  mut t1 : Int32
  mut t2 : Int32
  mut crashes : Int32
  mut new_sigs : Int32
  mut timeouts : Int32
}

///|
fn stats_new() -> Stats {
  { it: 0, t1: 0, t2: 0, crashes: 0, new_sigs: 0, timeouts: 0, }
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
fn behavior_sig(r : @exec.RunResult) -> String {
  let blob = r.stderr + r.stdout
  let codes = diag_codes(blob)
  let b = StringBuilder()
  b.write_string(if r.rc == 0 { "ACC" } else { "ERR" })
  for c in codes {
    b.write_string("|")
    b.write_string(c)
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
  let sig = @corpus.short_hash(stage + "|" + kind + "|" + detail)
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
async fn run_t1(
  moonc : String,
  wd : String,
  mode : String,
  fname : String,
  timeout_ms : Int32,
  builtin : String,
  prelude : String,
) -> @exec.RunResult {
  if mode == "mbt" || mode == "pkg" || mode == "mod" || mode == "mbtmd" {
    @exec.run(
      moonc,
      ["syncheck", "-error-format", "json", fname],
      wd,
      timeout_ms,
    )
  } else if mode == "mbti" {
    @exec.run(
      moonc,
      [
        "build-interface",
        fname,
        "-o",
        "out.mi",
        "-i",
        builtin + ":moonbitlang/core/builtin",
        "-i",
        prelude + ":prelude",
      ],
      wd,
      timeout_ms,
    )
  } else {
    @exec.run(
      moonc,
      ["syncheck", "-mbtx-frontmatter", "true", fname],
      wd,
      timeout_ms,
    )
  }
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
    r.wasm_kind +
    "|" +
    r.js_kind +
    "|" +
    r.wasm_rc.to_string() +
    "|" +
    r.js_rc.to_string() +
    "|" +
    r.wasm_out +
    "|" +
    r.js_out,
  )
  let b = StringBuilder()
  b.write_string("{\"stage\":\"diff\",\"kind\":\"DIFF\",\"signature\":\"")
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
  b.write_string("\",\"wasm_detail\":\"")
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
) -> Stats {
  let s = stats_new()
  let tag = @corpus.short_hash(cfg.out)
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
  let pkg = "minie135/tpl/cmd/main"
  while @async.now() < end {
    s.it += 1
    let base = rng.choice(seeds)
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
    let k1 = @exec.classify(r1)
    if k1 != "OK" && k1 != "ERR" {
      s.crashes += 1
      if save_crash(cfg, "t1", r1, src, id) {
        ()
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
      let r2 = @exec.run(
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
      )
      s.t2 += 1
      let k2 = @exec.classify(r2)
      if k2 != "OK" && k2 != "ERR" {
        s.crashes += 1
        ignore(save_crash(cfg, "t2", r2, src, id))
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
        if !d.same {
          s.crashes += 1
          ignore(save_diff(cfg, d, src, id))
        }
      }
    }
    let sig = behavior_sig(r1)
    if !local_sigs.contains(sig) {
      local_sigs.set(sig, ())
      s.new_sigs += 1
      let h = @corpus.short_hash(src)
      let corpus_dir = join(cfg.out, "corpus")
      @corpus.ensure_dir(corpus_dir)
      ignore(write(join(corpus_dir, h + ".mbt"), src))
      if local_pool.length() < 400 {
        local_pool.push(src)
      }
    }
  }
  s
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
    "            [--p-deep X] [--p-run X] [--body-only] [--seed N] [--mode mbt|pkg|mod|mbtmd|mbti|mbtx] [--seed-dir DIR] [--fmt-check] [--native-diff]",
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
    } else {
      main_usage()
      return
    }
  }
  let out = cfg.out
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
  println(
    "[mb-fuzz] mode=\{cfg.mode} workers=\{cfg.workers} duration=\{cfg.duration_s}s seeds=\{seeds.length()} dict=\{dict.length()} out=\{out} p_deep=\{cfg.p_deep} p_run=\{cfg.p_run}",
  )
  let tasks : Array[async () -> Stats] = []
  for id in 0..<cfg.workers {
    let w = id
    tasks.push(() => worker(cfg, w, seeds, seeds, dict, moonc, home))
  }
  let results = @async.all(tasks, max_concurrent=cfg.workers)
  let total = stats_new()
  for r in results {
    total.it += r.it
    total.t1 += r.t1
    total.t2 += r.t2
    total.crashes += r.crashes
    total.new_sigs += r.new_sigs
    total.timeouts += r.timeouts
  }
  println(
    "[mb-fuzz done] it=\{total.it} t1=\{total.t1} t2=\{total.t2} crashes=\{total.crashes} new_sigs=\{total.new_sigs}",
  )
}
