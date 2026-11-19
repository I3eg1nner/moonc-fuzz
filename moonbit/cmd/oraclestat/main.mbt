///|
/// Oracle statistics for the methodology write-up.
///
/// Three measurements, each answering a different question:
///
/// 1. **Decision matrix.** On the labelled probes, does every oracle fire on
///    its positives and stay silent on its controls?  A single missed positive
///    means the oracle's silence is not evidence; a single control hit means
///    the oracle manufactures defects.
/// 2. **Boundary vectors.** For each numeric axis, the exact values that flip
///    the decision.  This is what makes a threshold auditable: "timeout with
///    >= 50% CPU is a busy hang" is only meaningful together with the bit where
///    49% stops being a hang.
/// 3. **End-to-end false positives.** Real `moon build` runs on a generated
///    corpus whose truth is known (compiles clean / has a plain type error).
///    Any finding there is a false alarm, and with `n` clean runs the 95% upper
///    bound on the false-positive rate is the rule-of-three value `3/n`.

///|
fn usage() -> Unit {
  println(
    "usage: oraclestat [--clean N] [--broken N] [--stage S] [--target T] " +
    "[--json PATH] " +
    "[--root DIR] [--timeout-ms N] [--keep]",
  )
}

///|
/// Rule of three: with zero events in `n` trials the 95% upper bound on the
/// rate is about `3/n`.  Stated as an approximation because the exact
/// Clopper-Pearson value for `0/n` is `1 - 0.025^(1/n)`, which needs a
/// logarithm; the two agree to within 15% for `n >= 10`.
fn upper95_zero(n : Int32) -> Double {
  if n <= 0 {
    0.0
  } else {
    3.0 / n.to_double()
  }
}

///|
fn yn(b : Bool) -> String {
  if b {
    "Y"
  } else {
    "N"
  }
}

///|
fn fires(oracle : String, obs : @judge.Observation) -> Bool {
  for s in @judge.registry() {
    if s.id == oracle {
      return @judge.check(s, obs).length() > 0
    }
  }
  false
}

///|
fn matrix_line(spec : @judge.OracleSpec) -> String {
  let mut positives = 0
  let mut hits = 0
  let mut controls = 0
  let mut false_alarms = 0
  for p in @judge.probes() {
    if p.spec == spec.id {
      let n = @judge.check(spec, p.obs).length()
      if p.want_hit {
        positives += 1
        if n > 0 {
          hits += 1
        }
      } else {
        controls += 1
        if n > 0 {
          false_alarms += 1
        }
      }
    }
  }
  let b = StringBuilder()
  b.write_string("{\"oracle\":\"" + @stager.escape(spec.id) + "\"")
  b.write_string(",\"positives\":" + positives.to_string())
  b.write_string(",\"hits\":" + hits.to_string())
  b.write_string(",\"controls\":" + controls.to_string())
  b.write_string(",\"false_alarms\":" + false_alarms.to_string())
  b.write_string("}")
  b.to_string()
}

///|
/// One boundary vector: `label=[v:Y v:N ...]`.
fn vec(label : String, b : StringBuilder) -> String {
  let s = b.to_string().trim().to_owned()
  label + s + "]"
}

///|
fn sweep_cpu(
  oracle : String,
  wall : Int64,
  alive : Bool,
  expects : Bool,
) -> String {
  let b = StringBuilder()
  let vals : Array[Int64] = [0L, 50L, 500L, 1400L, 1500L, 1600L, 3000L]
  for v in vals {
    let obs = @judge.observation(
      "lsp", -1, true, wall, v, 0, expects, alive, "", "",
    )
    b.write_string(v.to_string() + ":" + yn(fires(oracle, obs)) + " ")
  }
  b.to_string()
}

///|
/// The decision-boundary vectors.  Every axis is numeric or boolean, so each
/// line is a finite falsifiable statement about the classifier.
fn boundaries() -> Array[String] {
  let out : Array[String] = []
  // crash: signal exits only.  rc 139 is a positive value, not a signal, and
  // must not be read as one.
  let b = StringBuilder()
  let rcs : Array[Int32] = [0, 1, 2, 134, 139, 255, -6, -11]
  for rc in rcs {
    let obs = @judge.observation(
      "build", rc, false, 100L, 90L, 0, false, false, "", "Error: type mismatch\n",
    )
    b.write_string(rc.to_string() + ":" + yn(fires("crash", obs)) + " ")
  }
  out.push(vec("crash/rc=[", b))
  // crash markers: stderr only.
  let b2 = StringBuilder()
  let names : Array[String] = ["ice", "oom", "exn", "stack", "assert"]
  let marks : Array[String] = [
    "Oops, the compiler has encountered an exception", "out of memory", "Fatal error: exception",
    "Stack overflow", "Assert_failure",
  ]
  let mut mi = 0
  while mi < marks.length() {
    let obs = @judge.observation(
      "build",
      1,
      false,
      100L,
      90L,
      0,
      false,
      false,
      "",
      marks[mi] + "\n",
    )
    b2.write_string(names[mi] + ":" + yn(fires("crash", obs)) + " ")
    mi += 1
  }
  // Same markers on stdout must not count.
  let mut si = 0
  while si < marks.length() {
    let obs = @judge.observation(
      "build",
      1,
      false,
      100L,
      90L,
      0,
      false,
      false,
      marks[si] + "\n",
      "",
    )
    b2.write_string("stdout-" + names[si] + ":" + yn(fires("crash", obs)) + " ")
    si += 1
  }
  out.push(vec("crash/markers=[", b2))
  out.push(
    "busy_hang/cpu_ms(wall=3000,alive)=" +
    sweep_cpu("busy_hang", 3000L, true, true),
  )
  out.push(
    "blocked_stall/cpu_ms(wall=3000,alive,owes)=" +
    sweep_cpu("blocked_stall", 3000L, true, true),
  )
  out.push(
    "blocked_stall/cpu_ms(not alive)=" +
    sweep_cpu("blocked_stall", 3000L, false, true),
  )
  out.push(
    "blocked_stall/cpu_ms(no output owed)=" +
    sweep_cpu("blocked_stall", 3000L, true, false),
  )
  out.push(
    "timeout_plain/cpu_ms(wall=3000,dead)=" +
    sweep_cpu("timeout_plain", 3000L, false, false),
  )
  // missing_frames: only frame 0 with an owed contract.
  let b3 = StringBuilder()
  let frames : Array[Int32] = [0, 1, 2]
  for f in frames {
    let obs = @judge.observation(
      "lsp", 0, false, 100L, 90L, f, true, false, "", "",
    )
    b3.write_string(
      f.to_string() + ":" + yn(fires("missing_frames", obs)) + " ",
    )
  }
  out.push(vec("missing_frames/frames=[", b3))
  // nonzero_silent: positive exit, no diagnostic.
  let b4 = StringBuilder()
  for rc in [0, 1, 2] {
    let obs = @judge.observation(
      "build", rc, false, 100L, 90L, 0, false, false, "", "",
    )
    b4.write_string(
      rc.to_string() + ":" + yn(fires("nonzero_silent", obs)) + " ",
    )
  }
  out.push(vec("nonzero_silent/rc=[", b4))
  // orphan_leak: alive child without a timeout.
  let b5 = StringBuilder()
  for alive in [false, true] {
    let obs = @judge.observation(
      "build", 0, false, 100L, 90L, 0, false, alive, "", "",
    )
    b5.write_string(yn(alive) + ":" + yn(fires("orphan_leak", obs)) + " ")
  }
  out.push(vec("orphan_leak/alive=[", b5))
  out
}

///|
struct Corpus {
  n : Int32
  defects : Int32
  unexpected : Int32
  ms : Int64
}

///|
async fn run_corpus(
  root : String,
  cases : Array[@numgen.Case],
  broken : Bool,
  stage : String,
  target : String,
  timeout_ms : Int32,
) -> Corpus {
  let mut n = 0
  let mut defects = 0
  let mut unexpected = 0
  let mut ms = 0L
  let tag = if broken { "b" } else { "c" }
  for i, c in cases {
    let dir = @stager.join(root, tag + i.to_string())
    @stager.rm_rf(dir)
    let _ = try {
      @fs.create_dir(dir)
      true
    } catch {
      _ => false
    }
    let body = if broken {
      c.src + "\nfn __fpr_probe() -> Int {\n  \"not an int\"\n}\n"
    } else {
      c.src
    }
    let _ = @stager.write_text(
      @stager.join(dir, "moon.mod"),
      "name = \"repro/oraclestat\"\nversion = \"0.1.0\"\n",
    )
    let _ = @stager.write_text(
      @stager.join(dir, "moon.pkg"),
      "pkgtype(kind: \"executable\")\n",
    )
    let _ = @stager.write_text(@stager.join(dir, "main.mbt"), body)
    let r = @stager.run_stage(stage, target, dir, timeout_ms)
    n += 1
    ms += r.ms
    if @stager.is_defect(stage, r) {
      defects += 1
    }
    // A clean case that does not compile, or a broken case that does, means
    // the corpus itself is wrong and the false-positive count is meaningless.
    let ok = if broken { r.rc != 0 } else { r.rc == 0 }
    if !ok {
      unexpected += 1
      println("corpus-mismatch: " + dir + " rc=" + r.rc.to_string())
    }
  }
  { n, defects, unexpected, ms, }
}

///|
fn corpus_json(name : String, c : Corpus) -> String {
  let b = StringBuilder()
  b.write_string("{\"name\":\"" + name + "\"")
  b.write_string(",\"n\":" + c.n.to_string())
  b.write_string(",\"defects\":" + c.defects.to_string())
  b.write_string(",\"unexpected\":" + c.unexpected.to_string())
  b.write_string(",\"ms\":" + c.ms.to_string())
  b.write_string(",\"upper95\":" + upper95_zero(c.n).to_string())
  b.write_string("}")
  b.to_string()
}

///|
async fn main {
  let args = @env.args()
  let mut n_clean = 24
  let mut n_broken = 24
  let mut target = "wasm-gc"
  let mut stage = "build"
  let mut json_path = ""
  let mut root = "/tmp/oraclestat"
  let mut timeout_ms = 20000
  let mut keep = false
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--clean" && i + 1 < args.length() {
      n_clean = @stager.parse_int(args[i + 1], n_clean)
      i += 2
    } else if a == "--broken" && i + 1 < args.length() {
      n_broken = @stager.parse_int(args[i + 1], n_broken)
      i += 2
    } else if a == "--target" && i + 1 < args.length() {
      target = args[i + 1]
      i += 2
    } else if a == "--stage" && i + 1 < args.length() {
      stage = args[i + 1]
      i += 2
    } else if a == "--json" && i + 1 < args.length() {
      json_path = args[i + 1]
      i += 2
    } else if a == "--root" && i + 1 < args.length() {
      root = args[i + 1]
      i += 2
    } else if a == "--timeout-ms" && i + 1 < args.length() {
      timeout_ms = @stager.parse_int(args[i + 1], timeout_ms)
      i += 2
    } else if a == "--keep" {
      keep = true
      i += 1
    } else if a == "--help" {
      usage()
      return
    } else {
      println("unknown argument: " + a)
      usage()
      return
    }
  }
  // --- decision matrix ---
  let mlines : Array[String] = []
  for s in @judge.registry() {
    mlines.push(matrix_line(s))
  }
  println("== decision matrix (labelled probes) ==")
  for s in @judge.registry() {
    let line = matrix_line(s)
    println("  " + s.id + " " + line)
  }
  println("== decision boundaries ==")
  let blines = boundaries()
  for l in blines {
    println("  " + l)
  }
  // --- end-to-end ---
  println("== end-to-end false positives (real moon build) ==")
  let all = @numgen.cases()
  let cases : Array[@numgen.Case] = []
  let mut k = 0
  while k < all.length() && cases.length() < n_clean.max(n_broken) {
    cases.push(all[k])
    k += 1
  }
  let clean_cases : Array[@numgen.Case] = []
  let broken_cases : Array[@numgen.Case] = []
  let mut j = 0
  while j < cases.length() {
    if j < n_clean {
      clean_cases.push(cases[j])
    }
    if j < n_broken {
      broken_cases.push(cases[j])
    }
    j += 1
  }
  let made = try {
    @fs.create_dir(root)
    true
  } catch {
    _ => false
  }
  if !made && !@fs.path_exists(root) {
    println("cannot create " + root)
    return
  }
  let clean = run_corpus(root, clean_cases, false, stage, target, timeout_ms)
  let broken = run_corpus(root, broken_cases, true, stage, target, timeout_ms)
  println(
    "  clean  n=" +
    clean.n.to_string() +
    " defects=" +
    clean.defects.to_string() +
    " unexpected=" +
    clean.unexpected.to_string() +
    " ms=" +
    clean.ms.to_string(),
  )
  println(
    "  broken n=" +
    broken.n.to_string() +
    " defects=" +
    broken.defects.to_string() +
    " unexpected=" +
    broken.unexpected.to_string() +
    " ms=" +
    broken.ms.to_string(),
  )
  let total_ms = clean.ms + broken.ms
  let total_n = clean.n + broken.n
  let per = if total_n > 0 {
    total_ms.to_double() / total_n.to_double()
  } else {
    0.0
  }
  let per_hour = if per > 0.0 { 3600000.0 / per } else { 0.0 }
  println(
    "  cost: " +
    per.to_string() +
    " ms/observation, " +
    per_hour.to_string() +
    " observations/hour",
  )
  if !keep {
    @stager.rm_rf(root)
  }
  if json_path != "" {
    let b = StringBuilder()
    b.write_string(
      "{\"clean\":" +
      corpus_json("clean", clean) +
      ",\"broken\":" +
      corpus_json("broken", broken) +
      ",\"decision\":[",
    )
    let mut first = true
    for l in mlines {
      if !first {
        b.write_string(",")
      }
      b.write_string(l)
      first = false
    }
    b.write_string("],\"boundaries\":[")
    let mut first2 = true
    for l in blines {
      if !first2 {
        b.write_string(",")
      }
      b.write_string("\"" + @stager.escape(l) + "\"")
      first2 = false
    }
    b.write_string("],\"ms_per_observation\":" + per.to_string())
    b.write_string(",\"observations_per_hour\":" + per_hour.to_string())
    b.write_string("}")
    let _ = @stager.write_text(json_path, b.to_string())
  }
}
