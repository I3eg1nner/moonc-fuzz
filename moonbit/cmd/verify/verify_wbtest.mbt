///|
fn synthetic(
  rc : Int32,
  stdout : String,
  stderr : String,
  timed_out : Bool,
) -> @exec.RunResult {
  {
    rc,
    stdout,
    stderr,
    ms: 0L,
    timed_out,
    stdout_digest: "",
    stdout_full_len: 0L,
    stdout_truncated: false,
  }
}

///|
test "signature normalizes a multiline Machine_error" {
  let text = "Error: Machine_error(kind=unsupported;\n  who=\"Machine_of_clam_lower.finish_stub_wrapper_shell\";\n  message=\"aggregate stub wrapper arguments are not lowered in this batch\")"
  assert_eq(
    run_signature(text, 1, false),
    "Machine_error(kind=unsupported; who=Machine_of_clam_lower.finish_stub_wrapper_shell; message=aggregate stub wrapper arguments are not lowered in this batch)",
  )
}

///|
test "signature normalizes a moonc.ml assertion line" {
  let text = "File \"moonc.ml\", line 1842, characters 7-15:\nAssertion failed"
  assert_eq(run_signature(text, 1, false), "moonc.ml:1842:assertion")
}

///|
test "signature keeps a generic Error line" {
  assert_eq(
    run_signature("Error: failed to link repro/x\nmore detail", 1, false),
    "Error: failed to link repro/x",
  )
}

///|
test "signature pairs Oops with the following Error line" {
  let text = "Oops, the compiler has encountered an unexpected situation.\nThis is a bug.\nError: Boom(42)"
  assert_eq(run_signature(text, 1, false), "ICE: Boom(42)")
}

///|
test "signature replaces package roots with <PKG>" {
  let text = "Error: cannot open /tmp/mbtfuzz_verify/pkg-abcd/repeats/repeat_0/lib.mbt"
  let clean = sanitize_paths(text, [
    "/tmp/mbtfuzz_verify/pkg-abcd/repeats/repeat_0",
  ])
  assert_eq(run_signature(clean, 1, false), "Error: cannot open <PKG>/lib.mbt")
}

///|
test "signature reports a signal when there is no diagnostic" {
  assert_eq(run_signature("", -11, false), "signal:SIGSEGV")
}

///|
test "signature on success is empty" {
  assert_eq(run_signature("Error: stale output", 0, false), "")
}

///|
test "stage classification is stage-aware" {
  let check = synthetic(2, "", "Error: bad type", false)
  assert_eq(classify_stage("check", check), "check_fail")
  let build = synthetic(2, "", "Error: bad type", false)
  assert_eq(classify_stage("build", build), "build_fail")
  let link = synthetic(1, "", "Error: failed to link p", false)
  assert_eq(classify_stage("test_build_only", link), "test_link_fail")
  assert_eq(classify_stage("test", link), "test_link_fail")
  let run = synthetic(1, "test failed", "Error: test failed", false)
  assert_eq(classify_stage("test", run), "run_fail")
  assert_eq(classify_stage("build", synthetic(0, "", "", false)), "ok")
  assert_eq(
    classify_stage("test_build_only", synthetic(1, "", "", true)),
    "timeout",
  )
  let ice = synthetic(
    1, "", "Error: Machine_error(kind=x; who=y; message=z)", false,
  )
  assert_eq(classify_stage("test_build_only", ice), "ice")
}

///|
test "copy excludes build, dependency and VCS directories" {
  let src = "/tmp/mbtfuzz_verify_copy_src"
  let dst = "/tmp/mbtfuzz_verify_copy_dst"
  rm_rf(src)
  rm_rf(dst)
  ensure_dir(join(src, "native"))
  ensure_dir(join(src, "_build"))
  ensure_dir(join(src, ".mooncakes/dep"))
  ensure_dir(join(src, ".git"))
  ensure_dir(join(src, "sub"))
  @fs.write_string_to_file(join(src, "moon.mod"), "name = \"t\"\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, "moon.pkg"), "") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, "lib.mbt"), "pub fn f() -> Int { 1 }\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, "native/stub.c"), "int x;\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, "sub/deep.txt"), "ok\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, "_build/out.o"), "bin\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, ".mooncakes/dep/x.mbt"), "x\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(join(src, ".git/HEAD"), "ref\n") catch {
    _ => ()
  }
  assert_true(copy_package(src, dst))
  assert_true(@fs.path_exists(join(dst, "moon.mod")))
  assert_true(@fs.path_exists(join(dst, "moon.pkg")))
  assert_true(@fs.path_exists(join(dst, "lib.mbt")))
  assert_true(@fs.path_exists(join(dst, "native/stub.c")))
  assert_true(@fs.path_exists(join(dst, "sub/deep.txt")))
  assert_true(!@fs.path_exists(join(dst, "_build")))
  assert_true(!@fs.path_exists(join(dst, ".mooncakes")))
  assert_true(!@fs.path_exists(join(dst, ".git")))
  rm_rf(src)
  rm_rf(dst)
}

///|
fn synthetic_run(
  terminal : String,
  stage : String,
  signature : String,
  rc : Int32,
) -> RepeatRun {
  {
    repeat: 0,
    work_dir: "",
    stages: [],
    terminal,
    failing_stage: stage,
    signature,
    rc,
    rc_class: rc_class(terminal, rc),
    ms: 0L,
    diagnostics: [],
  }
}

///|
test "stability compares terminal, stage, signature and rc class" {
  let a = synthetic_run("ice", "test_build_only", "sig-a", 1)
  let b = synthetic_run("ice", "test_build_only", "sig-a", 1)
  assert_true(runs_stable([a, b]))
  let c = synthetic_run("ice", "test_build_only", "sig-b", 1)
  assert_true(!runs_stable([a, c]))
  let d = synthetic_run("build_fail", "build", "sig-a", 1)
  assert_true(!runs_stable([a, d]))
}
