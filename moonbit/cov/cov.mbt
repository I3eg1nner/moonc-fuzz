///|
/// A set of compiler function names.
///
/// The Python harness materializes these as `set(r)` at every use site, so
/// duplicate names inside `funcs` are tolerated but never counted twice.
/// `new`, `parse_json`, and all set operations therefore store a
/// first-occurrence-preserving, de-duplicated array; `sorted` additionally
/// sorts it.  The array is intentionally not kept sorted internally, matching
/// the Python behaviour of carrying per-input lists and sorting only when a
/// report or set comparison needs it.
pub struct FuncSet {
  funcs : Array[String]
}

///|
/// Preserve first-occurrence order while removing duplicates.
fn unique_strings(items : Array[String]) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for name in items {
    if !seen.contains(name) {
      seen.set(name, ())
      out.push(name)
    }
  }
  out
}

///|
/// Python's `sorted(strings)` compares Unicode code points lexicographically.
/// MoonBit's default `String::compare` is shortlex over UTF-16 code units, so
/// `"_start".compare("Ppx")` would order `_start` first.  The harness must match
/// Python exactly, hence this explicit code-point comparator.
fn compare_codepoints(a : String, b : String) -> Int32 {
  let a_len = a.char_length()
  let b_len = b.char_length()
  let common = if a_len < b_len { a_len } else { b_len }
  let mut i = 0
  while i < common {
    let ca = a.get_char(i).unwrap()
    let cb = b.get_char(i).unwrap()
    if ca != cb {
      return if ca.to_int() < cb.to_int() { -1 } else { 1 }
    }
    i = i + 1
  }
  a_len.compare(b_len)
}

///|
fn sort_strings(items : Array[String]) -> Unit {
  items.sort_by(fn(a, b) { compare_codepoints(a, b) })
}

///|
/// Construct a `FuncSet` from arbitrary function names (duplicates allowed).
pub fn FuncSet::new(funcs : Array[String]) -> FuncSet {
  { funcs: unique_strings(funcs), }
}

///|
/// De-duplicated function names in first-occurrence order.
pub fn FuncSet::to_array(self : FuncSet) -> Array[String] {
  unique_strings(self.funcs)
}

///|
/// Number of distinct function names in the set.
pub fn FuncSet::len(self : FuncSet) -> Int32 {
  let seen : Map[String, Unit] = Map([])
  for name in self.funcs {
    seen.set(name, ())
  }
  seen.length()
}

///|
/// Distinct function names in ascending lexicographic order.
pub fn FuncSet::sorted(self : FuncSet) -> Array[String] {
  let out = unique_strings(self.funcs)
  sort_strings(out)
  out
}

///|
/// Set union; the result is sorted so downstream output is deterministic.
pub fn FuncSet::union(self : FuncSet, other : FuncSet) -> FuncSet {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for name in self.funcs {
    if !seen.contains(name) {
      seen.set(name, ())
      out.push(name)
    }
  }
  for name in other.funcs {
    if !seen.contains(name) {
      seen.set(name, ())
      out.push(name)
    }
  }
  sort_strings(out)
  { funcs: out, }
}

///|
/// Set intersection; the result is sorted so downstream output is deterministic.
pub fn FuncSet::intersection(self : FuncSet, other : FuncSet) -> FuncSet {
  let in_other : Map[String, Unit] = Map([])
  for name in other.funcs {
    in_other.set(name, ())
  }
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for name in self.funcs {
    if in_other.contains(name) && !seen.contains(name) {
      seen.set(name, ())
      out.push(name)
    }
  }
  sort_strings(out)
  { funcs: out, }
}

///|
/// Set difference (`self - other`); sorted for deterministic output.
pub fn FuncSet::difference(self : FuncSet, other : FuncSet) -> FuncSet {
  let in_other : Map[String, Unit] = Map([])
  for name in other.funcs {
    in_other.set(name, ())
  }
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for name in self.funcs {
    if !in_other.contains(name) && !seen.contains(name) {
      seen.set(name, ())
      out.push(name)
    }
  }
  sort_strings(out)
  { funcs: out, }
}

///|
/// Parse the harness JSON shape `{"funcs": ["a", "b"], ...}`.
///
/// Every object key except `funcs` is ignored, so the full
/// `cov_funcs_seeds.json` snapshot (which also carries `per_input_new`,
/// `cumulative`, `modules`, ...) parses without modification.  A missing or
/// `null` `funcs` is treated as an empty set, mirroring Python's
/// `d.get("funcs") or []`; a non-array `funcs` or a non-string element is an
/// error.
pub fn parse_json(text : String) -> FuncSet raise {
  let value = @json.parse(text)
  let object = match value {
    @json.Json::Object(object) => object
    _ =>
      raise Failure::Failure("cov.FuncSet.parse_json: expected a JSON object")
  }
  let items = match object.get("funcs") {
    None => []
    Some(@json.Json::Null) => []
    Some(@json.Json::Array(items)) => items
    Some(_) =>
      raise Failure::Failure(
        "cov.FuncSet.parse_json: \"funcs\" must be an array",
      )
  }
  let funcs : Array[String] = []
  let seen : Map[String, Unit] = Map([])
  for item in items {
    let name = match item {
      @json.Json::String(name) => name
      _ =>
        raise Failure::Failure(
          "cov.FuncSet.parse_json: every \"funcs\" entry must be a string",
        )
    }
    if !seen.contains(name) {
      seen.set(name, ())
      funcs.push(name)
    }
  }
  { funcs, }
}

///|
/// Serialize back to the canonical `{"funcs":[...]}` shape, sorted and
/// de-duplicated.  Used by the JSON round-trip test.
pub fn FuncSet::to_json_string(self : FuncSet) -> String {
  let items : Array[@json.Json] = []
  for name in self.sorted() {
    items.push(@json.Json::string(name))
  }
  let object : Map[String, @json.Json] = Map([])
  object.set("funcs", @json.Json::array(items))
  @json.Json::object(object).stringify()
}

///|
/// Order-sensitive aggregation, a direct port of `cov.py aggregate`.
///
/// Each input is treated as a `set`, so duplicates within one input do not
/// inflate `per_input_new`.  `per_input_new[i]` is the number of names first
/// seen in input `i`; `cumulative[i]` is the union size after input `i`.
/// The returned union is sorted, matching `sorted(union)` at the JSON/report
/// boundary in Python.
pub fn aggregate(
  sets : Array[Array[String]],
) -> (Array[String], Array[Int32], Array[Int32]) {
  let union_seen : Map[String, Unit] = Map([])
  let per_new : Array[Int32] = []
  let cumulative : Array[Int32] = []
  for input in sets {
    let local_seen : Map[String, Unit] = Map([])
    let mut new_count = 0
    for name in input {
      if local_seen.contains(name) {
        continue
      }
      local_seen.set(name, ())
      if !union_seen.contains(name) {
        union_seen.set(name, ())
        new_count = new_count + 1
      }
    }
    per_new.push(new_count)
    cumulative.push(union_seen.length())
  }
  let union : Array[String] = []
  for name in union_seen.keys() {
    union.push(name)
  }
  sort_strings(union)
  (union, per_new, cumulative)
}

///|
/// Greedy set cover, a direct port of `cov.py minimize_corpus`.
///
/// At every round the unused input with the largest number of still-uncovered
/// names wins.  The comparison is strict (`gain > best_gain`), so ties keep the
/// lowest input index.  Selection stops as soon as no input can add a new name
/// (which also covers the empty universe).  Returned indices are in selection
/// order, exactly like Python's `chosen` list.
pub fn minimize_sets(sets : Array[Array[String]]) -> Array[Int32] {
  let normalized : Array[Array[String]] = []
  for input in sets {
    normalized.push(unique_strings(input))
  }
  let uncovered : Map[String, Unit] = Map([])
  for input in normalized {
    for name in input {
      uncovered.set(name, ())
    }
  }
  let chosen : Array[Int32] = []
  let is_chosen : Array[Bool] = Array::make(normalized.length(), false)
  while uncovered.length() > 0 {
    let mut best_i = -1
    let mut best_gain = 0
    for i, input in normalized {
      if is_chosen[i] {
        continue
      }
      let mut gain = 0
      for name in input {
        if uncovered.contains(name) {
          gain = gain + 1
        }
      }
      if gain > best_gain {
        best_i = i
        best_gain = gain
      }
    }
    if best_i < 0 || best_gain == 0 {
      break
    }
    chosen.push(best_i)
    is_chosen[best_i] = true
    for name in normalized[best_i] {
      uncovered.remove(name)
    }
  }
  chosen
}

///|
/// `cov.py report` uses `MB_MAP_SIZE` with a 64K default.  `report_row` has no
/// map-size parameter, so it uses the same default.
pub let report_map_size : Int32 = 65536

///|
fn spaces(count : Int32) -> String {
  let builder = StringBuilder()
  let mut i = 0
  while i < count {
    builder.write_char(' ')
    i = i + 1
  }
  builder.to_string()
}

///|
fn zeros(count : Int32) -> String {
  let builder = StringBuilder()
  let mut i = 0
  while i < count {
    builder.write_char('0')
    i = i + 1
  }
  builder.to_string()
}

///|
fn pad_left(text : String, width : Int32) -> String {
  let fill = width - text.char_length()
  if fill > 0 {
    spaces(fill) + text
  } else {
    text
  }
}

///|
fn pad_right(text : String, width : Int32) -> String {
  let fill = width - text.char_length()
  if fill > 0 {
    text + spaces(fill)
  } else {
    text
  }
}

///|
fn pow10(digits : Int32) -> Int32 {
  let mut result = 1
  let mut i = 0
  while i < digits {
    result = result * 10
    i = i + 1
  }
  result
}

///|
/// Fixed-point formatting with round-half-to-even, matching Python's
/// `f"{value:.Nf}"` tie behaviour.  `num` and `den` must be non-negative and
/// `den` positive.
fn format_fixed(num : Int32, den : Int32, digits : Int32) -> String {
  let scale = pow10(digits)
  let scaled = num * scale
  let quotient = scaled / den
  let remainder = scaled % den
  let twice = remainder * 2
  let rounded = if twice > den || (twice == den && quotient % 2 != 0) {
    quotient + 1
  } else {
    quotient
  }
  if digits == 0 {
    return rounded.to_string()
  }
  let whole = rounded / scale
  let fraction = rounded % scale
  let fraction_text = fraction.to_string()
  whole.to_string() +
  "." +
  zeros(digits - fraction_text.char_length()) +
  fraction_text
}

///|
fn edges_field(edges : Int32) -> String {
  if edges == 0 {
    "-"
  } else {
    edges.to_string()
  }
}

///|
fn density_field(edges : Int32) -> String {
  if edges == 0 {
    "-"
  } else {
    format_fixed(edges, report_map_size, 3)
  }
}

///|
fn funcs_field(funcs : Int32) -> String {
  if funcs == 0 {
    "-"
  } else {
    funcs.to_string()
  }
}

///|
fn new_exec_field(per_new : Array[Int32], n : Int32) -> String {
  if per_new.length() == 0 {
    return "-"
  }
  let mut total = 0
  for value in per_new {
    total = total + value
  }
  format_fixed(total, if n > 0 { n } else { 1 }, 2)
}

///|
/// The exact header emitted by `cov.py report`.
pub fn report_header() -> String {
  pad_right("snapshot", 34) +
  " " +
  pad_right("tool", 22) +
  " " +
  pad_left("n", 5) +
  " " +
  pad_left("edges", 7) +
  " " +
  pad_left("dens", 6) +
  " " +
  pad_left("funcs", 7) +
  " " +
  pad_left("new/exec", 9)
}

///|
/// One fixed-width report row.
///
/// The frozen Python row has seven columns, but the required MoonBit signature
/// does not receive the snapshot's `tool` string, so this helper emits the six
/// available columns with identical widths/padding/placeholder rules.  Use
/// `report_row_with_tool` when byte-for-byte Python parity is needed.
pub fn report_row(
  name : String,
  n : Int32,
  edges : Int32,
  funcs : Int32,
  per_new : Array[Int32],
) -> String {
  pad_right(name, 34) +
  " " +
  pad_left(n.to_string(), 5) +
  " " +
  pad_left(edges_field(edges), 7) +
  " " +
  pad_left(density_field(edges), 6) +
  " " +
  pad_left(funcs_field(funcs), 7) +
  " " +
  pad_left(new_exec_field(per_new, n), 9)
}

///|
/// Byte-for-byte equivalent of the row printed by `cov.py report`.
pub fn report_row_with_tool(
  name : String,
  tool : String,
  n : Int32,
  edges : Int32,
  funcs : Int32,
  per_new : Array[Int32],
) -> String {
  pad_right(name, 34) +
  " " +
  pad_right(tool, 22) +
  " " +
  pad_left(n.to_string(), 5) +
  " " +
  pad_left(edges_field(edges), 7) +
  " " +
  pad_left(density_field(edges), 6) +
  " " +
  pad_left(funcs_field(funcs), 7) +
  " " +
  pad_left(new_exec_field(per_new, n), 9)
}

///|
fn json_int_array(items : Array[Int32]) -> String {
  let builder = StringBuilder()
  builder.write_string("[")
  for i, value in items {
    if i > 0 {
      builder.write_string(",")
    }
    builder.write_string(value.to_string())
  }
  builder.write_string("]")
  builder.to_string()
}

///|
/// The compact JSON summary used by the MoonBit port of the coverage report:
/// `{"func_count":N,"per_input_new":[...],"cumulative":[...]}`.
///
/// Key order is fixed (unlike a `Map` round-trip), so the output is stable and
/// diffable.  The sorted union itself is intentionally not repeated here;
/// call `aggregate` when the names are needed.
pub fn union_stats(sets : Array[Array[String]]) -> String {
  let (union, per_new, cumulative) = aggregate(sets)
  "{\"func_count\":" +
  union.length().to_string() +
  ",\"per_input_new\":" +
  json_int_array(per_new) +
  ",\"cumulative\":" +
  json_int_array(cumulative) +
  "}"
}
