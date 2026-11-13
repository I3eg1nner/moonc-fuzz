///|
/// Minimal, dependency-free PC -> function symbolizer for the closed-source
/// moonc binary.  This is a byte-for-byte port of harness/symbolize.py:
/// accept only PCs inside [text_lo, text_hi] (no guest-base subtraction) and
/// attribute a PC to the nearest preceding T/t/W/w symbol from `nm -n`.
///
/// Keeping the "no subtraction" rule is deliberate.  QEMU prints two address
/// spaces in `-d exec` logs; subtracting a guessed base turns dynamic-loader
/// PCs into plausible-but-wrong moonc symbols.  The audit found those false
/// positives, so the production path only accepts addresses that already match
/// the ET_EXEC symbol table.
pub struct Sym {
  addr : UInt64
  name : String
}

///|
pub struct SymTab {
  syms : Array[Sym]
  text_lo : UInt64
  text_hi : UInt64
}

///|
pub fn parse_hex_u64(s : StringView) -> UInt64? {
  if s.char_length() == 0 {
    return None
  }
  let mut v = 0UL
  for c in s {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    v = v * 16UL + d.to_uint64()
  }
  Some(v)
}

///|
fn is_text_symbol(kind : StringView) -> Bool {
  kind == "T" || kind == "t" || kind == "W" || kind == "w"
}

///|
/// Parse the output of `nm -n <binary>`.  Lines are `ADDR TYPE NAME`;
/// undefined and absolute symbols are ignored, matching harness/symbolize.py.
pub fn SymTab::parse(nm_text : String) -> SymTab {
  let syms : Array[Sym] = []
  for raw in nm_text.split("\n") {
    let line = raw.trim()
    if line.char_length() == 0 {
      continue
    }
    let fields : Array[StringView] = []
    for f in line.split(" ") {
      if f.char_length() > 0 {
        fields.push(f)
      }
    }
    if fields.length() < 3 {
      continue
    }
    if !is_text_symbol(fields[1]) {
      continue
    }
    // nm may append symbol versions or demangled suffixes; the name is field 2.
    match parse_hex_u64(fields[0]) {
      Some(addr) => syms.push({ addr, name: fields[2].to_owned(), })
      None => ()
    }
  }
  syms.sort_by(fn(a, b) {
    if a.addr < b.addr {
      -1
    } else if a.addr > b.addr {
      1
    } else {
      0
    }
  })
  let lo = if syms.length() > 0 { syms[0].addr } else { 0UL }
  let hi = if syms.length() > 0 { syms[syms.length() - 1].addr } else { 0UL }
  { syms, text_lo: lo, text_hi: hi, }
}

///|
pub fn SymTab::len(self : SymTab) -> Int32 {
  self.syms.length()
}

///|
pub fn SymTab::text_range(self : SymTab) -> (UInt64, UInt64) {
  (self.text_lo, self.text_hi)
}

///|
/// Nearest preceding text symbol, or None when the PC is outside moonc.
pub fn SymTab::func_of(self : SymTab, pc : UInt64) -> String? {
  if pc < self.text_lo || pc > self.text_hi || self.syms.length() == 0 {
    return None
  }
  let mut lo = 0
  let mut hi = self.syms.length() - 1
  let mut ans = -1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if self.syms[mid].addr <= pc {
      ans = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  if ans < 0 {
    None
  } else {
    Some(self.syms[ans].name)
  }
}

///|
/// Index form used by tests and by the audit tool: the symbol interval.
pub fn SymTab::range_of(self : SymTab, name : String) -> (UInt64, UInt64)? {
  for i, s in self.syms {
    if s.name == name {
      let end = if i + 1 < self.syms.length() {
        self.syms[i + 1].addr
      } else {
        s.addr + 4096UL
      }
      return Some((s.addr, end))
    }
  }
  None
}

///|
/// `camlMoonc__Lex_literal__foo_123` -> `Moonc.Lex_literal.foo`
pub fn short_name(name : StringView) -> String {
  let mut n = name
  if n.has_prefix("caml") {
    n = n.exact_view(start=4)
  }
  if n.has_prefix("Moonc__") {
    n = n.exact_view(start=7)
  }
  if n.has_prefix("Stdlib__") {
    return "Stdlib." + n.exact_view(start=8).to_owned()
  }
  n.to_owned()
}

///|
/// Extract the guest PC from a QEMU `-d exec` line.  The format is
/// `Trace 0: 0xHOST [0000000000000000/0000004000821290/0xTB]`.
pub fn parse_trace_pc(line : StringView) -> UInt64? {
  let lb = match line.find("[") {
    Some(i) => i
    None => return None
  }
  let after = line.exact_view(start=lb + 1)
  let s1 = match after.find("/") {
    Some(i) => i
    None => return None
  }
  let mid = after.exact_view(start=s1 + 1)
  let s2 = match mid.find("/") {
    Some(i) => i
    None => return None
  }
  parse_hex_u64(mid.exact_view(start=0, end=s2))
}

///|
pub struct TraceSummary {
  funcs : Array[String]
  total_tb : Int32
  mapped_tb : Int32
}

///|
/// Parse a full QEMU exec log and return the sorted unique function set.
/// The ordering and dedup semantics match the Python reference.
pub fn summarize_trace(trace : String, sym : SymTab) -> TraceSummary {
  let seen : Map[String, Unit] = Map([])
  let funcs : Array[String] = []
  let mut total_tb = 0
  let mut mapped_tb = 0
  for line in trace.split("\n") {
    match parse_trace_pc(line) {
      Some(pc) => {
        total_tb += 1
        match sym.func_of(pc) {
          Some(f) => {
            mapped_tb += 1
            if !seen.contains(f) {
              seen.set(f, ())
              funcs.push(f)
            }
          }
          None => ()
        }
      }
      None => ()
    }
  }
  funcs.sort()
  { funcs, total_tb, mapped_tb, }
}

///|
/// Convenience for CLI output: `["a","b"]` with JSON escaping.
pub fn json_string_array(items : Array[String]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  for i, s in items {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
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
      } else {
        b.write_char(c)
      }
    }
    b.write_string("\"")
  }
  b.write_string("]")
  b.to_string()
}
