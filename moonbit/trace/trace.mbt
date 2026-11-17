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
/// Exact per-function depth derived from the parsed TB sequence.
///
/// `blocks` is the number of distinct raw PCs attributed to this function.
/// `edges` is the number of distinct consecutive TB pairs whose two endpoints
/// both fall in this function.  Both are QEMU translation-block measures, not
/// source-level basic blocks or source CFG branches.
pub struct FuncDepth {
  name : String
  blocks : Int32
  edges : Int32
}

///|
pub struct TraceSummary {
  /// Sorted unique function names; unchanged from the function-only summary.
  funcs : Array[String]
  /// Every parsed TB entry, including entries whose PC does not map.
  total_tb : Int32
  /// Parsed TB entries whose PC maps to a symbol.
  mapped_tb : Int32
  /// Number of distinct raw PCs seen.
  unique_pc : Int32
  /// Number of distinct PCs that map to a symbol.
  mapped_unique_pc : Int32
  /// Number of distinct consecutive pairs `(pc_i, pc_{i+1})` over parsed TB
  /// entries.  The first parsed entry contributes no edge.  This is
  /// TB-transition coverage, not a source CFG edge count.
  edges : Int32
  /// Number of distinct consecutive pairs where BOTH endpoints map.
  mapped_edges : Int32
  /// Per-function exact depth, sorted by function name.
  func_depth : Array[FuncDepth]
}

///|
/// Injective string key for one TB transition.  Decimal PC representations
/// contain no comma, so splitting on the comma recovers both endpoints exactly.
fn tb_edge_key(a : UInt64, b : UInt64) -> String {
  a.to_string() + "," + b.to_string()
}

///|
fn count_or_zero(counts : Map[String, Int32], key : String) -> Int32 {
  match counts.get(key) {
    Some(n) => n
    None => 0
  }
}

///|
fn bump_count(counts : Map[String, Int32], key : String) -> Unit {
  counts.set(key, count_or_zero(counts, key) + 1)
}

///|
/// Shared single scan behind `summarize_trace` and `edge_keys`: the trace text
/// is parsed exactly once, and both the counters and (optionally) the exact
/// mapped-edge key set are produced from that one pass.
///
/// `with_keys=false` keeps the counter-only path from allocating the much
/// larger key array.  When keys are requested they are appended to a set-backed
/// array, deduplicated by the `seen_mapped_edge` map, and sorted before return.
fn scan_trace(
  trace : String,
  sym : SymTab,
  with_keys : Bool,
) -> (TraceSummary, Array[String]) {
  let seen_funcs : Map[String, Unit] = Map([])
  let funcs : Array[String] = []
  let seen_pc : Map[UInt64, Unit] = Map([])
  let seen_mapped_pc : Map[UInt64, Unit] = Map([])
  let seen_edge : Map[String, Unit] = Map([])
  let seen_mapped_edge : Map[String, Unit] = Map([])
  let edge_key_list : Array[String] = []
  let func_blocks : Map[String, Int32] = Map([])
  let func_edges : Map[String, Int32] = Map([])
  let mut total_tb = 0
  let mut mapped_tb = 0
  let mut unique_pc = 0
  let mut mapped_unique_pc = 0
  let mut edges = 0
  let mut mapped_edges = 0
  let mut prev_pc : UInt64? = None
  let mut prev_func : String? = None
  for line in trace.split("\n") {
    match parse_trace_pc(line) {
      Some(pc) => {
        total_tb += 1
        if !seen_pc.contains(pc) {
          seen_pc.set(pc, ())
          unique_pc += 1
        }
        let func = sym.func_of(pc)
        match func {
          Some(name) => {
            mapped_tb += 1
            if !seen_mapped_pc.contains(pc) {
              seen_mapped_pc.set(pc, ())
              mapped_unique_pc += 1
              bump_count(func_blocks, name)
            }
            if !seen_funcs.contains(name) {
              seen_funcs.set(name, ())
              funcs.push(name)
            }
          }
          None => ()
        }
        // Only parsed entries advance the sequence: malformed lines neither
        // create an edge nor break the adjacency of the surrounding entries.
        match prev_pc {
          Some(prior_pc) => {
            let edge = tb_edge_key(prior_pc, pc)
            if !seen_edge.contains(edge) {
              seen_edge.set(edge, ())
              edges += 1
            }
            match (prev_func, func) {
              (Some(prior_func), Some(current_func)) =>
                if !seen_mapped_edge.contains(edge) {
                  seen_mapped_edge.set(edge, ())
                  mapped_edges += 1
                  if with_keys {
                    edge_key_list.push(edge)
                  }
                  // A pair's endpoint functions are fixed by the symbol table,
                  // so a new mapped pair is also a new intra-function edge
                  // exactly when both endpoints share a name.
                  if prior_func == current_func {
                    bump_count(func_edges, current_func)
                  }
                }
              _ => ()
            }
          }
          None => ()
        }
        prev_pc = Some(pc)
        prev_func = func
      }
      None => ()
    }
  }
  funcs.sort()
  let func_depth : Array[FuncDepth] = []
  for name in funcs {
    func_depth.push({
      name,
      blocks: count_or_zero(func_blocks, name),
      edges: count_or_zero(func_edges, name),
    })
  }
  if with_keys {
    edge_key_list.sort()
  }
  let summary : TraceSummary = {
    funcs,
    total_tb,
    mapped_tb,
    unique_pc,
    mapped_unique_pc,
    edges,
    mapped_edges,
    func_depth,
  }
  (summary, edge_key_list)
}

///|
/// Parse a full QEMU exec log and return the sorted unique function set plus
/// exact TB block/edge depth.
///
/// All sets are keyed by the exact raw PC (or exact decimal PC pair), never by
/// a lossy bitmap hash.  Normalization is only the final sort of function
/// names, so repeated invocations over the same input are deterministic.
///
/// The trace is scanned exactly once per call.  `collect` uses this function
/// directly and derives its `camlMoonc*` function list from the same summary,
/// so a campaign does not pay for a second parse.
pub fn summarize_trace(trace : String, sym : SymTab) -> TraceSummary {
  let (summary, _) = scan_trace(trace, sym, false)
  summary
}

///|
/// Exact, deduplicated, sorted keys of the mapped TB transitions in `trace`.
///
/// Key format is the injective decimal string `"<pc0>,<pc1>"` built by
/// `tb_edge_key`.  Decimal PC text contains no comma, so the key needs no
/// escaping and a set of these keys can be unioned across runs without
/// collisions.  Ordering is the same shortlex `String` sort used for `funcs`,
/// which makes the array deterministic for a fixed input.
///
/// Scope: a key is emitted only when BOTH endpoint PCs map to a symbol, which
/// matches the `mapped_edges` counter exactly (`edge_keys(t, s).length()` is
/// always `summarize_trace(t, s).mapped_edges`).  This is deliberately WIDER
/// than the historical `TraceResult.functions` filter, which keeps only
/// `camlMoonc*` names: a transition inside `main` or a stdlib helper is
/// included here even though neither endpoint name appears in `functions`.
/// The keys are therefore "all-mapped", not "moonc-only".  Do not compare the
/// key count against `functions.length()`.
///
/// Bound and cost: the input is one trace log that the caller has already
/// limited (see `max_trace_bytes`), so the key set is bounded by that log and
/// is not campaign-wide.  An edge set is much larger than a function set, so
/// this array is meant for offline union/persistence, not for per-input
/// retention in the scheduler.
pub fn edge_keys(trace : String, sym : SymTab) -> Array[String] {
  let (_, keys) = scan_trace(trace, sym, true)
  keys
}

///|
fn write_json_string(b : StringBuilder, s : String) -> Unit {
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

///|
/// Convenience for CLI output: `["a","b"]` with JSON escaping.
pub fn json_string_array(items : Array[String]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  for i, s in items {
    if i > 0 {
      b.write_string(",")
    }
    write_json_string(b, s)
  }
  b.write_string("]")
  b.to_string()
}

///|
/// Convenience for CLI output: deterministic per-function depth objects.
pub fn json_func_depth_array(items : Array[FuncDepth]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  for i, d in items {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("{\"func\":")
    write_json_string(b, d.name)
    b.write_string(",\"blocks\":")
    b.write_string(d.blocks.to_string())
    b.write_string(",\"edges\":")
    b.write_string(d.edges.to_string())
    b.write_string("}")
  }
  b.write_string("]")
  b.to_string()
}
