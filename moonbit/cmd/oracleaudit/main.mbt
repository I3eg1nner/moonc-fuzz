///|
/// Oracle sensitivity gate.
///
/// WHY THIS EXISTS.  The project's expensive campaigns produced zero findings
/// while a one-line "expects a response, got none" predicate produced two real
/// defects (F11, F12).  The bottleneck was never sample count, it was oracle
/// strength.  So oracle strength is now measured, not assumed: every oracle
/// must be shown to fire on a known defect shape before its silence on a
/// campaign means anything.
///
/// Usage:
///   oracleaudit [--json PATH] [--verbose]
///
/// Exit codes: 0 every oracle proven and quiet on controls,
///             1 unproven/blind/noisy oracle, 2 unwritable output path.
fn pad(s : String, n : Int32) -> String {
  let b = StringBuilder()
  b.write_string(s)
  let mut i = s.char_length()
  while i < n {
    b.write_char(' ')
    i += 1
  }
  b.to_string()
}

///|
fn pad_left(n : Int32, width : Int32) -> String {
  let s = n.to_string()
  let b = StringBuilder()
  let mut i = s.char_length()
  while i < width {
    b.write_char(' ')
    i += 1
  }
  b.write_string(s)
  b.to_string()
}

///|
fn main {
  let args = @env.args()
  let mut json_path = ""
  let mut verbose = false
  for i, a in args {
    if i == 0 {
      continue
    }
    if a == "--json" && i + 1 < args.length() {
      json_path = args[i + 1]
    } else if a == "--verbose" {
      verbose = true
    }
  }
  let specs = @judge.registry()
  let probes = @judge.probes()
  let globals = @judge.global_negatives()
  let result = @judge.audit(specs, probes, globals)

  let head = pad("oracle", 16) +
    pad("pos", 5) +
    pad("caught", 8) +
    pad("neg", 6) +
    pad("fp", 5) +
    "  verdict"
  println(head)
  for s in result.scores {
    let verdict = if s.positives == 0 {
      "UNPROVEN"
    } else if s.caught < s.positives {
      "BLIND"
    } else if s.false_pos > 0 {
      "NOISY"
    } else {
      "ok"
    }
    let line = pad(s.spec, 16) +
      pad_left(s.positives, 5) +
      pad_left(s.caught, 8) +
      pad_left(s.negatives, 6) +
      pad_left(s.false_pos, 5) +
      "  " +
      verdict
    println(line)
    if verbose {
      for m in s.missed {
        println("  missed positive: " + m)
      }
      for m in s.spurious {
        println("  fired on control: " + m)
      }
    }
  }
  println("")
  println(result.to_json())

  if json_path != "" {
    let ok = try {
      @fs.write_string_to_file(json_path, result.to_json() + "\n")
      true
    } catch {
      _ => false
    }
    if !ok {
      println("cannot write " + json_path)
      @env.exit(2)
    }
  }
  if !result.ok() {
    @env.exit(1)
  }
}
