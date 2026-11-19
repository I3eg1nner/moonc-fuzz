///|
/// See `moon.pkg` for what this measures.  The observation worth stating: a
/// negative corpus is only evidence if the same harness, on a bad session,
/// would have reported something.  `--self-test` sends the F11 trigger and
/// expects at least one finding, which fails the run if the detector is blind.

///|
enum ReadResult {
  Msg(String)
  Eof
  TimedOut
  BadHeader
}

///|
fn usage() -> Unit {
  println(
    "usage: lspneg [--sessions N] [--timeout-ms N] [--moon-lsp PATH] " +
    "[--json PATH] [--self-test]",
  )
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
          None => BadHeader
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
/// Read frames until one carries `id`, the peer closes, or time runs out.
/// Returns how many frames were read before that (0 means no answer at all).
async fn await_id(
  p : @process.OrphanProcess,
  id : Int32,
  timeout_ms : Int32,
) -> (Bool, Int32) {
  let deadline = now_ms() + timeout_ms.to_int64()
  let mut frames = 0
  let mut answered = false
  while now_ms() < deadline {
    let left = (deadline - now_ms()).to_int()
    if left <= 0 {
      break
    }
    match read_message(p, left) {
      Msg(body) => {
        frames += 1
        if @lsp.inspect_response(body).id == Some(id) {
          answered = true
          break
        }
      }
      Eof => break
      TimedOut => break
      BadHeader => break
    }
  }
  (answered, frames)
}

///|
fn proc_alive(pid : Int32) -> Bool {
  let text = @fs.read_file_to_string("/proc/" + pid.to_string() + "/stat") catch {
    _ => ""
  }
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
async fn stop(p : @process.OrphanProcess) -> Unit {
  p.stdin.close()
  let _ = @process.run(
    "/bin/kill",
    ["-9", p.pid.to_string()],
    stdout=@process.ProcessOutput::Discard,
    stderr=@process.ProcessOutput::Discard,
    cancel_handler=@process.hard_cancel(),
  )
  let _ = @async.with_timeout_opt(3000, async fn() { p.wait() })
  p.stdout.close()
  p.stderr.close()
  p.close()
}

///|
/// One benign request in the fixed sequence.
struct Probe {
  label : String
  req : @lsp.Request
}

///|
fn probes(uri : String) -> Array[Probe] {
  [
    {
      label: "hover",
      req: @lsp.text_document_request(2, @lsp.Hover, uri, Some((1, 3))),
    },
    {
      label: "documentSymbol",
      req: @lsp.text_document_request(3, @lsp.DocumentSymbol, uri, None),
    },
    {
      label: "completion",
      req: @lsp.text_document_request(4, @lsp.Completion, uri, Some((0, 4))),
    },
    {
      label: "formatting",
      req: @lsp.text_document_request(5, @lsp.Formatting, uri, None),
    },
    // Not advertised, but routed: an error response is still a response, so a
    // server that answers -32603 has not stalled.
    {
      label: "diagnostic-not-supported",
      req: @lsp.text_document_request(6, @lsp.Diagnostic, uri, None),
    },
    // Unknown method: -32601 is the healthy answer.
    {
      label: "unknown-method",
      req: @lsp.unknown(7, "textDocument/doesNotExist"),
    },
    // Empty object, not a scalar: the F11 control shape.
    {
      label: "hover-empty-params",
      req: @lsp.raw_request(8, "textDocument/hover", "{}"),
    },
  ]
}

///|
struct Row {
  session : Int32
  label : String
  answered : Bool
  frames : Int32
  ms : Int64
  findings : Int32
}

///|
fn observe(obs : @judge.Observation) -> Int32 {
  @judge.check_all(@judge.registry(), obs).length()
}

///|
async fn session(
  server : String,
  index : Int32,
  timeout_ms : Int32,
  rows_out : Array[Row],
) -> Unit {
  let p = @process.spawn_orphan(
    server,
    ["--stdio"],
    stdin=@process.ProcessInput::FeedFromParent,
    stdout=@process.ProcessOutput::Collect,
    stderr=@process.ProcessOutput::Collect,
    cwd="/tmp",
  )
  let path = "/tmp/lspneg_" + index.to_string() + ".mbt"
  // The file has to exist: a `didOpen` for a missing path makes moon-lsp
  // answer `null` to hover/symbol/completion in ~1 ms, which measures frame
  // plumbing but not the analysis path we actually care about.
  let _ = try {
    @fs.write_string_to_file(path, "fn main {\n  println(\"hello\")\n}\n")
    true
  } catch {
    _ => false
  }
  let uri = "file://" + path
  // initialize must answer before anything else is meaningful.
  send(p, @lsp.initialize(1, None))
  let (init_ok, _) = await_id(p, 1, timeout_ms)
  if !init_ok {
    rows_out.push({
      session: index,
      label: "initialize",
      answered: false,
      frames: 0,
      ms: 0L,
      findings: 1,
    })
    stop(p)
    return
  }
  send(p, @lsp.initialized())
  send(p, @lsp.did_open(uri, "fn main {\n  println(\"hello\")\n}\n"))
  @async.sleep(150)
  // Warm-up: the first analysis request pays for loading the file.  It is not
  // counted, because a cold start is not a stall - on a 2-core CI runner the
  // first hover can take >5 s while the server is simply working.
  send(p, @lsp.text_document_request(100, @lsp.DocumentSymbol, uri, None))
  // A cold analysis on a 2-core runner took >8 s in CI even after this warm-up
  // started, so the warm-up gets its own, much larger budget.  It is not
  // counted: slow is not stalled.
  let _ = await_id(p, 100, 60000)
  for pr in probes(uri) {
    let t0 = now_ms()
    send(p, pr.req)
    let id = match pr.req.id {
      Some(i) => i
      None => 0
    }
    let (answered, frames) = await_id(p, id, timeout_ms)
    let ms = now_ms() - t0
    let alive = proc_alive(p.pid)
    let obs = @judge.observation(
      "lsp",
      0,
      !answered,
      ms,
      ms,
      frames,
      true,
      alive,
      "",
      "",
    )
    let n = observe(obs)
    rows_out.push({
      session: index,
      label: pr.label,
      answered,
      frames,
      ms,
      findings: n,
    })
  }
  // Lifecycle tail: shutdown answers, exit does not.
  send(p, @lsp.shutdown(9, Some("{}")))
  let (shutdown_ok, _) = await_id(p, 9, timeout_ms)
  send(p, @lsp.exit())
  if !shutdown_ok {
    rows_out.push({
      session: index,
      label: "shutdown",
      answered: false,
      frames: 0,
      ms: 0L,
      findings: 1,
    })
  }
  stop(p)
}

///|
/// The blind-detector check: the F11 trigger must produce a finding.  Without
/// it, "0 findings in N sessions" could mean "nothing wrong" or "the probe
/// never reports anything".
async fn self_test(server : String, timeout_ms : Int32) -> Bool {
  let p = @process.spawn_orphan(
    server,
    ["--stdio"],
    stdin=@process.ProcessInput::FeedFromParent,
    stdout=@process.ProcessOutput::Collect,
    stderr=@process.ProcessOutput::Collect,
    cwd="/tmp",
  )
  send(p, @lsp.initialize(1, None))
  let (init_ok, _) = await_id(p, 1, timeout_ms)
  if !init_ok {
    stop(p)
    return false
  }
  send(p, @lsp.initialized())
  @async.sleep(50)
  send(p, @lsp.raw_request(2, "textDocument/hover", "null"))
  let (answered, frames) = await_id(p, 2, 1500)
  let alive = proc_alive(p.pid)
  let obs = @judge.observation(
    "lsp",
    0,
    !answered,
    1500L,
    8L,
    frames,
    true,
    alive,
    "",
    "",
  )
  let n = observe(obs)
  stop(p)
  n > 0
}

///|
fn arg_value(args : Array[String], name : String) -> String? {
  let mut i = 1
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn flag(args : Array[String], name : String) -> Bool {
  for a in args {
    if a == name {
      return true
    }
  }
  false
}

///|
fn upper95_zero(n : Int32) -> Double {
  if n <= 0 {
    0.0
  } else {
    3.0 / n.to_double()
  }
}

///|
async fn main {
  let args = @env.args()
  if flag(args, "--help") {
    usage()
    return
  }
  let sessions = match arg_value(args, "--sessions") {
    Some(s) => @stager.parse_int(s, 6)
    None => 6
  }
  let timeout_ms = match arg_value(args, "--timeout-ms") {
    Some(s) => @stager.parse_int(s, 15000)
    None => 15000
  }
  let server = match arg_value(args, "--moon-lsp") {
    Some(s) => s
    None => @stager.tool_path("moon-lsp")
  }
  let json_path = arg_value(args, "--json")
  if !@fs.path_exists(server) {
    println("lspneg: no moon-lsp at " + server)
    @env.exit(2)
  }
  let rows : Array[Row] = []
  for i in 0..<sessions {
    session(server, i, timeout_ms, rows)
  }
  let mut answered = 0
  let mut alarms = 0
  for r in rows {
    if r.answered {
      answered += 1
    }
    alarms += r.findings
  }
  let blind = self_test(server, timeout_ms)
  let b = StringBuilder()
  b.write_string("{\"sessions\":" + sessions.to_string())
  b.write_string(",\"observations\":" + rows.length().to_string())
  b.write_string(",\"answered\":" + answered.to_string())
  b.write_string(",\"false_alarms\":" + alarms.to_string())
  b.write_string(",\"upper95\":" + upper95_zero(rows.length()).to_string())
  b.write_string(
    ",\"detector_proven\":" + (if blind { "true" } else { "false" }),
  )
  b.write_string(",\"rows\":[")
  let mut first = true
  for r in rows {
    if !first {
      b.write_string(",")
    }
    first = false
    b.write_string("{\"session\":" + r.session.to_string())
    b.write_string(",\"probe\":\"" + r.label + "\"")
    b.write_string(
      ",\"answered\":" + (if r.answered { "true" } else { "false" }),
    )
    b.write_string(",\"frames\":" + r.frames.to_string())
    b.write_string(",\"ms\":" + r.ms.to_string())
    b.write_string(",\"findings\":" + r.findings.to_string())
    b.write_string("}")
  }
  b.write_string("]}")
  println(b.to_string())
  match json_path {
    Some(path) => {
      let _ = @stager.write_text(path, b.to_string())
    }
    None => ()
  }
  @env.exit(if blind { 0 } else { 1 })
}
