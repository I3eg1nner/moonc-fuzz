///|
/// MoonBit regression runner for the defects already found in this project.
///
/// This is the first piece of the Python->MoonBit migration: a defect is only
/// "covered" when the new stack can reproduce its canonical command, expected
/// outcome class, and a discriminating substring, without importing any Python
/// module.  The runner is intentionally black-box: it drives the installed
/// `moonc`/`moonfmt`/`moon` binaries, so it also works against future builds.
///
/// Usage:
///   regress <repo-root> [out.jsonl]
struct Case {
  name : String
  cmd : String
  args : Array[String]
  cwd : String
  timeout_ms : Int32
  expect : String
  needle : String
  pre : String
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let isdir = @fs.is_dir(path) catch { _ => false }
  if isdir {
    let names = @fs.read_dir(path) catch { _ => [] }
    for n in names {
      rm_rf(join(path, n))
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
fn write_text(path : String, text : String) -> Unit {
  @fs.write_string_to_file(path, text) catch {
    _ => ()
  }
}

///|
async fn run_case(c : Case) -> String {
  if c.pre == "clean_build" {
    rm_rf(join(c.cwd, "_build"))
  }
  let r = @exec.run(c.cmd, c.args, c.cwd, c.timeout_ms)
  let kind = @exec.classify(r)
  let blob = r.stderr + r.stdout
  let has_needle = c.needle == "" || blob.find(c.needle) is Some(_)
  let ok = kind == c.expect && has_needle
  let b = StringBuilder()
  b.write_string("{\"case\":\"")
  b.write_string(c.name)
  b.write_string("\",\"ok\":")
  b.write_string(if ok { "true" } else { "false" })
  b.write_string(",\"kind\":\"")
  b.write_string(kind)
  b.write_string("\",\"expect\":\"")
  b.write_string(c.expect)
  b.write_string("\",\"rc\":")
  b.write_string(r.rc.to_string())
  b.write_string(",\"ms\":")
  b.write_string(r.ms.to_string())
  b.write_string(",\"timed_out\":")
  b.write_string(if r.timed_out { "true" } else { "false" })
  b.write_string(",\"needle\":")
  b.write_string(if has_needle { "true" } else { "false" })
  b.write_string(",\"detail\":\"")
  let d = @exec.ice_detail(r)
  // The detail is only diagnostic here; escape quotes/backslashes.
  for ch in d {
    if ch == '"' {
      b.write_string("\\\"")
    } else if ch == '\\' {
      b.write_string("\\\\")
    } else if ch == '\n' {
      b.write_string(" ")
    } else {
      b.write_char(ch)
    }
  }
  b.write_string("\"}")
  b.to_string()
}

///|
fn p1_source(k : Int32) -> String {
  let b = StringBuilder()
  b.write_string("fn f() -> String { \"")
  for i in 0..<k {
    b.write_string("\\{")
    b.write_string(i.to_string())
    b.write_string("}")
  }
  b.write_string("\" }\n")
  b.to_string()
}

///|
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let root = if args.length() >= 2 { args[1] } else { "/data/audit/mbtfuzz" }
  let out_path = if args.length() >= 3 { Some(args[2]) } else { None }
  let moonc = join(join(home, ".moon/bin"), "moonc")
  let moonfmt = join(join(home, ".moon/bin"), "moonfmt")
  let moon = join(join(home, ".moon/bin"), "moon")
  let tmp = "/tmp/mbtfuzz_mb_regress_" + @env.now().to_string()
  rm_rf(tmp)
  @fs.create_dir(tmp) catch {
    _ => ()
  }

  let cases : Array[Case] = [
    {
      name: "F1_moon_pkg_segv",
      cmd: moonc,
      args: ["syncheck", "moon.pkg"],
      cwd: join(root, "poc/f1_moon_pkg_segv"),
      timeout_ms: 10000,
      expect: "SIG",
      needle: "",
      pre: "",
    },
    {
      name: "F1b_pkg_map_segv",
      cmd: moonc,
      args: ["syncheck", "moon.pkg"],
      cwd: join(root, "poc/f1b_pkg_map_segv"),
      timeout_ms: 10000,
      expect: "SIG",
      needle: "",
      pre: "",
    },
    {
      name: "F2_lex_escape_ice",
      cmd: moon,
      args: ["check"],
      cwd: join(root, "poc/f2_lex_escape_ice"),
      timeout_ms: 90000,
      expect: "ICE",
      needle: "Invalid_argument(\"Char.chr\")",
      pre: "clean_build",
    },
    {
      name: "F2b_zwsp_escape_t2_ice",
      cmd: moonc,
      args: [
        "build-package",
        "main.mbt",
        "-o",
        "out.core",
        "-pkg",
        "f2b/p",
        "-pkg-type",
        "executable",
        "-i",
        join(
          join(home, ".moon/lib/core/_build/wasm/release/bundle"),
          "builtin/builtin.mi",
        ) +
        ":moonbitlang/core/builtin",
        "-i",
        join(
          join(home, ".moon/lib/core/_build/wasm/release/bundle"),
          "prelude/prelude.mi",
        ) +
        ":prelude",
        "-pkg-sources",
        "f2b/p:.",
        "-target",
        "wasm",
        "-g",
        "-O0",
        "-workspace-path",
        ".",
        "-all-pkgs",
        join(join(root, "harness"), "all_pkgs.json"),
      ],
      cwd: join(root, "poc/f2b_zwsp_escape_t2_ice"),
      timeout_ms: 15000,
      expect: "ICE",
      needle: "Char.chr",
      pre: "",
    },
    {
      name: "F3_parser_oom_capped",
      cmd: "/usr/bin/prlimit",
      args: ["--as=6442450944", "--", moonc, "syncheck", "cmd/main.mbt"],
      cwd: join(root, "poc/f3_parser_oom"),
      timeout_ms: 25000,
      expect: "OOM",
      needle: "",
      pre: "",
    },
    {
      name: "F4_invalid_utf8_ice",
      cmd: moonc,
      args: ["syncheck", "doc.mbt.md"],
      cwd: join(root, "poc/f4_invalid_utf8"),
      timeout_ms: 10000,
      expect: "ICE",
      needle: "utf8_decode",
      pre: "",
    },
    {
      name: "F4b_invalid_utf8_ice",
      cmd: moonc,
      args: ["syncheck", "doc.mbt.md"],
      cwd: join(root, "poc/f4b_invalid_utf8_2"),
      timeout_ms: 10000,
      expect: "ICE",
      needle: "utf8_decode",
      pre: "",
    },
    {
      name: "F5_prefix_plus_diagnostic",
      cmd: moonc,
      args: [
        "check",
        "-no-mi",
        "-pkg",
        "f5/p",
        "-i",
        join(
          join(home, ".moon/lib/core/_build/wasm-gc/release/bundle"),
          "prelude/prelude.mi",
        ),
        "u.mbt",
      ],
      cwd: join(root, "poc/f5_prefix_plus"),
      timeout_ms: 15000,
      expect: "ERR",
      needle: "~+",
      pre: "",
    },
    {
      name: "F5_prefix_plus_parses",
      cmd: moonc,
      args: ["syncheck", "u.mbt"],
      cwd: join(root, "poc/f5_prefix_plus"),
      timeout_ms: 10000,
      expect: "OK",
      needle: "",
      pre: "",
    },
  ]

  let lines : Array[String] = []
  let mut all_ok = true
  for c in cases {
    let line = run_case(c)
    println(line)
    if !line.contains("\"ok\":true") {
      all_ok = false
    }
    lines.push(line)
  }

  // F5 formatter round-trip: moonfmt turns unary `+` into the private token
  // `~+`, which the lexer then rejects.  This is a two-command case, so it is
  // handled explicitly rather than through the generic table.
  let f5dir = join(root, "poc/f5_prefix_plus")
  let f5out = join(tmp, "u1.mbt")
  let fr = @exec.run(moonfmt, ["u.mbt", "-o", f5out], f5dir, 30000)
  let formatted = read_text(f5out)
  let rr = @exec.run(moonc, ["syncheck", f5out], f5dir, 10000)
  let f5ok = fr.rc == 0 &&
    formatted.contains("~+") &&
    rr.rc == 2 &&
    (rr.stderr + rr.stdout).contains("E3001")
  let f5line = "{\"case\":\"F5_prefix_plus_fmt_roundtrip\",\"ok\":" +
    (if f5ok { "true" } else { "false" }) +
    ",\"kind\":\"unparseable\",\"expect\":\"unparseable\",\"rc\":" +
    rr.rc.to_string() +
    ",\"fmt_rc\":" +
    fr.rc.to_string() +
    ",\"has_tilde_plus\":" +
    (if formatted.contains("~+") { "true" } else { "false" }) +
    "}"
  println(f5line)
  if !f5ok {
    all_ok = false
  }
  lines.push(f5line)

  // P1: formatter interpolation scaling.  Measure 5/5/3 runs at
  // k=512/1024/2048 and compare against a plain-string control at the same
  // size.  A single absolute time is not evidence of superlinear growth.
  fn median_ms(xs : Array[Int32]) -> Int32 {
    xs.sort()
    if xs.length() == 0 {
      0
    } else {
      xs[xs.length() / 2]
    }
  }

  let mut p1_ok_all = true
  let p1_parts : Array[String] = []
  for k in [512, 1024, 2048] {
    let interp = join(tmp, "p1_interp_" + k.to_string() + ".mbt")
    let plain = join(tmp, "p1_plain_" + k.to_string() + ".mbt")
    write_text(interp, p1_source(k))
    let pb = StringBuilder()
    pb.write_string("fn f() -> String { \"")
    for _ in 0..<k {
      pb.write_string("a")
    }
    pb.write_string("\" }\n")
    write_text(plain, pb.to_string())
    let runs = if k == 2048 { 3 } else { 5 }
    let ti : Array[Int32] = []
    let tp : Array[Int32] = []
    for _ in 0..<runs {
      let ri = @exec.run(
        moonfmt,
        [basename(interp), "-o", "p1_i_out.mbt"],
        tmp,
        180000,
      )
      let rp = @exec.run(
        moonfmt,
        [basename(plain), "-o", "p1_p_out.mbt"],
        tmp,
        180000,
      )
      ti.push(ri.ms.to_int())
      tp.push(rp.ms.to_int())
    }
    let mi = median_ms(ti)
    let mp = median_ms(tp)
    let ratio = if mp > 0 { mi.to_double() / mp.to_double() } else { 0.0 }
    let ok = ratio > 5.0
    if !ok {
      all_ok = false
      p1_ok_all = false
    }
    p1_parts.push(
      "{\"k\":" +
      k.to_string() +
      ",\"interp_ms\":" +
      mi.to_string() +
      ",\"plain_ms\":" +
      mp.to_string() +
      ",\"ratio\":" +
      ratio.to_string() +
      ",\"ok\":" +
      (if ok { "true" } else { "false" }) +
      "}",
    )
  }
  let p1line = "{\"case\":\"P1_fmt_interp_scaling\",\"ok\":" +
    (if p1_ok_all { "true" } else { "false" }) +
    ",\"kind\":\"slow\",\"expect\":\"slow\",\"rows\":[" +
    p1_parts.join(",") +
    "]}"
  println(p1line)
  if !p1_ok_all {
    all_ok = false
  }
  lines.push(p1line)

  // F6: minimized single-package trigger.  No third-party fixture needed.
  let f6dir = join(root, "poc/f6_native_export_closure_min")
  let r6 = @exec.run(moon, ["build", "--target", "native"], f6dir, 120000)
  let blob6 = r6.stderr + r6.stdout
  let ok6 = @exec.classify(r6) == "ICE" &&
    blob6.contains("reject_export_type_containing_unsupported_callback")
  let l6 = "{\"case\":\"F6_native_export_closure\",\"ok\":" +
    (if ok6 { "true" } else { "false" }) +
    ",\"kind\":\"" +
    @exec.classify(r6) +
    "\",\"expect\":\"ICE\",\"rc\":" +
    r6.rc.to_string() +
    ",\"needle\":" +
    (if blob6.contains("reject_export_type_containing_unsupported_callback") {
      "true"
    } else {
      "false"
    }) +
    "}"
  println(l6)
  if !ok6 {
    all_ok = false
  }
  lines.push(l6)

  match out_path {
    Some(p) => {
      let b = StringBuilder()
      for l in lines {
        b.write_string(l)
        b.write_string("\n")
      }
      write_text(p, b.to_string())
    }
    None => ()
  }
  if !all_ok {
    @env.exit(1)
  }
}
