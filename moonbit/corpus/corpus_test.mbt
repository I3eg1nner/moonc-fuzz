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

///|
test "sha1 and short_hash match reference vectors" {
  assert_eq(@corpus.sha1_hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
  assert_eq(@corpus.sha1_hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
  assert_eq(@corpus.short_hash("abc"), "a9993e364706816a")
  assert_eq(@corpus.short_hash("abc").length(), 16)
}

///|
test "collect_files applies max_bytes and even sampling" {
  let root = "/tmp/mbtfuzz_corpus_limits"
  @corpus.ensure_dir(root)
  @fs.write_string_to_file(root + "/small.mbt", "fn a {}\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/empty.mbt", "") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/big.mbt", "x".repeat(500)) catch {
    _ => ()
  }
  let kept = @corpus.collect_files(root, [".mbt"], 100, 0)
  assert_eq(kept, [root + "/small.mbt"])
  // Four candidates, two slots: evenly spaced sample keeps the first and third.
  @fs.write_string_to_file(root + "/b.mbt", "fn b {}\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/c.mbt", "fn c {}\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/d.mbt", "fn d {}\n") catch {
    _ => ()
  }
  let all = @corpus.collect_files(root, [".mbt"], 100, 0)
  let sampled = @corpus.collect_files(root, [".mbt"], 100, 2)
  assert_eq(all.length(), 4)
  assert_eq(sampled.length(), 2)
  assert_eq(sampled[0], all[0])
  for name in ["small", "empty", "big", "b", "c", "d"] {
    @fs.remove_file(root + "/" + name + ".mbt") catch {
      _ => ()
    }
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "load_texts dedups by content and honours the limit" {
  let root = "/tmp/mbtfuzz_corpus_load"
  @corpus.ensure_dir(root)
  @fs.write_string_to_file(root + "/a.mbt", "same\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/b.mbt", "same\n") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/c.mbt", "other\n") catch {
    _ => ()
  }
  let all = @corpus.load_texts([root], [".mbt"], 100, 0)
  assert_eq(all, ["same\n", "other\n"])
  let one = @corpus.load_texts([root], [".mbt"], 100, 1)
  assert_eq(one, ["same\n"])
  for name in ["a", "b", "c"] {
    @fs.remove_file(root + "/" + name + ".mbt") catch {
      _ => ()
    }
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "ensure_dir builds parents and append_line appends" {
  let root = "/tmp/mbtfuzz_corpus_nested"
  @corpus.ensure_dir(root + "/a/b")
  let p = root + "/a/b/log.txt"
  @corpus.append_line(p, "one")
  @corpus.append_line(p, "two")
  assert_eq(@fs.read_file_to_string(p), "one\ntwo\n")
  @fs.remove_file(p) catch {
    _ => ()
  }
  @fs.remove_dir(root + "/a/b") catch {
    _ => ()
  }
  @fs.remove_dir(root + "/a") catch {
    _ => ()
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "json_escape handles tabs, CR and control bytes" {
  assert_eq(@corpus.json_escape("a\tb\rc"), "a\\tb\\rc")
  assert_eq(@corpus.json_escape("\u{0001}"), "\\u0001")
}
