///|
/// Wrong-code evidence must exist before the work dir is cleaned; this is the
/// whole point of a mismatch record.
test "mismatch evidence keeps source, expected, actual and argv" {
  let out = "/tmp/deepfuzz_evidence_test"
  @stager.rm_rf(out)
  assert_true(
    save_mismatch(
      out,
      7,
      "fn main { () }\n",
      ["a", "b"],
      "a\nc\n",
      "wasm-gc",
      12,
    ),
  )
  let dir = out + "/mismatch/7"
  assert_eq(@stager.read_text(dir + "/main.mbt"), "fn main { () }\n")
  assert_eq(@stager.read_text(dir + "/expected.txt"), "a\nb")
  assert_eq(@stager.read_text(dir + "/actual.txt"), "a\nc\n")
  assert_true(@stager.read_text(dir + "/argv.txt").contains("target=wasm-gc"))
  assert_true(@stager.read_text(dir + "/argv.txt").contains("case=7"))
  @stager.rm_rf(out)
}
