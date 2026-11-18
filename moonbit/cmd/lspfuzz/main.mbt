///|
/// Curated matrix and driver for `moon-lsp` stdio JSON-RPC probing.
///
/// Oracle: a matching response is OK/ERROR_RESPONSE, silence past the timeout
/// with a live process is HANG, an exited process is CRASH.  Every case gets
/// a fresh server because one unresponsive request poisons the queue.

///|
/// One write and the delay to observe before the next write.  A delay of 0
/// means "write immediately"; the driver still flushes after every chunk.
struct Step {
  data : String
  delay_ms : Int32
}

///|
enum Action {
  FormatNth(String, Int32, Bool)
  /// Method, URI mode, optional didOpen text, line, character.
  Doc(@lsp.RpcMethod, String, String?, Int32, Int32)
  ShutdownLiteral(String?)
  ShutdownThenHover
  ShutdownThenExit
  UnknownMethod
  /// Raw bytes sent after the handshake; no id is awaited.
  Raw(String)
  /// Ordered byte chunks for split-write and desync cases.
  Steps(Array[Step])
  /// Arbitrary method name plus literal params, sent as request id 2.
  Rpc(String, String, Bool)
}

///|
struct Case {
  cid : String
  family : String
  rpc_method : String
  action : Action
  /// Oracle shape: request, control, method, unsupported, incomplete,
  /// desync, pipeline, mixed, large.
  kind : String
  /// Response ids that must arrive, including duplicates for dup-id cases.
  expect_ids : Array[Int32]
  /// Text to `didOpen` before the probe, or None for no open.
  open_text : String?
  /// A frame is deliberately incomplete, so silence is EXPECTED_WAIT.
  expected_wait : Bool
  /// Pre-set classification note (known_f10, expected_wait, ...).
  known_kind : String
}

///|
fn case(
  cid : String,
  family : String,
  rpc_method : String,
  action : Action,
) -> Case {
  {
    cid,
    family,
    rpc_method,
    action,
    kind: "request",
    expect_ids: [],
    open_text: None,
    expected_wait: false,
    known_kind: "",
  }
}

///|
fn probe_case(
  cid : String,
  family : String,
  rpc_method : String,
  action : Action,
  kind : String,
  expect_ids : Array[Int32],
  open_text : String?,
  expected_wait : Bool,
  known_kind : String,
) -> Case {
  {
    cid,
    family,
    rpc_method,
    action,
    kind,
    expect_ids,
    open_text,
    expected_wait,
    known_kind,
  }
}

///|
/// About 90 cheap cases.  Contents are deliberately small; the point is shape
/// coverage, not volume.
fn build_cases() -> Array[Case] {
  let cs : Array[Case] = []
  let a = "fn a() -> Unit {\n  ()\n}\n"
  let b = "fn b() -> Unit {\n  ()\n}\n"
  let ab = a + b
  let ab_nl = ab
  let ab_no_nl = "fn a() -> Unit {\n  ()\n}\nfn b() -> Unit {\n  ()\n}"
  let single_no_nl = "fn f() -> Unit {\n  ()\n}"
  let single_nl = single_no_nl + "\n"
  let crlf = "fn f() -> Unit {\r\n  ()\r\n}\r\n"
  let crlf_no_nl = "fn f() -> Unit {\r\n  ()\r\n}"
  let comment = single_nl + "// tail comment"
  let mid_token = "fn f() -> Unit {\n  ()"
  let long_line = "fn f() -> Unit { let x = " + "1 + ".repeat(400) + "1 }"
  let emoji = "fn f() -> Unit {\n  // 😀 héllo\n  ()\n}"
  let multi_no_nl = "fn a() -> Unit {\n  ()\n}\nfn b() -> Unit {\n  ()\n}\nfn c() -> Unit {\n  ()\n}"
  let single_block_doc = "///|\nfn f() -> Unit {\n  ()\n}"
  let add_fmt = fn(cid : String, content : String, n : Int32, md : Bool) {
    cs.push(
      case(
        cid,
        "format-nth",
        "moonbit-lsp/format-nth",
        FormatNth(content, n, md),
      ),
    )
  }
  // Canonical F10 trigger and its control.
  add_fmt("fmt-f10-exact-no-final-newline", single_no_nl, 0, false)
  add_fmt("fmt-single-with-final-newline", single_nl, 0, false)
  // Empty / whitespace / separator-only content.
  add_fmt("fmt-empty-content", "", 0, false)
  add_fmt("fmt-whitespace-only", "   \n\t\n  ", 0, false)
  add_fmt("fmt-only-separators", "///|\n///|\n///|\n", 0, false)
  add_fmt("fmt-only-newline", "\n", 0, false)
  add_fmt("fmt-only-crlf", "\r\n", 0, false)
  // Multiple blocks, n in and out of range.
  add_fmt("fmt-multi-n0", ab_nl, 0, false)
  add_fmt("fmt-multi-n1-last", ab_nl, 1, false)
  add_fmt("fmt-multi-n2-too-large", ab_nl, 2, false)
  add_fmt("fmt-multi-n-neg", ab_nl, -1, false)
  add_fmt("fmt-multi-no-nl-n0", ab_no_nl, 0, false)
  add_fmt("fmt-multi-no-nl-n1-last", ab_no_nl, 1, false)
  add_fmt("fmt-multi-no-nl-n2-too-large", ab_no_nl, 2, false)
  add_fmt("fmt-multi-no-nl-n-neg", ab_no_nl, -1, false)
  add_fmt("fmt-triple-no-nl-n2-last", multi_no_nl, 2, false)
  add_fmt("fmt-triple-no-nl-n1-middle", multi_no_nl, 1, false)
  // Newline edge shapes.
  add_fmt("fmt-trailing-space", single_nl + " ", 0, false)
  add_fmt("fmt-trailing-space-no-nl", single_no_nl + " ", 0, false)
  add_fmt("fmt-crlf", crlf, 0, false)
  add_fmt("fmt-crlf-no-final-newline", crlf_no_nl, 0, false)
  add_fmt("fmt-ends-with-cr", single_no_nl + "\r", 0, false)
  add_fmt("fmt-ends-with-comment", comment, 0, false)
  add_fmt("fmt-ends-mid-token", mid_token, 0, false)
  add_fmt("fmt-separator-doc-no-nl", single_block_doc, 0, false)
  // Markdown mode.
  add_fmt("fmt-markdown-no-nl", single_no_nl, 0, true)
  add_fmt("fmt-markdown-with-nl", single_nl, 0, true)
  add_fmt("fmt-markdown-empty", "", 0, true)
  // Unicode and long lines.
  add_fmt("fmt-unicode-emoji-no-nl", emoji, 0, false)
  add_fmt("fmt-unicode-emoji-with-nl", emoji + "\n", 0, false)
  add_fmt("fmt-very-long-line", long_line, 0, false)
  add_fmt("fmt-very-long-line-nl", long_line + "\n", 0, false)
  let doc_cases = fn(
    cid : String,
    m : @lsp.RpcMethod,
    mode : String,
    open_text : String?,
    line : Int32,
    ch : Int32,
  ) {
    cs.push(case(cid, "documents", m.name(), Doc(m, mode, open_text, line, ch)))
  }
  // Opened document with a final newline: the normal path.
  doc_cases(
    "doc-format-opened",
    @lsp.Formatting,
    "opened",
    Some(single_nl),
    0,
    0,
  )
  doc_cases("doc-hover-eof", @lsp.Hover, "opened", Some(single_nl), 2, 1)
  doc_cases(
    "doc-completion-eof",
    @lsp.Completion,
    "opened",
    Some(single_nl),
    2,
    1,
  )
  doc_cases(
    "doc-symbol-opened",
    @lsp.DocumentSymbol,
    "opened",
    Some(single_nl),
    0,
    0,
  )
  doc_cases(
    "doc-diagnostic-opened",
    @lsp.Diagnostic,
    "opened",
    Some(single_nl),
    0,
    0,
  )
  // Opened document without a final newline.
  doc_cases(
    "doc-format-opened-no-nl",
    @lsp.Formatting,
    "opened",
    Some(single_no_nl),
    0,
    0,
  )
  doc_cases(
    "doc-hover-eof-no-nl",
    @lsp.Hover,
    "opened",
    Some(single_no_nl),
    2,
    1,
  )
  doc_cases(
    "doc-completion-eof-no-nl",
    @lsp.Completion,
    "opened",
    Some(single_no_nl),
    2,
    1,
  )
  doc_cases(
    "doc-symbol-opened-no-nl",
    @lsp.DocumentSymbol,
    "opened",
    Some(single_no_nl),
    0,
    0,
  )
  // Existing file that was never opened.
  doc_cases("doc-format-unopened", @lsp.Formatting, "unopened", None, 0, 0)
  doc_cases("doc-hover-unopened", @lsp.Hover, "unopened", None, 0, 0)
  doc_cases("doc-completion-unopened", @lsp.Completion, "unopened", None, 0, 0)
  doc_cases("doc-symbol-unopened", @lsp.DocumentSymbol, "unopened", None, 0, 0)
  // URI that does not exist on disk.
  doc_cases("doc-format-missing-file", @lsp.Formatting, "missing", None, 0, 0)
  doc_cases("doc-hover-missing-file", @lsp.Hover, "missing", None, 0, 0)
  doc_cases(
    "doc-completion-missing-file",
    @lsp.Completion,
    "missing",
    None,
    0,
    0,
  )
  doc_cases(
    "doc-symbol-missing-file",
    @lsp.DocumentSymbol,
    "missing",
    None,
    0,
    0,
  )
  // Positions outside the document.
  doc_cases("doc-hover-past-eof", @lsp.Hover, "opened", Some(single_nl), 99, 0)
  doc_cases(
    "doc-completion-past-eof",
    @lsp.Completion,
    "opened",
    Some(single_nl),
    99,
    0,
  )
  // Lifecycle and framing.
  cs.push(
    case(
      "life-shutdown-null",
      "lifecycle",
      "shutdown",
      ShutdownLiteral(Some("null")),
    ),
  )
  cs.push(
    case(
      "life-shutdown-omitted",
      "lifecycle",
      "shutdown",
      ShutdownLiteral(None),
    ),
  )
  cs.push(
    case(
      "life-shutdown-object",
      "lifecycle",
      "shutdown",
      ShutdownLiteral(Some("{}")),
    ),
  )
  cs.push(
    case(
      "life-shutdown-number",
      "lifecycle",
      "shutdown",
      ShutdownLiteral(Some("0")),
    ),
  )
  cs.push(
    case("life-shutdown-then-hover", "lifecycle", "shutdown", ShutdownThenHover),
  )
  cs.push(
    case("life-shutdown-then-exit", "lifecycle", "shutdown", ShutdownThenExit),
  )
  cs.push(case("life-unknown-method", "lifecycle", "unknown", UnknownMethod))
  cs.push(
    case(
      "frame-bad-json",
      "lifecycle",
      "malformed-json",
      Raw(@lsp.frame_message("{not json")),
    ),
  )
  cs.push(
    case(
      "frame-bad-content-length",
      "lifecycle",
      "bad-content-length",
      Raw("Content-Length: xyz\r\n\r\n{}"),
    ),
  )
  cs.push(
    case(
      "frame-no-header",
      "lifecycle",
      "no-header",
      Raw(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":{}}",
      ),
    ),
  )
  cs.push(
    case(
      "frame-length-too-small",
      "lifecycle",
      "content-length-small",
      Raw(
        "Content-Length: 5\r\n\r\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":{}}",
      ),
    ),
  )
  cs.push(
    case(
      "frame-length-too-large",
      "lifecycle",
      "content-length-large",
      Raw(
        "Content-Length: 200\r\n\r\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":{}}",
      ),
    ),
  )
  add_framing_cases(cs)
  add_method_cases(cs)
  cs
}

///|
fn replace_all(s : String, needle : String, repl : String) -> String {
  if needle == "" {
    return s
  }
  let b = StringBuilder()
  let n = needle.length()
  let mut i = 0
  while i < s.length() {
    if i + n <= s.length() && s[i:i + n].to_owned() == needle {
      b.write_string(repl)
      i += n
      continue
    }
    b.write_char(s.get_char(i).unwrap())
    i += 1
  }
  b.to_string()
}

///|
fn fstep(data : String, delay_ms : Int32) -> Step {
  { data, delay_ms, }
}

///|
/// Family A: transport/framing.  Every case sends bytes and then, where the
/// frame is not deliberately incomplete, a complete follow-up request id 3 so
/// "no error response" can be separated from "input loop is permanently
/// wedged".  Ids 2/3 are probes whose clean answer is -32601; that is a
/// perfectly valid response for a complete request.
fn add_framing_cases(cs : Array[Case]) -> Unit {
  let req2 = @lsp.encode_request(@lsp.unknown(2, "probe/no-such-method"))
  let req3 = @lsp.encode_request(@lsp.unknown(3, "probe/no-such-method"))
  let f2 = @lsp.frame_message(req2)
  let f3 = @lsp.frame_message(req3)
  let n = @utf8.encode(req2).length()
  let add = fn(
    cid : String,
    label : String,
    steps : Array[Step],
    expect : Array[Int32],
    kind : String,
    wait : Bool,
    known : String,
  ) {
    cs.push(
      probe_case(
        cid,
        "framing",
        label,
        Steps(steps),
        kind,
        expect,
        None,
        wait,
        known,
      ),
    )
  }
  // 1. Declared length larger than the body.  Alone this is a legitimate
  //    wait for more bytes and is excluded as EXPECTED_WAIT.
  add(
    "fr-larger-expect-wait",
    "content-length-too-large-alone",
    [fstep(@lsp.frame_declared(n + 200, req2), 0)],
    [2],
    "incomplete",
    true,
    "expected_wait",
  )
  // A complete follow-up request makes the oversized declaration observable.
  add(
    "fr-larger-then-valid",
    "content-length-too-large+next",
    [fstep(@lsp.frame_declared(n + 20, req2), 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "known_prior_silence",
  )
  add(
    "fr-larger-far-then-valid",
    "content-length-way-too-large+next",
    [fstep(@lsp.frame_declared(n + 400, req2), 0), fstep(f3, 60)],
    [2, 3],
    "incomplete",
    true,
    "expected_wait",
  )
  // 2. Declared length smaller than the body: the surplus bytes become a
  //    bogus header and the stream is desynchronised.
  add(
    "fr-short-then-valid",
    "content-length-too-small+next",
    [fstep(@lsp.frame_declared(5, req2), 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "known_prior_silence",
  )
  // 3. Header variants.
  add(
    "fr-missing-length-then-valid",
    "header-without-content-length+next",
    [fstep(@lsp.frame_with_header("X-Test: 1", req2), 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-wrong-header-name-then-valid",
    "content-lenght-typo+next",
    [
      fstep(@lsp.frame_with_header("Content-Lenght: " + n.to_string(), req2), 0),
      fstep(f3, 60),
    ],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-extra-content-type",
    "extra-content-type",
    [
      fstep(
        @lsp.frame_with_header(
          "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n" +
          "Content-Length: " +
          n.to_string(),
          req2,
        ),
        0,
      ),
    ],
    [2],
    "control",
    false,
    "",
  )
  add(
    "fr-extra-unknown-header",
    "extra-unknown-header",
    [
      fstep(
        @lsp.frame_with_header(
          "X-Foo: bar\r\nContent-Length: " + n.to_string(),
          req2,
        ),
        0,
      ),
    ],
    [2],
    "control",
    false,
    "",
  )
  add(
    "fr-lowercase-header",
    "lowercase-content-length",
    [fstep(@lsp.frame_with_header("content-length: " + n.to_string(), req2), 0)],
    [2],
    "control",
    false,
    "",
  )
  add(
    "fr-space-before-colon-then-valid",
    "space-before-colon+next",
    [
      fstep(
        @lsp.frame_with_header("Content-Length : " + n.to_string(), req2),
        0,
      ),
      fstep(f3, 60),
    ],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-extra-space-value",
    "space-after-colon",
    [
      fstep(
        @lsp.frame_with_header("Content-Length:   " + n.to_string(), req2),
        0,
      ),
    ],
    [2],
    "control",
    false,
    "",
  )
  add(
    "fr-trailing-crlf-between",
    "blank-line-between-frames",
    [fstep(f2 + "\r\n" + f3, 0)],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  // 4. Split writes.
  let (h1, h2) = @lsp.split_at(f2, 15)
  add(
    "fr-header-split",
    "header-split-across-writes",
    [fstep(h1, 0), fstep(h2, 50)],
    [2],
    "control",
    false,
    "",
  )
  let (b1, b2) = @lsp.split_at(f2, 45)
  add(
    "fr-body-split",
    "body-split-across-writes",
    [fstep(b1, 0), fstep(b2, 50)],
    [2],
    "control",
    false,
    "",
  )
  let bytewise : Array[Step] = []
  let mut off = 0
  while off < f2.length() {
    let (chunk, _) = @lsp.split_at(f2[off:].to_owned(), 9)
    bytewise.push(fstep(chunk, 15))
    off += 9
  }
  add(
    "fr-bytewise-split",
    "frame-in-nine-byte-writes",
    bytewise,
    [2],
    "control",
    false,
    "",
  )
  // 9. BOM and LF-only.
  add(
    "fr-bom-then-valid",
    "utf8-bom+next",
    [fstep("\u{feff}" + f2, 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-lf-only-header",
    "lf-only-terminator",
    [fstep(replace_all(f2, "\r\n", "\n"), 0)],
    [2],
    "control",
    false,
    "",
  )
  // 5. Valid JSON that is not a JSON-RPC object.
  add(
    "fr-top-array-then-valid",
    "top-level-array+next",
    [
      fstep(@lsp.frame_with_header("Content-Length: 5", "[1,2]"), 0),
      fstep(f3, 60),
    ],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-top-number-then-valid",
    "top-level-number+next",
    [fstep(@lsp.frame_with_header("Content-Length: 2", "42"), 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-top-string-then-valid",
    "top-level-string+next",
    [
      fstep(@lsp.frame_with_header("Content-Length: 3", "\"x\""), 0),
      fstep(f3, 60),
    ],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-top-null-then-valid",
    "top-level-null+next",
    [
      fstep(@lsp.frame_with_header("Content-Length: 4", "null"), 0),
      fstep(f3, 60),
    ],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  add(
    "fr-empty-body-then-valid",
    "content-length-zero+next",
    [fstep(@lsp.frame_declared(0, ""), 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "new_trigger",
  )
  // 6. Pipelining and duplicate ids.
  add(
    "fr-pipeline-two-valid",
    "two-valid-requests-one-write",
    [fstep(f2 + f3, 0)],
    [2, 3],
    "pipeline",
    false,
    "",
  )
  add(
    "fr-pipeline-valid-then-bad",
    "valid-then-malformed-one-write",
    [fstep(f2 + "Content-Length: 9\r\n\r\n{not json", 0)],
    [2],
    "mixed",
    false,
    "",
  )
  add(
    "fr-duplicate-id",
    "duplicate-id-two-responses",
    [fstep(f2 + f2, 0)],
    [2, 2],
    "dup",
    false,
    "",
  )
  // 7. Large single request.
  add(
    "fr-large-1mb",
    "1mb-params",
    [
      fstep(
        @lsp.frame_message(
          @lsp.encode_request(
            @lsp.raw_request(
              2,
              "probe/no-such-method",
              "{\"s\":\"" + "x".repeat(1024 * 1024) + "\"}",
            ),
          ),
        ),
        0,
      ),
    ],
    [2],
    "large",
    false,
    "",
  )
  add(
    "fr-large-8mb",
    "8mb-params",
    [
      fstep(
        @lsp.frame_message(
          @lsp.encode_request(
            @lsp.raw_request(
              2,
              "probe/no-such-method",
              "{\"s\":\"" + "x".repeat(8 * 1024 * 1024) + "\"}",
            ),
          ),
        ),
        0,
      ),
    ],
    [2],
    "large",
    false,
    "",
  )
  // 10. Request after a clean shutdown.
  let shutdown2 = @lsp.encode_request(@lsp.shutdown(2, Some("{}")))
  let shutdown3 = @lsp.encode_request(@lsp.shutdown(3, Some("{}")))
  add(
    "fr-shutdown-then-request",
    "shutdown-then-frame",
    [fstep(@lsp.frame_message(shutdown2), 0), fstep(f3, 80)],
    [2, 3],
    "lifecycle",
    false,
    "",
  )
  add(
    "fr-request-then-shutdown",
    "request-then-shutdown-one-write",
    [fstep(f2 + @lsp.frame_message(shutdown3), 0)],
    [2, 3],
    "lifecycle",
    false,
    "",
  )
  // Previously covered malformed shapes, now with a complete follow-up.
  add(
    "fr-bad-json-then-valid",
    "malformed-json+next",
    [fstep("Content-Length: 9\r\n\r\n{not json", 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "known_prior_silence",
  )
  add(
    "fr-no-header-then-valid",
    "headerless-json+next",
    [fstep(req2, 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "known_prior_silence",
  )
  add(
    "fr-bad-length-then-valid",
    "content-length-xyz+next",
    [fstep("Content-Length: xyz\r\n\r\n{}", 0), fstep(f3, 60)],
    [2, 3],
    "desync",
    false,
    "known_prior_silence",
  )
}

///|
/// Family B: only methods this binary advertises, plus two explicit
/// unadvertised checks.  Each advertised method gets (a) empty params,
/// (b) plausible params with a `didOpen` control, (c) plausible params for a
/// document that was never opened.
fn add_method_cases(cs : Array[Case]) -> Unit {
  let text = "fn f() -> Unit {\n  ()\n}\n"
  let pos = "\"position\":{\"line\":0,\"character\":3}"
  let range = "{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":5}}"
  let item = "{\"name\":\"f\",\"kind\":12,\"uri\":\"{{URI}}\",\"range\":" +
    range +
    ",\"selectionRange\":" +
    range +
    "}"
  let methods : Array[(String, String, String)] = [
    (
      "textDocument/definition",
      "definition",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," + pos + "}",
    ),
    (
      "textDocument/references",
      "references",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," +
      pos +
      ",\"context\":{\"includeDeclaration\":true}}",
    ),
    (
      "textDocument/rename",
      "rename",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," + pos + ",\"newName\":\"g\"}",
    ),
    (
      "textDocument/prepareRename",
      "prepare-rename",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," + pos + "}",
    ),
    (
      "textDocument/codeAction",
      "code-action",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"},\"range\":" +
      range +
      ",\"context\":{\"diagnostics\":[]}}",
    ),
    (
      "textDocument/codeLens", "code-lens", "{\"textDocument\":{\"uri\":\"{{URI}}\"}}",
    ),
    (
      "textDocument/inlayHint",
      "inlay-hint",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"},\"range\":" + range + "}",
    ),
    (
      "textDocument/foldingRange", "folding-range", "{\"textDocument\":{\"uri\":\"{{URI}}\"}}",
    ),
    (
      "textDocument/semanticTokens/full", "semantic-tokens-full", "{\"textDocument\":{\"uri\":\"{{URI}}\"}}",
    ),
    (
      "textDocument/signatureHelp",
      "signature-help",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," + pos + "}",
    ),
    ("workspace/symbol", "workspace-symbol", "{\"query\":\"f\"}"),
    ("callHierarchy/incomingCalls", "incoming-calls", "{\"item\":" + item + "}"),
    ("callHierarchy/outgoingCalls", "outgoing-calls", "{\"item\":" + item + "}"),
  ]
  for entry in methods {
    let (name, short, params) = entry
    cs.push(
      probe_case(
        "method-" + short + "-empty",
        "methods",
        name,
        Rpc(name, "{}", false),
        "method",
        [2],
        None,
        false,
        "",
      ),
    )
    cs.push(
      probe_case(
        "method-" + short + "-control",
        "methods",
        name,
        Rpc(name, params, true),
        "control",
        [2],
        Some(text),
        false,
        "",
      ),
    )
    cs.push(
      probe_case(
        "method-" + short + "-unopened",
        "methods",
        name,
        Rpc(name, params, false),
        "method",
        [2],
        None,
        false,
        "",
      ),
    )
  }
  // Names the task suggested but this binary does not advertise.  They are
  // kept so the -32601/-32603 verdict is recorded rather than assumed.
  let unadvertised : Array[(String, String, String)] = [
    (
      "textDocument/documentHighlight",
      "document-highlight",
      "{\"textDocument\":{\"uri\":\"{{URI}}\"}," + pos + "}",
    ),
    (
      "completionItem/resolve", "completion-resolve", "{\"label\":\"f\",\"kind\":3}",
    ),
  ]
  for entry in unadvertised {
    let (name, short, params) = entry
    cs.push(
      probe_case(
        "method-" + short + "-unadvertised",
        "methods",
        name,
        Rpc(name, params, true),
        "unsupported",
        [2],
        Some(text),
        false,
        "",
      ),
    )
  }
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
fn parse_digits(s : String, start : Int32) -> (Int32, Int32) {
  let mut i = start
  let mut v = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          v = v * 10 + (c.to_int() - 48)
          i += 1
        } else {
          break
        }
      None => break
    }
  }
  (v, i)
}

///|
/// Read a pseudo-file such as /proc/<pid>/stat.  `moonbitlang/x/fs` sizes the
/// read from `stat(2)`, which is 0 for procfs files, so it returns an empty
/// string; going through `cat` gives a real streaming read.
async fn read_proc(path : String) -> String {
  let res = @process.run(
    "/bin/cat",
    [path],
    stdout=@process.ProcessOutput::Collect,
    stderr=@process.ProcessOutput::Discard,
    cancel_handler=@process.hard_cancel(),
  )
  res.stdout_text() catch {
    _ => ""
  }
}

///|
/// Sample utime+stime (clock ticks) for `pid` from /proc.  Returns `None` when
/// the process is gone.
async fn cpu_ticks(pid : Int32) -> Int32? {
  let text = read_proc("/proc/" + pid.to_string() + "/stat")
  if text == "" {
    return None
  }
  // Field 2 is the command in parentheses; it may contain spaces, so skip to
  // the last ')'.  Fields 14 and 15 are utime and stime.
  let close = text.find(")")
  let idx = match close {
    Some(i) => i + 2
    None => return None
  }
  let mut i = idx
  let mut field = 3
  let mut utime = 0
  let mut stime = 0
  while i < text.length() && field <= 15 {
    // skip spaces
    while i < text.length() && text.get_char(i) == Some(' ') {
      i += 1
    }
    if field == 14 || field == 15 {
      let (v, next) = parse_digits(text, i)
      if field == 14 {
        utime = v
      } else {
        stime = v
      }
      i = next
    } else {
      while i < text.length() && text.get_char(i) != Some(' ') {
        i += 1
      }
    }
    field += 1
  }
  Some(utime + stime)
}

///|
enum ReadResult {
  Msg(String)
  Eof
  TimedOut
  BadHeader(String)
}

///|
async fn read_message(
  p : @process.OrphanProcess,
  timeout_ms : Int32,
) -> ReadResult {
  let maybe = @async.with_timeout_opt(timeout_ms, async fn() {
    let header = p.stdout.read_until(b"\r\n\r\n", include_delimiter=true)
    match header {
      None => Eof
      Some(h) => {
        let header_text = @utf8.decode_lossy(h)
        match @lsp.content_length(header_text) {
          None => BadHeader(header_text)
          Some(len) => Msg(@utf8.decode_lossy(p.stdout.read_exactly(len)))
        }
      }
    }
  })
  match maybe {
    None => TimedOut
    Some(r) => r
  }
}

///|
async fn send_bytes(p : @process.OrphanProcess, bytes : String) -> Unit {
  p.stdin.write(@utf8.encode(bytes))
}

///|
async fn send(p : @process.OrphanProcess, req : @lsp.Request) -> Unit {
  send_bytes(p, @lsp.frame_message(@lsp.encode_request(req)))
}

///|
fn now_ms() -> Int64 {
  @async.now()
}

///|
async fn wait_for_id(
  p : @process.OrphanProcess,
  id : Int32,
  timeout_ms : Int32,
) -> (ReadResult, Int64, Bool) {
  let t0 = now_ms()
  let deadline = t0 + timeout_ms.to_int64()
  let mut result = TimedOut
  let mut saw_response = false
  while now_ms() < deadline {
    let left = (deadline - now_ms()).to_int()
    if left <= 0 {
      break
    }
    match read_message(p, left) {
      Msg(body) => {
        let info = @lsp.inspect_response(body)
        if info.id == Some(id) {
          result = Msg(body)
          break
        }
        // Any response frame — including id:null or a string id — proves the
        // server was not silent.  TimedOut then means "unassociated", not
        // HANG.
        if info.is_response() {
          saw_response = true
        }
        // Diagnostic notifications and unrelated responses are skipped.
      }
      Eof => {
        result = Eof
        break
      }
      TimedOut => {
        result = TimedOut
        break
      }
      BadHeader(h) => {
        result = BadHeader(h)
        break
      }
    }
  }
  (result, now_ms() - t0, saw_response)
}

///|
async fn wait_any(
  p : @process.OrphanProcess,
  timeout_ms : Int32,
) -> (ReadResult, Int64) {
  let t0 = now_ms()
  let (r, _) = wait_for_any_msg(p, timeout_ms)
  (r, now_ms() - t0)
}

///|
async fn wait_for_any_msg(
  p : @process.OrphanProcess,
  timeout_ms : Int32,
) -> (ReadResult, Int64) {
  let t0 = now_ms()
  let deadline = t0 + timeout_ms.to_int64()
  let mut result = TimedOut
  while now_ms() < deadline {
    let left = (deadline - now_ms()).to_int()
    if left <= 0 {
      break
    }
    match read_message(p, left) {
      Msg(body) => {
        result = Msg(body)
        break
      }
      Eof => {
        result = Eof
        break
      }
      TimedOut => {
        result = TimedOut
        break
      }
      BadHeader(h) => {
        result = BadHeader(h)
        break
      }
    }
  }
  (result, now_ms() - t0)
}

///|
/// Liveness via /proc: a killed-but-unreaped child is a zombie, which still
/// has a /proc entry, so the state character must be inspected too.
async fn proc_alive(pid : Int32) -> Bool {
  let text = read_proc("/proc/" + pid.to_string() + "/stat")
  if text == "" {
    return false
  }
  match text.find(")") {
    None => false
    Some(i) => {
      let rest = text[i + 1:].to_owned().trim()
      match rest.get_char(0) {
        Some('Z') | Some('X') => false
        Some(_) => true
        None => false
      }
    }
  }
}

///|
/// One-line description of the case payload for the summary.
fn payload_of(a : Action) -> String {
  match a {
    FormatNth(c, n, md) =>
      "{\"content\":" +
      @lsp.json_quote(c) +
      ",\"n\":" +
      n.to_string() +
      ",\"isMarkdown\":" +
      (if md { "true" } else { "false" }) +
      "}"
    Doc(m, mode, text_opt, line, ch) =>
      m.name() +
      " uri_mode=" +
      mode +
      " didOpen=" +
      (match text_opt {
        Some(_) => "yes"
        None => "no"
      }) +
      " line=" +
      line.to_string() +
      " character=" +
      ch.to_string()
    ShutdownLiteral(p) =>
      "shutdown params=" +
      (match p {
        Some(v) => v
        None => "<omitted>"
      })
    ShutdownThenHover => "shutdown params=<omitted> then textDocument/hover"
    ShutdownThenExit => "shutdown params=<omitted> then exit"
    UnknownMethod => "moonbit-lsp/definitely-not-a-method params={}"
    Raw(b) => "raw=" + b
    Steps(steps) => {
      let mut total = 0
      for st in steps {
        total += st.data.length()
      }
      "frame steps=" +
      steps.length().to_string() +
      " chars=" +
      total.to_string()
    }
    Rpc(name, params, open) =>
      name +
      " params=" +
      params +
      " didOpen=" +
      (if open { "yes" } else { "no" })
  }
}

///|
async fn stop(p : @process.OrphanProcess) -> Int32 {
  p.stdin.close()
  // External kill: calling the async CancellationHandler value directly does
  // not schedule it, which previously left servers alive.
  let _ = @process.run(
    "/bin/kill",
    ["-9", p.pid.to_string()],
    stdout=@process.ProcessOutput::Discard,
    stderr=@process.ProcessOutput::Discard,
    cancel_handler=@process.hard_cancel(),
  )
  let rc = @async.with_timeout_opt(3000, async fn() { p.wait() })
  p.stdout.close()
  p.stderr.close()
  p.close()
  match rc {
    Some(code) => code
    None => -999
  }
}

///|
struct Row {
  cid : String
  family : String
  rpc_method : String
  stage : String
  outcome : @lsp.Outcome
  elapsed_ms : Int64
  cpu_pct : Int32
  excerpt : String
  signature : String
  repeats : Int32
  hits : Int32
  known : String
  rc : Int32
  payload : String
}

///|
fn excerpt_of(r : ReadResult) -> String {
  let s = match r {
    Msg(body) => body
    Eof => "<eof>"
    TimedOut => ""
    BadHeader(h) => "<bad-header:" + h + ">"
  }
  if s.length() > 240 {
    s[0:240].to_owned() + "..."
  } else {
    s
  }
}

///|
fn json_row(row : Row) -> String {
  let b = StringBuilder()
  b.write_string("{\"case\":")
  b.write_string(@lsp.json_quote(row.cid))
  b.write_string(",\"family\":")
  b.write_string(@lsp.json_quote(row.family))
  b.write_string(",\"method\":")
  b.write_string(@lsp.json_quote(row.rpc_method))
  b.write_string(",\"stage\":")
  b.write_string(@lsp.json_quote(row.stage))
  b.write_string(",\"outcome\":")
  b.write_string(@lsp.json_quote(row.outcome.to_string()))
  b.write_string(",\"elapsed_ms\":")
  b.write_string(row.elapsed_ms.to_string())
  b.write_string(",\"server_cpu_pct\":")
  b.write_string(row.cpu_pct.to_string())
  b.write_string(",\"response_excerpt\":")
  b.write_string(@lsp.json_quote(row.excerpt))
  b.write_string(",\"signature\":")
  b.write_string(@lsp.json_quote(row.signature))
  b.write_string(",\"repeats\":")
  b.write_string(row.repeats.to_string())
  b.write_string(",\"hits\":")
  b.write_string(row.hits.to_string())
  b.write_string(",\"known\":")
  b.write_string(@lsp.json_quote(row.known))
  b.write_string(",\"exit_code\":")
  b.write_string(row.rc.to_string())
  b.write_string(",\"payload\":")
  b.write_string(@lsp.json_quote(row.payload))
  b.write_string("}\n")
  b.to_string()
}

///|
fn write_project(dir : String, text : String) -> Unit {
  @fs.create_dir(dir) catch {
    _ => ()
  }
  @fs.write_string_to_file(
    join(dir, "moon.mod"),
    "name = \"probe/lsp\"\nversion = \"0.1.0\"\n",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file(join(dir, "a.mbt"), text) catch {
    _ => ()
  }
}

///|
fn cleanup_project(dir : String, keep : Bool) -> Unit {
  if !keep {
    @fs.remove_file(join(dir, "a.mbt")) catch {
      _ => ()
    }
    @fs.remove_file(join(dir, "moon.mod")) catch {
      _ => ()
    }
    @fs.remove_dir(dir) catch {
      _ => ()
    }
  }
}

///|
/// One response observed while collecting ids.  The body is kept so the
/// summary can quote the answer (for example the -32601 text of a probe).
struct Seen {
  id : Int32?
  has_error : Bool
  error_code : Int32?
  body : String
}

///|
struct Collect {
  seen : Array[Seen]
  /// At least one response frame arrived, whatever its id type.
  saw_response : Bool
  eof : Bool
  bad_header : String
  ms : Int64
}

///|
fn clip240(s : String) -> String {
  if s.length() > 240 {
    s[0:240].to_owned() + "..."
  } else {
    s
  }
}

///|
fn count_expected(seen : Array[Seen], id : Int32) -> Int32 {
  let mut n = 0
  for x in seen {
    if x.id == Some(id) {
      n += 1
    }
  }
  n
}

///|
fn count_wanted(expected : Array[Int32], id : Int32) -> Int32 {
  let mut n = 0
  for x in expected {
    if x == id {
      n += 1
    }
  }
  n
}

///|
fn expected_satisfied(seen : Array[Seen], expected : Array[Int32]) -> Bool {
  for id in expected {
    if count_expected(seen, id) < count_wanted(expected, id) {
      return false
    }
  }
  true
}

///|
/// Read responses until every expected id has arrived (duplicates counted) or
/// the timeout expires.  One bounded wait serves both single requests and
/// pipeline cases, and it cannot over-read: `read_message` consumes exactly
/// one frame.
async fn collect_responses(
  p : @process.OrphanProcess,
  expected : Array[Int32],
  timeout_ms : Int32,
) -> Collect {
  let t0 = now_ms()
  let deadline = t0 + timeout_ms.to_int64()
  let seen : Array[Seen] = []
  let mut saw_response = false
  let mut eof = false
  let mut bad = ""
  while now_ms() < deadline {
    let left = (deadline - now_ms()).to_int()
    if left <= 0 {
      break
    }
    match read_message(p, left) {
      Msg(body) => {
        let info = @lsp.inspect_response(body)
        if info.is_response() {
          saw_response = true
        }
        seen.push({
          id: info.id,
          has_error: info.has_error,
          error_code: info.error_code,
          body,
        })
        if expected_satisfied(seen, expected) {
          break
        }
      }
      Eof => {
        eof = true
        break
      }
      TimedOut => break
      BadHeader(h) => {
        bad = h
        break
      }
    }
  }
  { seen, saw_response, eof, bad_header: bad, ms: now_ms() - t0, }
}

///|
fn classify_collect(c : Case, col : Collect, alive : Bool) -> @lsp.Outcome {
  if col.eof || col.bad_header != "" {
    return @lsp.Crash
  }
  if expected_satisfied(col.seen, c.expect_ids) {
    if c.kind == "unsupported" {
      for x in col.seen {
        if x.error_code == Some(-32601) || x.error_code == Some(-32603) {
          return @lsp.Unsupported
        }
      }
      return @lsp.ErrorResponse
    }
    let mut err = false
    for x in col.seen {
      if x.has_error {
        err = true
      }
    }
    return if err { @lsp.ErrorResponse } else { @lsp.Ok }
  }
  if !alive {
    return @lsp.Crash
  }
  if c.expected_wait {
    return @lsp.Stall
  }
  if col.saw_response {
    // Some response frame arrived, just not the expected id(s).  The stream
    // was not silent, so this is DESYNC, never HANG.
    return @lsp.Desync
  }
  if c.kind == "method" {
    return @lsp.Hang
  }
  @lsp.Desync
}

///|
async fn run_once(
  server : String,
  case : Case,
  out_dir : String,
  timeout_ms : Int32,
  keep : Bool,
) -> Row {
  let dir = join(join(out_dir, "work"), case.cid)
  let uri = "file://" + join(dir, "a.mbt")
  let missing_uri = "file://" + join(dir, "missing.mbt")
  let mut use_uri = uri
  match case.action {
    FormatNth(content, _, _) => write_project(dir, content)
    Doc(_, uri_mode, text_opt, _, _) => {
      match text_opt {
        Some(t) => write_project(dir, t)
        None => write_project(dir, "fn f() -> Unit {\n  ()\n}\n")
      }
      if uri_mode == "missing" {
        use_uri = missing_uri
        @fs.remove_file(join(dir, "missing.mbt")) catch {
          _ => ()
        }
      }
    }
    _ => write_project(dir, "fn f() -> Unit {\n  ()\n}\n")
  }
  let p = @process.spawn_orphan(
    server,
    ["--stdio"],
    stdin=@process.ProcessInput::FeedFromParent,
    stdout=@process.ProcessOutput::Collect,
    stderr=@process.ProcessOutput::Collect,
    cwd=dir,
  )
  let mut stage = "initialize"
  let mut rc : Int32 = 0
  // Handshake.
  send(p, @lsp.initialize(1, Some("file://" + dir)))
  let c0 = cpu_ticks(p.pid)
  let (init_res, init_ms, init_saw_response) = wait_for_id(p, 1, timeout_ms)
  let c1 = cpu_ticks(p.pid)
  let init_ticks = match (c0, c1) {
    (Some(a), Some(b)) => b - a
    _ => 0
  }
  let init_cpu = if init_ms > 0 {
    init_ticks * 1000 / init_ms.to_int()
  } else {
    0
  }
  let init_info = match init_res {
    Msg(body) => Some(@lsp.inspect_response(body))
    _ => None
  }
  let mut done = false
  let mut outcome = @lsp.Ok
  let mut elapsed = init_ms
  let mut excerpt = excerpt_of(init_res)
  let mut cpu_pct = init_cpu
  let mut main_rc = 0
  if init_res is Eof || init_res is TimedOut {
    // Classify below; keep stage=initialize.
    outcome = @lsp.classify_stage(TimeoutAlive, true)
  } else if init_info is Some({ has_error: true, .. }) {
    outcome = @lsp.ErrorResponse
  } else {
    stage = "request"
    send(p, @lsp.initialized())
    let open_text = match case.action {
      Doc(_, _, Some(t), _, _) => Some(t)
      _ => case.open_text
    }
    match open_text {
      Some(t) => {
        send(p, @lsp.did_open(use_uri, t))
        @async.sleep(120)
      }
      None => ()
    }
    let req = match case.action {
      FormatNth(content, n, is_markdown) =>
        Some(@lsp.format_nth(2, content, n, is_markdown))
      Doc(rpc_method, _, _, line, character) => {
        let pos = if rpc_method == @lsp.Hover || rpc_method == @lsp.Completion {
          Some((line, character))
        } else {
          None
        }
        Some(@lsp.text_document_request(2, rpc_method, use_uri, pos))
      }
      ShutdownLiteral(params) => Some(@lsp.shutdown(2, params))
      ShutdownThenHover =>
        Some(@lsp.text_document_request(2, @lsp.Shutdown, use_uri, None))
      ShutdownThenExit => Some(@lsp.shutdown(2, None))
      UnknownMethod =>
        Some(@lsp.unknown(2, "moonbit-lsp/definitely-not-a-method"))
      Raw(_) => None
      Steps(_) => None
      Rpc(name, params, _) =>
        Some(@lsp.raw_request(2, name, replace_all(params, "{{URI}}", use_uri)))
    }
    match req {
      Some(r) => {
        let c2 = cpu_ticks(p.pid)
        send(p, r)
        let (res, ms, saw_response) = wait_for_id(p, 2, timeout_ms)
        elapsed = ms
        excerpt = excerpt_of(res)
        let c3 = cpu_ticks(p.pid)
        let ticks = match (c2, c3) {
          (Some(a), Some(b)) => b - a
          _ => 0
        }
        cpu_pct = if ms > 0 { ticks * 1000 / ms.to_int() } else { 0 }
        outcome = match res {
          Msg(body) => {
            let info = @lsp.inspect_response(body)
            if info.has_error {
              if case.kind == "unsupported" {
                @lsp.Unsupported
              } else {
                @lsp.ErrorResponse
              }
            } else {
              @lsp.Ok
            }
          }
          TimedOut => {
            let alive = proc_alive(p.pid)
            if !alive {
              @lsp.Crash
            } else if saw_response {
              // A response frame arrived, but not the id we wanted.  That is
              // unassociated traffic, never silence.
              @lsp.Desync
            } else {
              @lsp.Hang
            }
          }
          Eof => @lsp.Crash
          BadHeader(_) => @lsp.Crash
        }
        // Optional follow-up stages.
        match case.action {
          ShutdownThenHover =>
            if outcome == @lsp.Ok {
              send(
                p,
                @lsp.text_document_request(3, @lsp.Hover, use_uri, Some((0, 3))),
              )
              let (res2, ms2, saw_response2) = wait_for_id(p, 3, timeout_ms)
              elapsed += ms2
              if res2 is TimedOut && proc_alive(p.pid) {
                outcome = if saw_response2 { @lsp.Desync } else { @lsp.Hang }
              }
              excerpt = excerpt_of(res2)
            }
          ShutdownThenExit =>
            if outcome == @lsp.Ok {
              send(p, @lsp.exit())
              let exited = @async.with_timeout_opt(2000, async fn() { p.wait() })
              match exited {
                Some(code) => {
                  rc = code
                  outcome = if code == 0 { @lsp.Ok } else { @lsp.Crash }
                }
                None => outcome = @lsp.Hang
              }
              done = true
            }
          _ => ()
        }
      }
      None =>
        // Raw framing case: send bytes, then wait for any output.
        match case.action {
          Raw(bytes) => {
            let c2 = cpu_ticks(p.pid)
            send_bytes(p, bytes)
            let (res, ms) = wait_any(p, timeout_ms)
            elapsed = ms
            excerpt = excerpt_of(res)
            let c3 = cpu_ticks(p.pid)
            let ticks = match (c2, c3) {
              (Some(a), Some(b)) => b - a
              _ => 0
            }
            cpu_pct = if ms > 0 { ticks * 1000 / ms.to_int() } else { 0 }
            outcome = match res {
              Msg(body) => {
                let info = @lsp.inspect_response(body)
                if info.has_error {
                  @lsp.ErrorResponse
                } else {
                  @lsp.Ok
                }
              }
              Eof => @lsp.Crash
              BadHeader(_) => @lsp.Crash
              TimedOut =>
                if proc_alive(p.pid) {
                  if case.cid == "frame-length-too-large" {
                    // The message is deliberately incomplete: no response is
                    // expected by construction.
                    @lsp.Incomplete
                  } else {
                    @lsp.Hang
                  }
                } else {
                  @lsp.Crash
                }
            }
          }
          Steps(steps) => {
            let c2 = cpu_ticks(p.pid)
            for st in steps {
              send_bytes(p, st.data)
              if st.delay_ms > 0 {
                @async.sleep(st.delay_ms)
              }
            }
            let col = collect_responses(p, case.expect_ids, timeout_ms)
            elapsed = col.ms
            excerpt = if col.seen.length() > 0 {
              clip240(col.seen[col.seen.length() - 1].body)
            } else {
              ""
            }
            let c3 = cpu_ticks(p.pid)
            let ticks = match (c2, c3) {
              (Some(a), Some(b)) => b - a
              _ => 0
            }
            cpu_pct = if col.ms > 0 {
              ticks * 1000 / col.ms.to_int()
            } else {
              0
            }
            outcome = classify_collect(case, col, proc_alive(p.pid))
          }
          _ => ()
        }
    }
  }
  // Init-stage special cases: distinguish hang and crash.
  if stage == "initialize" && (init_res is TimedOut || init_res is Eof) {
    let alive = proc_alive(p.pid)
    match init_res {
      TimedOut =>
        outcome = if init_saw_response {
          @lsp.Desync
        } else if alive {
          @lsp.InitHang
        } else {
          @lsp.Crash
        }
      Eof => {
        outcome = @lsp.Crash
        rc = -1
      }
      _ => ()
    }
  }
  if !done {
    let code = stop(p)
    main_rc = code
  } else {
    p.stdin.close()
    p.stdout.close()
    p.stderr.close()
    p.close()
  }
  if rc == 0 {
    rc = main_rc
  }
  cleanup_project(dir, keep)
  let known = if outcome == @lsp.Hang && case.family == "format-nth" {
    // Every format-nth hang is the F10 shape: the last block has no trailing
    // newline and the formatter spins at ~100% CPU.
    "known_f10"
  } else if outcome == @lsp.Hang &&
    (case.cid == "life-shutdown-null" || case.cid == "life-shutdown-number") {
    // F11: any request whose params is a JSON scalar deadlocks at 0% CPU.
    "known_f11"
  } else if outcome == @lsp.Stall {
    "expected_wait"
  } else if outcome == @lsp.Desync {
    case.known_kind
  } else if outcome == @lsp.Hang && case.family == "lifecycle" {
    "known_prior_silence"
  } else {
    ""
  }
  {
    cid: case.cid,
    family: case.family,
    rpc_method: case.rpc_method,
    stage,
    outcome,
    elapsed_ms: elapsed,
    cpu_pct,
    excerpt,
    signature: @lsp.signature(outcome, case.rpc_method, rc),
    repeats: 1,
    hits: 1,
    known,
    rc,
    payload: payload_of(case.action),
  }
}

///|
async fn run_confirmed(
  server : String,
  case : Case,
  out_dir : String,
  timeout_ms : Int32,
  keep : Bool,
) -> Row {
  let first = run_once(server, case, out_dir, timeout_ms, keep)
  let candidate = first.outcome
  let interesting = candidate == @lsp.Hang ||
    candidate == @lsp.Crash ||
    candidate == @lsp.Desync ||
    candidate == @lsp.InitHang
  if !interesting {
    return first
  }
  let mut best = first
  let mut hits = 1
  let attempts = 3
  for i = 1; i < attempts; i = i + 1 {
    let r = run_once(server, case, out_dir, timeout_ms, keep)
    if r.outcome == candidate {
      hits += 1
    }
    best = r
  }
  let final_outcome = @lsp.confirm(candidate, attempts, hits)
  {
    cid: first.cid,
    family: first.family,
    rpc_method: first.rpc_method,
    stage: first.stage,
    outcome: final_outcome,
    elapsed_ms: best.elapsed_ms,
    cpu_pct: best.cpu_pct,
    excerpt: first.excerpt,
    signature: @lsp.signature(final_outcome, first.rpc_method, best.rc),
    repeats: attempts,
    hits,
    known: first.known,
    rc: best.rc,
    payload: first.payload,
  }
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 0
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn has_arg(args : Array[String], name : String) -> Bool {
  let mut found = false
  for a in args {
    if a == name {
      found = true
    }
  }
  found
}

///|
fn usage() -> Unit {
  println(
    "usage: lspfuzz --out ABS_DIR [--timeout-ms N] [--family all|framing|methods] [--cases all|format-nth|documents|all-methods] [--limit N] [--keep]",
  )
}

///|
async fn main {
  let args = @env.args()
  let out_dir = match arg_value(args, "--out") {
    Some(p) => p
    None => {
      usage()
      return
    }
  }
  let timeout_ms = match arg_value(args, "--timeout-ms") {
    Some(s) => @string.parse_int(s) catch { _ => 1200 }
    None => 1200
  }
  let selection = match arg_value(args, "--family") {
    Some(s) => s
    None =>
      match arg_value(args, "--cases") {
        Some(s) => s
        None => "all"
      }
  }
  let limit = match arg_value(args, "--limit") {
    Some(s) => @string.parse_int(s) catch { _ => 0 }
    None => 0
  }
  let keep = has_arg(args, "--keep")
  @fs.create_dir(out_dir) catch {
    _ => ()
  }
  @fs.create_dir(join(out_dir, "work")) catch {
    _ => ()
  }
  let server = match @env.get_env_var("MOON_LSP") {
    Some(p) => p
    None =>
      match @env.get_env_var("HOME") {
        Some(h) => h + "/.moon/bin/moon-lsp"
        None => "/usr/bin/moon-lsp"
      }
  }
  let all = build_cases()
  let selected : Array[Case] = []
  for c in all {
    let family_ok = selection == "all" ||
      (selection == "framing" && c.family == "framing") ||
      (selection == "methods" && c.family == "methods") ||
      (selection == "format-nth" && c.family == "format-nth") ||
      (selection == "documents" && c.family == "documents") ||
      (selection == "all-methods" && c.family != "format-nth")
    if family_ok {
      if limit == 0 || selected.length() < limit {
        selected.push(c)
      }
    }
  }
  println(
    "lspfuzz: " +
    selected.length().to_string() +
    " cases, timeout " +
    timeout_ms.to_string() +
    " ms, server " +
    server,
  )
  let rows : Array[Row] = []
  for c in selected {
    let row = run_confirmed(server, c, out_dir, timeout_ms, keep)
    println(
      row.cid +
      "  " +
      row.outcome.to_string() +
      "  " +
      row.elapsed_ms.to_string() +
      "ms  cpu=" +
      row.cpu_pct.to_string() +
      "%",
    )
    rows.push(row)
    // Write incrementally so an interrupted run still has evidence.
    let b = StringBuilder()
    for r in rows {
      b.write_string(json_row(r))
    }
    @fs.write_string_to_file(join(out_dir, "results.jsonl"), b.to_string()) catch {
      _ => ()
    }
  }
  // Summary.
  let counts : Map[String, Int32] = Map([])
  let hangs : Array[Row] = []
  let crashes : Array[Row] = []
  let desyncs : Array[Row] = []
  let stalls : Array[Row] = []
  for r in rows {
    let k = r.outcome.to_string()
    counts[k] = counts.get(k).unwrap_or(0) + 1
    if r.outcome == @lsp.Hang ||
      r.outcome == @lsp.FlakyHang ||
      r.outcome == @lsp.InitHang {
      hangs.push(r)
    }
    if r.outcome == @lsp.Crash || r.outcome == @lsp.FlakyCrash {
      crashes.push(r)
    }
    if r.outcome == @lsp.Desync || r.outcome == @lsp.FlakyDesync {
      desyncs.push(r)
    }
    if r.outcome == @lsp.Stall {
      stalls.push(r)
    }
  }
  let b = StringBuilder()
  b.write_string("{\n  \"cases\": ")
  b.write_string(rows.length().to_string())
  b.write_string(",\n  \"counts\": {")
  let mut first_count = true
  for k, v in counts {
    if !first_count {
      b.write_string(", ")
    }
    first_count = false
    b.write_string(@lsp.json_quote(k))
    b.write_string(": ")
    b.write_string(v.to_string())
  }
  b.write_string("},\n  \"signatures\": {")
  let sigs : Map[String, Int32] = Map([])
  for r in rows {
    if r.signature != "" {
      sigs[r.signature] = sigs.get(r.signature).unwrap_or(0) + 1
    }
  }
  let mut first_sig = true
  for k, v in sigs {
    if !first_sig {
      b.write_string(", ")
    }
    first_sig = false
    b.write_string(@lsp.json_quote(k))
    b.write_string(": ")
    b.write_string(v.to_string())
  }
  b.write_string("},\n  \"hangs\": [")
  let mut first_h = true
  for r in hangs {
    if !first_h {
      b.write_string(",")
    }
    first_h = false
    b.write_string("\n    {")
    b.write_string("\"case\": ")
    b.write_string(@lsp.json_quote(r.cid))
    b.write_string(", \"method\": ")
    b.write_string(@lsp.json_quote(r.rpc_method))
    b.write_string(", \"outcome\": ")
    b.write_string(@lsp.json_quote(r.outcome.to_string()))
    b.write_string(", \"known\": ")
    b.write_string(@lsp.json_quote(r.known))
    b.write_string(", \"repeats\": ")
    b.write_string(r.repeats.to_string())
    b.write_string(", \"hits\": ")
    b.write_string(r.hits.to_string())
    b.write_string(", \"server_cpu_pct\": ")
    b.write_string(r.cpu_pct.to_string())
    b.write_string(", \"payload\": ")
    b.write_string(@lsp.json_quote(r.payload))
    b.write_string("}")
  }
  b.write_string("\n  ],\n  \"crashes\": [")
  let mut first_c = true
  for r in crashes {
    if !first_c {
      b.write_string(",")
    }
    first_c = false
    b.write_string("\n    {")
    b.write_string("\"case\": ")
    b.write_string(@lsp.json_quote(r.cid))
    b.write_string(", \"outcome\": ")
    b.write_string(@lsp.json_quote(r.outcome.to_string()))
    b.write_string(", \"exit_code\": ")
    b.write_string(r.rc.to_string())
    b.write_string("}")
  }
  b.write_string("\n  ],\n  \"desyncs\": [")
  let mut first_d = true
  for r in desyncs {
    if !first_d {
      b.write_string(",")
    }
    first_d = false
    b.write_string("\n    {")
    b.write_string("\"case\": ")
    b.write_string(@lsp.json_quote(r.cid))
    b.write_string(", \"method\": ")
    b.write_string(@lsp.json_quote(r.rpc_method))
    b.write_string(", \"outcome\": ")
    b.write_string(@lsp.json_quote(r.outcome.to_string()))
    b.write_string(", \"known\": ")
    b.write_string(@lsp.json_quote(r.known))
    b.write_string(", \"repeats\": ")
    b.write_string(r.repeats.to_string())
    b.write_string(", \"hits\": ")
    b.write_string(r.hits.to_string())
    b.write_string(", \"elapsed_ms\": ")
    b.write_string(r.elapsed_ms.to_string())
    b.write_string(", \"server_cpu_pct\": ")
    b.write_string(r.cpu_pct.to_string())
    b.write_string("}")
  }
  b.write_string("\n  ],\n  \"stalls\": [")
  let mut first_s = true
  for r in stalls {
    if !first_s {
      b.write_string(",")
    }
    first_s = false
    b.write_string("\n    {\"case\": ")
    b.write_string(@lsp.json_quote(r.cid))
    b.write_string(", \"known\": ")
    b.write_string(@lsp.json_quote(r.known))
    b.write_string(", \"elapsed_ms\": ")
    b.write_string(r.elapsed_ms.to_string())
    b.write_string("}")
  }
  b.write_string("\n  ]\n}\n")
  @fs.write_string_to_file(join(out_dir, "summary.json"), b.to_string()) catch {
    _ => ()
  }
  println("summary written to " + join(out_dir, "summary.json"))
}
