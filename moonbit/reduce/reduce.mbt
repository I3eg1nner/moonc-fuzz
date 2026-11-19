// Automatic test-case reduction.
//
// WHY THIS EXISTS.  Every one of the twelve reproduced defects was minimised by
// hand, which is the step that turns "interesting crash" into "fileable bug".
// Doing it by hand caps throughput at a few defects per day no matter how good
// the generator becomes.
//
// The core is deliberately a state machine, not a `reduce(src, predicate)`
// function: the real predicate spawns the compiler, and that is `async` in
// MoonBit, so a synchronous callback cannot express it.  Driver inversion also
// makes the engine testable with a pure in-memory predicate.

///|
/// A reduction in progress.  Callers drive it as:
///
///     let r = start(src, fuel)
///     while candidate(r) is Some(text) {
///       verdict(r, still_fails(text))
///     }
///
/// `candidate` is idempotent: asking twice without a verdict returns the same
/// text, so a caller may retry without corrupting the state.

///|
pub(all) struct Reducer {
  mut lines : Array[String]
  /// Number of partitions in the current line-level sweep.
  mut gran : Int32
  /// Next partition to try at `gran`.
  mut idx : Int32
  /// Candidate awaiting a verdict.  Storing the lines (not the text) keeps
  /// `result()` exact and avoids re-splitting.
  mut pending : Array[String]?
  /// Brace spans for the block phase, recomputed whenever `lines` changes.
  mut spans : Array[(Int32, Int32)]
  mut blocks_done : Bool
  mut calls : Int32
  mut fuel : Int32
  mut exhausted : Bool
}

///|
pub fn start(src : String, fuel : Int32) -> Reducer {
  let r : Reducer = {
    lines: split_lines(src),
    gran: 2,
    idx: 0,
    pending: None,
    spans: [],
    blocks_done: false,
    calls: 0,
    fuel,
    exhausted: false,
  }
  r.spans = top_blocks(r.lines)
  r
}

///|
fn split_lines(src : String) -> Array[String] {
  let out : Array[String] = []
  for line in src.split("\n") {
    out.push(line.to_owned())
  }
  // A trailing newline produces one empty element; drop it so "removing the
  // first line" means what a reader expects.
  while out.length() > 0 && out[out.length() - 1] == "" {
    let _ = out.pop()
  }
  out
}

///|
fn join_lines(lines : Array[String]) -> String {
  if lines.length() == 0 {
    return ""
  }
  let b = StringBuilder()
  for i, line in lines {
    if i > 0 {
      b.write_string("\n")
    }
    b.write_string(line)
  }
  b.to_string()
}

///|
fn remove_span(lines : Array[String], lo : Int32, hi : Int32) -> Array[String] {
  let out : Array[String] = []
  for i, line in lines {
    if i < lo || i >= hi {
      out.push(line)
    }
  }
  out
}

///|
/// Line spans of top-level brace blocks, largest first.  Line-level and
/// brace-blind on purpose: a `{` inside a string or comment can produce a
/// wrong span, and the verdict gate simply rejects it.  A parser here would
/// duplicate the compiler's grammar and rot.
pub fn top_blocks(lines : Array[String]) -> Array[(Int32, Int32)] {
  let raw : Array[(Int32, Int32)] = []
  let mut depth = 0
  let mut start = 0
  for i, line in lines {
    for c in line {
      if c == '{' {
        if depth == 0 {
          start = i
        }
        depth += 1
      } else if c == '}' {
        if depth > 0 {
          depth -= 1
          if depth == 0 {
            raw.push((start, i + 1))
          }
        }
      }
    }
  }
  // Largest span first: one big cut beats four small ones when both work.
  // Insertion sort keeps this allocation-free and deterministic.
  let out = raw.copy()
  let mut i = 1
  while i < out.length() {
    let cur = out[i]
    let mut j = i
    while j > 0 && span_len(out[j - 1]) < span_len(cur) {
      out[j] = out[j - 1]
      j -= 1
    }
    out[j] = cur
    i += 1
  }
  out
}

///|
fn span_len(s : (Int32, Int32)) -> Int32 {
  let (lo, hi) = s
  hi - lo
}

///|
/// Next text to test, or `None` when the reduction is finished or out of fuel.
pub fn next_text(r : Reducer) -> String? {
  match r.pending {
    Some(lines) => return Some(join_lines(lines))
    None => ()
  }
  if r.exhausted || r.lines.length() < 2 {
    return None
  }
  if r.calls >= r.fuel {
    r.exhausted = true
    return None
  }
  if !r.blocks_done {
    if r.idx < r.spans.length() {
      let (lo, hi) = r.spans[r.idx]
      let cand = remove_span(r.lines, lo, hi)
      r.pending = Some(cand)
      r.calls += 1
      return Some(join_lines(cand))
    }
    r.blocks_done = true
    r.idx = 0
  }
  let mut out : String? = None
  let mut go = true
  while go {
    let n = r.lines.length()
    if n < 2 {
      go = false
    } else if r.idx >= r.gran {
      if r.gran >= n {
        go = false
      } else {
        r.gran = if r.gran * 2 > n { n } else { r.gran * 2 }
        r.idx = 0
      }
    } else {
      let chunk = (n + r.gran - 1) / r.gran
      let lo = r.idx * chunk
      let hi = if lo + chunk > n { n } else { lo + chunk }
      if lo >= hi {
        r.idx += 1
      } else if r.calls >= r.fuel {
        r.exhausted = true
        go = false
      } else {
        let cand = remove_span(r.lines, lo, hi)
        r.pending = Some(cand)
        r.calls += 1
        out = Some(join_lines(cand))
        go = false
      }
    }
  }
  out
}

///|
/// Record whether the outstanding candidate still exhibits the defect.
pub fn verdict(r : Reducer, ok : Bool) -> Unit {
  match r.pending {
    None => ()
    Some(cand) => {
      r.pending = None
      if ok {
        r.lines = cand
        if r.blocks_done {
          r.gran = if r.gran > 2 { r.gran - 1 } else { 2 }
          r.idx = 0
        } else {
          // A block cut changes the brace structure; re-derive spans.
          r.spans = top_blocks(r.lines)
          r.idx = 0
        }
      } else {
        r.idx += 1
      }
    }
  }
}

///|
pub fn done(r : Reducer) -> Bool {
  next_text(r) is None
}

///|
pub fn result(r : Reducer) -> String {
  join_lines(r.lines)
}

///|
pub fn result_lines(r : Reducer) -> Int32 {
  r.lines.length()
}

///|
pub fn test_calls(r : Reducer) -> Int32 {
  r.calls
}

///|
pub fn was_exhausted(r : Reducer) -> Bool {
  r.exhausted
}

///|
/// Convenience driver for synchronous predicates (tests, in-process corpora).
/// Process-spawning callers must use the state machine directly.
pub fn reduce_with(
  src : String,
  fuel : Int32,
  accept : (String) -> Bool,
) -> String {
  let r = start(src, fuel)
  let mut go = true
  while go {
    match next_text(r) {
      Some(c) => verdict(r, accept(c))
      None => go = false
    }
  }
  result(r)
}
