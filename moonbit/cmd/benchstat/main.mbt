// Summarize the three feedback arms produced by scripts/bench_campaigns.sh.
//
// The repository keeps no Python on the main branch, so this is a MoonBit
// command rather than a script.  It reads only the artifacts the campaign
// writes (summary.json, stats.jsonl, <arm>.time) and keeps the parsing
// deliberately small: the formats are ours.
//
// Usage: benchstat DIR

///|
fn usage() -> Unit {
  println("usage: benchstat DIR")
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
/// Digits after `"key":` — enough for ints and simple floats, which is all the
/// campaign summaries contain.
fn num_field(text : String, key : String) -> Int64 {
  let pat = "\"" + key + "\":"
  let i = match text.find(pat) {
    None => return 0L
    Some(i) => i + pat.length()
  }
  let mut j = i
  let mut neg = false
  if j < text.length() && text.get_char(j) == Some('-') {
    neg = true
    j += 1
  }
  let mut n = 0L
  let mut seen = false
  while j < text.length() {
    match text.get_char(j) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
          seen = true
          j += 1
        } else {
          break
        }
      None => break
    }
  }
  if !seen {
    return 0L
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
fn read(path : String) -> String {
  @stager.read_text(path)
}

///|
fn list_dir(path : String) -> Array[String] {
  @stager.try_read_dir(path)
}

///|
fn latest_run(arm_dir : String) -> String {
  if !@stager.path_exists(arm_dir) {
    return ""
  }
  let names = list_dir(arm_dir)
  let mut best = ""
  for n in names {
    let full = join(arm_dir, n)
    let isd = @fs.is_dir(full) catch { _ => false }
    if isd && n > best {
      best = n
    }
  }
  best
}

///|
fn median(xs : Array[Int64]) -> Int64 {
  if xs.length() == 0 {
    return 0L
  }
  let ys = xs.copy()
  ys.sort()
  ys[ys.length() / 2]
}

///|
/// Cumulative counters sampled every ~2 s; convert to per-30-sample windows
/// (~60 s) so the table reports "new stable features per minute", using the
/// median window rather than the total to reduce startup bias.
fn window_deltas(stats_path : String) -> Array[Int64] {
  let text = read(stats_path)
  let samples : Array[(Int64, Int64)] = []
  for line in text.split("\n") {
    let s = line.trim().to_owned()
    if s.has_prefix("{") {
      samples.push((num_field(s, "coverage_adds"), num_field(s, "new_edges")))
    }
  }
  let deltas : Array[Int64] = []
  let mut i = 1
  while i < samples.length() {
    let (a0, e0) = samples[i - 1]
    let (a1, e1) = samples[i]
    deltas.push(a1 - a0 + (e1 - e0))
    i += 1
  }
  let windows : Array[Int64] = []
  let mut k = 0
  while k < deltas.length() {
    let mut sum = 0L
    let mut j = k
    while j < deltas.length() && j < k + 30 {
      sum += deltas[j]
      j += 1
    }
    if sum >= 0L {
      windows.push(sum)
    }
    k += 30
  }
  windows
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 || args[1] == "--help" {
    usage()
    return
  }
  let out = args[1]
  let arms = ["behavior", "function", "func-edge"]
  let b = StringBuilder()
  b.write_string("[\n")
  let mut first = true
  for arm in arms {
    let run = latest_run(join(out, arm))
    if run == "" {
      continue
    }
    let dir = join(join(out, arm), run)
    let summary = read(join(dir, "summary.json"))
    let time_text = read(join(out, arm + ".time"))
    // "user sys maxrss_kb"
    let parts : Array[String] = []
    for p in time_text.split(" ") {
      if p.trim().length() > 0 {
        parts.push(p.trim().to_owned())
      }
    }
    let mut cpu_tenths = 0L
    for i in 0..<2 {
      if i < parts.length() {
        cpu_tenths += num_field("{\"v\":" + parts[i] + "}", "v")
      }
    }
    let rss_kb = if parts.length() >= 3 {
      num_field("{\"v\":" + parts[2] + "}", "v")
    } else {
      0L
    }
    let windows = window_deltas(join(dir, "stats.jsonl"))
    if !first {
      b.write_string(",\n")
    }
    first = false
    b.write_string("{\"arm\":\"" + arm + "\"")
    b.write_string(",\"it\":" + num_field(summary, "it").to_string())
    b.write_string(",\"t2_ok\":" + num_field(summary, "t2_ok").to_string())
    b.write_string(
      ",\"adds\":" + num_field(summary, "coverage_adds").to_string(),
    )
    b.write_string(",\"edges\":" + num_field(summary, "new_edges").to_string())
    b.write_string(
      ",\"completed\":" + num_field(summary, "trace_completed").to_string(),
    )
    b.write_string(
      ",\"dropped\":" + num_field(summary, "trace_dropped").to_string(),
    )
    b.write_string(
      ",\"failed\":" + num_field(summary, "trace_failed").to_string(),
    )
    b.write_string(",\"cpu_s\":" + (cpu_tenths.to_double() / 10.0).to_string())
    b.write_string(",\"rss_mb\":" + (rss_kb / 1024L).to_string())
    b.write_string(",\"median_window\":" + median(windows).to_string())
    b.write_string(",\"windows\":" + windows.length().to_string() + "}")
  }
  b.write_string("\n]")
  println(b.to_string())
}
