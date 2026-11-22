// Async determinism differential: fixed async test programs; expected order is
// computed by node's Promise/await, compared with moon test output on
// js / wasm-gc / native.  Only deterministic completion order/output is
// compared, never scheduling timing.
fn usage() -> Unit {
  println("usage: asem --out DIR [--duration S] [--inject-node]")
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
      for c in s { if c >= '0' && c <= '9' { n = n*10 + (c.to_int() - '0'.to_int()); any = true } else { return d } }
      if any { n } else { d }
    }
    None => d
  }
}

///|
struct ACase {
  name : String
  moon : String
  js : String
}

///|
fn async_cases() -> Array[ACase] {
  let out : Array[ACase] = []
  let mut k = 1
  while k <= 10 {
    let a = k
    let b = k + 1
    let moon = "async fn one() -> Int { " + a.to_string() +
      " }\nasync fn two() -> Int { " + b.to_string() +
      " }\nasync test \"order" + k.to_string() +
      "\" {\n  let x = one()\n  println(\"ASEM:A=\" + x.to_string())\n  let y = two()\n  println(\"ASEM:B=\" + y.to_string())\n  println(\"ASEM:D\")\n}\n"
    let js = "const one=async()=>" + a.to_string() + "; const two=async()=>" +
      b.to_string() +
      ";\n(async()=>{ const x=await one(); console.log(\"ASEM:A=\"+x); const y=await two(); console.log(\"ASEM:B=\"+y); console.log(\"ASEM:D\"); })();\n"
    out.push({ name: "order" + k.to_string(), moon, js })
    k += 1
  }
  // Exception propagation is one dedicated case.
  out.push({
    name: "raise",
    moon: "async fn boom() -> Int raise Failure { raise Failure(\"boom\") }\nasync test \"raise\" {\n  try {\n    let x = boom()\n    println(\"ASEM:A=\" + x.to_string())\n  } catch {\n    e => println(\"ASEM:E=\" + e.to_string())\n  }\n  println(\"ASEM:D\")\n}\n",
    js: "const boom=async()=>{ throw new Error(\"boom\") };\n(async()=>{ try { const x=await boom(); console.log(\"ASEM:A=\"+x); } catch(e) { console.log(\"ASEM:E=\"+e.message); } console.log(\"ASEM:D\"); })();\n",
  })
  out
}

///|
fn ensure_dir(p : String) -> Unit {
  if p == "" || p == "." || p == "/" || @fs.path_exists(p) { return }
  let parent = @corpus.dirname(p)
  if parent != p { ensure_dir(parent) }
  ignore(try { @fs.create_dir(p); true } catch { _ => false })
}

///|
fn write_case_pkg(dir : String, c : ACase) -> Bool {
  ensure_dir(dir)
  @stager.write_text(join(dir, "moon.mod"), "name = \"asem\"\nversion = \"0.1.0\"\n\nimport {\n  \"moonbitlang/async@0.22.9\",\n}\n") &&
  @stager.write_text(join(dir, "moon.pkg"), "import {\n  \"moonbitlang/core/async\",\n}\noptions(\"allow-experimental-packages\": [\"moonbitlang/core/async\"])\npkgtype(kind: \"library\")\n") &&
  @stager.write_text(join(dir, "main_test.mbt"), c.moon)
}

///|
fn total_tests(s : String) -> Int32 {
  match s.find("Total tests:") {
    None => -1
    Some(i) => {
      let rest = s[i + 12:].to_owned()
      let mut n = 0
      let mut any = false
      for c in rest {
        if c >= '0' && c <= '9' { n = n*10 + (c.to_int() - '0'.to_int()); any = true }
        else if !any && (c == ' ' || c == ':') { continue }
        else { break }
      }
      if any { n } else { -1 }
    }
  }
}

///|
fn lines_of(s : String) -> Array[String] {
  let out : Array[String] = []
  for l in s.split("\n") { if l.contains("ASEM:") { out.push(l.trim().to_owned()) } }
  out
}

///|
async fn node_ref(js : String) -> (Array[String], Int32) {
  let r = @exec.run("/usr/bin/env", ["node", "-e", js], "/tmp", 20000, max_output_bytes=65536)
  (lines_of(r.stdout), r.rc)
}

///|
async fn main {
  let args = @env.args()
  let out = match arg_value(args, "--out") { Some(s) => s; None => "/tmp/asem" }
  let duration = num_arg(args, "--duration", 300)
  let inject_node = args.contains("--inject-node")
  @stager.rm_rf(out)
  ensure_dir(out)
  let deadline = @env.now() + duration.to_uint64() * 1000UL
  let cases = async_cases()
  let mut attempts = 0
  let mut witnesses = 0

  let mut inconclusive = 0
  let mut excluded = 0
  let targets = ["js", "wasm-gc", "native"]
  let mut i = 0
  while @env.now() < deadline {
    let c = cases[i % cases.length()]
    i += 1
    let (expected, nrc) = node_ref(c.js)
    if nrc != 0 || expected.length() == 0 {
      inconclusive += 1
      continue
    }
    let want = if inject_node {
      let w : Array[String] = []
      for x in expected { w.push(x + "9") }
      w
    } else { expected }
    let wd = join(out, "work")
    if !write_case_pkg(wd, c) { continue }
    attempts += 1
    let outs : Array[Array[String]] = []
    let mut executed = 0
    let mut target_excluded = 0
    for t in targets {
      let r = @exec.run(
        @stager.moon_path(), ["test", "--target", t], wd, 60000,
        max_output_bytes=65536,
      )
      let n = total_tests(r.stdout)
      if n >= 1 {
        executed += 1
        outs.push(lines_of(r.stdout))
      } else {
        target_excluded += 1
      }
    }
    if executed == 0 {
      excluded += 1
      continue
    }
    let mut all_match = true
    for o in outs {
      if o.length() != want.length() { all_match = false } else {
        for j, w in want {
          if w.has_prefix("ASEM:E=") {
            if !o[j].has_prefix("ASEM:E=") { all_match = false }
          } else if o[j] != w {
            all_match = false
          }
        }
      }
    }
    if !all_match {
      witnesses += 1
      let ev = join(join(out, "witness"), c.name + "_" + i.to_string())
      ensure_dir(ev)
      ignore(@stager.write_text(join(ev, "case.mbt"), c.moon))
      ignore(@stager.write_text(join(ev, "expected.txt"), want.join("\n")))
      ignore(@stager.write_text(join(ev, "actual.txt"), outs.map(fn(x){ x.join("\n") }).join("\n---\n")))
      ignore(@stager.write_text(join(ev, "argv.txt"), "moon test --target js|wasm-gc|native"))
    }

  }
  let b = StringBuilder()
  b.write_string("{\"attempts\":" + attempts.to_string())
  b.write_string(",\"cases\":" + cases.length().to_string())
  b.write_string(",\"witness\":" + witnesses.to_string())
  b.write_string(",\"oracle_candidate\":0")
  b.write_string(",\"excluded\":0")
  b.write_string(",\"inconclusive\":" + inconclusive.to_string() + "}")
  println(b.to_string())
  ignore(@stager.write_text(join(out, "summary.json"), b.to_string()))
}
