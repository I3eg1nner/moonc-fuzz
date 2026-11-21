///|
/// The staging layer every driver shares.
///
/// Two rules hold this package together:
///
/// 1. "Same defect" means the same `judge` signature, digits normalised.  The
///    reducer, the campaign and the seed fuzzer must agree or a candidate can
///    be accepted by one and rejected by another.
/// 2. A *defect* is a finding with severity `Defect`.  A syntax error is a
///    failed experiment, not a finding; without this filter a byte mutator
///    produces thousands of "new signatures" that are all parse errors.

///|
pub fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
pub fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
pub fn write_text(path : String, text : String) -> Bool {
  try {
    @fs.write_string_to_file(path, text)
    true
  } catch {
    _ => false
  }
}

///|
pub fn path_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
pub fn try_read_dir(path : String) -> Array[String] {
  let out : Array[String] = []
  let names = @fs.read_dir(path) catch { _ => return out }
  for n in names {
    out.push(n)
  }
  out
}

///|
pub fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let is_dir_here = @fs.is_dir(path) catch { _ => false }
  if is_dir_here {
    for name in try_read_dir(path) {
      rm_rf(join(path, name))
    }
    let _ = try {
      @fs.remove_dir(path)
      true
    } catch {
      _ => false
    }
  } else {
    let _ = try {
      @fs.remove_file(path)
      true
    } catch {
      _ => false
    }
  }
}

///|
pub fn copy_tree(src : String, dst : String) -> Bool {
  let made = try {
    @fs.create_dir(dst)
    true
  } catch {
    _ => false
  }
  if !made && !@fs.path_exists(dst) {
    return false
  }
  let mut ok = true
  for name in try_read_dir(src) {
    if ok {
      let sp = join(src, name)
      let dp = join(dst, name)
      let is_dir_here = @fs.is_dir(sp) catch { _ => false }
      if is_dir_here {
        if !copy_tree(sp, dp) {
          ok = false
        }
      } else {
        let wrote = try {
          let bytes = @fs.read_file_to_bytes(sp)
          @fs.write_bytes_to_file(dp, bytes)
          true
        } catch {
          _ => false
        }
        if !wrote {
          ok = false
        }
      }
    }
  }
  ok
}

///|
pub fn moon_path() -> String {
  match @env.get_env_var("MOON") {
    Some(p) => if p == "" { tool_path("moon") } else { p }
    None => tool_path("moon")
  }
}

///|
/// `MOON_HOME` first, `~/.moon` second.  A restored toolchain archive sets
/// `MOON_HOME`; ignoring it made every driver rebuild against whatever happened
/// to be in the user's home directory - which is exactly what a frozen
/// toolchain is supposed to stop depending on.
pub fn moon_home() -> String {
  match @env.get_env_var("MOON_HOME") {
    Some(h) => if h == "" { default_moon_home() } else { h }
    None => default_moon_home()
  }
}

///|
pub fn tool_path(name : String) -> String {
  join(join(moon_home(), "bin"), name)
}

///|
fn default_moon_home() -> String {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  join(home, ".moon")
}

///|
/// `check` / `build` / `test --build-only`.
pub fn stage_args(stage : String, target : String) -> Array[String] {
  let args : Array[String] = [stage, "--target", target]
  if stage == "test" {
    args.push("--build-only")
  }
  args
}

///|
pub async fn run_stage(
  stage : String,
  target : String,
  dir : String,
  timeout_ms : Int32,
) -> @exec.RunResult {
  @exec.run_isolated(
    moon_path(),
    stage_args(stage, target),
    dir,
    timeout_ms,
    max_output_bytes=65536,
  )
}

///|

///|
/// `harness/all_pkgs.json` is generated on one machine and embeds absolute
/// paths for both this repository and the toolchain's core bundle.  Rewriting
/// them is what lets any driver run from another checkout or against a
/// restored toolchain (`MOON_HOME`) without regenerating the file.
pub fn portable_all_pkgs(root : String) -> String {
  let path = join(join(root, "harness"), "all_pkgs.json")
  let src = read_text(path)
  if src == "" {
    return path
  }
  // Two statements, not a chain: pinned and latest formatters wrap a chained
  // call differently, and an unnecessary formatting difference turns CI red.
  let rooted = src.replace_all(old="/data/audit/mbtfuzz", new=root)
  let out = rooted.replace_all(old="/home/user/.moon", new=moon_home())
  let tmp = "/tmp/mbtfuzz_all_pkgs_" + @env.now().to_string() + ".json"
  if write_text(tmp, out) {
    tmp
  } else {
    path
  }
}

///|
/// Collapse digit runs and whitespace.  Link-time ICE text embeds temp paths,
/// hashes and byte counts; an exact compare would make every candidate look
/// different and reduction would silently do nothing.
pub fn normalize(s : String) -> String {
  let b = StringBuilder()
  let mut in_digits = false
  let mut in_space = false
  for c in s {
    let is_digit = c >= '0' && c <= '9'
    let is_space = c == ' ' || c == '\t'
    if is_digit {
      if !in_digits {
        b.write_char('#')
      }
      in_digits = true
      in_space = false
    } else if is_space {
      if !in_space {
        b.write_char(' ')
      }
      in_space = true
      in_digits = false
    } else {
      b.write_char(c)
      in_digits = false
      in_space = false
    }
  }
  let t = b.to_string().trim().to_owned()
  if t.char_length() > 180 {
    t[0:180].to_owned()
  } else {
    t
  }
}

///|
pub fn observation_of(
  stage : String,
  r : @exec.RunResult,
) -> @judge.Observation {
  @judge.observation(
    stage,
    r.rc,
    r.timed_out,
    r.ms,
    // This adapter has no child CPU accounting (RunResult carries wall time
    // only).  Reporting r.ms as cpu_ms made every timeout satisfy
    // cpu*2 >= wall and be classified BusyHang; unknown CPU must instead fall
    // through to timeout_plain.
    0L,
    0,
    false,
    false,
    r.stdout,
    r.stderr,
  )
}

///|
/// All findings for one run, defect severities first by registry order.
pub fn findings(stage : String, r : @exec.RunResult) -> Array[@judge.Finding] {
  @judge.check_all(@judge.registry(), observation_of(stage, r))
}

///|
/// True if the run produced at least one product-defect finding.  A parse or
/// type error is not one: it means the experiment was invalid.
pub fn is_defect(stage : String, r : @exec.RunResult) -> Bool {
  for f in findings(stage, r) {
    if @judge.severity_name(f.severity) == "defect" {
      return true
    }
  }
  false
}

///|
/// Defect signature of one staged run.
pub fn signature(stage : String, r : @exec.RunResult) -> String {
  let parts : Array[String] = []
  for f in findings(stage, r) {
    parts.push(f.signature)
  }
  let raw = if parts.length() > 0 {
    let b = StringBuilder()
    for i, p in parts {
      if i > 0 {
        b.write_string(";")
      }
      b.write_string(p)
    }
    b.to_string()
  } else if r.timed_out {
    "timeout"
  } else if r.rc != 0 {
    "fail/rc=" + r.rc.to_string()
  } else {
    "ok"
  }
  normalize(raw)
}

///|
pub fn count_lines(text : String) -> Int32 {
  let mut n = 0
  for line in text.split("\n") {
    if line.char_length() > 0 {
      n += 1
    }
  }
  n
}

///|
pub fn parse_int(s : String, dflt : Int32) -> Int32 {
  let mut v = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - 48)
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
pub fn escape(s : String) -> String {
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
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// Copy a package for mutation, skipping build output.  A PoC directory with
/// `_build/` in it is hundreds of megabytes; copying it per mutant would make
/// the campaign IO-bound.
pub fn copy_pkg(src : String, dst : String) -> Bool {
  let made = try {
    @fs.create_dir(dst)
    true
  } catch {
    _ => false
  }
  if !made && !@fs.path_exists(dst) {
    return false
  }
  let mut ok = true
  for name in try_read_dir(src) {
    if ok && name != "_build" && name != ".git" && name != ".mooncakes" {
      let sp = join(src, name)
      let dp = join(dst, name)
      let is_dir_here = @fs.is_dir(sp) catch { _ => false }
      if is_dir_here {
        if !copy_pkg(sp, dp) {
          ok = false
        }
      } else {
        let wrote = try {
          @fs.write_bytes_to_file(dp, @fs.read_file_to_bytes(sp))
          true
        } catch {
          _ => false
        }
        if !wrote {
          ok = false
        }
      }
    }
  }
  ok
}

///|
/// All `.mbt` files under `dir`, relative paths, `_build` excluded.
pub fn mbt_files(dir : String) -> Array[String] {
  let out : Array[String] = []
  collect_mbt(dir, "", out)
  out
}

///|
fn collect_mbt(dir : String, prefix : String, out : Array[String]) -> Unit {
  for name in try_read_dir(dir) {
    if name != "_build" && name != ".git" && name != ".mooncakes" {
      let path = join(dir, name)
      let rel = if prefix == "" { name } else { prefix + "/" + name }
      let is_dir_here = @fs.is_dir(path) catch { _ => false }
      if is_dir_here {
        collect_mbt(path, rel, out)
      } else if name.has_suffix(".mbt") {
        out.push(rel)
      }
    }
  }
}
