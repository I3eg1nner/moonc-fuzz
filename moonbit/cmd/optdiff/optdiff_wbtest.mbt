///|
test "shell split preserves quoted test args" {
  let argv = shell_split(
    "moonrun --test-args '{\"package\":\"p\",\"file_and_index\":[]}' a.wasm --",
  )
  assert_true(argv is Some(_))
  assert_eq(argv.unwrap().length(), 5)
  assert_eq(argv.unwrap()[1], "--test-args")
  assert_eq(argv.unwrap()[4], "--")
}

///|
test "link argv replacement keeps the rest of the command" {
  let argv = shell_split("moonc link-core a.core -o old.wasm -O0 -wasi")
  assert_true(argv is Some(_))
  let got = make_link_argv(argv.unwrap(), "/tmp/new.wasm", true)
  assert_true(got is Some(_))
  let a = got.unwrap()
  assert_eq(a[4], "/tmp/new.wasm")
  assert_eq(count_arg(a, "-O0"), 0)
  assert_eq(a[a.length() - 1], "-wasi")
}

///|
test "O0 arm keeps exactly one optimization flag" {
  let argv = shell_split("moonc link-core a.core -o old.wasm -O0 -wasi")
  assert_true(argv is Some(_))
  let got = make_link_argv(argv.unwrap(), "/tmp/new.wasm", false)
  assert_true(got is Some(_))
  assert_eq(count_arg(got.unwrap(), "-O0"), 1)
}

///|
test "link argv rejects duplicate O0" {
  let argv = shell_split("moonc link-core a.core -O0 -o old.wasm -O0 -wasi")
  assert_true(argv is Some(_))
  assert_eq(make_link_argv(argv.unwrap(), "/tmp/new.wasm", true), None)
}

///|
test "result parser keeps file and index" {
  let line = "{\"type\":\"result\",\"file\":\"a_test.mbt\",\"index\":7,\"message\":\"\"}"
  assert_eq(parse_result_line(line), Some(("a_test.mbt|7", "")))
}

///|
test "result parser requires message" {
  let line = "{\"type\":\"result\",\"file\":\"a_test.mbt\",\"index\":7}"
  assert_eq(parse_result_line(line), None)
}

///|
test "result collection rejects duplicate ids" {
  let blob = "{\"type\":\"result\",\"file\":\"a\",\"index\":0,\"message\":\"\"}\n" +
    "{\"type\":\"result\",\"file\":\"a\",\"index\":0,\"message\":\"\"}\n"
  let parsed = collect_results(blob)
  assert_true(parsed.duplicate)
  assert_eq(parsed.results.length(), 1)
}

///|
test "test args expand ranges" {
  let args = "{\"package\":\"p\",\"file_and_index\":[[\"a.mbt\",[{\"start\":0,\"end\":3}]]]}"
  let ids = expected_ids(args)
  assert_true(ids is Some(_))
  assert_eq(ids.unwrap().length(), 3)
  assert_true(ids.unwrap().contains("a.mbt|2"))
}

///|
test "summary parser reads the final failed count" {
  let text = "one failed: not a count\nTotal tests: 164, passed: 86, failed: 78.\n"
  assert_eq(summary_failures(text), 78)
}

///|
test "safe_name replaces every separator" {
  assert_eq(
    safe_name("moonbitlang/core/argparse"),
    "moonbitlang__core__argparse",
  )
}

///|
test "link argv rejects duplicate output flags" {
  let argv = shell_split("moonc link-core a.core -o one.wasm -o two.wasm -O0")
  assert_true(argv is Some(_))
  assert_eq(make_link_argv(argv.unwrap(), "/tmp/new.wasm", true), None)
}

///|
test "coverage requires the exact expected keys" {
  let expected : Map[String, Unit] = Map([("a|0", ()), ("a|1", ())])
  let actual : Map[String, String] = Map([("a|0", ""), ("b|1", "")])
  assert_false(exact_coverage(actual, expected))
}

///|
test "fault paths stay relative and inside the copy" {
  assert_true(fault_file_ok("argparse/help_render.mbt"))
  assert_false(fault_file_ok("../outside.mbt"))
  assert_false(fault_file_ok("/etc/passwd"))
}

///|
test "stack trace text does not create a semantic difference" {
  let a : Map[String, String] = Map([("a|0", "Error\n at 0x111")])
  let b : Map[String, String] = Map([("a|0", "Error\n at 0x222")])
  let c = compare_results(a, b, Map([]))
  assert_eq(c.changed, 0)
  assert_eq(c.missing, 0)
  assert_eq(c.extra, 0)
}

///|
test "pass fail and skip are semantic states" {
  assert_eq(test_status("", false), "pass")
  assert_eq(test_status("skipped test", false), "skip")
  assert_eq(test_status("Error\n at 0x1", false), "fail")
  assert_eq(test_status("Error\n at 0x1", true), "pass")
  assert_eq(test_status("", true), "fail")
}

///|
test "path containment is component based" {
  assert_true(path_within("/tmp/a/b", "/tmp/a"))
  assert_false(path_within("/tmp/ab", "/tmp/a"))
  assert_false(path_within("/tmp/a", "/tmp/a/b"))
}

///|
test "metadata marks panic-named tests only" {
  let path = "/tmp/optdiff_panic_info.json"
  let text = "{\"tests\":{\"a.mbt\":[{\"index\":0,\"name\":\"panic div\"},{\"index\":1,\"name\":\"normal\"}]}}"
  @fs.write_string_to_file(path, text) catch {
    _ => ()
  }
  let meta = load_test_meta(path)
  assert_true(meta is Some(_))
  let meta = meta.unwrap()
  assert_true(meta.panic_ids.contains("a.mbt|0"))
  assert_false(meta.panic_ids.contains("a.mbt|1"))
  assert_true(meta.known.contains("a.mbt|1"))
}

///|
test "invalid metadata is rejected, not treated as no panic" {
  let path = "/tmp/optdiff_bad_meta.json"
  @fs.write_string_to_file(path, "{\"tests\":") catch {
    _ => ()
  }
  assert_true(load_test_meta(path) is None)
}

///|
test "subset ids checks every expected key" {
  let expected : Map[String, Unit] = Map([("a|0", ()), ("a|1", ())])
  let known : Map[String, Unit] = Map([("a|0", ())])
  assert_false(subset_ids(expected, known))
}

///|
test "root directory contains every absolute path" {
  assert_true(path_within("/tmp/x", "/"))
  assert_true(path_within("/", "/"))
  assert_false(path_within("tmp/x", "/"))
}

///|
test "non-string non-null metadata name is rejected" {
  let path = "/tmp/optdiff_bad_name.json"
  @fs.write_string_to_file(
    path, "{\"tests\":{\"a.mbt\":[{\"index\":0,\"name\":42}]}}",
  ) catch {
    _ => ()
  }
  assert_true(load_test_meta(path) is None)
}
