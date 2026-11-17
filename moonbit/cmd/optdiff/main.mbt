///|
/// Controlled optimization differential for real MoonBit package tests.
///
/// Stage 1 is intentionally link-only.  It reuses the official `moon test
/// --debug` artifacts, captures the exact `link-core` and
/// `moonrun --test-args` argv arrays, relinks each test wasm with and without
/// `-O0`, and compares the complete per-test result map.  It does not isolate
/// build-package optimization; that is the next stage.
///
/// A run is successful only when the baseline test build passed, the dry-run
/// plan is complete, every requested test ID appears exactly once, both arms
/// exit consistently, and all requested arms have stable repeated results.

///|
struct Config {
  mut source_dir : String
  mut module_dir : String
  mut out : String
  mut packages : Array[String]
  mut target : String
  mut llvm_opt : String
  mut timeout_ms : Int32
  mut repeats : Int32
  mut aa : Bool
  mut four_cell : Bool
  mut four_control : Bool
  mut candidate : Bool
  mut fault_file : String
  mut fault_from : String
  mut fault_to : String
}

///|
struct ParsedRun {
  results : Map[String, String]
  bad : Bool
  duplicate : Bool
}

///|
struct RunTask {
  argv : Array[String]
  wasm_index : Int32
  wasm_path : String
  expected : Map[String, Unit]
}

///|
struct LinkTask {
  argv : Array[String]
  run : RunTask
  base : String
  panic_ids : Map[String, Unit]
}

///|
struct LinkLine {
  argv : Array[String]
  base : String
}

///|
struct NativeLink {
  argv : Array[String]
  base : String
}

///|
struct CcLine {
  argv : Array[String]
  base : String
}

///|
fn artifact_stem(path : String) -> String {
  let b = @corpus.basename(path)
  if b.has_suffix(".o") {
    b[0:b.length() - 2].to_owned()
  } else if b.has_suffix(".exe") {
    b[0:b.length() - 4].to_owned()
  } else if b.has_suffix(".wasm") {
    b[0:b.length() - 5].to_owned()
  } else {
    b
  }
}

///|
fn usage() -> Unit {
  println(
    "usage: optdiff --module ABS_DIR --out ABS_DIR [--packages p1,p2] [--target wasm-gc|wasm|native] [--llvm-opt N] [--timeout MS] [--repeats N] [--aa] [--four-cell] [--four-cell-control FILE FROM TO] [--candidate-check FILE FROM TO] [--fault-check FILE FROM TO]",
  )
}

///|
fn is_abs(p : String) -> Bool {
  p.has_prefix("/")
}

///|
fn path_within(child : String, parent : String) -> Bool {
  if child == parent {
    true
  } else if parent == "/" {
    child.has_prefix("/")
  } else {
    child.has_prefix(parent + "/")
  }
}

///|
async fn real_path(p : String) -> String? {
  let r = @exec.run("/usr/bin/readlink", ["-f", p], "/tmp", 5000)
  if r.rc == 0 {
    let s = r.stdout.trim().to_owned()
    if s != "" {
      Some(s)
    } else {
      None
    }
  } else {
    None
  }
}

///|
fn parse_int(s : String, dflt : Int32) -> Int32 {
  let mut v = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      return dflt
    }
  }
  if any {
    v
  } else {
    dflt
  }
}

///|
fn parse_packages(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split(",") {
    let p = part.trim().to_owned()
    if p != "" {
      out.push(p)
    }
  }
  out
}

///|
fn safe_name(pkg : String) -> String {
  let b = StringBuilder()
  for c in pkg {
    if c == '/' {
      b.write_string("__")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn package_tag(pkg : String) -> String {
  safe_name(pkg) + "-" + @corpus.short_hash(pkg)
}

///|
/// Split a command printed by `moon` into argv.  It supports single and double
/// quotes but deliberately rejects shell metacharacters; the command is then
/// executed directly, not through a shell.
fn shell_split(line : String) -> Array[String]? {
  let args : Array[String] = []
  let b = StringBuilder()
  let mut quote = 0
  let mut any = false
  for c in line {
    if quote == 0 {
      if c == ' ' || c == '\t' {
        if any {
          args.push(b.to_string())
          b.reset()
          any = false
        }
      } else if c == '\'' {
        quote = 1
        any = true
      } else if c == '"' {
        quote = 2
        any = true
      } else if c == ';' ||
        c == '|' ||
        c == '&' ||
        c == '<' ||
        c == '>' ||
        c == '`' ||
        c == '$' ||
        c == '\n' ||
        c == '\r' {
        return None
      } else {
        b.write_char(c)
        any = true
      }
    } else if quote == 1 {
      if c == '\'' {
        quote = 0
      } else {
        b.write_char(c)
      }
    } else if c == '"' {
      quote = 0
    } else {
      b.write_char(c)
    }
  }
  if quote != 0 {
    return None
  }
  if any {
    args.push(b.to_string())
  }
  Some(args)
}

///|
fn join_argv(argv : Array[String]) -> String {
  let b = StringBuilder()
  for i, a in argv {
    if i > 0 {
      b.write_string(" ")
    }
    b.write_string(a)
  }
  b.to_string()
}

///|
fn find_arg(argv : Array[String], token : String) -> Int32? {
  let mut i = 0
  while i < argv.length() {
    if argv[i] == token {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn replace_arg(
  argv : Array[String],
  index : Int32,
  value : String,
) -> Array[String] {
  let out : Array[String] = []
  for i, a in argv {
    out.push(if i == index { value } else { a })
  }
  out
}

///|
fn remove_arg(argv : Array[String], index : Int32) -> Array[String] {
  let out : Array[String] = []
  for i, a in argv {
    if i != index {
      out.push(a)
    }
  }
  out
}

///|
fn count_arg(argv : Array[String], token : String) -> Int32 {
  let mut n = 0
  for a in argv {
    if a == token {
      n += 1
    }
  }
  n
}

///|
fn resolve_tool(home : String, name : String) -> String {
  let p = @corpus.join(@corpus.join(home, ".moon/bin"), name)
  if @fs.path_exists(p) {
    p
  } else {
    name
  }
}

///|
async fn run_argv(
  argv : Array[String],
  cwd : String,
  timeout_ms : Int32,
  home : String,
) -> @exec.RunResult {
  if argv.length() == 0 {
    return {
      rc: -998,
      stdout: "",
      stderr: "empty argv",
      ms: 0L,
      timed_out: false,
      stdout_digest: "",
      stdout_full_len: 0L,
      stdout_truncated: false,
    }
  }
  let args : Array[String] = []
  for i, a in argv {
    if i == 0 && (a == "moonc" || a == "moonrun" || a == "moon") {
      args.push(resolve_tool(home, a))
    } else {
      args.push(a)
    }
  }
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(args[i])
  }
  @exec.run(args[0], rest, cwd, timeout_ms, max_output_bytes=32 * 1024 * 1024)
}

///|
fn write_json(path : String, text : String) -> Bool {
  @corpus.ensure_dir(@corpus.dirname(path))
  @fs.write_string_to_file(path, text) catch {
    _ => return false
  }
  true
}

///|
fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
/// Extract test IDs from the `--test-args` JSON.  Each entry is
/// `[file, [{start, end}, ...]]`; ranges are left-inclusive/right-exclusive.
fn expected_ids(args_json : String) -> Map[String, Unit]? {
  let parsed = @json.parse(args_json) catch { _ => return None }
  match parsed {
    Object(obj) => {
      let files = match obj.get("file_and_index") {
        Some(Array(items)) => items
        _ => return None
      }
      let out : Map[String, Unit] = Map([])
      for item in files {
        match item {
          Array(pair) => {
            if pair.length() < 2 {
              return None
            }
            let file = match pair[0] {
              String(s) => s
              _ => return None
            }
            let ranges = match pair[1] {
              Array(rs) => rs
              _ => return None
            }
            for range in ranges {
              match range {
                Object(o) => {
                  let start = match o.get("start") {
                    Some(Number(n, ..)) => n.to_int()
                    _ => return None
                  }
                  let end = match o.get("end") {
                    Some(Number(n, ..)) => n.to_int()
                    _ => return None
                  }
                  if start < 0 || end < start {
                    return None
                  }
                  for i in start..<end {
                    let key = file + "|" + i.to_string()
                    if out.contains(key) {
                      return None
                    }
                    out.set(key, ())
                  }
                }
                _ => return None
              }
            }
          }
          _ => return None
        }
      }
      if out.length() == 0 {
        None
      } else {
        Some(out)
      }
    }
    _ => None
  }
}

///|
fn expected_native_ids(args : String) -> Map[String, Unit]? {
  let out : Map[String, Unit] = Map([])
  let mut prefix = ""
  let mut malformed = false
  for raw in args.split("/") {
    let seg = raw.to_owned()
    if seg == "" {
      malformed = true
    } else if seg.contains(":") {
      let colon = match seg.find(":") {
        Some(i) => i
        None => {
          malformed = true
          continue
        }
      }
      let file_part = seg[0:colon].to_owned()
      let range = seg[colon + 1:].to_owned()
      let file = if prefix == "" { file_part } else { prefix + "/" + file_part }
      let mut start = -1
      let mut end = -1
      let mut part_i = 0
      for part in range.split("-") {
        if part_i == 0 {
          start = parse_int(part.to_owned(), -1)
        } else if part_i == 1 {
          end = parse_int(part.to_owned(), -1)
        } else {
          malformed = true
        }
        part_i += 1
      }
      if start < 0 || end <= start || part_i != 2 {
        malformed = true
      } else {
        for i in start..<end {
          let key = file + "|" + i.to_string()
          if out.contains(key) {
            malformed = true
          } else {
            out.set(key, ())
          }
        }
      }
      prefix = ""
    } else {
      prefix = if prefix == "" { seg } else { prefix + "/" + seg }
    }
  }
  if malformed || prefix != "" || out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
fn parse_result_line(line : StringView) -> (String, String)? {
  let parsed = @json.parse(line) catch { _ => return None }
  match parsed {
    Object(obj) => {
      let ty = match obj.get("type") {
        Some(String(s)) => s
        _ => return None
      }
      if ty != "result" {
        return None
      }
      let file = match obj.get("file") {
        Some(String(s)) => s
        _ => return None
      }
      let index = match obj.get("index") {
        Some(Number(n, ..)) => n.to_int().to_string()
        Some(String(s)) => s
        _ => return None
      }
      let message = match obj.get("message") {
        Some(String(s)) => s
        _ => return None
      }
      if file == "" || index == "" {
        None
      } else {
        Some((file + "|" + index, message))
      }
    }
    _ => None
  }
}

///|
fn collect_results(out : String) -> ParsedRun {
  let results : Map[String, String] = Map([])
  let mut bad = false
  let mut duplicate = false
  for line in out.split("\n") {
    let t = line.trim()
    if t.has_prefix("{\"type\":\"result\"") {
      match parse_result_line(t) {
        Some((key, msg)) =>
          if results.contains(key) {
            duplicate = true
          } else {
            results.set(key, msg)
          }
        None => bad = true
      }
    }
  }
  { results, bad, duplicate, }
}

///|
fn count_failures(
  results : Map[String, String],
  panic_ids : Map[String, Unit],
) -> Int32 {
  let mut n = 0
  for k in results.keys() {
    match results.get(k) {
      Some(msg) =>
        if test_status(msg, panic_ids.contains(k)) == "fail" {
          n += 1
        }
      None => ()
    }
  }
  n
}

///|
fn leading_int(s : StringView) -> Int32 {
  let mut n = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      break
    }
  }
  if any {
    n
  } else {
    0
  }
}

///|
fn summary_failures(text : String) -> Int32 {
  for line in text.split("\n") {
    if line.has_prefix("Total tests:") {
      match line.find("failed:") {
        Some(i) => return leading_int(line[i + 7:].trim())
        None => ()
      }
    }
  }
  0
}

///|
fn test_status(message : String, expected_panic : Bool) -> String {
  if message.has_prefix("skipped test") {
    "skip"
  } else if expected_panic {
    if message == "" {
      "fail"
    } else {
      "pass"
    }
  } else if message == "" {
    "pass"
  } else {
    "fail"
  }
}

///|
struct Compare {
  changed : Int32
  missing : Int32
  extra : Int32
}

///|
fn compare_results(
  a : Map[String, String],
  b : Map[String, String],
  panic_ids : Map[String, Unit],
) -> Compare {
  let seen : Map[String, Unit] = Map([])
  for k in a.keys() {
    seen.set(k, ())
  }
  for k in b.keys() {
    seen.set(k, ())
  }
  let mut changed = 0
  let mut missing = 0
  let mut extra = 0
  for k in seen.keys() {
    match (a.get(k), b.get(k)) {
      (Some(x), Some(y)) =>
        if test_status(x, panic_ids.contains(k)) !=
          test_status(y, panic_ids.contains(k)) {
          changed += 1
        }
      (Some(_), None) => missing += 1
      (None, Some(_)) => extra += 1
      (None, None) => ()
    }
  }
  { changed, missing, extra, }
}

///|
fn exact_coverage(
  results : Map[String, String],
  expected : Map[String, Unit],
) -> Bool {
  if results.length() != expected.length() {
    return false
  }
  for k in expected.keys() {
    if !results.contains(k) {
      return false
    }
  }
  true
}

///|
fn parse_runs(runs : Array[String]) -> Array[RunTask]? {
  if runs.length() == 0 {
    return None
  }
  let out : Array[RunTask] = []
  let seen : Map[String, Unit] = Map([])
  let seen_base : Map[String, Unit] = Map([])
  for line in runs {
    let argv = match shell_split(line) {
      Some(a) => a
      None => return None
    }
    let args_i = match find_arg(argv, "--test-args") {
      Some(i) => i
      None => return None
    }
    if args_i + 1 >= argv.length() {
      return None
    }
    let expected = match expected_ids(argv[args_i + 1]) {
      Some(e) => e
      None => return None
    }
    let mut wasm_i = -1
    let mut wasm_path = ""
    for i, a in argv {
      if a.has_suffix(".wasm") {
        if wasm_i >= 0 {
          return None
        }
        wasm_i = i
        wasm_path = a
      }
    }
    let base = @corpus.basename(wasm_path)
    if wasm_i < 0 || seen.contains(wasm_path) || seen_base.contains(base) {
      return None
    }
    seen.set(wasm_path, ())
    seen_base.set(base, ())
    out.push({ argv, wasm_index: wasm_i, wasm_path, expected, })
  }
  Some(out)
}

///|
fn filter_empty_link_lines(
  links : Array[LinkLine],
  runs : Array[RunTask],
  build_root : String,
  target : String,
  pkg : String,
) -> Array[LinkLine]? {
  let run_bases : Map[String, Unit] = Map([])
  for r in runs {
    run_bases.set(@corpus.basename(r.wasm_path), ())
  }
  let out : Array[LinkLine] = []
  for line in links {
    if run_bases.contains(line.base) {
      out.push(line)
    } else {
      let meta = match metadata_path_at(build_root, target, pkg, line.base) {
        Some(path) => load_test_meta(path)
        None => None
      }
      match meta {
        Some(m) =>
          if m.known.length() == 0 {
            // Valid zero-test artifact: link exists, runtime does not.
          } else {
            return None
          }
        None => return None
      }
    }
  }
  Some(out)
}

///|
fn parse_links(
  links : Array[String],
  runs : Array[RunTask],
) -> Array[LinkTask]? {
  let tasks : Array[LinkTask] = []
  let used : Map[String, Unit] = Map([])
  for line in links {
    let argv = match shell_split(line) {
      Some(a) => a
      None => return None
    }
    let o_i = match find_arg(argv, "-o") {
      Some(i) => i
      None => return None
    }
    if o_i + 1 >= argv.length() {
      return None
    }
    let old_path = argv[o_i + 1]
    if used.contains(old_path) {
      return None
    }
    let mut run_match : RunTask? = None
    for r in runs {
      if r.wasm_path == old_path {
        if run_match is Some(_) {
          return None
        }
        run_match = Some(r)
        used.set(r.wasm_path, ())
      }
    }
    let run = match run_match {
      Some(r) => r
      None => return None
    }
    tasks.push({
      argv,
      run,
      base: @corpus.basename(old_path),
      panic_ids: Map([]),
    })
  }
  for r in runs {
    if !used.contains(r.wasm_path) {
      return None
    }
  }
  Some(tasks)
}

///|
fn fault_file_ok(p : String) -> Bool {
  p != "" &&
  !p.has_prefix("/") &&
  !p.contains("..") &&
  !p.contains("\\") &&
  !p.contains("'") &&
  !p.contains("\"")
}

///|
async fn copy_one(src : String, dst : String, timeout_ms : Int32) -> Bool {
  @corpus.ensure_dir(@corpus.dirname(dst))
  let r = @exec.run("/bin/cp", [src, dst], "/tmp", timeout_ms)
  r.rc == 0
}

///|
fn strip_o0_arg(argv : Array[String]) -> Array[String]? {
  if count_arg(argv, "-O0") != 1 {
    return None
  }
  let i = match find_arg(argv, "-O0") {
    Some(i) => i
    None => return None
  }
  Some(remove_arg(argv, i))
}

///|
fn parse_link_lines(links : Array[String]) -> Array[LinkLine]? {
  let out : Array[LinkLine] = []
  let seen : Map[String, Unit] = Map([])
  for line in links {
    let argv = match shell_split(line) {
      Some(a) => a
      None => return None
    }
    let o_i = match find_arg(argv, "-o") {
      Some(i) => i
      None => return None
    }
    if o_i + 1 >= argv.length() {
      return None
    }
    let base = @corpus.basename(argv[o_i + 1])
    if seen.contains(base) {
      return None
    }
    seen.set(base, ())
    out.push({ argv, base, })
  }
  Some(out)
}

///|
fn find_link_line(lines : Array[LinkLine], base : String) -> LinkLine? {
  for line in lines {
    if line.base == base {
      return Some(line)
    }
  }
  None
}

///|
fn parse_native_link_lines(links : Array[String]) -> Array[NativeLink]? {
  let out : Array[NativeLink] = []
  let seen : Map[String, Unit] = Map([])
  for line in links {
    let argv = match shell_split(line) {
      Some(a) => a
      None => return None
    }
    let o_i = match find_arg(argv, "-o") {
      Some(i) => i
      None => return None
    }
    if o_i + 1 >= argv.length() {
      return None
    }
    let base = artifact_stem(argv[o_i + 1])
    if base == "" || seen.contains(base) {
      return None
    }
    seen.set(base, ())
    out.push({ argv, base, })
  }
  Some(out)
}

///|
fn lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  for line in text.split("\n") {
    out.push(line.to_owned())
  }
  out
}

///|
fn parse_native_cc_lines(lines : Array[String]) -> Array[CcLine]? {
  let out : Array[CcLine] = []
  let seen : Map[String, Unit] = Map([])
  for line in lines {
    let t = line.trim()
    if t == "" || !t.has_prefix("/usr/bin/cc ") {
      continue
    }
    let argv = match shell_split(t.to_owned()) {
      Some(a) => a
      None => return None
    }
    let o_i = match find_arg(argv, "-o") {
      Some(i) => i
      None => return None
    }
    if o_i + 1 >= argv.length() || !argv[o_i + 1].has_suffix(".exe") {
      continue
    }
    let base = artifact_stem(argv[o_i + 1])
    if base == "" || seen.contains(base) {
      return None
    }
    seen.set(base, ())
    out.push({ argv, base, })
  }
  Some(out)
}

///|
fn find_native_link(lines : Array[NativeLink], base : String) -> NativeLink? {
  for line in lines {
    if line.base == base {
      return Some(line)
    }
  }
  None
}

///|
fn find_native_cc(lines : Array[CcLine], base : String) -> CcLine? {
  for line in lines {
    if line.base == base {
      return Some(line)
    }
  }
  None
}

///|
fn parse_native_runs(
  lines : Array[String],
  build_root : String,
) -> Array[RunTask]? {
  let out : Array[RunTask] = []
  let seen : Map[String, Unit] = Map([])
  for line in lines {
    let argv = match shell_split(line) {
      Some(a) => a
      None => return None
    }
    if argv.length() == 0 {
      continue
    }
    let exe = argv[0]
    if !exe.has_suffix(".exe") {
      continue
    }
    if !exe.has_prefix(build_root + "/") {
      return None
    }
    let base = artifact_stem(exe)
    if base == "" || seen.contains(base) {
      return None
    }
    let expected = if argv.length() > 1 {
      match expected_native_ids(argv[1]) {
        Some(e) => e
        None => return None
      }
    } else {
      Map([])
    }
    seen.set(base, ())
    out.push({ argv, wasm_index: 0, wasm_path: exe, expected, })
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
fn filter_native_links(
  links : Array[NativeLink],
  runs : Array[RunTask],
  build_root : String,
  pkg : String,
) -> Array[NativeLink]? {
  let run_bases : Map[String, Unit] = Map([])
  for r in runs {
    run_bases.set(artifact_stem(r.wasm_path), ())
  }
  let out : Array[NativeLink] = []
  for line in links {
    if run_bases.contains(line.base) {
      out.push(line)
    } else {
      let meta = match
        metadata_path_at(build_root, "native", pkg, line.base + ".exe") {
        Some(path) => load_test_meta(path)
        None => None
      }
      match meta {
        Some(m) =>
          if m.known.length() == 0 {
            // Valid zero-test artifact: link exists, runtime does not.
          } else {
            return None
          }
        None => return None
      }
    }
  }
  Some(out)
}

///|
fn expand_moon_home(argv : Array[String], home : String) -> Array[String] {
  let out : Array[String] = []
  for a in argv {
    if a.has_prefix("$MOON_HOME/") {
      out.push(home + "/.moon/" + a[11:].to_owned())
    } else if a == "$MOON_HOME" {
      out.push(home + "/.moon")
    } else {
      out.push(a)
    }
  }
  out
}

///|
fn add_llvm_opt(argv : Array[String], level : String) -> Array[String] {
  let out : Array[String] = []
  for a in argv {
    out.push(a)
  }
  out.push("-llvm-opt")
  out.push(level)
  out
}

///|
fn make_native_link_argv(
  argv : Array[String],
  new_path : String,
  remove_o0 : Bool,
) -> Array[String]? {
  if count_arg(argv, "-o") != 1 || count_arg(argv, "-O0") != 1 {
    return None
  }
  let o_i = match find_arg(argv, "-o") {
    Some(i) => i
    None => return None
  }
  if o_i + 1 >= argv.length() {
    return None
  }
  let with_out = replace_output(argv, o_i, new_path)
  if !remove_o0 {
    return Some(with_out)
  }
  let o0_i = match find_arg(with_out, "-O0") {
    Some(i) => i
    None => return None
  }
  Some(remove_arg(with_out, o0_i))
}

///|
fn make_native_cc_argv(
  cc : CcLine,
  object_path : String,
  exe_path : String,
  home : String,
) -> Array[String]? {
  if count_arg(cc.argv, "-o") != 1 {
    return None
  }
  let o_i = match find_arg(cc.argv, "-o") {
    Some(i) => i
    None => return None
  }
  if o_i + 1 >= cc.argv.length() {
    return None
  }
  let expected_obj = cc.base + ".o"
  let mut replaced = false
  let argv : Array[String] = []
  for i, a in cc.argv {
    if i == o_i + 1 {
      argv.push(exe_path)
    } else if @corpus.basename(a) == expected_obj {
      if replaced {
        return None
      }
      argv.push(object_path)
      replaced = true
    } else {
      argv.push(a)
    }
  }
  if !replaced {
    return None
  }
  Some(expand_moon_home(argv, home))
}

///|
async fn build_arm(
  cfg : Config,
  pkg : String,
  root : String,
  build_root : String,
  remove_o0 : Bool,
  home : String,
) -> (Array[String], Bool) {
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  @corpus.ensure_dir(build_root)
  // Generate all_pkgs.json, test drivers and a complete O0 build first.  A
  // bare dry-run cannot be replayed: it prints commands that depend on these
  // generated files.
  let prep = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--build-only",
      "--target-dir",
      build_root,
    ],
    root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if prep.rc != 0 {
    println("[optdiff] prebuild failed for \{build_root}: \{prep.rc}")
    return ([], false)
  }
  let dry = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--dry-run",
      "-v",
      "--target-dir",
      build_root,
    ],
    root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  let dry_path = @corpus.join(build_root, "dryrun.stdout")
  if dry.rc != 0 || !write_json(dry_path, dry.stdout) {
    println("[optdiff] cannot build dry-run for \{build_root}")
    return ([], false)
  }
  let links : Array[String] = []
  for line in dry.stdout.split("\n") {
    let t = line.trim()
    if t.has_prefix("moonc link-core ") {
      links.push(t.to_owned())
    } else if t.has_prefix("moonc build-package ") ||
      t.has_prefix("moon generate-test-driver ") {
      let argv = match shell_split(t.to_owned()) {
        Some(a) => a
        None => return ([], false)
      }
      if remove_o0 &&
        argv.length() > 1 &&
        argv[0] == "moonc" &&
        argv[1] == "build-package" {
        let cmd = match strip_o0_arg(argv) {
          Some(a) => a
          None => {
            println("[optdiff] build command has no unique -O0: \{t}")
            return ([], false)
          }
        }
        let r = run_argv(cmd, root, cfg.timeout_ms, home)
        if r.rc != 0 {
          println("[optdiff] build command failed for \{build_root}: \{r.rc}")
          return ([], false)
        }
      }
    }
  }
  (links, true)
}

///|
fn link_has_core(link : LinkLine, core_name : String) -> Bool {
  for a in link.argv {
    if a.has_suffix("/" + core_name + ".core") {
      return true
    }
  }
  false
}

///|
fn native_link_has_core(link : NativeLink, core_name : String) -> Bool {
  for a in link.argv {
    if a.has_suffix("/" + core_name + ".core") {
      return true
    }
  }
  false
}

///|
async fn run_test_arm(
  cfg : Config,
  root : String,
  run : RunTask,
  link : LinkLine,
  arm_path : String,
  remove_o0 : Bool,
  home : String,
  evidence : String,
  label : String,
  override_core : String?,
  core_name : String,
  repeats : Int32,
) -> Map[String, String]? {
  let mut link_argv = link.argv
  if remove_o0 && override_core is Some(core) {
    let mut replaced = false
    for i, a in link.argv {
      if a.has_suffix("/" + core_name + ".core") {
        link_argv = replace_arg(link_argv, i, core)
        replaced = true
      }
    }
    if !replaced {
      return None
    }
  }
  let mut base_results : Map[String, String] = Map([])
  let mut r = 0
  while r < repeats {
    let repeated_path = arm_path + ".r" + r.to_string() + ".wasm"
    let link_cmd = match make_link_argv(link_argv, repeated_path, remove_o0) {
      Some(a) => a
      None => return None
    }
    let lr = run_argv(link_cmd, root, cfg.timeout_ms, home)
    if lr.rc != 0 {
      println("[optdiff] link failed for \{repeated_path}: \{lr.rc}")
      println("[optdiff] link stderr: \{lr.stderr}")
      return None
    }
    let rr = run_argv(
      make_run_argv(run, repeated_path),
      root,
      cfg.timeout_ms,
      home,
    )
    let parsed = collect_results(rr.stdout)
    let tag = @corpus.basename(run.wasm_path) +
      "." +
      label +
      ".r" +
      r.to_string()
    if !write_json(@corpus.join(evidence, tag + ".stdout"), rr.stdout) ||
      !write_json(@corpus.join(evidence, tag + ".stderr"), rr.stderr) {
      return None
    }
    if rr.rc != 0 ||
      rr.timed_out ||
      rr.stdout_truncated ||
      parsed.bad ||
      parsed.duplicate ||
      !exact_coverage(parsed.results, run.expected) {
      println("[optdiff] test run invalid for \{repeated_path}")
      return None
    }
    if r == 0 {
      base_results = parsed.results
    } else {
      let c = compare_results(base_results, parsed.results, Map([]))
      if c.changed > 0 || c.missing > 0 || c.extra > 0 {
        println("[optdiff] unstable repeat for \{repeated_path}")
        return None
      }
    }
    r += 1
  }
  Some(base_results)
}

///|

///|
async fn run_native_test_arm(
  cfg : Config,
  root : String,
  run : RunTask,
  link : NativeLink,
  cc : CcLine,
  arm_base : String,
  remove_o0 : Bool,
  home : String,
  evidence : String,
  label : String,
  override_core : String?,
  core_name : String,
  repeats : Int32,
) -> Map[String, String]? {
  let mut link_argv = link.argv
  if remove_o0 && override_core is Some(core) {
    let mut replaced = false
    for i, a in link.argv {
      if a.has_suffix("/" + core_name + ".core") {
        link_argv = replace_arg(link_argv, i, core)
        replaced = true
      }
    }
    if !replaced {
      return None
    }
  }
  let mut base_results : Map[String, String] = Map([])
  let mut r = 0
  while r < repeats {
    let suffix = "." + label + ".r" + r.to_string()
    let object_path = arm_base + suffix + ".o"
    let exe_path = arm_base + suffix + ".exe"
    let link_cmd = match
      make_native_link_argv(link_argv, object_path, remove_o0) {
      Some(a) => a
      None => return None
    }
    let link_cmd = if remove_o0 && cfg.llvm_opt != "" {
      add_llvm_opt(link_cmd, cfg.llvm_opt)
    } else {
      link_cmd
    }
    let lr = run_argv(link_cmd, root, cfg.timeout_ms, home)
    if lr.rc != 0 {
      println("[optdiff] native link failed for \{object_path}: \{lr.rc}")
      println("[optdiff] native link stderr: \{lr.stderr}")
      return None
    }
    let cc_cmd = match make_native_cc_argv(cc, object_path, exe_path, home) {
      Some(a) => a
      None => return None
    }
    let cr = run_argv(cc_cmd, root, cfg.timeout_ms, home)
    if cr.rc != 0 {
      println("[optdiff] native cc failed for \{exe_path}: \{cr.rc}")
      println("[optdiff] native cc stderr: \{cr.stderr}")
      return None
    }
    let rr = run_argv(make_run_argv(run, exe_path), root, cfg.timeout_ms, home)
    let parsed = collect_results(rr.stdout)
    let tag = @corpus.basename(run.wasm_path) +
      "." +
      label +
      ".r" +
      r.to_string()
    if !write_json(@corpus.join(evidence, tag + ".stdout"), rr.stdout) ||
      !write_json(@corpus.join(evidence, tag + ".stderr"), rr.stderr) {
      return None
    }
    if rr.rc != 0 ||
      rr.timed_out ||
      rr.stdout_truncated ||
      parsed.bad ||
      parsed.duplicate ||
      !exact_coverage(parsed.results, run.expected) {
      println("[optdiff] native test run invalid for \{exe_path}")
      return None
    }
    if r == 0 {
      base_results = parsed.results
    } else {
      let c = compare_results(base_results, parsed.results, Map([]))
      if c.changed > 0 || c.missing > 0 || c.extra > 0 {
        println("[optdiff] unstable native repeat for \{exe_path}")
        return None
      }
    }
    r += 1
  }
  Some(base_results)
}

///|
async fn run_four_package(cfg : Config, pkg : String) -> (Int32, Int32, Int32) {
  if cfg.target != "wasm" && cfg.target != "wasm-gc" && cfg.target != "native" {
    println("[optdiff] four-cell needs wasm/wasm-gc/native")
    @env.exit(2)
  }
  let pkg_tag = package_tag(pkg)
  let base_dir = @corpus.join(cfg.out, "four/" + pkg_tag)
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  @corpus.ensure_dir(base_dir)
  let work = @corpus.join(base_dir, "module")
  if !work.has_prefix(cfg.out + "/") {
    println("[optdiff] unsafe four-cell work path")
    @env.exit(2)
  }
  let rm = @exec.run("/bin/rm", ["-rf", work], "/tmp", cfg.timeout_ms)
  if rm.rc != 0 {
    println("[optdiff] cannot clean four-cell work")
    @env.exit(2)
  }
  let cp = @exec.run(
    "/bin/cp",
    ["-a", cfg.source_dir, work],
    "/tmp",
    cfg.timeout_ms,
  )
  if cp.rc != 0 {
    println("[optdiff] cannot copy four-cell work")
    @env.exit(2)
  }
  match real_path(work) {
    Some(p) =>
      if p != work {
        println("[optdiff] four-cell work is a symlink")
        @env.exit(2)
      }
    None => {
      println("[optdiff] cannot resolve four-cell work")
      @env.exit(2)
    }
  }
  let clean = @exec.run(
    "/bin/rm",
    ["-rf", @corpus.join(work, "_build")],
    "/tmp",
    cfg.timeout_ms,
  )
  if clean.rc != 0 {
    println("[optdiff] cannot clean four-cell cache")
    @env.exit(2)
  }
  cfg.module_dir = work
  if !write_manifest_to(cfg, home, @corpus.join(base_dir, "manifest.json")) {
    println("[optdiff] cannot write four-cell manifest")
    @env.exit(2)
  }
  let b0 = @corpus.join(base_dir, "build/O0")
  let bd = @corpus.join(base_dir, "build/default")
  let (links_o0, ok_o0) = build_arm(cfg, pkg, work, b0, false, home)
  if !ok_o0 {
    @env.exit(2)
  }
  let (links_d, ok_d) = build_arm(cfg, pkg, work, bd, true, home)
  if !ok_d {
    @env.exit(2)
  }
  let parsed_o0_links = match parse_link_lines(links_o0) {
    Some(l) => l
    None => {
      println("[optdiff] duplicate/invalid O0 link plan")
      @env.exit(2)
    }
  }
  let parsed_d_links = match parse_link_lines(links_d) {
    Some(l) => l
    None => {
      println("[optdiff] duplicate/invalid default link plan")
      @env.exit(2)
    }
  }
  // Run the O0 build once to capture official runtime args. The artifacts are
  // already built; this is also the green baseline check.
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  let actual = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--no-parallelize",
      "-v",
      "--target-dir",
      b0,
    ],
    work,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if actual.rc != 0 || summary_failures(actual.stdout) > 0 {
    println("[optdiff] four-cell O0 baseline is not green")
    @env.exit(2)
  }
  if cfg.target == "native" {
    let parsed_o0_links = match parse_native_link_lines(links_o0) {
      Some(l) => l
      None => {
        println("[optdiff] duplicate/invalid native O0 link plan")
        @env.exit(2)
      }
    }
    let parsed_d_links = match parse_native_link_lines(links_d) {
      Some(l) => l
      None => {
        println("[optdiff] duplicate/invalid native default link plan")
        @env.exit(2)
      }
    }
    let o0_cc = match
      parse_native_cc_lines(
        lines_of(read_text(@corpus.join(b0, "dryrun.stdout"))),
      ) {
      Some(c) => c
      None => {
        println("[optdiff] invalid native O0 cc plan")
        @env.exit(2)
      }
    }
    let d_cc = match
      parse_native_cc_lines(
        lines_of(read_text(@corpus.join(bd, "dryrun.stdout"))),
      ) {
      Some(c) => c
      None => {
        println("[optdiff] invalid native default cc plan")
        @env.exit(2)
      }
    }
    let run_lines : Array[String] = []
    for line in actual.stderr.split("\n") {
      let t = line.trim()
      if t.contains(".exe") {
        run_lines.push(t.to_owned())
      }
    }
    let run_tasks = match parse_native_runs(run_lines, b0) {
      Some(r) => r
      None => {
        println("[optdiff] cannot parse native runtime commands")
        @env.exit(2)
      }
    }
    let parsed_o0_links = match
      filter_native_links(parsed_o0_links, run_tasks, b0, pkg) {
      Some(l) => l
      None => {
        println("[optdiff] cannot classify native O0 empty artifacts")
        @env.exit(2)
      }
    }
    let parsed_d_links = match
      filter_native_links(parsed_d_links, run_tasks, bd, pkg) {
      Some(l) => l
      None => {
        println("[optdiff] cannot classify native default empty artifacts")
        @env.exit(2)
      }
    }
    if parsed_o0_links.length() != run_tasks.length() ||
      parsed_d_links.length() != run_tasks.length() {
      println("[optdiff] native link/runtime plan sizes differ")
      @env.exit(2)
    }
    let mut override_core : String? = None
    if cfg.four_control {
      if !fault_file_ok(cfg.fault_file) {
        println("[optdiff] unsafe four-cell control file")
        @env.exit(2)
      }
      let ctrl = @corpus.join(cfg.out, "four/control_module")
      let rm = @exec.run("/bin/rm", ["-rf", ctrl], "/tmp", cfg.timeout_ms)
      let cp = @exec.run(
        "/bin/cp",
        ["-a", cfg.source_dir, ctrl],
        "/tmp",
        cfg.timeout_ms,
      )
      if rm.rc != 0 || cp.rc != 0 {
        println("[optdiff] cannot prepare native control module")
        @env.exit(2)
      }
      let ctrl_path = @corpus.join(ctrl, cfg.fault_file)
      let real = @exec.run("/usr/bin/readlink", ["-f", ctrl_path], "/tmp", 5000)
      if real.rc != 0 || !real.stdout.trim().has_prefix(ctrl + "/") {
        println("[optdiff] native control file escapes copy")
        @env.exit(2)
      }
      let src = read_text(ctrl_path)
      let next = match replace_once(src, cfg.fault_from, cfg.fault_to) {
        Some(v) => v
        None => {
          println("[optdiff] native control mutation not found")
          @env.exit(2)
        }
      }
      if next == src || !write_json(ctrl_path, next) {
        println("[optdiff] native control mutation failed")
        @env.exit(2)
      }
      let ctrl_build = @corpus.join(cfg.out, "four/control_build")
      let ctrl_test = @exec.run(
        moon,
        [
          "test",
          "-p",
          pkg,
          "--target",
          cfg.target,
          "--debug",
          "--build-only",
          "--target-dir",
          ctrl_build,
        ],
        ctrl,
        cfg.timeout_ms,
        max_output_bytes=32 * 1024 * 1024,
      )
      if ctrl_test.rc != 0 {
        println("[optdiff] native control build failed")
        @env.exit(2)
      }
      let core = package_core_path(ctrl_build, cfg.target, pkg)
      if !@fs.path_exists(core) {
        println("[optdiff] native control core missing")
        @env.exit(2)
      }
      override_core = Some(core)
    }
    let arm_root = @corpus.join(base_dir, "arms")
    let evidence = @corpus.join(base_dir, "evidence")
    @corpus.ensure_dir(evidence)
    let mut artifacts = 0
    let mut errors = 0
    let mut candidates = 0
    let mut changed_total = 0
    for run in run_tasks {
      let base = artifact_stem(run.wasm_path)
      let link_o0 = match find_native_link(parsed_o0_links, base) {
        Some(l) => l
        None => {
          errors += 1
          continue
        }
      }
      let link_d = match find_native_link(parsed_d_links, base) {
        Some(l) => l
        None => {
          errors += 1
          continue
        }
      }
      let cc_o0 = match find_native_cc(o0_cc, base) {
        Some(c) => c
        None => {
          errors += 1
          continue
        }
      }
      let cc_d = match find_native_cc(d_cc, base) {
        Some(c) => c
        None => {
          errors += 1
          continue
        }
      }
      let meta = match metadata_path_at(b0, cfg.target, pkg, base + ".exe") {
        Some(path) => load_test_meta(path)
        None => None
      }
      let meta = match meta {
        Some(m) => m
        None => {
          println("[optdiff] native metadata missing for \{base}")
          errors += 1
          continue
        }
      }
      let run = if run.expected.length() == 0 {
        { ..run, expected: meta.known, }
      } else {
        run
      }
      if !subset_ids(run.expected, meta.known) {
        println("[optdiff] native metadata incomplete for \{base}")
        errors += 1
        continue
      }
      if cfg.four_control &&
        !native_link_has_core(link_o0, @corpus.basename(pkg)) {
        continue
      }
      let arm_base = @corpus.join(arm_root, base)
      @corpus.ensure_dir(arm_base)
      let core_name = @corpus.basename(pkg)
      let m00 = run_native_test_arm(
        cfg,
        work,
        run,
        link_o0,
        cc_o0,
        arm_base,
        false,
        home,
        evidence,
        "B0L0",
        None,
        core_name,
        cfg.repeats,
      )
      let m0d = run_native_test_arm(
        cfg,
        work,
        run,
        link_o0,
        cc_o0,
        arm_base,
        true,
        home,
        evidence,
        "B0Ld",
        override_core,
        core_name,
        cfg.repeats,
      )
      let md0 = run_native_test_arm(
        cfg,
        work,
        run,
        link_d,
        cc_d,
        arm_base,
        false,
        home,
        evidence,
        "BdL0",
        None,
        core_name,
        cfg.repeats,
      )
      let mdd = run_native_test_arm(
        cfg,
        work,
        run,
        link_d,
        cc_d,
        arm_base,
        true,
        home,
        evidence,
        "BdLd",
        override_core,
        core_name,
        cfg.repeats,
      )
      let (m00, m0d, md0, mdd) = match (m00, m0d, md0, mdd) {
        (Some(a), Some(b), Some(c), Some(d)) => (a, b, c, d)
        _ => {
          errors += 1
          continue
        }
      }
      if count_failures(m00, meta.panic_ids) > 0 {
        println("[optdiff] native B0L0 is not green for \{base}")
        errors += 1
        continue
      }
      let c_link = compare_results(m00, m0d, meta.panic_ids)
      let c_build = compare_results(m00, md0, meta.panic_ids)
      let c_both = compare_results(m00, mdd, meta.panic_ids)
      if cfg.four_control {
        let link_n = c_link.changed + c_link.missing + c_link.extra
        let build_n = c_build.changed + c_build.missing + c_build.extra
        let both_n = c_both.changed + c_both.missing + c_both.extra
        if link_n == 0 || build_n != 0 || both_n == 0 {
          println(
            "[optdiff] native four-cell control pattern failed for \{base}",
          )
          errors += 1
        }
      }
      let changed = c_link.changed +
        c_link.missing +
        c_link.extra +
        c_build.changed +
        c_build.missing +
        c_build.extra +
        c_both.changed +
        c_both.missing +
        c_both.extra
      let candidate = changed > 0
      if candidate {
        candidates += 1
        changed_total += changed
      }
      artifacts += 1
      let row = "{\"package\":\"" +
        @corpus.json_escape(pkg) +
        "\",\"artifact\":\"" +
        @corpus.json_escape(base) +
        "\",\"expected\":" +
        run.expected.length().to_string() +
        ",\"changed\":" +
        changed.to_string() +
        ",\"link_changed\":" +
        (c_link.changed + c_link.missing + c_link.extra).to_string() +
        ",\"build_changed\":" +
        (c_build.changed + c_build.missing + c_build.extra).to_string() +
        ",\"both_changed\":" +
        (c_both.changed + c_both.missing + c_both.extra).to_string() +
        ",\"candidate\":" +
        (if candidate { "true" } else { "false" }) +
        "}"
      if !write_json(@corpus.join(evidence, base + ".row.json"), row) {
        errors += 1
      }
    }
    if cfg.four_control && artifacts == 0 {
      println(
        "[optdiff] native four-cell control produced no eligible artifact",
      )
      errors += 1
    }
    let summary = "{\"source_module\":\"" +
      @corpus.json_escape(cfg.source_dir) +
      "\",\"package\":\"" +
      @corpus.json_escape(pkg) +
      "\",\"target\":\"" +
      @corpus.json_escape(cfg.target) +
      "\",\"mode\":\"" +
      (if cfg.four_control { "four-cell-control" } else { "four-cell" }) +
      "\",\"packages\":1,\"artifacts\":" +
      artifacts.to_string() +
      ",\"candidates\":" +
      candidates.to_string() +
      ",\"changed\":" +
      changed_total.to_string() +
      ",\"errors\":" +
      errors.to_string() +
      ",\"repeats\":" +
      cfg.repeats.to_string() +
      ",\"aa\":" +
      (if cfg.aa { "true" } else { "false" }) +
      "}"
    if !write_json(@corpus.join(base_dir, "summary.json"), summary) {
      errors += 1
    }
    println("[optdiff] \{summary}")
    return (artifacts, candidates, errors)
  }
  let runs : Array[String] = []
  for line in actual.stderr.split("\n") {
    let t = line.trim()
    if t.has_prefix("moonrun --test-args ") {
      runs.push(t.to_owned())
    }
  }
  let run_tasks = match parse_runs(runs) {
    Some(r) => r
    None => {
      println("[optdiff] cannot parse four-cell runtime commands")
      @env.exit(2)
    }
  }
  let parsed_o0_links = match
    filter_empty_link_lines(parsed_o0_links, run_tasks, b0, cfg.target, pkg) {
    Some(l) => l
    None => {
      println("[optdiff] cannot classify O0 empty/non-empty link artifacts")
      @env.exit(2)
    }
  }
  let parsed_d_links = match
    filter_empty_link_lines(parsed_d_links, run_tasks, bd, cfg.target, pkg) {
    Some(l) => l
    None => {
      println(
        "[optdiff] cannot classify default empty/non-empty link artifacts",
      )
      @env.exit(2)
    }
  }
  if parsed_o0_links.length() != run_tasks.length() ||
    parsed_d_links.length() != run_tasks.length() {
    println("[optdiff] link/runtime plan sizes differ")
    @env.exit(2)
  }
  let mut override_core : String? = None
  if cfg.four_control {
    if !fault_file_ok(cfg.fault_file) {
      println("[optdiff] unsafe four-cell control file")
      @env.exit(2)
    }
    let ctrl = @corpus.join(cfg.out, "four/control_module")
    let rm = @exec.run("/bin/rm", ["-rf", ctrl], "/tmp", cfg.timeout_ms)
    let cp = @exec.run(
      "/bin/cp",
      ["-a", cfg.source_dir, ctrl],
      "/tmp",
      cfg.timeout_ms,
    )
    if rm.rc != 0 || cp.rc != 0 {
      println("[optdiff] cannot prepare four-cell control module")
      @env.exit(2)
    }
    let ctrl_path = @corpus.join(ctrl, cfg.fault_file)
    let real = @exec.run("/usr/bin/readlink", ["-f", ctrl_path], "/tmp", 5000)
    if real.rc != 0 || !real.stdout.trim().has_prefix(ctrl + "/") {
      println("[optdiff] four-cell control file escapes copy")
      @env.exit(2)
    }
    let src = read_text(ctrl_path)
    let next = match replace_once(src, cfg.fault_from, cfg.fault_to) {
      Some(v) => v
      None => {
        println("[optdiff] four-cell control mutation not found")
        @env.exit(2)
      }
    }
    if next == src || !write_json(ctrl_path, next) {
      println("[optdiff] four-cell control mutation failed")
      @env.exit(2)
    }
    let ctrl_build = @corpus.join(cfg.out, "four/control_build")
    let ctrl_test = @exec.run(
      moon,
      [
        "test",
        "-p",
        pkg,
        "--target",
        cfg.target,
        "--debug",
        "--build-only",
        "--target-dir",
        ctrl_build,
      ],
      ctrl,
      cfg.timeout_ms,
      max_output_bytes=32 * 1024 * 1024,
    )
    if ctrl_test.rc != 0 {
      println("[optdiff] four-cell control build failed")
      @env.exit(2)
    }
    let core = package_core_path(ctrl_build, cfg.target, pkg)
    if !@fs.path_exists(core) {
      println("[optdiff] four-cell control core missing")
      @env.exit(2)
    }
    override_core = Some(core)
  }
  let arm_root = @corpus.join(base_dir, "arms")
  let evidence = @corpus.join(base_dir, "evidence")
  @corpus.ensure_dir(evidence)
  let mut artifacts = 0
  let mut errors = 0
  let mut candidates = 0
  let mut changed_total = 0
  for run in run_tasks {
    let base = @corpus.basename(run.wasm_path)
    let link_o0 = match find_link_line(parsed_o0_links, base) {
      Some(l) => l
      None => {
        errors += 1
        continue
      }
    }
    let link_d = match find_link_line(parsed_d_links, base) {
      Some(l) => l
      None => {
        errors += 1
        continue
      }
    }
    let meta = match metadata_path_at(b0, cfg.target, pkg, base) {
      Some(path) => load_test_meta(path)
      None => None
    }
    let meta = match meta {
      Some(m) => m
      None => {
        println("[optdiff] four-cell metadata missing for \{base}")
        errors += 1
        continue
      }
    }
    if !subset_ids(run.expected, meta.known) {
      println("[optdiff] four-cell metadata incomplete for \{base}")
      errors += 1
      continue
    }
    if cfg.four_control {
      let core_name = @corpus.basename(pkg)
      if !link_has_core(link_o0, core_name) || !link_has_core(link_d, core_name) {
        continue
      }
    }
    let arm_base = @corpus.join(arm_root, base)
    @corpus.ensure_dir(arm_base)
    let a0 = @corpus.join(arm_base, "B0L0.wasm")
    let ald = @corpus.join(arm_base, "B0Ld.wasm")
    let ad0 = @corpus.join(arm_base, "BdL0.wasm")
    let add = @corpus.join(arm_base, "BdLd.wasm")
    let core_name = @corpus.basename(pkg)
    let m00 = run_test_arm(
      cfg,
      work,
      run,
      link_o0,
      a0,
      false,
      home,
      evidence,
      "B0L0",
      None,
      core_name,
      cfg.repeats,
    )
    let m0d = run_test_arm(
      cfg,
      work,
      run,
      link_o0,
      ald,
      true,
      home,
      evidence,
      "B0Ld",
      override_core,
      core_name,
      cfg.repeats,
    )
    let md0 = run_test_arm(
      cfg,
      work,
      run,
      link_d,
      ad0,
      false,
      home,
      evidence,
      "BdL0",
      None,
      core_name,
      cfg.repeats,
    )
    let mdd = run_test_arm(
      cfg,
      work,
      run,
      link_d,
      add,
      true,
      home,
      evidence,
      "BdLd",
      override_core,
      core_name,
      cfg.repeats,
    )
    let (m00, m0d, md0, mdd) = match (m00, m0d, md0, mdd) {
      (Some(a), Some(b), Some(c), Some(d)) => (a, b, c, d)
      _ => {
        errors += 1
        continue
      }
    }
    if count_failures(m00, meta.panic_ids) > 0 {
      println("[optdiff] relinked B0L0 is not green for \{base}")
      errors += 1
      continue
    }
    let c_link = compare_results(m00, m0d, meta.panic_ids)
    let c_build = compare_results(m00, md0, meta.panic_ids)
    let c_both = compare_results(m00, mdd, meta.panic_ids)
    if cfg.four_control {
      let link_n = c_link.changed + c_link.missing + c_link.extra
      let build_n = c_build.changed + c_build.missing + c_build.extra
      let both_n = c_both.changed + c_both.missing + c_both.extra
      if link_n == 0 || build_n != 0 || both_n == 0 {
        println("[optdiff] four-cell control pattern failed for \{base}")
        errors += 1
      }
    }
    let changed = c_link.changed +
      c_link.missing +
      c_link.extra +
      c_build.changed +
      c_build.missing +
      c_build.extra +
      c_both.changed +
      c_both.missing +
      c_both.extra
    let candidate = changed > 0
    if candidate {
      candidates += 1
      changed_total += changed
    }
    artifacts += 1
    let row = "{\"package\":\"" +
      @corpus.json_escape(pkg) +
      "\",\"artifact\":\"" +
      @corpus.json_escape(base) +
      "\",\"expected\":" +
      run.expected.length().to_string() +
      ",\"changed\":" +
      changed.to_string() +
      ",\"link_changed\":" +
      (c_link.changed + c_link.missing + c_link.extra).to_string() +
      ",\"build_changed\":" +
      (c_build.changed + c_build.missing + c_build.extra).to_string() +
      ",\"both_changed\":" +
      (c_both.changed + c_both.missing + c_both.extra).to_string() +
      ",\"candidate\":" +
      (if candidate { "true" } else { "false" }) +
      "}"
    if !write_json(@corpus.join(evidence, base + ".row.json"), row) {
      errors += 1
    }
  }
  if cfg.four_control && artifacts == 0 {
    println("[optdiff] four-cell control produced no eligible artifact")
    errors += 1
  }
  let summary = "{\"source_module\":\"" +
    @corpus.json_escape(cfg.source_dir) +
    "\",\"package\":\"" +
    @corpus.json_escape(pkg) +
    "\",\"target\":\"" +
    @corpus.json_escape(cfg.target) +
    "\",\"mode\":\"" +
    (if cfg.four_control { "four-cell-control" } else { "four-cell" }) +
    "\",\"packages\":1,\"artifacts\":" +
    artifacts.to_string() +
    ",\"candidates\":" +
    candidates.to_string() +
    ",\"changed\":" +
    changed_total.to_string() +
    ",\"errors\":" +
    errors.to_string() +
    ",\"repeats\":" +
    cfg.repeats.to_string() +
    ",\"aa\":" +
    (if cfg.aa { "true" } else { "false" }) +
    "}"
  if !write_json(@corpus.join(base_dir, "summary.json"), summary) {
    errors += 1
  }
  println("[optdiff] \{summary}")
  (artifacts, candidates, errors)
}

///|
async fn run_four_cell(cfg : Config) -> Unit {
  if cfg.packages.length() == 0 {
    println("[optdiff] four-cell needs at least one package")
    @env.exit(2)
  }
  if cfg.four_control && cfg.packages.length() != 1 {
    println("[optdiff] four-cell-control needs exactly one package")
    @env.exit(2)
  }
  let seen_pkgs : Map[String, Unit] = Map([])
  for pkg in cfg.packages {
    if seen_pkgs.contains(pkg) {
      println("[optdiff] duplicate package in four-cell list: \{pkg}")
      @env.exit(2)
    }
    seen_pkgs.set(pkg, ())
  }
  let mut artifacts = 0
  let mut candidates = 0
  let mut errors = 0
  for pkg in cfg.packages {
    let (a, c, e) = run_four_package(cfg, pkg)
    artifacts += a
    candidates += c
    errors += e
  }
  let summary = "{\"source_module\":\"" +
    @corpus.json_escape(cfg.source_dir) +
    "\",\"mode\":\"" +
    (if cfg.four_control { "four-cell-control" } else { "four-cell" }) +
    "\",\"packages\":" +
    cfg.packages.length().to_string() +
    ",\"artifacts\":" +
    artifacts.to_string() +
    ",\"candidates\":" +
    candidates.to_string() +
    ",\"errors\":" +
    errors.to_string() +
    ",\"repeats\":" +
    cfg.repeats.to_string() +
    ",\"aa\":" +
    (if cfg.aa { "true" } else { "false" }) +
    "}"
  if !write_json(@corpus.join(cfg.out, "summary.json"), summary) {
    errors += 1
  }
  println("[optdiff] \{summary}")
  if errors > 0 {
    @env.exit(2)
  }
  if candidates > 0 {
    @env.exit(1)
  }
}

///|
/// End-to-end control for the candidate path: build a green baseline, mutate
/// one implementation file, rebuild, run the same test IDs, and require at
/// least one semantic status change.  This deliberately uses a source-level
/// change, so it validates the harness, not link optimization.
async fn run_candidate_check(cfg : Config) -> Unit {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  if cfg.packages.length() != 1 || !fault_file_ok(cfg.fault_file) {
    println("[optdiff] candidate-check requires one package and a safe file")
    @env.exit(2)
  }
  let pkg = cfg.packages[0]
  let root = @corpus.join(cfg.out, "candidate_module")
  if !root.has_prefix(cfg.out + "/") {
    println("[optdiff] unsafe candidate module path")
    @env.exit(2)
  }
  let rm = @exec.run("/bin/rm", ["-rf", root], "/tmp", cfg.timeout_ms)
  if rm.rc != 0 {
    println("[optdiff] cannot clean candidate module")
    @env.exit(2)
  }
  let cp = @exec.run(
    "/bin/cp",
    ["-a", cfg.source_dir, root],
    "/tmp",
    cfg.timeout_ms,
  )
  if cp.rc != 0 {
    println("[optdiff] cannot copy candidate module")
    @env.exit(2)
  }
  match real_path(root) {
    Some(p) =>
      if p != root {
        println("[optdiff] candidate copy is a symlink")
        @env.exit(2)
      }
    None => {
      println("[optdiff] cannot resolve candidate copy")
      @env.exit(2)
    }
  }
  let clean = @exec.run(
    "/bin/rm",
    ["-rf", @corpus.join(root, "_build")],
    "/tmp",
    cfg.timeout_ms,
  )
  if clean.rc != 0 {
    println("[optdiff] cannot clean candidate build cache")
    @env.exit(2)
  }
  cfg.module_dir = root
  if !write_manifest(cfg, home) {
    println("[optdiff] cannot write candidate manifest")
    @env.exit(2)
  }
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  let base = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--no-parallelize",
      "-v",
    ],
    root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if base.rc != 0 || summary_failures(base.stdout) > 0 {
    println("[optdiff] candidate baseline is not green")
    @env.exit(2)
  }
  let runs_a : Array[String] = []
  for line in base.stderr.split("\n") {
    let t = line.trim()
    if t.has_prefix("moonrun --test-args ") {
      runs_a.push(t.to_owned())
    }
  }
  let run_tasks = match parse_runs(runs_a) {
    Some(r) => r
    None => {
      println("[optdiff] cannot parse candidate runtime commands")
      @env.exit(2)
    }
  }
  let arts : Array[CandidateArtifact] = []
  let a_dir = @corpus.join(cfg.out, "candidate/A")
  let b_dir = @corpus.join(cfg.out, "candidate/B")
  for run in run_tasks {
    let base_name = @corpus.basename(run.wasm_path)
    let meta = match metadata_path(root, cfg.target, pkg, base_name) {
      Some(path) => load_test_meta(path)
      None => None
    }
    let meta = match meta {
      Some(m) => m
      None => {
        println("[optdiff] candidate metadata missing for \{base_name}")
        @env.exit(2)
      }
    }
    if !subset_ids(run.expected, meta.known) {
      println("[optdiff] candidate metadata incomplete for \{base_name}")
      @env.exit(2)
    }
    let a_path = @corpus.join(a_dir, base_name)
    if !copy_one(@corpus.join(root, run.wasm_path), a_path, cfg.timeout_ms) {
      println("[optdiff] cannot save candidate A artifact")
      @env.exit(2)
    }
    arts.push({ base: base_name, run, meta, })
  }
  // Mutate exactly one implementation file after A is frozen.
  let path = @corpus.join(root, cfg.fault_file)
  let real = @exec.run("/usr/bin/readlink", ["-f", path], "/tmp", 5000)
  if real.rc != 0 || !real.stdout.trim().has_prefix(root + "/") {
    println("[optdiff] candidate file escapes the copy")
    @env.exit(2)
  }
  let src = read_text(path)
  let next = match replace_once(src, cfg.fault_from, cfg.fault_to) {
    Some(v) => v
    None => {
      println("[optdiff] candidate mutation string not found")
      @env.exit(2)
    }
  }
  if next == src || !write_json(path, next) {
    println("[optdiff] candidate mutation failed")
    @env.exit(2)
  }
  for art in arts {
    let stale = @corpus.join(root, art.run.wasm_path)
    let rm = @exec.run("/bin/rm", ["-f", stale], "/tmp", cfg.timeout_ms)
    if rm.rc != 0 {
      println(
        "[optdiff] cannot remove stale candidate artifact for \{art.base}",
      )
      @env.exit(2)
    }
  }
  let mutated = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--no-parallelize",
      "-v",
    ],
    root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if mutated.timed_out {
    println("[optdiff] candidate rebuild timed out")
    @env.exit(2)
  }
  if !write_json(
      @corpus.join(cfg.out, "candidate/mutated.stdout"),
      mutated.stdout,
    ) ||
    !write_json(
      @corpus.join(cfg.out, "candidate/mutated.stderr"),
      mutated.stderr,
    ) {
    println("[optdiff] cannot save candidate evidence")
    @env.exit(2)
  }
  let mut changed = 0
  let mut errors = 0
  for art in arts {
    let b_path = @corpus.join(b_dir, art.base)
    let built = @corpus.join(root, art.run.wasm_path)
    if !@fs.path_exists(built) || !copy_one(built, b_path, cfg.timeout_ms) {
      println("[optdiff] candidate B artifact missing for \{art.base}")
      errors += 1
      continue
    }
    let ar = run_argv(
      make_run_argv(art.run, @corpus.join(a_dir, art.base)),
      root,
      cfg.timeout_ms,
      home,
    )
    let br = run_argv(
      make_run_argv(art.run, b_path),
      root,
      cfg.timeout_ms,
      home,
    )
    let a_parsed = collect_results(ar.stdout)
    let b_parsed = collect_results(br.stdout)
    if ar.rc != 0 ||
      br.rc != 0 ||
      br.timed_out ||
      ar.stdout_truncated ||
      br.stdout_truncated ||
      a_parsed.bad ||
      b_parsed.bad ||
      a_parsed.duplicate ||
      b_parsed.duplicate ||
      !exact_coverage(a_parsed.results, art.run.expected) ||
      !exact_coverage(b_parsed.results, art.run.expected) {
      errors += 1
      continue
    }
    let cmp = compare_results(
      a_parsed.results,
      b_parsed.results,
      art.meta.panic_ids,
    )
    changed += cmp.changed + cmp.missing + cmp.extra
  }
  let candidate = errors == 0 && changed > 0
  let row = "{\"stage\":\"candidate_check\",\"file\":\"" +
    @corpus.json_escape(cfg.fault_file) +
    "\",\"changed\":" +
    changed.to_string() +
    ",\"errors\":" +
    errors.to_string() +
    ",\"candidate\":" +
    (if candidate { "true" } else { "false" }) +
    "}"
  if !write_json(@corpus.join(cfg.out, "candidate.json"), row) {
    println("[optdiff] cannot write candidate verdict")
    @env.exit(2)
  }
  println("[optdiff] \{row}")
  if !candidate {
    @env.exit(2)
  }
  @env.exit(1)
}

///|
async fn run_fault(cfg : Config) -> Unit {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let pkg = if cfg.packages.length() == 1 {
    cfg.packages[0]
  } else {
    println("[optdiff] fault-check requires exactly one package")
    @env.exit(2)
  }
  if !fault_file_ok(cfg.fault_file) {
    println("[optdiff] unsafe fault file path")
    @env.exit(2)
  }
  let fault_root = @corpus.join(cfg.out, "fault_module")
  if !fault_root.has_prefix(cfg.out + "/") {
    println("[optdiff] unsafe fault root")
    @env.exit(2)
  }
  let rm = @exec.run("/bin/rm", ["-rf", fault_root], "/tmp", cfg.timeout_ms)
  if rm.rc != 0 {
    println("[optdiff] fault cleanup failed rc=\{rm.rc}")
    @env.exit(2)
  }
  let copy = @exec.run(
    "/bin/cp",
    ["-a", cfg.source_dir, fault_root],
    "/tmp",
    cfg.timeout_ms,
  )
  if copy.rc != 0 {
    println("[optdiff] fault copy failed rc=\{copy.rc}")
    @env.exit(2)
  }
  match real_path(fault_root) {
    Some(p) =>
      if p != fault_root {
        println("[optdiff] fault copy is a symlink")
        @env.exit(2)
      }
    None => {
      println("[optdiff] cannot resolve fault copy")
      @env.exit(2)
    }
  }
  cfg.module_dir = fault_root
  let clean = @exec.run(
    "/bin/rm",
    ["-rf", @corpus.join(fault_root, "_build")],
    "/tmp",
    cfg.timeout_ms,
  )
  if clean.rc != 0 {
    println("[optdiff] cannot clean fault build cache")
    @env.exit(2)
  }
  if !write_manifest(cfg, home) {
    println("[optdiff] cannot write fault manifest")
    @env.exit(2)
  }
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  let baseline = @exec.run(
    moon,
    ["test", "-p", pkg, "--target", cfg.target, "--no-parallelize", "-v"],
    fault_root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if baseline.rc != 0 || summary_failures(baseline.stdout) > 0 {
    println("[optdiff] fault baseline is not green")
    @env.exit(2)
  }
  let path = @corpus.join(fault_root, cfg.fault_file)
  let real = @exec.run("/usr/bin/readlink", ["-f", path], "/tmp", 5000)
  if real.rc != 0 || !real.stdout.trim().has_prefix(fault_root + "/") {
    println("[optdiff] fault file escapes the copied module")
    @env.exit(2)
  }
  let src = read_text(path)
  if src == "" {
    println("[optdiff] cannot read fault file")
    @env.exit(2)
  }
  let next = match replace_once(src, cfg.fault_from, cfg.fault_to) {
    Some(v) => v
    None => {
      println("[optdiff] fault string not found")
      @env.exit(2)
    }
  }
  if next == src {
    println("[optdiff] fault replacement made no change")
    @env.exit(2)
  }
  if !write_json(path, next) {
    println("[optdiff] cannot write fault file")
    @env.exit(2)
  }
  let run = @exec.run(
    moon,
    ["test", "-p", pkg, "--target", cfg.target, "--no-parallelize", "-v"],
    fault_root,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if !write_json(@corpus.join(cfg.out, "fault.stdout"), run.stdout) ||
    !write_json(@corpus.join(cfg.out, "fault.stderr"), run.stderr) {
    println("[optdiff] cannot write fault evidence")
    @env.exit(2)
  }
  let failed = summary_failures(run.stdout)
  let detected = failed > 0 && run.rc != 0
  let row = "{\"stage\":\"fault_check\",\"file\":\"" +
    @corpus.json_escape(cfg.fault_file) +
    "\",\"rc\":" +
    run.rc.to_string() +
    ",\"failed\":" +
    failed.to_string() +
    ",\"detected\":" +
    (if detected { "true" } else { "false" }) +
    "}"
  if !write_json(@corpus.join(cfg.out, "fault.json"), row) {
    println("[optdiff] cannot write fault verdict")
    @env.exit(2)
  }
  println("[optdiff] \{row}")
  if !detected {
    println("[optdiff] fault was not detected as an assertion failure")
    @env.exit(2)
  }
}

///|
fn replace_once(s : String, old : String, new : String) -> String? {
  match s.find(old) {
    Some(i) => Some(s[0:i].to_owned() + new + s[i + old.length():].to_owned())
    None => None
  }
}

///|
fn replace_output(
  argv : Array[String],
  index : Int32,
  new_path : String,
) -> Array[String] {
  replace_arg(argv, index + 1, new_path)
}

///|
fn make_link_argv(
  argv : Array[String],
  new_path : String,
  remove_o0 : Bool,
) -> Array[String]? {
  if count_arg(argv, "-o") != 1 {
    return None
  }
  let o_i = match find_arg(argv, "-o") {
    Some(i) => i
    None => return None
  }
  if o_i + 1 >= argv.length() {
    return None
  }
  if count_arg(argv, "-O0") != 1 {
    return None
  }
  let with_out = replace_output(argv, o_i, new_path)
  if !remove_o0 {
    return Some(with_out)
  }
  let o0_i = match find_arg(with_out, "-O0") {
    Some(i) => i
    None => return None
  }
  Some(remove_arg(with_out, o0_i))
}

///|
fn make_run_argv(run : RunTask, new_path : String) -> Array[String] {
  replace_arg(run.argv, run.wasm_index, new_path)
}

///|
fn metadata_path_at(
  build_root : String,
  target : String,
  pkg : String,
  base : String,
) -> String? {
  let rel = if pkg.has_prefix("moonbitlang/core/") {
    pkg[17:].to_owned()
  } else {
    pkg
  }
  let kind = if base.contains(".blackbox_test") {
    "blackbox"
  } else if base.contains(".internal_test") {
    "internal"
  } else if base.contains(".whitebox_test") {
    "whitebox"
  } else {
    return None
  }
  let dir = @corpus.join(
    @corpus.join(@corpus.join(build_root, target), "debug/test"),
    rel,
  )
  Some(@corpus.join(dir, "__" + kind + "_test_info.json"))
}

///|
fn metadata_path(
  module_dir : String,
  target : String,
  pkg : String,
  base : String,
) -> String? {
  metadata_path_at(@corpus.join(module_dir, "_build"), target, pkg, base)
}

///|
fn package_core_path(
  build_root : String,
  target : String,
  pkg : String,
) -> String {
  let rel = if pkg.has_prefix("moonbitlang/core/") {
    pkg[17:].to_owned()
  } else {
    pkg
  }
  let dir = @corpus.join(
    @corpus.join(@corpus.join(build_root, target), "debug/test"),
    rel,
  )
  @corpus.join(dir, @corpus.basename(pkg) + ".core")
}

///|
struct TestMeta {
  panic_ids : Map[String, Unit]
  known : Map[String, Unit]
}

///|
struct CandidateArtifact {
  base : String
  run : RunTask
  meta : TestMeta
}

///|
fn load_test_meta(path : String) -> TestMeta? {
  let panic_ids : Map[String, Unit] = Map([])
  let known : Map[String, Unit] = Map([])
  let text = read_text(path)
  if text == "" {
    return None
  }
  let parsed = @json.parse(text) catch { _ => return None }
  match parsed {
    Object(root) => {
      let tests = match root.get("tests") {
        Some(Object(t)) => t
        _ => return None
      }
      for file in tests.keys() {
        let items = match tests.get(file) {
          Some(Array(items)) => items
          _ => return None
        }
        for item in items {
          match item {
            Object(o) => {
              let index = match o.get("index") {
                Some(Number(n, ..)) => n.to_int()
                _ => return None
              }
              let name = match o.get("name") {
                Some(String(s)) => s
                Some(Null) => ""
                None => ""
                _ => return None
              }
              let key = file + "|" + index.to_string()
              known.set(key, ())
              if name.has_prefix("panic") {
                panic_ids.set(key, ())
              }
            }
            _ => return None
          }
        }
      }
    }
    _ => return None
  }
  Some({ panic_ids, known, })
}

///|
fn subset_ids(expected : Map[String, Unit], known : Map[String, Unit]) -> Bool {
  for k in expected.keys() {
    if !known.contains(k) {
      return false
    }
  }
  true
}

///|
async fn process_task(
  cfg : Config,
  pkg : String,
  task : LinkTask,
  home : String,
  evidence : String,
) -> (Bool, Bool, Int32) {
  // (candidate, error, changed_count)
  let pkg_tag = package_tag(pkg)
  let a_dir = @corpus.join(@corpus.join(cfg.out, "link/O0"), pkg_tag)
  let b_dir = @corpus.join(@corpus.join(cfg.out, "link/default"), pkg_tag)
  let a_path = @corpus.join(a_dir, task.base)
  let b_path = @corpus.join(b_dir, task.base)
  @corpus.ensure_dir(a_dir)
  @corpus.ensure_dir(b_dir)
  let a_cmd = match make_link_argv(task.argv, a_path, false) {
    Some(a) => a
    None => {
      println("[optdiff] cannot form O0 link argv for \{task.base}")
      return (false, true, 0)
    }
  }
  let b_cmd = match make_link_argv(task.argv, b_path, !cfg.aa) {
    Some(a) => a
    None => {
      println("[optdiff] cannot form default link argv for \{task.base}")
      return (false, true, 0)
    }
  }
  let a_run = make_run_argv(task.run, a_path)
  let b_run = make_run_argv(task.run, b_path)
  let a_link = run_argv(a_cmd, cfg.module_dir, cfg.timeout_ms, home)
  let b_link = run_argv(b_cmd, cfg.module_dir, cfg.timeout_ms, home)
  if !write_json(
      @corpus.join(evidence, task.base + ".O0.link"),
      join_argv(a_cmd),
    ) ||
    !write_json(
      @corpus.join(evidence, task.base + ".default.link"),
      join_argv(b_cmd),
    ) {
    println("[optdiff] cannot write link plan for \{task.base}")
    return (false, true, 0)
  }
  if a_link.rc != 0 || b_link.rc != 0 {
    println(
      "[optdiff] link failed for \{task.base}: O0=\{a_link.rc} default=\{b_link.rc}",
    )
    ignore(
      write_json(
        @corpus.join(evidence, task.base + ".O0.link.stderr"),
        a_link.stderr,
      ),
    )
    ignore(
      write_json(
        @corpus.join(evidence, task.base + ".default.link.stderr"),
        b_link.stderr,
      ),
    )
    return (false, true, 0)
  }
  let mut a_results : Map[String, String] = Map([])
  let mut b_results : Map[String, String] = Map([])
  let mut a_rc = 0
  let mut b_rc = 0
  let mut unstable = false
  let mut error = false
  let mut changed = 0
  let mut i = 0
  while i < cfg.repeats {
    let ar = run_argv(a_run, cfg.module_dir, cfg.timeout_ms, home)
    let br = run_argv(b_run, cfg.module_dir, cfg.timeout_ms, home)
    let a_parsed = collect_results(ar.stdout)
    let b_parsed = collect_results(br.stdout)
    if !write_json(
        @corpus.join(evidence, task.base + ".O0." + i.to_string() + ".stdout"),
        ar.stdout,
      ) ||
      !write_json(
        @corpus.join(evidence, task.base + ".O0." + i.to_string() + ".stderr"),
        ar.stderr,
      ) ||
      !write_json(
        @corpus.join(
          evidence,
          task.base + ".default." + i.to_string() + ".stdout",
        ),
        br.stdout,
      ) ||
      !write_json(
        @corpus.join(
          evidence,
          task.base + ".default." + i.to_string() + ".stderr",
        ),
        br.stderr,
      ) {
      error = true
    }
    if a_parsed.bad ||
      b_parsed.bad ||
      a_parsed.duplicate ||
      b_parsed.duplicate ||
      ar.timed_out ||
      br.timed_out ||
      ar.rc != 0 ||
      br.rc != 0 ||
      ar.stdout_truncated ||
      br.stdout_truncated ||
      !exact_coverage(a_parsed.results, task.run.expected) ||
      !exact_coverage(b_parsed.results, task.run.expected) {
      error = true
    }
    if i == 0 {
      a_results = a_parsed.results
      b_results = b_parsed.results
      a_rc = ar.rc
      b_rc = br.rc
    } else {
      let ac = compare_results(a_results, a_parsed.results, task.panic_ids)
      let bc = compare_results(b_results, b_parsed.results, task.panic_ids)
      if ac.changed > 0 ||
        ac.missing > 0 ||
        ac.extra > 0 ||
        bc.changed > 0 ||
        bc.missing > 0 ||
        bc.extra > 0 ||
        ar.rc != a_rc ||
        br.rc != b_rc {
        unstable = true
      }
    }
    i += 1
  }
  let cmp = compare_results(a_results, b_results, task.panic_ids)
  if unstable {
    println("[optdiff] unstable repeated result for \{task.base}")
    error = true
  }
  let has_diff = cmp.changed > 0 || cmp.missing > 0 || cmp.extra > 0
  if cfg.aa && has_diff {
    println("[optdiff] A/A control produced a difference for \{task.base}")
    error = true
  }
  let candidate = !error && !cfg.aa && has_diff
  if candidate {
    changed += cmp.changed + cmp.missing + cmp.extra
  }
  let a_fail = count_failures(a_results, task.panic_ids)
  let b_fail = count_failures(b_results, task.panic_ids)
  let row = "{\"package\":\"" +
    @corpus.json_escape(pkg) +
    "\",\"artifact\":\"" +
    @corpus.json_escape(task.base) +
    "\",\"o0_rc\":" +
    a_rc.to_string() +
    ",\"default_rc\":" +
    b_rc.to_string() +
    ",\"expected\":" +
    task.run.expected.length().to_string() +
    ",\"o0_total\":" +
    a_results.length().to_string() +
    ",\"default_total\":" +
    b_results.length().to_string() +
    ",\"o0_failed\":" +
    a_fail.to_string() +
    ",\"default_failed\":" +
    b_fail.to_string() +
    ",\"changed\":" +
    cmp.changed.to_string() +
    ",\"missing\":" +
    cmp.missing.to_string() +
    ",\"extra\":" +
    cmp.extra.to_string() +
    ",\"repeats\":" +
    cfg.repeats.to_string() +
    ",\"unstable\":" +
    (if unstable { "true" } else { "false" }) +
    ",\"aa\":" +
    (if cfg.aa { "true" } else { "false" }) +
    ",\"candidate\":" +
    (if candidate { "true" } else { "false" }) +
    "}"
  if !write_json(@corpus.join(evidence, task.base + ".row.json"), row) {
    error = true
  }
  (candidate, error, changed)
}

///|
async fn process_package(
  cfg : Config,
  pkg : String,
  home : String,
) -> (Int32, Int32, Int32, Int32) {
  // (artifacts, candidates, changed, errors)
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  let pkg_tag = package_tag(pkg)
  let plan_dir = @corpus.join(@corpus.join(cfg.out, "plan"), pkg_tag)
  let evidence = @corpus.join(@corpus.join(cfg.out, "evidence"), pkg_tag)
  @corpus.ensure_dir(plan_dir)
  @corpus.ensure_dir(evidence)
  println("[optdiff] package \{pkg}")

  let base = @exec.run(
    moon,
    [
      "test",
      "-p",
      pkg,
      "--target",
      cfg.target,
      "--debug",
      "--no-parallelize",
      "-v",
    ],
    cfg.module_dir,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if !write_json(@corpus.join(plan_dir, "base.stdout"), base.stdout) ||
    !write_json(@corpus.join(plan_dir, "base.stderr"), base.stderr) {
    println("[optdiff] cannot write baseline evidence for \{pkg}")
    return (0, 0, 0, 1)
  }
  if base.rc != 0 || summary_failures(base.stdout) > 0 {
    println(
      "[optdiff] baseline test build failed for \{pkg}; refusing to compare",
    )
    return (0, 0, 0, 1)
  }

  let dry = @exec.run(
    moon,
    ["test", "-p", pkg, "--target", cfg.target, "--debug", "--dry-run", "-v"],
    cfg.module_dir,
    cfg.timeout_ms,
    max_output_bytes=32 * 1024 * 1024,
  )
  if !write_json(@corpus.join(plan_dir, "dryrun.stdout"), dry.stdout) ||
    !write_json(@corpus.join(plan_dir, "dryrun.stderr"), dry.stderr) {
    println("[optdiff] cannot write dry-run evidence for \{pkg}")
    return (0, 0, 0, 1)
  }
  if dry.rc != 0 {
    println("[optdiff] dry-run failed for \{pkg}; refusing to compare")
    return (0, 0, 0, 1)
  }

  let links : Array[String] = []
  for line in dry.stdout.split("\n") {
    let t = line.trim()
    if t.has_prefix("moonc link-core ") {
      links.push(t.to_owned())
    }
  }
  let runs : Array[String] = []
  for line in base.stderr.split("\n") {
    let t = line.trim()
    if t.has_prefix("moonrun --test-args ") {
      runs.push(t.to_owned())
    }
  }
  if links.length() == 0 || runs.length() == 0 {
    println("[optdiff] incomplete test plan for \{pkg}")
    return (0, 0, 0, 1)
  }
  let run_tasks = match parse_runs(runs) {
    Some(r) => r
    None => {
      println("[optdiff] cannot parse test runtime commands for \{pkg}")
      return (0, 0, 0, 1)
    }
  }
  let link_tasks = match parse_links(links, run_tasks) {
    Some(t) => t
    None => {
      println("[optdiff] cannot pair link and runtime commands for \{pkg}")
      return (0, 0, 0, 1)
    }
  }
  let mut artifacts = 0
  let mut candidates = 0
  let mut changed = 0
  let mut errors = 0
  for task in link_tasks {
    let meta_path = metadata_path(cfg.module_dir, cfg.target, pkg, task.base)
    let meta = match meta_path {
      Some(path) => {
        let m = load_test_meta(path)
        if m is None {
          println("[optdiff] metadata parse failed at \{path}")
        }
        m
      }
      None => None
    }
    let meta = match meta {
      Some(m) => m
      None => {
        println("[optdiff] missing/unreadable test metadata for \{task.base}")
        errors += 1
        continue
      }
    }
    if !subset_ids(task.run.expected, meta.known) {
      println(
        "[optdiff] metadata does not explain every requested test for \{task.base}",
      )
      errors += 1
      continue
    }
    let task = { ..task, panic_ids: meta.panic_ids, }
    let (cand, err, delta) = process_task(cfg, pkg, task, home, evidence)
    artifacts += 1
    if cand {
      candidates += 1
      changed += delta
    }
    if err {
      errors += 1
    }
  }
  println(
    "[optdiff] \{pkg}: artifacts=\{artifacts} candidates=\{candidates} changed=\{changed} errors=\{errors}",
  )
  (artifacts, candidates, changed, errors)
}

///|
async fn write_manifest_to(cfg : Config, home : String, path : String) -> Bool {
  let moon = @corpus.join(@corpus.join(home, ".moon/bin"), "moon")
  let moonc = @corpus.join(@corpus.join(home, ".moon/bin"), "moonc")
  let moon_v = @exec.run(moon, ["version"], "/tmp", 10000)
  let moonc_v = @exec.run(moonc, ["-v"], "/tmp", 10000)
  let mod_text = read_text(@corpus.join(cfg.module_dir, "moon.mod"))
  let manifest = "{\"source_module\":\"" +
    @corpus.json_escape(cfg.source_dir) +
    "\",\"work_module\":\"" +
    @corpus.json_escape(cfg.module_dir) +
    "\",\"out\":\"" +
    @corpus.json_escape(cfg.out) +
    "\",\"target\":\"" +
    @corpus.json_escape(cfg.target) +
    "\",\"repeats\":" +
    cfg.repeats.to_string() +
    ",\"aa\":" +
    (if cfg.aa { "true" } else { "false" }) +
    ",\"moon\":\"" +
    @corpus.json_escape(moon) +
    "\",\"moonc\":\"" +
    @corpus.json_escape(moonc) +
    "\",\"moon_version\":\"" +
    @corpus.json_escape((moon_v.stdout + moon_v.stderr).trim().to_owned()) +
    "\",\"moonc_version\":\"" +
    @corpus.json_escape((moonc_v.stdout + moonc_v.stderr).trim().to_owned()) +
    "\",\"moon_mod_sha1\":\"" +
    @corpus.sha1_hex(mod_text) +
    "\"}"
  write_json(path, manifest)
}

///|
async fn write_manifest(cfg : Config, home : String) -> Bool {
  write_manifest_to(cfg, home, @corpus.join(cfg.out, "manifest.json"))
}

///|
async fn main {
  let args = @env.args()
  let cfg : Config = {
    source_dir: "",
    module_dir: "",
    out: "",
    packages: ["moonbitlang/core/argparse"],
    target: "wasm-gc",
    llvm_opt: "",
    timeout_ms: 300000,
    repeats: 1,
    aa: false,
    four_cell: false,
    four_control: false,
    candidate: false,
    fault_file: "",
    fault_from: "",
    fault_to: "",
  }
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--module" && i + 1 < args.length() {
      cfg.source_dir = args[i + 1]
      cfg.module_dir = args[i + 1]
      i += 2
    } else if a == "--out" && i + 1 < args.length() {
      cfg.out = args[i + 1]
      i += 2
    } else if a == "--packages" && i + 1 < args.length() {
      cfg.packages = parse_packages(args[i + 1])
      i += 2
    } else if a == "--target" && i + 1 < args.length() {
      cfg.target = args[i + 1]
      i += 2
    } else if a == "--llvm-opt" && i + 1 < args.length() {
      cfg.llvm_opt = args[i + 1]
      i += 2
    } else if a == "--timeout" && i + 1 < args.length() {
      cfg.timeout_ms = parse_int(args[i + 1], cfg.timeout_ms)
      i += 2
    } else if a == "--repeats" && i + 1 < args.length() {
      cfg.repeats = parse_int(args[i + 1], cfg.repeats)
      i += 2
    } else if a == "--aa" {
      cfg.aa = true
      i += 1
    } else if a == "--four-cell" {
      cfg.four_cell = true
      i += 1
    } else if a == "--four-cell-control" && i + 3 < args.length() {
      cfg.four_cell = true
      cfg.four_control = true
      cfg.fault_file = args[i + 1]
      cfg.fault_from = args[i + 2]
      cfg.fault_to = args[i + 3]
      i += 4
    } else if a == "--candidate-check" && i + 3 < args.length() {
      cfg.candidate = true
      cfg.fault_file = args[i + 1]
      cfg.fault_from = args[i + 2]
      cfg.fault_to = args[i + 3]
      i += 4
    } else if a == "--fault-check" && i + 3 < args.length() {
      cfg.fault_file = args[i + 1]
      cfg.fault_from = args[i + 2]
      cfg.fault_to = args[i + 3]
      i += 4
    } else {
      usage()
      @env.exit(2)
    }
  }
  if cfg.module_dir == "" || !is_abs(cfg.module_dir) {
    println("[optdiff] --module must be an absolute path")
    @env.exit(2)
  }
  if cfg.out == "" {
    cfg.out = @corpus.join("/tmp/mbtfuzz_optdiff", @env.now().to_string())
  }
  if !is_abs(cfg.out) {
    println("[optdiff] --out must be an absolute path")
    @env.exit(2)
  }
  @corpus.ensure_dir(cfg.out)
  cfg.out = match real_path(cfg.out) {
    Some(p) => p
    None => {
      println("[optdiff] cannot resolve --out")
      @env.exit(2)
    }
  }
  let resolved = match real_path(cfg.source_dir) {
    Some(p) => p
    None => {
      println("[optdiff] cannot resolve --module")
      @env.exit(2)
    }
  }
  cfg.source_dir = resolved
  if path_within(cfg.source_dir, cfg.out) ||
    path_within(cfg.out, cfg.source_dir) {
    println("[optdiff] --module and --out must not contain each other")
    @env.exit(2)
  }
  if cfg.repeats < 1 {
    println("[optdiff] --repeats must be >= 1")
    @env.exit(2)
  }
  if cfg.llvm_opt != "" {
    if cfg.target != "native" {
      println("[optdiff] --llvm-opt requires --target native")
      @env.exit(2)
    }
    let n = parse_int(cfg.llvm_opt, -1)
    if n < 0 || n > 3 {
      println("[optdiff] --llvm-opt must be 0..3")
      @env.exit(2)
    }
  }
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  if cfg.candidate {
    run_candidate_check(cfg)
    return
  }
  if cfg.four_cell {
    if cfg.aa && cfg.repeats < 2 {
      println("[optdiff] four-cell --aa needs --repeats >= 2")
      @env.exit(2)
    }
    run_four_cell(cfg)
    return
  }
  if cfg.fault_file != "" {
    run_fault(cfg)
    return
  }
  let work = @corpus.join(cfg.out, "module")
  if !work.has_prefix(cfg.out + "/") {
    println("[optdiff] unsafe work module path")
    @env.exit(2)
  }
  let rm = @exec.run("/bin/rm", ["-rf", work], "/tmp", cfg.timeout_ms)
  if rm.rc != 0 {
    println("[optdiff] cannot clean work module")
    @env.exit(2)
  }
  let cp = @exec.run(
    "/bin/cp",
    ["-a", cfg.source_dir, work],
    "/tmp",
    cfg.timeout_ms,
  )
  if cp.rc != 0 {
    println("[optdiff] cannot copy module to work area")
    @env.exit(2)
  }
  match real_path(work) {
    Some(p) =>
      if p != work {
        println("[optdiff] work module is a symlink")
        @env.exit(2)
      }
    None => {
      println("[optdiff] cannot resolve work module")
      @env.exit(2)
    }
  }
  let clean = @exec.run(
    "/bin/rm",
    ["-rf", @corpus.join(work, "_build")],
    "/tmp",
    cfg.timeout_ms,
  )
  if clean.rc != 0 {
    println("[optdiff] cannot clean copied build cache")
    @env.exit(2)
  }
  cfg.module_dir = work
  if !write_manifest(cfg, home) {
    println("[optdiff] cannot write manifest")
    @env.exit(2)
  }
  if cfg.packages.length() == 0 {
    println("[optdiff] no packages selected")
    @env.exit(2)
  }
  if cfg.target != "wasm" && cfg.target != "wasm-gc" {
    println("[optdiff] link-only currently supports wasm/wasm-gc only")
    @env.exit(2)
  }
  println(
    "[optdiff] module=\{cfg.module_dir} out=\{cfg.out} target=\{cfg.target} packages=\{cfg.packages.length()}",
  )
  let mut artifacts = 0
  let mut candidates = 0
  let mut changed = 0
  let mut errors = 0
  for pkg in cfg.packages {
    let (a, c, d, e) = process_package(cfg, pkg, home)
    artifacts += a
    candidates += c
    changed += d
    errors += e
  }
  if cfg.four_control && artifacts == 0 {
    println("[optdiff] four-cell control produced no eligible artifact")
    errors += 1
  }
  let summary = "{\"source_module\":\"" +
    @corpus.json_escape(cfg.source_dir) +
    "\",\"module\":\"" +
    @corpus.json_escape(cfg.module_dir) +
    "\",\"target\":\"" +
    @corpus.json_escape(cfg.target) +
    "\",\"mode\":\"" +
    (if cfg.aa { "link-only-aa" } else { "link-only" }) +
    "\",\"packages\":" +
    cfg.packages.length().to_string() +
    ",\"artifacts\":" +
    artifacts.to_string() +
    ",\"candidates\":" +
    candidates.to_string() +
    ",\"changed\":" +
    changed.to_string() +
    ",\"errors\":" +
    errors.to_string() +
    ",\"repeats\":" +
    cfg.repeats.to_string() +
    "}"
  if !write_json(@corpus.join(cfg.out, "summary.json"), summary) {
    errors += 1
  }
  println("[optdiff] done \{summary}")
  if errors > 0 {
    @env.exit(2)
  }
  if candidates > 0 {
    @env.exit(1)
  }
}
