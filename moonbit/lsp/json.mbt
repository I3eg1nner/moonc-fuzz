///|
/// Minimal JSON helpers for the probe.  The probe never needs a full JSON
/// parser on the response side: it only needs the top-level `id`, whether a
/// top-level `error` key is present, and a byte-exact re-encoding of request
/// payloads.

///|
/// Escape a string for embedding in a JSON document.  Non-ASCII code points
/// are emitted as UTF-8, which is what MoonBit strings already hold.
pub fn json_escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '"' {
      b.write_string("\\\"")
    } else if c == '\\' {
      b.write_string("\\\\")
    } else if c == '\n' {
      b.write_string("\\n")
    } else if c == '\r' {
      b.write_string("\\r")
    } else if c == '\t' {
      b.write_string("\\t")
    } else if c.to_int() < 32 {
      // JSON requires four hex digits; the branch guarantees a zero high byte.
      b.write_string("\\u00")
      let h = c.to_int()
      let hex = "0123456789abcdef"
      b.write_char(hex.get_char(h / 16 % 16).unwrap())
      b.write_char(hex.get_char(h % 16).unwrap())
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// JSON string literal (including quotes) for `s`.
pub fn json_quote(s : String) -> String {
  "\"" + json_escape(s) + "\""
}

///|
/// How the top-level `id` member was written.  JSON-RPC allows an id to be a
/// number or a string, and an *error* response generated for a request whose
/// id could not be parsed must carry `id: null`.  `IdMissing` is the only
/// value that means "notification"; every other value proves a response frame.
pub(all) enum IdKind {
  IdMissing
  IdNull
  IdInt(Int32)
  IdString(String)
  /// An id member was present but had an unexpected JSON type (object, array,
  /// boolean).  Malformed, but still a response-shaped frame, never a
  /// notification.
  IdOther
}

///|
pub fn IdKind::text(self : IdKind) -> String {
  match self {
    IdMissing => "missing"
    IdNull => "null"
    IdInt(n) => n.to_string()
    IdString(s) => "\"" + s + "\""
    IdOther => "other"
  }
}

///|
/// Top-level facts extracted from a JSON-RPC frame.
pub(all) struct ResponseInfo {
  /// The integer id, when one was present.  Kept for id correlation; it is
  /// `None` for `id: null`, string ids and notifications.
  id : Int32?
  id_kind : IdKind
  has_error : Bool
  has_result : Bool
  error_code : Int32?
}

///|
/// True when the frame has an `id` member of any type.  Notifications have no
/// `id` at all; an `id: null` error response is *not* a notification.
pub fn ResponseInfo::has_id(self : ResponseInfo) -> Bool {
  match self.id_kind {
    IdMissing => false
    _ => true
  }
}

///|
/// True when the frame is a response: it has an `id` member and a top-level
/// `result` or `error` member.  Detection is deliberately independent of the
/// id's type, so `{"id":null,"error":{...}}` and `{"id":"2",...}` count.
pub fn ResponseInfo::is_response(self : ResponseInfo) -> Bool {
  self.has_id() && (self.has_result || self.has_error)
}

///|
/// Short, type-preserving rendering of the id for diagnostics.
pub fn ResponseInfo::id_text(self : ResponseInfo) -> String {
  self.id_kind.text()
}

///|
fn skip_ws(s : String, start : Int32) -> Int32 {
  let mut i = start
  while i < s.length() {
    match s.get_char(i) {
      Some(' ') | Some('\t') | Some('\r') | Some('\n') => i += 1
      _ => break
    }
  }
  i
}

///|
/// `i` points at an opening quote; return the index just past the close quote.
fn scan_string(s : String, start : Int32) -> Int32 {
  let n = s.length()
  let mut i = start + 1
  while i < n {
    match s.get_char(i) {
      Some('\\') => i += 2
      Some('"') => return i + 1
      _ => i += 1
    }
  }
  n
}

///|
/// `i` points at the first byte of a value; return the index just past it.
fn skip_value(s : String, start : Int32) -> Int32 {
  let n = s.length()
  let mut i = start
  if i >= n {
    return i
  }
  match s.get_char(i) {
    Some('"') => scan_string(s, i)
    Some('{') | Some('[') => {
      let mut depth = 0
      while i < n {
        match s.get_char(i) {
          Some('"') => {
            i = scan_string(s, i)
            continue
          }
          Some('{') | Some('[') => depth += 1
          Some('}') | Some(']') => {
            depth -= 1
            if depth == 0 {
              return i + 1
            }
          }
          _ => ()
        }
        i += 1
      }
      i
    }
    _ => {
      // Number / true / false / null: consume until a structural character.
      while i < n {
        match s.get_char(i) {
          Some(',') | Some('}') | Some(']') => break
          _ => i += 1
        }
      }
      i
    }
  }
}

///|
fn digit_value(c : Char) -> Int32 {
  c.to_int() - 48
}

///|
fn parse_int_at(s : String, start : Int32) -> (Int32?, Int32) {
  let n = s.length()
  let mut i = start
  let mut neg = false
  if i < n && s.get_char(i) == Some('-') {
    neg = true
    i += 1
  }
  let begin = i
  let mut v = 0
  while i < n {
    match s.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          v = v * 10 + digit_value(c)
          i += 1
        } else {
          break
        }
      None => break
    }
  }
  if i == begin {
    (None, i)
  } else {
    (Some(if neg { -v } else { v }), i)
  }
}

///|
/// `i` points at the value of a top-level `"error"` member.  Walk the object
/// and return its integer `code`, or `None` when the shape is unexpected.
fn error_code_at(s : String, start : Int32) -> Int32? {
  let n = s.length()
  let mut i = skip_ws(s, start)
  if i >= n || s.get_char(i) != Some('{') {
    return None
  }
  i += 1
  while i < n {
    i = skip_ws(s, i)
    if i >= n || s.get_char(i) == Some('}') {
      break
    }
    if s.get_char(i) != Some('"') {
      break
    }
    let key_end = scan_string(s, i)
    let key = s[i + 1:key_end - 1].to_owned()
    i = skip_ws(s, key_end)
    if i >= n || s.get_char(i) != Some(':') {
      break
    }
    i = skip_ws(s, i + 1)
    if key == "code" {
      let (v, _) = parse_int_at(s, i)
      return v
    }
    i = skip_value(s, i)
    i = skip_ws(s, i)
    if i < n && s.get_char(i) == Some(',') {
      i += 1
    }
  }
  None
}

///|
/// Scan a response body for the top-level `id`, `error` and `result` keys.
/// Values are skipped with a string- and nesting-aware scanner, so an
/// `"error"` inside a result string does not count.
pub fn inspect_response(body : String) -> ResponseInfo {
  let n = body.length()
  let mut i = skip_ws(body, 0)
  if i >= n || body.get_char(i) != Some('{') {
    return {
      id: None,
      id_kind: IdMissing,
      has_error: false,
      has_result: false,
      error_code: None,
    }
  }
  i += 1
  let mut id = None
  let mut id_kind = IdMissing
  let mut has_error = false
  let mut has_result = false
  let mut error_code = None
  while i < n {
    i = skip_ws(body, i)
    if i >= n || body.get_char(i) == Some('}') {
      break
    }
    if body.get_char(i) != Some('"') {
      break
    }
    let key_end = scan_string(body, i)
    let key = body[i + 1:key_end - 1].to_owned()
    i = skip_ws(body, key_end)
    if i >= n || body.get_char(i) != Some(':') {
      break
    }
    i = skip_ws(body, i + 1)
    if key == "id" {
      // Do not lose a response because its id is null or a string: parse the
      // type, keep the integer when there is one, and fall through to the
      // generic skipper for the actual value.
      let start = i
      match body.get_char(i) {
        Some('"') => {
          let end = scan_string(body, i)
          id_kind = IdString(body[i + 1:end - 1].to_owned())
        }
        Some('n') => id_kind = IdNull
        Some('-')
        | Some('0')
        | Some('1')
        | Some('2')
        | Some('3')
        | Some('4')
        | Some('5')
        | Some('6')
        | Some('7')
        | Some('8')
        | Some('9') => {
          let (v, _) = parse_int_at(body, i)
          match v {
            Some(n) => {
              id = Some(n)
              id_kind = IdInt(n)
            }
            None => id_kind = IdOther
          }
        }
        Some(_) => id_kind = IdOther
        None => ()
      }
      i = skip_value(body, start)
    } else {
      if key == "error" {
        has_error = true
        error_code = error_code_at(body, i)
      } else if key == "result" {
        has_result = true
      }
      i = skip_value(body, i)
    }
    i = skip_ws(body, i)
    if i < n && body.get_char(i) == Some(',') {
      i += 1
    }
  }
  { id, id_kind, has_error, has_result, error_code, }
}
