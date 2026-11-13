///|
/// Byte-level fuzzer for inputs that cannot be represented as valid UTF-8
/// Strings (the Python `m_unicode`/`m_bitflip` paths used surrogateescape).
///
/// This is a separate binary because MoonBit `String` is UTF-16; keeping the
/// corpus as `Bytes` avoids silently normalizing exactly the inputs that
/// exercise `Basic_utf8_decode` and the lexer's byte paths.
struct Config {
  mut root : String
  mut out : String
  mut workers : Int32
  mut duration_s : Int32
  mut mode : String
  mut seed : UInt64
  timeout_ms : Int32
}

///|
struct Stats {
  mut it : Int32
  mut ok : Int32
  mut crashes : Int32
  mut timeouts : Int32
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
fn mutate_bytes(src : Bytes, rng : @mutate.Rng, pool : Array[Bytes]) -> Bytes {
  let a = src.to_array()
  let n = rng.int_range(1, 4)
  for _ in 0..<n {
    let op = rng.int(8)
    if op == 0 && a.length() > 0 {
      // bit flip
      let i = rng.int(a.length())
      a[i] = rng.int(256).to_byte()
    } else if op == 1 && a.length() > 1 {
      // delete a range
      let i = rng.int(a.length())
      let k = rng.int_range(1, 8)
      let mut j = 0
      while j < k && i < a.length() {
        ignore(a.remove(i))
        j += 1
      }
    } else if op == 2 {
      // insert random bytes
      let i = rng.int(a.length() + 1)
      let k = rng.int_range(1, 8)
      for _ in 0..<k {
        a.insert(i, rng.int(256).to_byte())
      }
    } else if op == 3 && a.length() > 1 {
      // truncate
      let cut = rng.int_range(1, a.length())
      while a.length() > cut {
        ignore(a.pop())
      }
    } else if op == 4 && a.length() > 0 && a.length() < 6000 {
      // duplicate a slice
      let i = rng.int(a.length())
      let k = rng.int_range(1, 64)
      let end = if i + k < a.length() { i + k } else { a.length() }
      let copy = []
      for j in i..<end {
        copy.push(a[j])
      }
      let at = rng.int(a.length() + 1)
      for j, b in copy {
        a.insert(at + j, b)
      }
    } else if op == 5 && pool.length() > 0 {
      // splice a random pool slice
      let other = rng.choice(pool)
      if other.length() > 0 {
        let i = rng.int(other.length())
        let k = rng.int_range(1, 64)
        let end = if i + k < other.length() { i + k } else { other.length() }
        let at = rng.int(a.length() + 1)
        let mut j = 0
        for x in i..<end {
          a.insert(at + j, other[x])
          j += 1
        }
      }
    } else if op == 6 {
      // classic invalid UTF-8 sequences
      let bad : Array[Array[Int32]] = [
        [0xC0, 0x80],
        [0xED, 0xA0, 0x80],
        [0xF4, 0x90, 0x80, 0x80],
        [0x80],
        [0xFF],
        [0xFE],
        [0xC2],
        [0xE2, 0x28, 0xA1],
      ]
      let seq = rng.choice(bad)
      let at = rng.int(a.length() + 1)
      for j, v in seq {
        a.insert(at + j, v.to_byte())
      }
    } else if a.length() > 0 {
      // replace a byte with an ASCII delimiter/quote/backslash
      let i = rng.int(a.length())
      let chars = [34, 39, 92, 123, 125, 40, 41, 91, 93, 10, 0]
      a[i] = rng.choice(chars).to_byte()
    }
    if a.length() > 20000 {
      while a.length() > 20000 {
        ignore(a.pop())
      }
    }
  }
  Bytes::from_array(a)
}

///|
fn save_bytes_finding(
  cfg : Config,
  stage : String,
  kind : String,
  detail : String,
  r : @exec.RunResult,
  bytes : Bytes,
  ext : String,
  worker : Int32,
) -> Unit {
  let sig = @corpus.short_hash(stage + "|" + kind + "|" + detail)
  let d = join(join(join(join(cfg.out, "findings"), stage), kind), sig)
  @corpus.ensure_dir(d)
  let case = join(d, "case" + ext)
  if !@fs.path_exists(case) {
    @fs.write_bytes_to_file(case, bytes) catch {
      _ => ()
    }
    let meta = "{\"stage\":\"" +
      stage +
      "\",\"kind\":\"" +
      kind +
      "\",\"detail\":\"" +
      detail +
      "\",\"signature\":\"" +
      sig +
      "\",\"rc\":" +
      r.rc.to_string() +
      ",\"ms\":" +
      r.ms.to_string() +
      ",\"worker\":" +
      worker.to_string() +
      "}"
    @fs.write_string_to_file(join(d, "meta.json"), meta) catch {
      _ => ()
    }
  }
}

///|
async fn worker(
  cfg : Config,
  id : Int32,
  seeds : Array[Bytes],
  pool : Array[Bytes],
  moonc : String,
  home : String,
) -> Stats {
  let s = { it: 0, ok: 0, crashes: 0, timeouts: 0, }
  let tag = @corpus.short_hash(cfg.out)
  let wd = join(join("/tmp/mbtfuzz_bytes", tag), "w" + id.to_string())
  rm_rf(wd)
  @corpus.ensure_dir(wd)
  let rng = @mutate.Rng::new(cfg.seed + id.to_uint64() * 0x9E3779B97F4A7C15UL)
  let fname = fname_of(cfg.mode)
  let ext = if cfg.mode == "pkg" {
    ".pkg"
  } else if cfg.mode == "mod" {
    ".mod"
  } else {
    ".mbt"
  }
  let builtin = join(
    home, ".moon/lib/core/_build/wasm/release/bundle/builtin/builtin.mi",
  )
  let prelude = join(
    home, ".moon/lib/core/_build/wasm/release/bundle/prelude/prelude.mi",
  )
  let end = @async.now() + cfg.duration_s.to_int64() * 1000L
  while @async.now() < end {
    s.it += 1
    let src = mutate_bytes(rng.choice(seeds), rng, pool)
    @fs.write_bytes_to_file(join(wd, fname), src) catch {
      _ => continue
    }
    let args = if cfg.mode == "mbti" {
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
    } else if cfg.mode == "mbtx" {
      ["syncheck", "-mbtx-frontmatter", "true", fname]
    } else {
      ["syncheck", "-error-format", "json", fname]
    }
    let r = @exec.run(moonc, args, wd, cfg.timeout_ms)
    let kind = @exec.classify(r)
    if r.timed_out {
      s.timeouts += 1
    }
    if kind == "OK" {
      s.ok += 1
    } else if kind != "ERR" {
      s.crashes += 1
      save_bytes_finding(cfg, "t1", kind, @exec.ice_detail(r), r, src, ext, id)
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
fn load_bytes(
  root : String,
  suffixes : Array[String],
  limit : Int32,
) -> Array[Bytes] {
  let files = @corpus.collect_files(root, suffixes, 12000, limit)
  let out : Array[Bytes] = []
  for p in files {
    let b = @fs.read_file_to_bytes(p) catch { _ => Bytes::new(0) }
    if b.length() > 0 {
      out.push(b)
    }
  }
  out
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
    out: "/data/audit/mbtfuzz/out/mb_bytefuzz",
    workers: 32,
    duration_s: 60,
    mode: "mbt",
    seed: 1UL,
    timeout_ms: 8000,
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
    } else if a == "--mode" && i + 1 < args.length() {
      cfg.mode = args[i + 1]
      i += 2
    } else if a == "--seed" && i + 1 < args.length() {
      cfg.seed = parse_int(args[i + 1], 1).to_uint64()
      i += 2
    } else {
      println("bad arg: " + a)
      return
    }
  }
  @corpus.ensure_dir(join(cfg.out, "findings"))
  let seeds = load_bytes(join(cfg.root, "seeds"), suffixes_of(cfg.mode), 400)
  if seeds.length() == 0 {
    println("no seeds")
    return
  }
  let moonc = join(home, ".moon/bin/moonc")
  println(
    "[bytefuzz] mode=\{cfg.mode} workers=\{cfg.workers} seeds=\{seeds.length()} out=\{cfg.out}",
  )
  let tasks : Array[async () -> Stats] = []
  for id in 0..<cfg.workers {
    let w = id
    tasks.push(() => worker(cfg, w, seeds, seeds, moonc, home))
  }
  let rs = @async.all(tasks, max_concurrent=cfg.workers)
  let total = { it: 0, ok: 0, crashes: 0, timeouts: 0, }
  for r in rs {
    total.it += r.it
    total.ok += r.ok
    total.crashes += r.crashes
    total.timeouts += r.timeouts
  }
  println(
    "[bytefuzz done] it=\{total.it} ok=\{total.ok} crashes=\{total.crashes} timeouts=\{total.timeouts}",
  )
}
