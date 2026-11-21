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
/// Parse a decimal seconds value scaled by 100 ("814.39" -> 81439).
fn parse_x100(s : String) -> Int64 {
  let mut i = 0
  let mut n = 0L
  let mut frac = 0L
  let mut frac_digits = 0
  while i < s.length() && s.get_char(i) != Some('.') {
    match s.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
        } else {
          return 0L
        }
      None => break
    }
    i += 1
  }
  if i < s.length() && s.get_char(i) == Some('.') {
    i += 1
    while i < s.length() && frac_digits < 2 {
      match s.get_char(i) {
        Some(c) =>
          if c >= '0' && c <= '9' {
            frac = frac * 10L + (c.to_int() - '0'.to_int()).to_int64()
            frac_digits += 1
          } else {
            break
          }
        None => break
      }
      i += 1
    }
  }
  while frac_digits < 2 {
    frac = frac * 10L
    frac_digits += 1
  }
  n * 100L + frac
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
///|
/// (adds_sat_ms, edges_sat_ms, has_time).  Saturation = the cumulative value
/// stops increasing well before the run ends; such an arm cannot contribute
/// a benefit statistic.
fn saturation_ms(stats_path : String) -> (Int64, Int64, Bool) {
  let text = read(stats_path)
  let times : Array[Int64] = []
  let adds : Array[Int64] = []
  let edges : Array[Int64] = []
  let mut has_time = true
  for line in text.split("\n") {
    let s = line.trim().to_owned()
    if s.has_prefix("{") {
      if !s.contains("\"elapsed_ms\"") {
        has_time = false
      }
      times.push(num_field(s, "elapsed_ms"))
      adds.push(num_field(s, "coverage_adds"))
      edges.push(num_field(s, "new_edges"))
    }
  }
  if !has_time || times.length() < 2 {
    return (0L, 0L, has_time)
  }
  let last_ms = times[times.length() - 1]
  let mut adds_sat = last_ms
  if adds[adds.length() - 1] > 0L {
    let fa = adds[adds.length() - 1]
    let mut i = 0
    while i < adds.length() {
      if adds[i] == fa {
        adds_sat = times[i]
        break
      }
      i += 1
    }
  }
  let mut edges_sat = last_ms
  if edges[edges.length() - 1] > 0L {
    let fe = edges[edges.length() - 1]
    let mut i = 0
    while i < edges.length() {
      if edges[i] == fe {
        edges_sat = times[i]
        break
      }
      i += 1
    }
  }
  (adds_sat, edges_sat, true)
}

///|
fn saturation_last_ms(stats_path : String) -> Int64 {
  let text = read(stats_path)
  let mut last = 0L
  for line in text.split("\n") {
    let s = line.trim().to_owned()
    if s.has_prefix("{") {
      last = num_field(s, "elapsed_ms")
    }
  }
  last
}

///|
/// Backpressure adequacy: completed / (completed + failed + deferred) >= 0.8.
fn completion_ok(completed : Int64, failed : Int64, deferred : Int64) -> Bool {
  let total = completed + failed + deferred
  if total <= 0L {
    return true
  }
  completed * 10L >= total * 8L
}

fn field_text(line : String, key : String) -> String {
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
///|
/// Windows are 60 s buckets of the real elapsed time, not fixed sample
/// counts.  Returns (values, has_fields, has_time): a stats file without
/// coverage_adds/new_edges or elapsed_ms makes the window metric invalid
/// rather than zero.
fn window_deltas(stats_path : String) -> (Array[Int64], Bool, Bool) {
  let text = read(stats_path)
  let times : Array[Int64] = []
  let adds : Array[Int64] = []
  let edges : Array[Int64] = []
  let mut has_fields = false
  let mut has_time = false
  for line in text.split("\n") {
    let s = line.trim().to_owned()
    if s.has_prefix("{") {
      if s.contains("\"coverage_adds\"") && s.contains("\"new_edges\"") {
        has_fields = true
      }
      if s.contains("\"elapsed_ms\"") {
        has_time = true
      }
      times.push(num_field(s, "elapsed_ms"))
      adds.push(num_field(s, "coverage_adds"))
      edges.push(num_field(s, "new_edges"))
    }
  }
  let windows : Array[Int64] = []
  if has_fields && has_time {
    let bucket_ms = 60000L
    let mut last_bucket = -1L
    let mut last_total = 0L
    for i, t in times {
      let b = t / bucket_ms
      let total = adds[i] + edges[i]
      if b != last_bucket {
        if last_bucket >= 0 && total >= last_total {
          windows.push(total - last_total)
        }
        last_bucket = b
        last_total = total
      }
    }
  }
  (windows, has_fields, has_time)
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 || args[1] == "--help" {
    println("usage: benchstat OUT")
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
    let parts : Array[String] = []
    for p in time_text.split(" ") {
      if p.trim().length() > 0 {
        parts.push(p.trim().to_owned())
      }
    }
    let mut cpu_x100 = 0L
    for i in 0..<2 {
      if i < parts.length() {
        cpu_x100 += parse_x100(parts[i])
      }
    }
    let rss_kb = if parts.length() >= 3 {
      num_field("{\"v\":" + parts[2] + "}", "v")
    } else {
      0L
    }
    let (windows, has_fields, has_time) = window_deltas(join(dir, "stats.jsonl"))
    let (adds_sat, edges_sat, sat_time) = saturation_ms(
      join(dir, "stats.jsonl"),
    )
    let baseline = field_text(summary, "baseline_state")
    let edge_status = field_text(summary, "edge_status")
    let reasons : Array[String] = []
    if baseline != "complete" {
      reasons.push("baseline=" + baseline)
    }
    if edge_status == "degraded_cap" {
      reasons.push("edge=degraded_cap")
    }
    if !has_fields {
      reasons.push("stats missing coverage_adds/new_edges")
    }
    if !has_time {
      reasons.push("stats missing elapsed_ms")
    }
    let completed = num_field(summary, "trace_completed")
    let failed = num_field(summary, "trace_failed")
    let deferred = num_field(summary, "trace_deferred")
    if !completion_ok(completed, failed, deferred) {
      reasons.push(
        "trace completion " +
        completed.to_string() +
        "/" +
        (completed + failed + deferred).to_string(),
      )
    }
    if sat_time && has_time {
      // The run's last sample time is the denominator for "well before end".
      let last_ms = saturation_last_ms(join(dir, "stats.jsonl"))
      if last_ms > 0L {
        if adds_sat > 0L && adds_sat * 10L < last_ms * 8L {
          reasons.push("adds saturated at " + (adds_sat / 1000L).to_string() + "s")
        }
        if edges_sat > 0L && edges_sat * 10L < last_ms * 8L {
          reasons.push("edges saturated at " + (edges_sat / 1000L).to_string() + "s")
        }
      }
    }
    let valid = reasons.length() == 0
    if !first {
      b.write_string(",\n")
    }
    first = false
    b.write_string("{\"arm\":\"" + arm + "\"")
    b.write_string(",\"it\":" + num_field(summary, "it").to_string())
    b.write_string(",\"t2_ok\":" + num_field(summary, "t2_ok").to_string())
    b.write_string(",\"adds\":" + num_field(summary, "coverage_adds").to_string())
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
    b.write_string(",\"cpu_s\":" + (cpu_x100.to_double() / 100.0).to_string())
    b.write_string(",\"rss_mb\":" + (rss_kb / 1024L).to_string())
    b.write_string(
      ",\"median_window\":" +
      (if valid && windows.length() > 0 {
        median(windows).to_string()
      } else {
        "null"
      }),
    )
    b.write_string(",\"windows\":" + windows.length().to_string())
    b.write_string(",\"valid\":" + (if valid { "true" } else { "false" }))
    b.write_string(",\"invalid_reasons\":[")
    for i, r in reasons {
      if i > 0 {
        b.write_string(",")
      }
      b.write_string("\"" + @stager.escape(r) + "\"")
    }
    b.write_string("]}")
  }
  b.write_string("\n]")
  println(b.to_string())
}
