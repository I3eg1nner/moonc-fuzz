///|
/// Filesystem helpers for the fuzz driver.  The Python harness used
/// `os.walk` + `os.path.getsize`; the same policy is kept here: skip build
/// products and only keep small source-like files.
///
/// All functions are synchronous except where noted; this package is pure
/// bookkeeping and does not spawn children.

///|
pub fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[0:i].to_owned()
    None => "."
  }
}

///|
pub fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
pub fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn path_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
/// Recursive mkdir, because the native `x/fs` backend only creates one level.
pub fn ensure_dir(path : String) -> Unit {
  if path == "" || path == "." || path == "/" || path_exists(path) {
    return
  }
  let parent = dirname(path)
  if parent != path {
    ensure_dir(parent)
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// SHA-1 is used because the original harness used SHA-1 for signatures;
/// this keeps old finding directories comparable.  It is not a security use.
pub fn sha1_hex(s : String) -> String {
  let digest = @crypto.sha1(@utf8.encode(s))
  @crypto.bytes_to_hex_string(digest)
}

///|
pub fn short_hash(s : String) -> String {
  let h = sha1_hex(s)
  match h[0:16].to_owned() {
    v => v
  }
}

///|
fn should_skip_dir(name : String) -> Bool {
  name == "_build" ||
  name == ".git" ||
  name == ".mooncakes" ||
  name == "__pycache__" ||
  name == "target" ||
  name == "node_modules"
}

///|
/// Recursively collect files under `root` whose name ends with one of
/// `suffixes` and whose content is non-empty and below `max_bytes`.
/// Results are sorted so a run is reproducible.
pub fn collect_files(
  root : String,
  suffixes : Array[String],
  max_bytes : Int32,
  limit : Int32,
) -> Array[String] {
  let out : Array[String] = []
  let stack : Array[String] = [root]
  while stack.length() > 0 {
    let d = stack.pop().unwrap()
    let names = @fs.read_dir(d) catch { _ => [] }
    for n in names {
      let p = join(d, n)
      let isdir = @fs.is_dir(p) catch { _ => false }
      if isdir {
        if !should_skip_dir(n) {
          stack.push(p)
        }
      } else {
        let mut want = false
        for s in suffixes {
          if n.has_suffix(s) {
            want = true
          }
        }
        if want {
          let data = @fs.read_file_to_string(p) catch { _ => "" }
          if data.length() > 0 && data.length() <= max_bytes {
            out.push(p)
          }
        }
      }
    }
  }
  out.sort()
  if limit > 0 && out.length() > limit {
    // Evenly spaced sample, same spirit as cov.py's list_inputs.
    let sampled : Array[String] = []
    let step = out.length().to_double() / limit.to_double()
    for i in 0..<limit {
      sampled.push(out[(i.to_double() * step).to_int()])
    }
    sampled
  } else {
    out
  }
}

///|
/// Load source texts from one or more roots, deduplicated by content.
pub fn load_texts(
  roots : Array[String],
  suffixes : Array[String],
  max_bytes : Int32,
  limit : Int32,
) -> Array[String] {
  let files : Array[String] = []
  for r in roots {
    for p in collect_files(r, suffixes, max_bytes, 0) {
      files.push(p)
    }
  }
  files.sort()
  let seen : Map[String, Unit] = Map([])
  let texts : Array[String] = []
  for p in files {
    let t = @fs.read_file_to_string(p) catch { _ => "" }
    if t.length() == 0 {
      continue
    }
    let h = sha1_hex(t)
    if !seen.contains(h) {
      seen.set(h, ())
      texts.push(t)
      if limit > 0 && texts.length() >= limit {
        break
      }
    }
  }
  texts
}

///|
/// Atomically-ish persist one crash: directory name is the signature, so
/// concurrent workers converge on the same path.  Returns true only for the
/// worker that created the case file first.
pub fn save_finding(
  out_root : String,
  stage : String,
  kind : String,
  sig : String,
  src : String,
  meta : String,
  fname : String,
) -> Bool {
  let d = join(join(join(out_root, "findings"), stage), kind) + "/" + sig
  ensure_dir(d)
  let case = join(d, fname)
  if path_exists(case) {
    return false
  }
  // Write case first, then meta, so a concurrent reader never sees a
  // half-populated directory with meta but no input.
  @fs.write_string_to_file(case, src) catch {
    _ => return false
  }
  @fs.write_string_to_file(join(d, "meta.json"), meta) catch {
    _ => ()
  }
  true
}

///|
pub fn append_line(path : String, line : String) -> Unit {
  ensure_dir(dirname(path))
  let old = @fs.read_file_to_string(path) catch { _ => "" }
  @fs.write_string_to_file(path, old + line + "\n") catch {
    _ => ()
  }
}

///|
/// Minimal JSON string escaper for evidence metadata.  Keeps the original
/// stdout/stderr traceable without relying on a JSON dependency at every call.
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
      b.write_string("\\u")
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
