// Stable defect signatures.
//
// The campaign used stage|kind|detail|rc directly, so two problems showed up:
//
//   - the first `Error:` line carries temp paths, hashes and byte counts, and
//     different witnesses of one root cause could land in different buckets;
//   - the formatter path hashed the *source*, so every input got its own
//     directory even when the failure was identical.
//
// The normaliser below keeps the parts that identify a cause (the class, the
// `who=` token from Machine_error, the exception constructor, the first stack
// frame) and replaces the parts that do not (digits, paths, addresses).

///|
/// Known-defect library.  A match means "this signature is a witness of an
/// already documented class", not "not a defect".
pub fn known_id(text : String) -> String? {
  let table : Array[(String, String)] = [
    ("lower_array_make", "F7"),
    ("finish_stub_wrapper_shell", "F9"),
    ("Char.chr", "F2"),
    ("Basic_utf8_decode", "F4"),
    ("Assertion failed", "F8"),
    ("out of memory", "F3"),
  ]
  for entry in table {
    let (needle, id) = entry
    if text.contains(needle) {
      return Some(id)
    }
  }
  None
}

///|
/// Replace the volatile parts of a diagnostic with fixed tokens.
pub fn normalize_text(s : String) -> String {
  let b = StringBuilder()
  let mut i = 0
  let n = s.length()
  while i < n {
    let c = s.get_char(i).unwrap_or(' ')
    if c >= '0' && c <= '9' {
      // Collapse a digit run to one token.
      while i < n {
        match s.get_char(i) {
          Some(d) => if d >= '0' && d <= '9' { i += 1 } else { break }
          None => break
        }
      }
      b.write_char('#')
    } else if c == '/' {
      // Collapse an absolute path to <path>.
      let mut j = i + 1
      let mut has_slash = false
      while j < n {
        match s.get_char(j) {
          Some(d) =>
            if d == ' ' || d == '\n' || d == '"' {
              break
            } else {
              if d == '/' {
                has_slash = true
              }
              j += 1
            }
          None => break
        }
      }
      if has_slash || j - i > 3 {
        b.write_string("<path>")
        i = j
      } else {
        b.write_char(c)
        i += 1
      }
    } else if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      b.write_char(' ')
      i += 1
    } else {
      b.write_char(c)
      i += 1
    }
  }
  let out = b.to_string().trim().to_owned()
  if out.length() > 220 {
    out[0:220].to_owned()
  } else {
    out
  }
}

///|
fn strip_paths(s : String) -> String {
  normalize_text(s)
}

///|
/// `who="..."` from a Machine_error, else an exception constructor, else the
/// first stack frame, else the first `Error:` line.
pub fn cause_token(text : String) -> String {
  for line in text.split("\n") {
    let t = line.trim()
    if t.contains("who=") {
      return strip_paths(t.to_owned())
    }
    if t.contains("Fatal error: exception") ||
      t.contains("Assert_failure") ||
      t.contains("Stack overflow") ||
      t.contains("out of memory") {
      return strip_paths(t.to_owned())
    }
    if t.has_prefix("File \"") ||
      t.has_prefix("Raised at") ||
      t.has_prefix("Called from") {
      return strip_paths(t.to_owned())
    }
    if t.has_prefix("Error: ") {
      // `moon build` wraps the compiler failure in an `Error: failed to ...`
      // line before the actual ICE text; using it as the cause makes the
      // re-run signature depend on the wrapper and the argv.
      if t.has_prefix("Error: failed to ") ||
        t.has_prefix("Error: failed when building") {
        continue
      }
      return strip_paths(t.to_owned())
    }
  }
  ""
}

///|
/// Signature for a crash-class observation.  `kind` is the judge class
/// (`ICE`/`OOM`/`SIG`/...); `rc` distinguishes signals when there is no text.
pub fn crash_signature(
  kind : String,
  rc : Int32,
  stderr : String,
  stdout : String,
) -> String {
  let text = stderr + "\n" + stdout
  let known = known_id(text)
  let raw = cause_token(text)
  // Drop the diagnostic prefix so the stored signature is the cause itself.
  let token = if raw.has_prefix("Error: ") { raw[7:].to_owned() } else { raw }
  let head = if token == "" {
    "crash|" + kind + "|rc=" + rc.to_string()
  } else {
    "crash|" + kind + "|" + token
  }
  match known {
    Some(id) => head + "|known=" + id
    None => head
  }
}

///|
/// Signature for formatter findings.  The source hash is deliberately absent:
/// a formatter defect is identified by what the formatter says or by the
/// failure class, so the same defect in different files shares one directory.
pub fn formatter_signature(
  rc : Int32,
  stderr : String,
  stdout : String,
) -> String {
  let token = cause_token(stderr + "\n" + stdout)
  if token == "" {
    "fmt|rc=" + rc.to_string()
  } else {
    "fmt|" + token
  }
}

///|
/// Read a string field from one-line JSON, honouring backslash escapes.
/// The naive "find the next quote" scan truncates signatures such as
/// `Invalid_argument(\"Char.chr\")`.
pub fn json_get_string(text : String, key : String) -> String {
  let pat = "\"" + key + "\":\""
  let i = match text.find(pat) {
    None => return ""
    Some(i) => i + pat.length()
  }
  let b = StringBuilder()
  let mut j = i
  let mut closed = false
  while j < text.length() && !closed {
    match text.get_char(j) {
      Some('\\') =>
        if j + 1 < text.length() {
          match text.get_char(j + 1) {
            Some('n') => b.write_char('\n')
            Some('t') => b.write_char('\t')
            Some('r') => b.write_char('\r')
            Some('"') => b.write_char('"')
            Some('\\') => b.write_char('\\')
            Some(c) => b.write_char(c)
            None => ()
          }
          j += 2
        } else {
          j += 1
        }
      Some('"') => {
        closed = true
        j += 1
      }
      Some(c) => {
        b.write_char(c)
        j += 1
      }
      None => j += 1
    }
  }
  b.to_string()
}
