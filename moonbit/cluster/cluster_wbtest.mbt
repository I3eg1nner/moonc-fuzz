///|
/// Witness merging: different witnesses of one class must share a bucket.

///|
test "F1/F1b merge: signal with no text" {
  let a = crash_signature("SIG", -11, "", "")
  let b = crash_signature("SIG", -11, "", "")
  assert_eq(a, b)
  assert_true(a.contains("rc=-11"))
}

///|
test "F2/F2b merge on the exception constructor" {
  let a = crash_signature(
    "ICE", 199, "Oops, the compiler has encountered an exception\nError: Invalid_argument(\"Char.chr\")\n",
    "",
  )
  let b = crash_signature(
    "ICE", 199, "Error: Invalid_argument(\"Char.chr\")\nCompiler args: /tmp/x 12\n",
    "",
  )
  assert_eq(a, b)
  assert_true(a.contains("Char.chr"))
}

///|
test "F4/F4b merge on the decoder constructor" {
  let a = crash_signature(
    "ICE", 199, "Error: Moonc.Basic_utf8_decode.Malformed\n", "",
  )
  let b = crash_signature(
    "ICE", 199, "Error: Moonc.Basic_utf8_decode.Malformed\n  raised at lsp.ml:12\n",
    "",
  )
  assert_eq(a, b)
}

///|
/// Distinct causes must not merge, including when the text looks similar.

///|
test "F7/F8/F9 stay distinct" {
  let f7 = crash_signature(
    "ICE", 1, "Error: Machine_error(kind=unsupported; who=\"Machine_of_clam_lower.lower_array_make\"; message=\"aggregate\")\n",
    "",
  )
  let f8 = crash_signature(
    "ICE", 1, "Error: File \"moonc.ml\", line 125623, characters 29-35: Assertion failed\n",
    "",
  )
  let f9 = crash_signature(
    "ICE", 1, "Error: Machine_error(kind=unsupported; who=\"Machine_of_clam_lower.finish_stub_wrapper_shell\"; message=\"aggregate\")\n",
    "",
  )
  assert_true(f7 != f8)
  assert_true(f7 != f9)
  assert_true(f8 != f9)
  assert_true(f7.contains("known=F7"))
  assert_true(f8.contains("known=F8"))
  assert_true(f9.contains("known=F9"))
}

///|
test "paths and numbers are normalised" {
  let a = crash_signature(
    "ICE", 1, "Error: failed at /tmp/build_123/a.mb:44:2\n", "",
  )
  let b = crash_signature(
    "ICE", 1, "Error: failed at /home/u/b_999/b.mb:11:9\n", "",
  )
  assert_eq(a, b)
  assert_true(a.contains("<path>") || a.contains("failed at"))
  // same shape, different path/number -> same bucket
  let n1 = normalize_text("/tmp/a_123/x.mb:44:2")
  let n2 = normalize_text("/home/u/b_999/y.mb:11:9")
  assert_eq(n1, n2)
  assert_true(n1.contains("<path>"))
}

///|
test "formatter signature ignores the source" {
  let a = formatter_signature(0, "Parse error at line 3\n", "")
  let b = formatter_signature(0, "Parse error at line 3\n", "")
  assert_eq(a, b)
  assert_true(!a.contains("fmt-hang"))
  // two different failures stay distinct
  let c = formatter_signature(0, "Error: unterminated string\n", "")
  assert_true(a != c)
}

///|
test "signature fields with escaped quotes are read back intact" {
  let meta = "{\"stage\":\"build\",\"signature\":\"crash|ICE|Invalid_argument(\\\"Char.chr\\\")|known=F2\"}"
  assert_eq(
    json_get_string(meta, "signature"),
    "crash|ICE|Invalid_argument(\"Char.chr\")|known=F2",
  )
  assert_eq(json_get_string("{\"signature\":\"plain\"}", "signature"), "plain")
  assert_eq(json_get_string("{}", "signature"), "")
}
