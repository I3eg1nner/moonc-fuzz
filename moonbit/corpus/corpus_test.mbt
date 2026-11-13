///|
test "dirname and basename" {
  assert_eq(@corpus.dirname("/a/b/c.mbt"), "/a/b")
  assert_eq(@corpus.basename("/a/b/c.mbt"), "c.mbt")
  assert_eq(@corpus.dirname("x.mbt"), ".")
  assert_eq(@corpus.basename("x.mbt"), "x.mbt")
}

///|
test "collect_files filters suffixes and skips build dirs" {
  let root = "/tmp/mbtfuzz_corpus_test"
  @corpus.ensure_dir(root + "/_build")
  @corpus.ensure_dir(root + "/sub")
  @fs.write_string_to_file(root + "/a.mbt", "fn a {}\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/sub/b.mbt", "fn b {}\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/sub/c.txt", "no\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/_build/skip.mbt", "fn x {}\n") catch {
    _ => ()
  }
  let files = @corpus.collect_files(root, [".mbt"], 1000, 0)
  assert_eq(files, [root + "/a.mbt", root + "/sub/b.mbt"])
  @fs.remove_file(root + "/a.mbt") catch {
    _ => ()
  }
  @fs.remove_file(root + "/sub/b.mbt") catch {
    _ => ()
  }
  @fs.remove_file(root + "/sub/c.txt") catch {
    _ => ()
  }
  @fs.remove_file(root + "/_build/skip.mbt") catch {
    _ => ()
  }
  @fs.remove_dir(root + "/sub") catch {
    _ => ()
  }
  @fs.remove_dir(root + "/_build") catch {
    _ => ()
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "save_finding is first-writer-wins" {
  let out = "/tmp/mbtfuzz_corpus_test_out"
  @corpus.ensure_dir(out)
  let first = @corpus.save_finding(
    out, "t1", "ICE", "deadbeef", "fn x {}", "{}", "case.mbt",
  )
  let second = @corpus.save_finding(
    out, "t1", "ICE", "deadbeef", "fn y {}", "{}", "case.mbt",
  )
  assert_true(first)
  assert_true(!second)
  assert_eq(
    @fs.read_file_to_string(out + "/findings/t1/ICE/deadbeef/case.mbt"),
    "fn x {}",
  )
  @fs.remove_file(out + "/findings/t1/ICE/deadbeef/case.mbt") catch {
    _ => ()
  }
  @fs.remove_file(out + "/findings/t1/ICE/deadbeef/meta.json") catch {
    _ => ()
  }
  @fs.remove_dir(out + "/findings/t1/ICE/deadbeef") catch {
    _ => ()
  }
  @fs.remove_dir(out + "/findings/t1/ICE") catch {
    _ => ()
  }
  @fs.remove_dir(out + "/findings/t1") catch {
    _ => ()
  }
  @fs.remove_dir(out + "/findings") catch {
    _ => ()
  }
  @fs.remove_dir(out) catch {
    _ => ()
  }
}

///|
test "json_escape preserves quotes, newlines and backslashes" {
  assert_eq(@corpus.json_escape("a\"b\\c\nd"), "a\\\"b\\\\c\\nd")
}
