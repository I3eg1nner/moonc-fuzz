// Diagnostic for the RSS question the 2 h soak raised: is memory retained per
// spawned child (async runtime) or per campaign iteration (corpus/stats)?
//
// Usage: spawnprobe [--n N] [--cmd true|moonc]

///|
async fn rss_mb() -> Int64 {
  let r = @exec.run(
    "/bin/sh",
    ["-c", "grep VmRSS /proc/$PPID/status"],
    "/tmp",
    2000,
  )
  let t = r.stdout
  let d = match t.find(":") {
    Some(i) => t[i + 1:].to_owned().trim()
    None => ""
  }
  let mut n = 0L
  for c in d {
    if c >= '0' && c <= '9' {
      n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
    } else {
      break
    }
  }
  n / 1024L
}

///|
async fn main {
  let args = @env.args()
  let mut n = 4000
  let mut cmd = "true"
  let mut i = 1
  while i < args.length() {
    if args[i] == "--n" && i + 1 < args.length() {
      n = parse_num(args[i + 1])
      i += 2
    } else if args[i] == "--cmd" && i + 1 < args.length() {
      cmd = args[i + 1]
      i += 2
    } else {
      i += 1
    }
  }
  let first = rss_mb()
  println("start rss=" + first.to_string() + " MB cmd=" + cmd)
  for k in 0..<n {
    if cmd == "moonc" {
      let _ = @exec.run(
        "/home/user/.moon/bin/moonc",
        [
          "syncheck", "-error-format", "json", "/data/audit/mbtfuzz/templates/01_int_ops.mbt",
        ],
        "/tmp",
        20000,
      )
    } else {
      let _ = @exec.run("/bin/true", [], "/tmp", 5000)
    }
    if k % 1000 == 999 {
      println(
        "n=" + (k + 1).to_string() + " rss=" + rss_mb().to_string() + " MB",
      )
    }
  }
  println("end rss=" + rss_mb().to_string() + " MB")
}

///|
fn parse_num(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
  }
  n
}
