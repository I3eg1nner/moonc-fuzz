///|
/// Structure-aware mutators for MoonBit source.
///
/// This is a hand-written port of `harness/mutate.py`.  It deliberately does not
/// parse MoonBit: matching brackets and quoted regions plus a small token table
/// is enough to keep most mutations "near syntax", which is what lets them reach
/// the typer/codegen instead of dying in the lexer.
///
/// No file IO and no external dependencies: the AFL dictionary is parsed from a
/// caller-supplied string with `parse_dict`.

///|
/// Reserved words.  Mirrors `KEYWORDS` in `harness/mutate.py`; the exact list is
/// part of the mutation behaviour because these words are never renamed and are
/// never taken from the dictionary as replacement identifiers.
let keywords : Array[String] = [
  "fn", "let", "mut", "match", "if", "else", "while", "for", "in", "return", "break",
  "continue", "raise", "try", "catch", "async", "await", "struct", "enum", "trait",
  "impl", "type", "alias", "pub", "priv", "const", "test", "bench", "derive", "dyn",
  "is", "as", "with", "where", "using", "guard", "loop", "do", "yield", "throw",
  "macro", "extern", "import", "typealias", "traitalias", "super", "self", "true",
  "false", "not",
]

///|
/// Builtin type names used by `replace_token`.
let builtin_types : Array[String] = [
  "Int", "Int64", "UInt", "UInt64", "Double", "Float", "String", "Char", "Bool",
  "Unit", "Byte", "Bytes", "Array", "ArrayView", "FixedArray", "Option", "Result",
]

///|
/// Operators used by `replace_token`.
let operators : Array[String] = [
  "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "!", "&",
  "|", "^", "<<", ">>", "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=",
  ">>=", "..", "...", "=>", "->", "::", ".",
]

///|
/// Attributes injected by `inject_attr`.
let attrs : Array[String] = [
  "#[inline]", "#[inline(always)]", "#[inline(never)]", "#[deprecated(\"x\")]", "#[test]",
  "#[bench]", "#[derive(Show)]", "#[derive(Eq)]", "#[derive(Compare)]", "#[derive(Hash)]",
  "#[derive(Default)]", "#[derive(Arbitrary)]", "#[coverage(never)]", "#[js_only]",
]

///|
/// Boundary and special literals used by numeric replacement and by
/// `literal_edges`.  `\u{...}` in the Python list is source text here, hence the
/// doubled backslashes.
let literals : Array[String] = [
  "0", "-1", "1", "2147483647", "-2147483648", "9223372036854775807", "-9223372036854775808",
  "18446744073709551615", "0x7fffffff", "0xffffffffffffffff", "1.0", "-0.0", "1e308",
  "1e-308", "0x1p-1074", "nan", "infinity", "\"\"", "\"\\u{0}\"", "\"\\u{10FFFF}\"",
  "\"\\u{110000}\"", "\"\\x00\"", "'a'", "'\\u{0}'", "'\\u{10FFFF}'", "'\\u{110000}'",
  "b\"\\xff\"", "b'\\xff'", "true", "false", "()", "[]", "{}",
]

///|
/// Unicode code points inserted by `unicode`.  Includes zero-width characters,
/// BOM, combining marks, an astral emoji, and the edges of the BMP scalar range.
let unicode_seeds : Array[String] = [
  "\u{200B}", "\u{FEFF}", "\u{0301}", "\u{1F600}", "\u{202E}", "\u{0085}", "\u{00E9}",
  "\u{4E2D}", "\u{D7FF}", "\u{E000}",
]

///|
/// Replacement string literals used by `replace_token`.
let str_replacements : Array[String] = [
  "\"a\"", "\"\"", "\"\\u{10FFFF}\"", "\"%.100s\"", "\"$(1)\"",
]

///|
/// Replacement character literals used by `replace_token`.
let chr_replacements : Array[String] = ["'a'", "'\\u{0}'", "'\\n'"]

///|
/// Statement snippets used by `insert_stmt`.
let insert_stmts : Array[String] = [
  "let x = 1", "let x = 1 + 2", "let x : Int = 0", "let mut y = 0\ny = y + 1", "for i in 0..10 { () }",
  "while false { () }", "if true { () }", "match 1 { 1 => () _ => () }", "let f = fn() { () }",
  "f()", "raise Failure(\"x\")", "let (a, b) = (1, 2)", "return", "loop { break }",
  "let s = \"a\\u{1F600}b\"", "let a : Array[Int] = []", "#[inline]\nfn g() -> Int { 0 }",
]

///|
/// Built-in fallback dictionary.  `mutate` does not do file IO, so callers that
/// want the real AFL dictionary should use `parse_dict` and pass it through
/// `mutate_named(..., dict=...)` / `mutate(..., dict=...)`.  This small list
/// keeps `dict_token` useful out of the box.
let fallback_dict : Array[String] = [
  "Array", "ArrayView", "Bool", "Byte", "Bytes", "Char", "Double", "Err", "FixedArray",
  "Float", "Int", "Int64", "None", "Ok", "Option", "Result", "Some", "String", "StringBuilder",
  "StringView", "UInt", "UInt64", "Unit", "abort", "abs", "compare", "default", "eq",
  "fail", "filter", "find", "fold", "from_array", "hash", "inspect", "is_empty",
  "iter", "length", "map", "panic", "pop", "println", "push", "raise", "repeat",
  "show", "sort_by", "to_string", "unwrap", "unwrap_or",
]

///|
/// splitmix64: a tiny, fully specified PRNG.  It only uses 64-bit wrapping
/// integer arithmetic, so the same seed yields the same sequence on every
/// MoonBit backend (native, wasm, js).
///
/// Python's `random.Random` (Mersenne Twister) is intentionally *not*
/// reproduced: the audit only needs stable, seed-reproducible mutation, not
/// bit-identical Python streams.
pub struct Rng {
  mut state : UInt64
}

///|
/// Create a generator from `seed`.  Two generators with the same seed produce
/// the same sequence.
pub fn Rng::new(seed : UInt64) -> Rng {
  { state: seed, }
}

///|
/// Current internal state.  Exposed for debugging and for tests that want to
/// confirm a generator advanced deterministically.
pub fn Rng::state(self : Rng) -> UInt64 {
  self.state
}

///|
/// Create a generator from a signed 32-bit seed.  Convenience wrapper around
/// `Rng::new` for callers that keep seeds in `Int`.
pub fn Rng::from_int(seed : Int32) -> Rng {
  { state: seed.reinterpret_as_uint().to_uint64(), }
}

///|
/// Create a generator from a signed 64-bit seed.
pub fn Rng::from_int64(seed : Int64) -> Rng {
  { state: seed.reinterpret_as_uint64(), }
}

///|
/// Advance the generator and return the next 64-bit output.
pub fn Rng::next_u64(self : Rng) -> UInt64 {
  self.state += 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// Uniform-ish integer in `[0, limit)`.  Returns 0 for a non-positive limit.
pub fn Rng::int(self : Rng, limit : Int32) -> Int32 {
  if limit <= 0 {
    return 0
  }
  // Mask off the sign bit so the modulo operand is non-negative.
  (self.next_u64() & 0x7FFFFFFFUL).to_int() % limit
}

///|
/// Uniform-ish integer in `[lo, hi]` (inclusive).  Returns `lo` when the range
/// is empty or inverted.
pub fn Rng::int_range(self : Rng, lo : Int32, hi : Int32) -> Int32 {
  if hi < lo {
    return lo
  }
  lo + self.int(hi - lo + 1)
}

///|
/// Uniform double in `[0.0, 1.0)` with 53 bits of precision.
pub fn Rng::float(self : Rng) -> Double {
  (self.next_u64() >> 11).to_double() / 9007199254740992.0
}

///|
/// True with probability `p` (clamped to `[0, 1]`).
pub fn Rng::chance(self : Rng, p : Double) -> Bool {
  if p <= 0.0 {
    return false
  }
  if p >= 1.0 {
    return true
  }
  self.float() < p
}

///|
/// Pick one element uniformly.  Aborts on an empty array; use `choice_opt` when
/// the array may be empty.
pub fn[T] Rng::choice(self : Rng, xs : Array[T]) -> T {
  if xs.length() == 0 {
    abort("Rng::choice: empty array")
  }
  xs[self.int(xs.length())]
}

///|
/// Pick one element, or `None` for an empty array.
pub fn[T] Rng::choice_opt(self : Rng, xs : Array[T]) -> T? {
  if xs.length() == 0 {
    return None
  }
  Some(xs[self.int(xs.length())])
}

///|
/// Parse the AFL dictionary format used by `harness/moonbit.dict`: one bare
/// double-quoted token per line.  Blank lines, comments and `name="value"`
/// lines are ignored, exactly like the Python loader.  Escape sequences are
/// kept verbatim (the Python loader does not unescape them either).
pub fn parse_dict(text : String) -> Array[String] {
  let out : Array[String] = []
  // Python opens the dictionary in text mode, so universal newlines turn CRLF
  // and lone CR into LF before the line loop.
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  for raw in normalized.split("\n") {
    let line = raw.trim()
    let chars = line.to_array()
    let n = chars.length()
    if n >= 2 && chars[0] == '"' && chars[n - 1] == '"' {
      out.push(str_slice(chars, 1, n - 1))
    }
  }
  out
}

///|
/// The small fallback dictionary used when no parsed dictionary is supplied.
pub fn default_dict() -> Array[String] {
  fallback_dict.copy()
}

// ---------------------------------------------------------------------------
// Local string helpers.  MoonBit strings are UTF-16 internally; all mutation
// positions below are Unicode scalar offsets so astral characters and surrogate
// pairs stay intact.
// ---------------------------------------------------------------------------

///|
fn str_slice(cs : Array[Char], start : Int32, end : Int32) -> String {
  String::from_array(cs.exact_view(start~, end~))
}

///|
fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ascii_word(c : Char) -> Bool {
  is_ascii_alpha(c) || is_ascii_digit(c) || c == '_'
}

///|
fn is_ident_start(c : Char) -> Bool {
  is_ascii_alpha(c) || c == '_'
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn is_op_char(c : Char) -> Bool {
  match c {
    '+'
    | '-'
    | '*'
    | '/'
    | '%'
    | '='
    | '<'
    | '>'
    | '&'
    | '|'
    | '^'
    | '!'
    | '~'
    | '?'
    | ':'
    | '.'
    | '@'
    | '#'
    | ','
    | ';'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}' => true
    _ => false
  }
}

///|
/// Python's `\s`: the ASCII whitespace plus the common Unicode line separators.
/// The mutators only inspect indentation and the `fn\s+` gap, so this is close
/// enough without pulling in a Unicode table.
fn is_space_char(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\r' ||
  c == '\u{0B}' ||
  c == '\u{0C}' ||
  c == '\u{0085}' ||
  c == '\u{2028}' ||
  c == '\u{2029}'
}

///|
fn is_keyword(s : String) -> Bool {
  for k in keywords {
    if k == s {
      return true
    }
  }
  false
}

///|
fn matches_at(cs : Array[Char], pos : Int32, pat : String) -> Bool {
  let p = pat.to_array()
  if pos < 0 || pos + p.length() > cs.length() {
    return false
  }
  for i = 0; i < p.length(); i = i + 1 {
    if cs[pos + i] != p[i] {
      return false
    }
  }
  true
}

///|
fn prefix_at(cs : Array[Char], pos : Int32, end : Int32, pat : String) -> Bool {
  let p = pat.to_array()
  if pos + p.length() > end {
    return false
  }
  for i = 0; i < p.length(); i = i + 1 {
    if cs[pos + i] != p[i] {
      return false
    }
  }
  true
}

///|
/// Replace `cs[start:end]` with `repl`.
fn rebuild(
  cs : Array[Char],
  start : Int32,
  end : Int32,
  repl : String,
) -> String {
  let sb = StringBuilder()
  for i = 0; i < start; i = i + 1 {
    sb.write_char(cs[i])
  }
  sb.write_string(repl)
  for i = end; i < cs.length(); i = i + 1 {
    sb.write_char(cs[i])
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Tokenizer.  Mirrors the alternation in `harness/mutate.py`:
//   string | char | identifier | number | operator-run
// ---------------------------------------------------------------------------

///|
priv enum TokenKind {
  TStr
  TChr
  TId
  TNum
  TOp
}

///|
priv struct Token {
  kind : TokenKind
  text : String
  start : Int32
  end : Int32
}

///|
/// Scan one number starting at a digit.  Handles `0x...`, decimal fractions and
/// decimal exponents with the same greedy/optional structure as the Python
/// regex.
fn scan_number(cs : Array[Char], start : Int32) -> Int32 {
  let n = cs.length()
  if start + 2 < n &&
    cs[start] == '0' &&
    (cs[start + 1] == 'x' || cs[start + 1] == 'X') {
    let mut j = start + 2
    while j < n && (is_hex_digit(cs[j]) || cs[j] == '_') {
      j = j + 1
    }
    if j > start + 2 {
      return j
    }
  }
  let mut j = start
  while j < n && (is_ascii_digit(cs[j]) || cs[j] == '_') {
    j = j + 1
  }
  if j + 1 < n &&
    cs[j] == '.' &&
    (is_ascii_digit(cs[j + 1]) || cs[j + 1] == '_') {
    j = j + 1
    while j < n && (is_ascii_digit(cs[j]) || cs[j] == '_') {
      j = j + 1
    }
  }
  if j < n && (cs[j] == 'e' || cs[j] == 'E') {
    let mut k = j + 1
    if k < n && (cs[k] == '+' || cs[k] == '-') {
      k = k + 1
    }
    if k < n && is_ascii_digit(cs[k]) {
      while k < n && is_ascii_digit(cs[k]) {
        k = k + 1
      }
      j = k
    }
  }
  j
}

///|
fn tokenize(src : String) -> Array[Token] {
  let cs = src.to_array()
  let n = cs.length()
  let out : Array[Token] = []
  let mut i = 0
  while i < n {
    let c = cs[i]
    if c == '"' {
      let s = i
      let mut j = i + 1
      let mut closed = false
      while j < n {
        if cs[j] == '\\' {
          j = j + 2
        } else if cs[j] == '"' {
          j = j + 1
          closed = true
          break
        } else {
          j = j + 1
        }
      }
      if closed {
        out.push({ kind: TStr, text: str_slice(cs, s, j), start: s, end: j, })
        i = j
      } else {
        // An unterminated quote is not a token; skip it and retry, matching
        // `finditer`'s one-character advance.
        i = s + 1
      }
    } else if c == '\'' {
      let s = i
      let mut j = i + 1
      let mut closed = false
      while j < n {
        if cs[j] == '\\' {
          j = j + 2
        } else if cs[j] == '\'' {
          j = j + 1
          closed = true
          break
        } else {
          j = j + 1
        }
      }
      if closed {
        out.push({ kind: TChr, text: str_slice(cs, s, j), start: s, end: j, })
        i = j
      } else {
        i = s + 1
      }
    } else if is_ident_start(c) {
      let s = i
      let mut j = i + 1
      while j < n && is_ascii_word(cs[j]) {
        j = j + 1
      }
      out.push({ kind: TId, text: str_slice(cs, s, j), start: s, end: j, })
      i = j
    } else if is_ascii_digit(c) {
      let s = i
      let j = scan_number(cs, s)
      out.push({ kind: TNum, text: str_slice(cs, s, j), start: s, end: j, })
      i = j
    } else if is_op_char(c) {
      let s = i
      let mut j = i + 1
      while j < n && is_op_char(cs[j]) {
        j = j + 1
      }
      out.push({ kind: TOp, text: str_slice(cs, s, j), start: s, end: j, })
      i = j
    } else {
      i = i + 1
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Structural helpers.
// ---------------------------------------------------------------------------

///|
/// A balanced bracket pair; `end` is the index of the closing bracket
/// (inclusive), matching the Python `(start, end)` tuples.
priv struct Span {
  start : Int32
  end : Int32
}

///|
/// Half-open character range.
priv struct Range {
  start : Int32
  end : Int32
}

///|
fn closer_matches(top : Char, closer : Char) -> Bool {
  (top == '(' && closer == ')') ||
  (top == '[' && closer == ']') ||
  (top == '{' && closer == '}')
}

///|
/// Return all balanced `(...)`, `[...]`, `{...}` pairs outside string and char
/// literals, inner pairs first.  Unmatched closers are ignored, exactly like
/// `_boundaries` in the Python harness.
fn boundaries(src : String) -> Array[Span] {
  let cs = src.to_array()
  let n = cs.length()
  let stack : Array[Int32] = []
  let out : Array[Span] = []
  let mut in_str = false
  let mut in_chr = false
  let mut esc = false
  let mut i = 0
  while i < n {
    let c = cs[i]
    if in_str || in_chr {
      if esc {
        esc = false
      } else if c == '\\' {
        esc = true
      } else if (in_str && c == '"') || (in_chr && c == '\'') {
        in_str = false
        in_chr = false
      }
    } else if c == '"' {
      in_str = true
    } else if c == '\'' {
      in_chr = true
    } else if c == '(' || c == '[' || c == '{' {
      stack.push(i)
    } else if c == ')' || c == ']' || c == '}' {
      if stack.length() > 0 && closer_matches(cs[stack[stack.length() - 1]], c) {
        let s = stack.pop()
        match s {
          Some(s) => out.push({ start: s, end: i, })
          None => ()
        }
      }
    }
    i = i + 1
  }
  out
}

///|
/// Split into lines, keeping the terminating `\n` in each line.  This matches
/// `str.splitlines(keepends=True)` for the line endings that appear in MoonBit
/// source (`\n` and `\r\n`).
fn split_lines(cs : Array[Char]) -> Array[Range] {
  let n = cs.length()
  let out : Array[Range] = []
  let mut start = 0
  let mut i = 0
  while i < n {
    if cs[i] == '\n' {
      out.push({ start, end: i + 1, })
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    out.push({ start, end: n, })
  }
  out
}

///|
fn leading_whitespace(cs : Array[Char], line : Range) -> String {
  let mut i = line.start
  while i < line.end && is_space_char(cs[i]) {
    i = i + 1
  }
  str_slice(cs, line.start, i)
}

///|
/// `(pub )?(fn|struct|enum|trait|impl|type|let)\b` at the start of a line.
fn line_starts_decl(cs : Array[Char], line : Range) -> Bool {
  let mut p = line.start
  while p < line.end && is_space_char(cs[p]) {
    p = p + 1
  }
  if prefix_at(cs, p, line.end, "pub ") {
    p = p + 4
  }
  let keywords = ["fn", "struct", "enum", "trait", "impl", "type", "let"]
  for kw in keywords {
    if prefix_at(cs, p, line.end, kw) {
      let after = p + kw.to_array().length()
      if after >= line.end || !is_ascii_word(cs[after]) {
        return true
      }
    }
  }
  false
}

///|
/// Extract top-level `(pub )?fn ...` definitions, mirroring the DOTALL regex
/// `^(?:#\[[^\n]*\]\n)?(?:pub )?fn .*?^\}` used by `splice_fn`.  The closing
/// brace only has to start a line, not be alone on it.
fn find_functions(cs : Array[Char]) -> Array[String] {
  let n = cs.length()
  let out : Array[String] = []
  let mut i = 0
  while i < n {
    if i == 0 || cs[i - 1] == '\n' {
      let mut j = i
      let mut ok = true
      if matches_at(cs, j, "#[") {
        let mut k = j
        while k < n && cs[k] != '\n' {
          k = k + 1
        }
        if k >= n || k == j || cs[k - 1] != ']' {
          ok = false
        } else {
          j = k + 1
        }
      }
      if ok && prefix_at(cs, j, n, "pub ") {
        j = j + 4
      }
      if !ok || !prefix_at(cs, j, n, "fn ") {
        ok = false
      }
      if ok {
        let mut k = j + 3
        let mut found = -1
        while k < n {
          if (k == 0 || cs[k - 1] == '\n') && cs[k] == '}' {
            found = k
            break
          }
          k = k + 1
        }
        if found >= 0 {
          out.push(str_slice(cs, i, found + 1))
          i = found + 1
          continue
        }
      }
    }
    i = i + 1
  }
  out
}

///|
/// `(?<![\w.])\d{1,18}(?![\w.])`: maximal decimal runs of 1..18 digits that are
/// not glued to an identifier, another dot, or more digits.
fn short_number_ranges(cs : Array[Char]) -> Array[Range] {
  let n = cs.length()
  let out : Array[Range] = []
  let mut i = 0
  while i < n {
    if is_ascii_digit(cs[i]) {
      let s = i
      let mut j = i
      while j < n && is_ascii_digit(cs[j]) {
        j = j + 1
      }
      let prev_ok = s == 0 || !(is_ascii_word(cs[s - 1]) || cs[s - 1] == '.')
      let next_ok = j == n || !(is_ascii_word(cs[j]) || cs[j] == '.')
      let len = j - s
      if prev_ok && next_ok && len >= 1 && len <= 18 {
        out.push({ start: s, end: j, })
      }
      i = j
    } else {
      i = i + 1
    }
  }
  out
}

// ---------------------------------------------------------------------------
// UTF-8 helpers for `bitflip`.  MoonBit's String is UTF-16 and its legacy
// `to_bytes` is not UTF-8, so encoding/decoding is implemented locally.
// ---------------------------------------------------------------------------

///|
fn push_replacement(out : Array[Byte]) -> Unit {
  out.push(b'\xEF')
  out.push(b'\xBF')
  out.push(b'\xBD')
}

///|
fn utf8_encode(src : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for c in src {
    let cp = c.to_uint()
    if cp <= 0x7F {
      out.push(cp.to_byte())
    } else if cp <= 0x7FF {
      out.push(((cp >> 6) | 0xC0).to_byte())
      out.push(((cp & 0x3F) | 0x80).to_byte())
    } else if cp >= 0xD800 && cp <= 0xDFFF {
      // Lone surrogates cannot be encoded as valid UTF-8; Python uses
      // surrogatepass.  Use U+FFFD so the result is a valid MoonBit string.
      push_replacement(out)
    } else if cp <= 0xFFFF {
      out.push(((cp >> 12) | 0xE0).to_byte())
      out.push((((cp >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((cp & 0x3F) | 0x80).to_byte())
    } else if cp <= 0x10FFFF {
      out.push(((cp >> 18) | 0xF0).to_byte())
      out.push((((cp >> 12) & 0x3F) | 0x80).to_byte())
      out.push((((cp >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((cp & 0x3F) | 0x80).to_byte())
    } else {
      push_replacement(out)
    }
  }
  out
}

///|
/// Decode UTF-8, replacing malformed sequences with U+FFFD.  Python decodes
/// with `surrogateescape`; MoonBit strings are valid UTF-16, so replacement is
/// the closest safe behaviour.  A malformed lead byte always advances by one,
/// which keeps a flipped byte from swallowing the rest of the input.
fn utf8_decode(bs : Array[Byte]) -> String {
  let n = bs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let b0 = bs[i].to_uint()
    if b0 <= 0x7F {
      sb.write_char(b0.reinterpret_as_int().unsafe_to_char())
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 < n {
        let b1 = bs[i + 1].to_uint()
        if b1 >= 0x80 && b1 <= 0xBF {
          let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
          sb.write_char(cp.reinterpret_as_int().unsafe_to_char())
          i = i + 2
          continue
        }
      }
      sb.write_char('\u{FFFD}')
      i = i + 1
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 < n {
        let b1 = bs[i + 1].to_uint()
        let b2 = bs[i + 2].to_uint()
        let cont_ok = b1 >= 0x80 && b1 <= 0xBF && b2 >= 0x80 && b2 <= 0xBF
        let overlong = b0 == 0xE0 && b1 < 0xA0
        let surrogate = b0 == 0xED && b1 >= 0xA0
        if cont_ok && !overlong && !surrogate {
          let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
          sb.write_char(cp.reinterpret_as_int().unsafe_to_char())
          i = i + 3
          continue
        }
      }
      sb.write_char('\u{FFFD}')
      i = i + 1
    } else if b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 < n {
        let b1 = bs[i + 1].to_uint()
        let b2 = bs[i + 2].to_uint()
        let b3 = bs[i + 3].to_uint()
        let cont_ok = b1 >= 0x80 &&
          b1 <= 0xBF &&
          b2 >= 0x80 &&
          b2 <= 0xBF &&
          b3 >= 0x80 &&
          b3 <= 0xBF
        let overlong = b0 == 0xF0 && b1 < 0x90
        let too_large = b0 == 0xF4 && b1 > 0x8F
        if cont_ok && !overlong && !too_large {
          let cp = ((b0 & 0x07) << 18) |
            ((b1 & 0x3F) << 12) |
            ((b2 & 0x3F) << 6) |
            (b3 & 0x3F)
          sb.write_char(cp.reinterpret_as_int().unsafe_to_char())
          i = i + 4
          continue
        }
      }
      sb.write_char('\u{FFFD}')
      i = i + 1
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
fn utf16_width(c : Char) -> Int32 {
  if c.to_int() > 0xFFFF {
    2
  } else {
    1
  }
}

///|
/// Enforce the 20000 length cap.  Python counts code points; here the cap is
/// applied to UTF-16 code units (never splitting a surrogate pair), so both
/// `String::length()` and `String::char_length()` stay at or below 20000.
fn cap_length(src : String) -> String {
  if src.length() <= 20000 {
    return src
  }
  let cs = src.to_array()
  let mut width = 0
  let mut cut = 0
  while cut < cs.length() && width + utf16_width(cs[cut]) <= 20000 {
    width = width + utf16_width(cs[cut])
    cut = cut + 1
  }
  str_slice(cs, 0, cut)
}

// ---------------------------------------------------------------------------
// Mutators.  Each corresponds one-to-one to an `m_*` function in the Python
// harness; `mutate_named` dispatches by the Python name.
// ---------------------------------------------------------------------------

///|
fn fresh_name(rng : Rng, base : String) -> String {
  base + rng.int(10000).to_string()
}

///|
/// Replace one token with another token of the same lexical class.
pub fn replace_token(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let toks = tokenize(src)
  if toks.length() == 0 {
    return src
  }
  let t = rng.choice(toks)
  let rep : String = match t.kind {
    TId => {
      let pool : Array[String] = []
      for k in keywords {
        pool.push(k)
      }
      for b in builtin_types {
        pool.push(b)
      }
      for other in toks {
        match other.kind {
          TId => pool.push(other.text)
          _ => ()
        }
      }
      pool.push(fresh_name(rng, "v"))
      rng.choice(pool)
    }
    TNum => rng.choice(literals)
    TStr => rng.choice(str_replacements)
    TChr => rng.choice(chr_replacements)
    TOp => {
      let pool : Array[String] = []
      for op in operators {
        pool.push(op)
      }
      for d in ["(", ")", "{", "}", "[", "]", ",", ";"] {
        pool.push(d)
      }
      rng.choice(pool)
    }
  }
  rebuild(cs, t.start, t.end, rep)
}

///|
/// Replace identifier `val` with a dictionary candidate `d`, keeping the
/// original token position.  Only alphanumeric identifiers shorter than 24
/// characters are considered, mirroring the Python filter (this is what keeps
/// operators and punctuation out of the replacement set).
fn dict_token_with(src : String, rng : Rng, dict : Array[String]) -> String {
  let cs = src.to_array()
  let toks = tokenize(src)
  let ids : Array[Token] = []
  for t in toks {
    match t.kind {
      TId => ids.push(t)
      _ => ()
    }
  }
  if ids.length() == 0 {
    return src
  }
  let t = rng.choice(ids)
  let cands : Array[String] = []
  for d in dict {
    if d != t.text &&
      !is_keyword(d) &&
      d.char_length() < 24 &&
      is_dict_identifier(d) {
      cands.push(d)
    }
  }
  if cands.length() == 0 {
    return src
  }
  rebuild(cs, t.start, t.end, rng.choice(cands))
}

///|
fn is_dict_identifier(s : String) -> Bool {
  if s.char_length() == 0 {
    return false
  }
  for c in s {
    if c != '_' && !is_ascii_alpha(c) && !is_ascii_digit(c) {
      return false
    }
  }
  true
}

///|
/// Dictionary replacement using the small built-in fallback dictionary.
pub fn dict_token(src : String, rng : Rng) -> String {
  dict_token_with(src, rng, default_dict())
}

///|
/// Insert a statement after a random line, preserving that line's indentation.
pub fn insert_stmt(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let lines = split_lines(cs)
  if lines.length() == 0 {
    return src
  }
  let idx = rng.int(lines.length())
  let line = lines[idx]
  let ind = leading_whitespace(cs, line)
  let stmt = rng.choice(insert_stmts)
  str_slice(cs, 0, line.end) +
  ind +
  stmt +
  "\n" +
  str_slice(cs, line.end, cs.length())
}

///|
/// Duplicate a balanced bracket region, including its delimiters.
pub fn dup_block(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let bs = boundaries(src)
  if bs.length() == 0 {
    return src
  }
  let b = rng.choice(bs)
  if b.end - b.start > 4000 {
    return src
  }
  str_slice(cs, 0, b.end + 1) +
  "\n" +
  str_slice(cs, b.start, b.end + 1) +
  str_slice(cs, b.end + 1, cs.length())
}

///|
/// Delete a balanced bracket region (delimiters included).
pub fn del_block(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let eligible : Array[Span] = []
  for b in boundaries(src) {
    if b.end - b.start < 2000 {
      eligible.push(b)
    }
  }
  if eligible.length() == 0 {
    return src
  }
  let b = rng.choice(eligible)
  rebuild(cs, b.start, b.end + 1, "")
}

///|
/// Wrap a balanced region in a control-flow construct.
pub fn wrap(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let eligible : Array[Span] = []
  for b in boundaries(src) {
    if b.end - b.start > 0 && b.end - b.start < 1000 {
      eligible.push(b)
    }
  }
  if eligible.length() == 0 {
    return src
  }
  let b = rng.choice(eligible)
  let frag = str_slice(cs, b.start, b.end + 1)
  let pair : (String, String) = match rng.int(6) {
    0 => ("if true { ", " }")
    1 => ("if false { ", " } else { " + frag + " }")
    2 => ("match () { () => ", " }")
    3 => ("{ ", " }")
    4 => ("try { ", " } catch { _ => () }")
    _ => ("loop { break ", " }")
  }
  str_slice(cs, 0, b.start) +
  pair.0 +
  frag +
  pair.1 +
  str_slice(cs, b.end + 1, cs.length())
}

///|
/// Delete one bracket character without trying to rebalance.
pub fn delim(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let idx : Array[Int32] = []
  for i = 0; i < cs.length(); i = i + 1 {
    let c = cs[i]
    if c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' {
      idx.push(i)
    }
  }
  if idx.length() == 0 {
    return src
  }
  let i = rng.choice(idx)
  rebuild(cs, i, i + 1, "")
}

///|
/// Cut the source at a random character position.
pub fn truncate(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let n = cs.length()
  if n < 4 {
    return src
  }
  let cut = rng.int_range(1, n - 1)
  str_slice(cs, 0, cut)
}

///|
/// Flip 1..4 random UTF-8 bytes and decode the result.  Invalid UTF-8 is
/// replaced with U+FFFD rather than Python's surrogate escapes.
pub fn bitflip(src : String, rng : Rng) -> String {
  let bs = utf8_encode(src)
  if bs.length() == 0 {
    return src
  }
  let flips = rng.int_range(1, 4)
  for _ in 0..<flips {
    let i = rng.int(bs.length())
    bs[i] = rng.int(256).to_byte()
  }
  utf8_decode(bs)
}

///|
/// Replace a standalone short decimal literal with a boundary literal.
pub fn literal_edges(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let nums = short_number_ranges(cs)
  if nums.length() == 0 {
    return src
  }
  let r = rng.choice(nums)
  rebuild(cs, r.start, r.end, rng.choice(literals))
}

///|
/// Replace every whole-word occurrence of a random non-keyword identifier.
pub fn rename_ident(src : String, rng : Rng) -> String {
  let toks = tokenize(src)
  let ids : Array[String] = []
  for t in toks {
    match t.kind {
      TId => if !is_keyword(t.text) { ids.push(t.text) }
      _ => ()
    }
  }
  if ids.length() == 0 {
    return src
  }
  let old = rng.choice(ids)
  let old_chars = old.to_array()
  let base = if old_chars.length() >= 2 {
    str_slice(old_chars, 0, 2)
  } else {
    old
  }
  let new = fresh_name(rng, base)
  let cs = src.to_array()
  let n = cs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let mut matched = false
    if i + old_chars.length() <= n {
      matched = true
      for k = 0; k < old_chars.length(); k = k + 1 {
        if cs[i + k] != old_chars[k] {
          matched = false
          break
        }
      }
    }
    if matched {
      let prev_ok = i == 0 || !is_ascii_word(cs[i - 1])
      let after = i + old_chars.length()
      let next_ok = after >= n || !is_ascii_word(cs[after])
      if prev_ok && next_ok {
        sb.write_string(new)
        i = after
      } else {
        sb.write_char(cs[i])
        i = i + 1
      }
    } else {
      sb.write_char(cs[i])
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// Insert a random attribute before a declaration line, preserving indentation.
pub fn inject_attr(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let lines = split_lines(cs)
  let idx : Array[Int32] = []
  for i = 0; i < lines.length(); i = i + 1 {
    if line_starts_decl(cs, lines[i]) {
      idx.push(i)
    }
  }
  if idx.length() == 0 {
    return src
  }
  let i = rng.choice(idx)
  let line = lines[i]
  let ind = leading_whitespace(cs, line)
  str_slice(cs, 0, line.start) +
  ind +
  rng.choice(attrs) +
  "\n" +
  str_slice(cs, line.start, cs.length())
}

///|
/// Append a top-level async function and a function that raises.
pub fn async_mut(src : String, _rng : Rng) -> String {
  src +
  "\n\nasync fn __af() -> Unit { () }\nfn __bf() -> Unit raise Failure { () }\n"
}

///|
/// Insert one Unicode seed at a random character position.
pub fn unicode(src : String, rng : Rng) -> String {
  let cs = src.to_array()
  let pos = rng.int(cs.length() + 1)
  str_slice(cs, 0, pos) +
  rng.choice(unicode_seeds) +
  str_slice(cs, pos, cs.length())
}

///|
/// Splice a top-level function from another corpus member.
pub fn splice_fn(src : String, rng : Rng, pool : Array[String]) -> String {
  let cand : Array[String] = []
  for p in pool {
    if p != src && p.char_length() < 4000 {
      cand.push(p)
    }
  }
  if cand.length() == 0 {
    return src
  }
  let other = rng.choice(cand)
  let fns = find_functions(other.to_array())
  if fns.length() == 0 {
    return src
  }
  src + "\n\n" + rng.choice(fns) + "\n"
}

///|
/// Turn `fn name(...)` into `fn name[T] (x : T) -> T (...)` by inserting a
/// generic parameter list before the existing one.
pub fn generic(src : String, _rng : Rng) -> String {
  let cs = src.to_array()
  let n = cs.length()
  let mut i = 0
  while i < n {
    if cs[i] == 'f' &&
      matches_at(cs, i, "fn") &&
      (i == 0 || !is_ascii_word(cs[i - 1])) {
      let mut j = i + 2
      if j < n && is_space_char(cs[j]) {
        while j < n && is_space_char(cs[j]) {
          j = j + 1
        }
        if j < n && is_ident_start(cs[j]) {
          j = j + 1
          while j < n && is_ascii_word(cs[j]) {
            j = j + 1
          }
          while j < n && is_space_char(cs[j]) {
            j = j + 1
          }
          if j < n && cs[j] == '(' {
            return str_slice(cs, 0, j) +
              "[T] (x : T) -> T (" +
              str_slice(cs, j + 1, n)
          }
        }
      }
    }
    i = i + 1
  }
  src
}

///|
/// Append an unterminated block comment.
pub fn comment_cut(src : String, rng : Rng) -> String {
  src + "\n/*" + "x".repeat(rng.int_range(1, 199))
}

///|
/// Mutate only inside one balanced block (normally a function body), keeping
/// the surrounding declarations intact.
fn body_with(src : String, rng : Rng, dict : Array[String]) -> String {
  let cs = src.to_array()
  let eligible : Array[Span] = []
  for b in boundaries(src) {
    if b.end - b.start > 20 && b.end - b.start < 6000 {
      eligible.push(b)
    }
  }
  if eligible.length() == 0 {
    return src
  }
  let b = rng.choice(eligible)
  let mut inner = str_slice(cs, b.start + 1, b.end)
  let rounds = rng.int_range(1, 3)
  for _ in 0..<rounds {
    inner = match rng.int(7) {
      0 => replace_token(inner, rng)
      1 => insert_stmt(inner, rng)
      2 => literal_edges(inner, rng)
      3 => wrap(inner, rng)
      4 => dup_block(inner, rng)
      5 => rename_ident(inner, rng)
      _ => dict_token_with(inner, rng, dict)
    }
  }
  str_slice(cs, 0, b.start + 1) + inner + str_slice(cs, b.end, cs.length())
}

///|
/// Body-only mutation using the fallback dictionary.
pub fn body(src : String, rng : Rng) -> String {
  body_with(src, rng, default_dict())
}

// ---------------------------------------------------------------------------
// Driver.
// ---------------------------------------------------------------------------

///|
/// Weighted operator table, in the same order and with the same weights as the
/// Python `ops_list` list.
let ops_list : Array[(String, Int32)] = [
  ("replace_token", 30),
  ("dict_token", 8),
  ("insert_stmt", 14),
  ("dup_block", 8),
  ("wrap", 8),
  ("delim", 8),
  ("truncate", 6),
  ("bitflip", 5),
  ("literal_edges", 5),
  ("unicode", 5),
  ("rename_ident", 4),
  ("inject_attr", 4),
  ("del_block", 3),
  ("splice_fn", 3),
  ("generic", 2),
  ("async", 1),
  ("comment_cut", 1),
]

///|
fn choose_op(rng : Rng) -> String {
  let mut total = 0
  for op in ops_list {
    total = total + op.1
  }
  let mut r = rng.int(total)
  for op in ops_list {
    if r < op.1 {
      return op.0
    }
    r = r - op.1
  }
  "replace_token"
}

///|
/// Apply one named operator.  The `m_`-prefixed Python spellings are accepted
/// as aliases so callers can use either style.
fn apply_named(
  name : String,
  src : String,
  rng : Rng,
  pool : Array[String],
  dict : Array[String],
) -> String {
  if name == "replace_token" || name == "m_replace_token" {
    replace_token(src, rng)
  } else if name == "dict_token" || name == "m_dict_token" {
    dict_token_with(src, rng, dict)
  } else if name == "insert_stmt" || name == "m_insert_stmt" {
    insert_stmt(src, rng)
  } else if name == "dup_block" || name == "m_dup_block" {
    dup_block(src, rng)
  } else if name == "del_block" || name == "m_del_block" {
    del_block(src, rng)
  } else if name == "wrap" || name == "m_wrap" {
    wrap(src, rng)
  } else if name == "delim" || name == "m_delim" {
    delim(src, rng)
  } else if name == "truncate" || name == "m_truncate" {
    truncate(src, rng)
  } else if name == "bitflip" || name == "m_bitflip" {
    bitflip(src, rng)
  } else if name == "literal_edges" || name == "m_literal_edges" {
    literal_edges(src, rng)
  } else if name == "unicode" || name == "m_unicode" {
    unicode(src, rng)
  } else if name == "rename_ident" || name == "m_rename_ident" {
    rename_ident(src, rng)
  } else if name == "inject_attr" || name == "m_inject_attr" {
    inject_attr(src, rng)
  } else if name == "splice_fn" || name == "m_splice_fn" {
    splice_fn(src, rng, pool)
  } else if name == "generic" || name == "m_generic" {
    generic(src, rng)
  } else if name == "async" || name == "m_async" {
    async_mut(src, rng)
  } else if name == "comment_cut" || name == "m_comment_cut" {
    comment_cut(src, rng)
  } else if name == "body" || name == "m_body" {
    body_with(src, rng, dict)
  } else {
    src
  }
}

///|
/// Run one named mutator.  Unknown names are a no-op.  Pass `dict=...` to use a
/// dictionary parsed with `parse_dict`; otherwise a small built-in fallback is
/// used for `dict_token` and `body`.
pub fn mutate_named(
  name : String,
  src : String,
  rng : Rng,
  pool : Array[String],
  dict? : Array[String],
) -> String {
  let d = match dict {
    Some(d) => d
    None => default_dict()
  }
  apply_named(name, src, rng, pool, d)
}

///|
/// Structure-aware mutation driver.
///
/// 55% of calls apply a single operator; the rest apply 2..5.  With
/// `body_only=true`, 85% of rounds use `body`, otherwise the normal weighted
/// operator table is used.  The result is capped at 20000 UTF-16 code units
/// after every round, matching the Python harness's per-round `len(src) >
/// 20000` trim.
pub fn mutate(
  src : String,
  rng : Rng,
  pool : Array[String],
  body_only : Bool,
  dict? : Array[String],
) -> String {
  let d = match dict {
    Some(d) => d
    None => default_dict()
  }
  let rounds = if rng.float() < 0.55 { 1 } else { rng.int_range(2, 5) }
  let mut out = src
  for _ in 0..<rounds {
    let name = if body_only && rng.chance(0.85) {
      "body"
    } else {
      choose_op(rng)
    }
    out = apply_named(name, out, rng, pool, d)
    out = cap_length(out)
  }
  out
}
