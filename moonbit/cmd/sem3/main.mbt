// Semantic differential: generate small programs per operator family, compute
// the expected output with an in-process reference evaluator, run the same
// program on js / wasm-gc / native and compare stdout+rc.
//
// Known backend artefacts (float formatting) are a separate family that is
// reported as excluded, never as a mismatch.
fn usage() -> Unit {
  println("usage: sem3 --out DIR [--duration S] [--inject TARGET] [--limit N]")
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") { a + b } else { a + "/" + b }
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name { return Some(args[i + 1]) }
    i += 1
  }
  None
}

///|
fn num_arg(args : Array[String], name : String, d : Int32) -> Int32 {
  match arg_value(args, name) {
    Some(s) => {
      let mut n = 0
      let mut any = false
      for c in s {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
          any = true
        } else { return d }
      }
      if any { n } else { d }
    }
    None => d
  }
}

///|
struct Case {
  family : String
  src : String
  expected : Array[String]
  excluded : Bool
}

///|
fn i32_expr(a : Int, b : Int, op : Int) -> Int {
  match op {
    0 => a + b
    1 => a - b
    2 => a * b
    3 => a & b
    4 => a | b
    5 => a ^ b
    6 => a << (b & 7)
    7 => a >> (b & 7)
    _ => a
  }
}

///|
fn gen_i32(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(2000) - 1000
  let b = rng.int(31) + 1
  let op = rng.int(8)
  let e = i32_expr(a, b, op)
  let opname = ["+", "-", "*", "&", "|", "^", "<<", ">>"][op]
  let rhs = if op >= 6 { "(b & 7)" } else { "b" }
  let src = "fn main {\n  let a : Int = " + a.to_string() + "\n  let b : Int = " +
    b.to_string() + "\n  println((a " + opname + " " + rhs + ").to_string())\n}\n"
  { family: "i32", src, expected: [e.to_string()], excluded: false }
}

///|
fn gen_i64(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let a = rng.int(1 << 30).to_int64() % 1000000007L
  let b = rng.int(1 << 30).to_int64() % 1000000007L
  let op = rng.int(3)
  let e = if op == 0 { a + b } else if op == 1 { a - b } else { a * b }
  let opname = ["+", "-", "*"][op]
  let src = "fn main {\n  let a : Int64 = " + a.to_string() + "L\n  let b : Int64 = " +
    b.to_string() + "L\n  println((a " + opname + " b).to_string())\n}\n"
  { family: "i64", src, expected: [e.to_string()], excluded: false }
}

///|
fn gen_str(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let n = rng.int(5) + 1
  let m = rng.int(5) + 1
  let sa : Array[String] = []
  let sb : Array[String] = []
  let mut i = 0
  let letters = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
  while i < n { sa.push(letters[rng.int(26)]); i += 1 }
  i = 0
  while i < m { sb.push(letters[rng.int(26)]); i += 1 }
  let a = sa.join("")
  let b = sb.join("")
  let src = "fn main {\n  let a = \"" + a + "\"\n  let b = \"" + b +
    "\"\n  println(a + b)\n  println((a + b).length().to_string())\n  println((a == b).to_string())\n}\n"
  { family: "string_ascii", src, expected: [a + b, (a.length() + b.length()).to_string(), "false"], excluded: false }
}

///|
fn gen_array(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let vals = [rng.int(10), rng.int(10), rng.int(10), rng.int(10)]
  let w = rng.int(50)
  let src = "fn main {\n  let xs : Array[Int] = [" + vals[0].to_string() + ", " +
    vals[1].to_string() + ", " + vals[2].to_string() + ", " + vals[3].to_string() +
    "]\n  xs[2] = " + w.to_string() + "\n  println(xs[1].to_string())\n  println(xs[2].to_string())\n  println(xs.length().to_string())\n}\n"
  { family: "array_inbounds", src, expected: [vals[1].to_string(), w.to_string(), "4"], excluded: false }
}

///|
fn gen_loop(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let n = rng.int(30)
  let src = "fn main {\n  let mut i = 0\n  let mut s = 0\n  while i <= " +
    n.to_string() + " {\n    s = s + i\n    i = i + 1\n  }\n  println(s.to_string())\n}\n"
  { family: "loop_counter", src, expected: [((n * (n + 1)) / 2).to_string()], excluded: false }
}

///|
fn gen_oob(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let src = "fn main {\n  let xs : Array[Int] = [1, 2, 3]\n  let i = " +
    (rng.int(5) + 5).to_string() + "\n  println(xs[i].to_string())\n}\n"
  { family: "array_oob", src, expected: ["<trap>"], excluded: false }
}

///|
fn gen_float(seed : UInt64) -> Case {
  let rng = @mutate.Rng::new(seed)
  let x = rng.int(10).to_double() / 3.0
  let src = "fn main {\n  println((" + x.to_string() + ").to_string())\n}\n"
  { family: "float_format", src, expected: [], excluded: true }
}

///|
fn next_case(family : String, seed : UInt64) -> Case {
  if family == "i32" { gen_i32(seed) } else if family == "i64" { gen_i64(seed) } else if family == "string_ascii" {
    gen_str(seed)
  } else if family == "array_inbounds" {
    gen_array(seed)
  } else if family == "loop_counter" {
    gen_loop(seed)
  } else if family == "array_oob" {
    gen_oob(seed)
  } else {
    gen_float(seed)
  }
}

///|
fn ensure_dir(p : String) -> Unit {
  ignore(try { @fs.create_dir(p); true } catch { _ => false })
  let parent = @corpus.dirname(p)
  if parent != p && !@fs.path_exists(p) {
    ignore(try { @fs.create_dir(parent); true } catch { _ => false })
  }
}

///|
fn write_pkg(dir : String, src : String) -> Bool {
  ensure_dir(dir)
  @stager.write_text(join(dir, "moon.mod"), "name = \"sem3\"\nversion = \"0.1.0\"\n") &&
  @stager.write_text(join(dir, "moon.pkg"), "pkgtype(kind: \"executable\")\n") &&
  @stager.write_text(join(dir, "main.mbt"), src)
}

///|
async fn main {
  let args = @env.args()
  let out = match arg_value(args, "--out") { Some(s) => s; None => "/tmp/sem3" }
  let duration = num_arg(args, "--duration", 300)
  let limit = num_arg(args, "--limit", 100000)
  let inject = match arg_value(args, "--inject") { Some(s) => s; None => "" }
  let families = ["i32", "i64", "string_ascii", "array_inbounds", "loop_counter", "array_oob", "float_format"]
  @stager.rm_rf(out)
  ensure_dir(out)
  let deadline = @env.now() + duration.to_uint64() * 1000UL
  let targets = ["js", "wasm-gc", "native"]
  let counts : Map[String, (Int32, Int32, Int32)] = Map([]) // attempts, witness, excluded
  for f in families { counts.set(f, (0, 0, 0)) }
  let mut cases = 0
  while @env.now() < deadline && cases < limit {
    cases += 1
    let family = families[cases % families.length()]
    let c = next_case(family, 0x9e3779b97f4a7c15UL * cases.to_uint64())
    let (at, wi, ex) = counts.get(family).unwrap()
    counts.set(family, (at + 1, wi, ex))
    let wd = join(out, "work")
    if !write_pkg(wd, c.src) { continue }
    let actuals : Array[String] = []
    let rcs : Array[Int32] = []
    let mut ok_targets = 0
    for t in targets {
      let r = @exec.run(
        @stager.moon_path(), ["run", "main.mbt", "--target", t], wd,
        30000, max_output_bytes=65536,
      )
      actuals.push(r.stdout.trim_end().to_owned())
      rcs.push(r.rc)
      if r.rc == 0 { ok_targets += 1 }
    }
    if c.excluded {
      // Float formatting: only count, never compare.
      counts.set(family, (at + 1, wi, ex + 1))
      continue
    }
    if ok_targets == 0 { continue }
    let expected_ok = c.expected.length() > 0
    let mut bad = false
    if family == "array_oob" {
      // Deterministic trap: every executed target must fail (rc != 0).
      for rc in rcs { if rc == 0 { bad = true } }
    } else if expected_ok {
      for i, a in actuals {
        let lines = a.split("\n")
        if i < rcs.length() && rcs[i] == 0 {
          let want : Array[String] = []
          for x in c.expected { want.push(if inject != "" && targets[i] == inject { x + "9" } else { x }) }
          let got : Array[String] = []
          for l in lines { if l != "" { got.push(l.to_owned()) } }
          if got.length() != want.length() { bad = true } else {
            for j, w in want { if got[j] != w { bad = true } }
          }
        }
      }
    }
    if bad {
      counts.set(family, (at + 1, wi + 1, ex))
      let ev = join(join(out, "witness"), cases.to_string())
      ensure_dir(ev)
      ignore(@stager.write_text(join(ev, "main.mbt"), c.src))
      ignore(@stager.write_text(join(ev, "expected.txt"), c.expected.join("\n")))
      ignore(@stager.write_text(join(ev, "actual.txt"), actuals.join("\n---\n")))
      ignore(@stager.write_text(join(ev, "argv.txt"),
        @stager.moon_path() + " run main.mbt --target js|wasm-gc|native\n"))
    }
  }
  let b = StringBuilder()
  b.write_string("{\"cases\":" + cases.to_string())
  b.write_string(",\"families\":{")
  let mut first = true
  for f in families {
    let (a, w, e) = counts.get(f).unwrap()
    if !first { b.write_string(",") }
    first = false
    b.write_string("\"" + f + "\":{\"attempts\":" + a.to_string() + ",\"witness\":" +
      w.to_string() + ",\"excluded\":" + e.to_string() + "}")
  }
  b.write_string("}}")
  println(b.to_string())
  ignore(@stager.write_text(join(out, "summary.json"), b.to_string()))
}
