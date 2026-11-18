///|
/// Curated matrix and driver for `moon-lsp` stdio JSON-RPC probing.
///
/// Oracle: a matching response is OK/ERROR_RESPONSE, silence past the timeout
/// with a live process is HANG, an exited process is CRASH.  Every case gets
/// a fresh server because one unresponsive request poisons the queue.

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
}

///|
struct Case {
  cid : String
  family : String
  rpc_method : String
  action : Action
}

///|
fn case(
  cid : String,
  family : String,
  rpc_method : String,
  action : Action,
) -> Case {
  { cid, family, rpc_method, action, }
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
  cs
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
        let info = @lsp.inspect_response(body)
        if info.id == Some(id) {
          result = Msg(body)
          break
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
  (result, now_ms() - t0)
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
  let (init_res, init_ms) = wait_for_id(p, 1, timeout_ms)
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
    match case.action {
      Doc(_, _, Some(t), _, _) => {
        send(p, @lsp.did_open(use_uri, t))
        @async.sleep(120)
      }
      _ => ()
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
    }
    match req {
      Some(r) => {
        let c2 = cpu_ticks(p.pid)
        send(p, r)
        let (res, ms) = wait_for_id(p, 2, timeout_ms)
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
          TimedOut => {
            let alive = proc_alive(p.pid)
            if alive {
              @lsp.Hang
            } else {
              @lsp.Crash
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
              let (res2, ms2) = wait_for_id(p, 3, timeout_ms)
              elapsed += ms2
              if res2 is TimedOut && proc_alive(p.pid) {
                outcome = @lsp.Hang
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
          _ => ()
        }
    }
  }
  // Init-stage special cases: distinguish hang and crash.
  if stage == "initialize" && (init_res is TimedOut || init_res is Eof) {
    let alive = proc_alive(p.pid)
    match init_res {
      TimedOut => outcome = if alive { @lsp.InitHang } else { @lsp.Crash }
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
  let known = if case.cid == "fmt-f10-exact-no-final-newline" &&
    outcome == @lsp.Hang {
    "known_f10"
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
    "usage: lspfuzz --out ABS_DIR [--timeout-ms N] [--cases all|format-nth|documents|all-methods] [--limit N] [--keep]",
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
  let selection = match arg_value(args, "--cases") {
    Some(s) => s
    None => "all"
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
  b.write_string("\n  ]\n}\n")
  @fs.write_string_to_file(join(out_dir, "summary.json"), b.to_string()) catch {
    _ => ()
  }
  println("summary written to " + join(out_dir, "summary.json"))
}
