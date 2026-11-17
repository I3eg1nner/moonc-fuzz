///|
/// Low-cardinality compiler failure signatures and the F8 known-positive key.
/// Keeping this in the generator package makes it unit-testable without
/// spawning a compiler.

///|
pub fn known_f8_signature() -> String {
  "moonc.ml:125623:29-35|Assertion failed"
}

///|
fn index_of_from(s : String, from : Int32, needle : String) -> Int32 {
  let n = s.length()
  let m = needle.length()
  if m == 0 {
    return from
  }
  let mut i = from
  while i + m <= n {
    let mut j = 0
    let mut ok = true
    while j < m {
      if s.get_char(i + j) != needle.get_char(j) {
        ok = false
        break
      }
      j += 1
    }
    if ok {
      return i
    }
    i += 1
  }
  -1
}

///|
fn index_of(s : String, needle : String) -> Int32 {
  index_of_from(s, 0, needle)
}

///|
fn slice(s : String, start : Int32, end : Int32) -> String {
  let b = StringBuilder()
  let mut i = start
  while i < end && i < s.length() {
    match s.get_char(i) {
      Some(ch) => b.write_char(ch)
      None => ()
    }
    i += 1
  }
  b.to_string()
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn digit_end(s : String, from : Int32) -> Int32 {
  let mut i = from
  while i < s.length() {
    match s.get_char(i) {
      Some(ch) => if is_digit(ch) { i += 1 } else { break }
      None => break
    }
  }
  i
}

///|
fn parse_uint(s : String, start : Int32, end : Int32) -> Int32 {
  let mut v = 0
  let mut i = start
  while i < end {
    match s.get_char(i) {
      Some(ch) => if is_digit(ch) { v = v * 10 + (ch.to_int() - '0'.to_int()) }
      None => ()
    }
    i += 1
  }
  v
}

///|
fn line_after(s : String, from : Int32) -> String {
  let mut end = from
  while end < s.length() {
    match s.get_char(end) {
      Some(ch) => if ch == '\n' || ch == '\r' { break } else { end += 1 }
      None => break
    }
  }
  slice(s, from, end).trim().to_owned()
}

///|
/// Canonical MoonBit compiler location signature:
/// `moonc.ml:<line>:<char-start>-<char-end>|<message>`.
fn moonc_location(s : String) -> String {
  let marker = "File \"moonc.ml\", line "
  let p = index_of(s, marker)
  if p < 0 {
    return ""
  }
  let line_start = p + marker.length()
  let line_end = digit_end(s, line_start)
  if line_end == line_start {
    return ""
  }
  let line = parse_uint(s, line_start, line_end)
  let chars_marker = "characters "
  let cp = index_of_from(s, line_end, chars_marker)
  if cp < 0 {
    return "moonc.ml:" + line.to_string()
  }
  let cs_start = cp + chars_marker.length()
  let ce_start = digit_end(s, cs_start)
  if ce_start == cs_start {
    return "moonc.ml:" + line.to_string()
  }
  let cstart = parse_uint(s, cs_start, ce_start)
  let mut ce = ce_start
  if ce < s.length() {
    match s.get_char(ce) {
      Some(ch) => if ch == '-' { ce += 1 }
      None => ()
    }
  }
  let ce_end = digit_end(s, ce)
  let cend = if ce_end > ce { parse_uint(s, ce, ce_end) } else { cstart }
  let mesg_start = index_of_from(s, ce_end, ":")
  let msg = if mesg_start >= 0 { line_after(s, mesg_start + 1) } else { "" }
  let msg = if msg == "" { "unknown" } else { msg }
  "moonc.ml:" +
  line.to_string() +
  ":" +
  cstart.to_string() +
  "-" +
  cend.to_string() +
  "|" +
  msg
}

///|
/// Extract a stable key from a compiler/test log.  `rc` is needed for signal
/// crashes and spawn errors.  Test assertion text is deliberately *not* part
/// of the key: it is program output, not a compiler signature.
pub fn normalize_signature(blob : String, rc : Int32) -> String {
  if rc == -999 {
    return "spawn_error"
  }
  let loc = moonc_location(blob)
  if loc != "" {
    return loc
  }
  if blob.contains("Machine_error") {
    return "Machine_error"
  }
  if blob.contains("Assert_failure") || blob.contains("Assertion failed") {
    return "assert_failure"
  }
  if blob.contains("Fatal error: exception") {
    let p = index_of(blob, "Fatal error: exception")
    let tail = line_after(blob, p + "Fatal error: exception".length())
    return if tail == "" {
      "ocaml_exception"
    } else {
      "ocaml_exception:" + tail
    }
  }
  if blob.contains("Stack overflow") || blob.contains("Stack_overflow") {
    return "stack_overflow"
  }
  if blob.contains("Out_of_memory") ||
    blob.contains("out of memory") ||
    blob.contains("Cannot allocate memory") {
    return "oom"
  }
  if rc < 0 {
    return "signal:" + rc.to_string()
  }
  ""
}

///|
pub fn is_crash_signature(sig : String) -> Bool {
  if sig == "" || sig == "spawn_error" {
    return false
  }
  sig.has_prefix("moonc.ml:") ||
  sig == "Machine_error" ||
  sig == "assert_failure" ||
  sig == "stack_overflow" ||
  sig == "oom" ||
  sig.has_prefix("ocaml_exception") ||
  sig.has_prefix("signal:")
}

///|
pub fn is_known_f8(sig : String) -> Bool {
  let k = known_f8_signature()
  sig == k || sig.has_prefix("moonc.ml:125623:")
}

///|
/// Dependency/network failures must never be counted as compiler evidence.
pub fn is_infra(blob : String) -> Bool {
  blob.contains("module was not found in the registry") ||
  blob.contains("failed to download") ||
  blob.contains("download failed") ||
  blob.contains("network error") ||
  blob.contains("Network error") ||
  blob.contains("Connection refused") ||
  blob.contains("Could not resolve host") ||
  blob.contains("registry index") ||
  blob.contains("failed to fetch") ||
  blob.contains("TLS error") ||
  blob.contains("HTTP error")
}
