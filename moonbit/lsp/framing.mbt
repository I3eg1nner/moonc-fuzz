///|
/// Parsed view of one LSP frame.
///
/// `Complete(body, consumed)` means `body` was fully present and that many
/// bytes were consumed (header + body).  `Incomplete` means more bytes are
/// needed; `Malformed` means the bytes cannot start a valid frame.
pub(all) enum FrameStatus {
  Complete(String, Int32)
  Incomplete
  Malformed(String)
}

///|
/// Encode one LSP message: `Content-Length: N\r\n\r\n` + UTF-8 body.
///
/// The length is the number of UTF-8 bytes, not the number of MoonBit
/// characters, which matters for the unicode cases in the probe matrix.
pub fn frame_message(body : String) -> String {
  let n = @utf8.encode(body).length()
  "Content-Length: " + n.to_string() + "\r\n\r\n" + body
}

///|
/// Case-insensitive ASCII lower-casing, enough for HTTP-style header names.
fn ascii_lower(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      b.write_char(Int32::to_char(c.to_int() + 32).unwrap())
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn starts_with_ci(s : String, prefix : String) -> Bool {
  if s.length() < prefix.length() {
    return false
  }
  let mut i = 0
  while i < prefix.length() {
    let a = s.get_char(i).unwrap()
    let b = prefix.get_char(i).unwrap()
    if a.to_int() < 128 && b.to_int() < 128 {
      if ascii_lower(a.to_string()) != ascii_lower(b.to_string()) {
        return false
      }
    } else if a != b {
      return false
    }
    i += 1
  }
  true
}

///|
/// Find `needle` in `buf` at or after `from`.
fn find_bytes(buf : BytesView, needle : BytesView, from : Int32) -> Int32? {
  let n = buf.length()
  let m = needle.length()
  let mut i = from
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m && same {
      if buf[i + j] != needle[j] {
        same = false
      }
      j += 1
    }
    if same {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Parse a decimal integer from a trimmed header value, rejecting junk.
fn parse_decimal(s : String) -> Int32? {
  let t = s.trim()
  if t.length() == 0 {
    return None
  }
  let mut v = 0
  for c in t {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - 48)
  }
  Some(v)
}

///|
/// Extract Content-Length from the header block (without the final blank
/// line).  Returns `None` when it is absent or not a non-negative decimal.
pub fn content_length(header : String) -> Int32? {
  for line in header.split("\r\n") {
    let t = line.trim().to_owned()
    if starts_with_ci(t, "content-length:") {
      // Header names are ASCII; after the colon the value is decimal spaces.
      return parse_decimal(t[15:].to_owned())
    }
  }
  None
}

///|
/// Parse one frame from the front of `buf`.
pub fn parse_frame(buf : BytesView) -> FrameStatus {
  let n = buf.length()
  if n == 0 {
    return Incomplete
  }
  match find_bytes(buf, b"\r\n\r\n", 0) {
    Some(idx) => {
      let header = @utf8.decode_lossy(buf[0:idx])
      match content_length(header) {
        None => Malformed("missing or invalid Content-Length")
        Some(len) =>
          if len < 0 {
            Malformed("negative Content-Length")
          } else {
            let start = idx + 4
            if n - start < len {
              Incomplete
            } else {
              let body = @utf8.decode_lossy(buf[start:start + len])
              Complete(body, start + len)
            }
          }
      }
    }
    None => {
      // No terminator yet.  Decide between "partial header" and "this is not
      // a frame at all".  A plausible header line must contain a colon and a
      // header name before it; otherwise callers get a malformed verdict as
      // soon as enough bytes are present to tell.
      let head = @utf8.decode_lossy(buf)
      let first_line = match head.find("\r\n") {
        Some(i) => head[0:i].to_owned()
        None => head
      }
      let colon = first_line.find(":")
      let quote = first_line.find("\"")
      let brace = first_line.find("{")
      let looks_like_header = match colon {
        None => false
        Some(c) => {
          let before_quote = match quote {
            Some(q) => c < q
            None => true
          }
          let before_brace = match brace {
            Some(b) => c < b
            None => true
          }
          // Header names start with an ASCII letter.
          before_quote &&
          before_brace &&
          (match first_line.get_char(0) {
            Some(ch) => ch.is_ascii_alphabetic()
            None => false
          })
        }
      }
      if looks_like_header {
        Incomplete
      } else if head.length() >= 24 {
        Malformed("no Content-Length header")
      } else {
        Incomplete
      }
    }
  }
}
