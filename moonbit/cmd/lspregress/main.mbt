///|
/// LSP defect regression gate for F10, F11 and F12.
///
/// INVERTED ORACLE, ON PURPOSE.  Every `*-hang` case below asserts that a
/// *defect still exists*: `moon-lsp` must stay alive and silent past the
/// timeout.  A fix upstream is therefore a FAILURE of this command, not a
/// pass.  When a `*-hang` case fails with `observed=OK` (or any response),
/// do not "fix" the gate by flipping the expectation silently: follow the
/// procedure in `findings/lsp_regression.md` (update the PoC and
/// `findings/lsp_probe.md`, then re-classify the case as a control).
///
/// The gate is deliberately tiny and serial: each case gets one fresh
/// `moon-lsp --stdio`, at most one server is ever alive, and every case is
/// SIGKILLed and reaped on all paths before the next one starts.
///
/// Usage:
///   lspregress [--moon-lsp PATH] [--timeout-ms N] [--only case1,case2]
///
/// Output: one JSON line per selected case, then
///   {"ok":bool,"passed":N,"failed":N}
/// Exit codes: 0 all cases match, 1 any mismatch, 2 bad usage or missing
/// `moon-lsp` (a missing binary never counts as a pass).

///|
/// What a case asserts about the server's wire behaviour.
pub(all) enum Expected {
  /// No response frame of any kind within the deadline, process still alive.
  Hang
  /// F11 defect: a scalar-params request and a following complete request are
  /// *both* left unanswered, proving session-level loss rather than one
  /// dropped message.
  TwoRequestHang(Int32, Int32)
  /// A response with `id` arrives and its body contains `needle`.
  ResponseContains(Int32, String)
  /// A response with `id` arrives and its `error.code` equals `code`.
  ErrorCode(Int32, Int32)
  /// Every listed response id arrives, whether result or error.
  AllAnswered(Array[Int32])
}

///|
pub fn Expected::label(self : Expected) -> String {
  match self {
    Hang => "HANG"
    TwoRequestHang(_, _) => "HANG"
    ResponseContains(_, needle) => "RESPONSE(" + needle + ")"
    ErrorCode(_, code) => "ERROR(" + code.to_string() + ")"
    AllAnswered(ids) => "IDS" + ids_text(ids)
  }
}

///|
/// One observation of the server's stdout, reduced to response ids/bodies.
/// Notifications (no `id` member at all) are ignored: they are not responses.
pub(all) struct Wire {
  /// Correlated integer ids, in arrival order.
  ids : Array[Int32]
  /// Bodies aligned with `ids`.
  bodies : Array[String]
  /// Every response frame, regardless of id type.  A frame with `id: null`, a
  /// string id, or even an unparseable id lands here; only notifications do
  /// not.  `Hang` requires this to be empty.
  response_frames : Array[String]
  alive : Bool
  timed_out : Bool
  eof : Bool
  bad_header : String
}

///|
pub(all) struct Verdict {
  ok : Bool
  observed : String
  detail : String
}

///|
fn verdict(ok : Bool, observed : String, detail : String) -> Verdict {
  { ok, observed, detail, }
}

///|
pub fn ids_text(ids : Array[Int32]) -> String {
  let b = StringBuilder()
  b.write_string("[")
  let mut i = 0
  for id in ids {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(id.to_string())
    i += 1
  }
  b.write_string("]")
  b.to_string()
}

///|
fn body_for_id(w : Wire, id : Int32) -> String? {
  let mut i = 0
  while i < w.ids.length() {
    if w.ids[i] == id {
      return Some(w.bodies[i])
    }
    i += 1
  }
  None
}

///|
/// Short, stable label for a response body: `OK`, `ERROR -32602`, `ERROR`.
pub fn response_kind(body : String) -> String {
  let info = @lsp.inspect_response(body)
  if info.has_error {
    match info.error_code {
      Some(code) => "ERROR " + code.to_string()
      None => "ERROR"
    }
  } else {
    "OK"
  }
}

///|
/// Pure expectation matcher.  This is the whole oracle and it has no IO, so
/// the inverted-oracle semantics can be unit-tested without a server.
pub fn evaluate(e : Expected, w : Wire) -> Verdict {
  match e {
    Hang =>
      if w.bad_header != "" {
        verdict(
          false, "BAD_HEADER", "server produced an unreadable frame header",
        )
      } else if w.eof {
        verdict(false, "EXITED", "server exited before the deadline")
      } else if w.response_frames.length() > 0 {
        // Any response frame — even one whose id we cannot correlate — means
        // the server was not silent.  Never report HANG for this case.
        if w.ids.length() > 0 {
          verdict(
            false,
            response_kind(w.bodies[0]),
            "response id=" + w.ids[0].to_string() + " arrived; expected silence",
          )
        } else {
          verdict(
            false,
            "RESPONSE_UNASSOCIATED",
            "a response frame arrived but its id could not be correlated: " +
            clip(w.response_frames[0], 200),
          )
        }
      } else if !w.timed_out {
        verdict(
          false, "NO_RESPONSE", "wait ended without a response or timeout",
        )
      } else if !w.alive {
        verdict(false, "CRASH", "server is not alive after the timeout")
      } else {
        verdict(true, "HANG", "")
      }
    TwoRequestHang(first, second) =>
      if w.bad_header != "" {
        verdict(
          false, "BAD_HEADER", "server produced an unreadable frame header",
        )
      } else if w.eof {
        verdict(false, "EXITED", "server exited before the deadline")
      } else if body_for_id(w, first) is Some(body) {
        // The original scalar-params request was answered: F11 is fixed (or
        // this run did not reproduce it).
        verdict(
          false,
          response_kind(body),
          "first request id=" +
          first.to_string() +
          " was answered; expected silence",
        )
      } else if body_for_id(w, second) is Some(body) {
        // The follow-up complete request was answered even though the first
        // was not.  That is queue recovery, not the documented session-level
        // loss, so it must fail with its own message.
        verdict(
          false,
          "PARTIAL_RECOVERY",
          "second request id=" +
          second.to_string() +
          " was answered after the first was not; this is partial/queue " +
          "recovery, not the documented F11 session hang: " +
          clip(body, 200),
        )
      } else if w.response_frames.length() > 0 {
        verdict(
          false,
          "RESPONSE_UNASSOCIATED",
          "a response frame arrived but no expected id could be correlated: " +
          clip(w.response_frames[0], 200),
        )
      } else if !w.timed_out {
        verdict(
          false, "NO_RESPONSE", "wait ended without a response or timeout",
        )
      } else if !w.alive {
        verdict(false, "CRASH", "server is not alive after the timeout")
      } else {
        verdict(true, "HANG", "")
      }
    ResponseContains(id, needle) =>
      match body_for_id(w, id) {
        None =>
          verdict(
            false,
            "MISSING_ID",
            "no response with id " +
            id.to_string() +
            "; saw ids " +
            ids_text(w.ids),
          )
        Some(body) => {
          let info = @lsp.inspect_response(body)
          if info.has_error {
            verdict(
              false,
              response_kind(body),
              "expected a result containing " + needle,
            )
          } else if body.contains(needle) {
            verdict(true, "OK", "")
          } else {
            verdict(
              false,
              "NO_NEEDLE",
              "response id " +
              id.to_string() +
              " does not contain " +
              needle +
              ": " +
              clip(body, 160),
            )
          }
        }
      }
    ErrorCode(id, code) =>
      match body_for_id(w, id) {
        None =>
          verdict(
            false,
            "MISSING_ID",
            "no response with id " +
            id.to_string() +
            "; saw ids " +
            ids_text(w.ids),
          )
        Some(body) => {
          let info = @lsp.inspect_response(body)
          if !info.has_error {
            verdict(
              false,
              "OK",
              "expected error " + code.to_string() + ", got a result",
            )
          } else {
            match info.error_code {
              Some(got) =>
                if got == code {
                  verdict(true, "ERROR " + got.to_string(), "")
                } else {
                  verdict(
                    false,
                    "ERROR " + got.to_string(),
                    "expected error code " + code.to_string(),
                  )
                }
              None =>
                verdict(false, "ERROR", "error response has no numeric code")
            }
          }
        }
      }
    AllAnswered(ids) => {
      let missing : Array[Int32] = []
      for id in ids {
        match body_for_id(w, id) {
          None => missing.push(id)
          Some(_) => ()
        }
      }
      if missing.length() > 0 {
        verdict(
          false,
          "MISSING_IDS " + ids_text(missing),
          "saw ids " + ids_text(w.ids),
        )
      } else {
        // "Answered" means a response frame arrived for every id.  A
        // spec-conformant server may answer with an error (for example
        // InvalidRequest after shutdown), and that still proves the stream /
        // decode loop is healthy, which is what this control checks.
        verdict(true, "IDS " + ids_text(w.ids), "")
      }
    }
  }
}

///|
pub fn clip(s : String, n : Int32) -> String {
  if s.length() <= n {
    return s
  }
  s[0:n].to_owned() + "..."
}

///|
/// Pure missing-binary check.  `exists` is injected so the unit tests can
/// exercise both branches without touching the filesystem.
pub fn check_server(path : String, exists : (String) -> Bool) -> String? {
  if exists(path) {
    None
  } else {
    Some(
      "moon-lsp not found: " +
      path +
      " (install the MoonBit toolchain or pass --moon-lsp PATH)",
    )
  }
}

///|
pub fn expand_home(path : String, home : String) -> String {
  if path == "~" {
    home
  } else if path.has_prefix("~/") {
    join(home, path[2:].to_owned())
  } else {
    path
  }
}

///|
/// Parse a comma-separated `--only` list, trimming and dropping empty names.
pub fn parse_only(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split(",") {
    let t = part.trim().to_owned()
    if t.length() > 0 {
      out.push(t)
    }
  }
  out
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
enum Setup {
  /// `moonbit-lsp/format-nth` with an explicit content string.
  FormatNth(String)
  /// `textDocument/hover` with literal JSON params text.
  Hover(String)
  /// F12 trigger: `Content-Length: 5\r\n\r\n[1,2]`, then shutdown id 3.
  FrameWedge
  /// F12 control: two complete, well-formed `format-nth` requests in a row.
  TwoHealthy
  /// F11 defect: scalar-`params` hover (id 2) then a complete `format-nth`
  /// (id 3).  A healthy server answers both; the defect answers neither.
  HoverThenFormatNth
}

///|
struct CaseSpec {
  name : String
  expected : Expected
  setup : Setup
  /// "defect" asserts a bug exists; "control" asserts the happy path.
  kind : String
}

///|
fn case_spec(
  name : String,
  expected : Expected,
  setup : Setup,
  kind : String,
) -> CaseSpec {
  { name, expected, setup, kind, }
}

///|
/// Six cases, one canonical trigger and one control per defect.  Keep this
/// list small: every hang costs the full `--timeout-ms` on a loaded host.
fn build_cases() -> Array[CaseSpec] {
  [
    case_spec(
      "F10-hang",
      Hang,
      FormatNth("fn f() -> Unit {\n  ()\n}"),
      "defect",
    ),
    case_spec(
      "F10-control",
      ResponseContains(2, "newText"),
      FormatNth("fn f() -> Unit {\n  ()\n}\n"),
      "control",
    ),
    case_spec("F11-hang", TwoRequestHang(2, 3), HoverThenFormatNth, "defect"),
    case_spec("F11-control", ErrorCode(2, -32602), Hover("{}"), "control"),
    case_spec("F12-hang", Hang, FrameWedge, "defect"),
    case_spec("F12-control", AllAnswered([2, 3]), TwoHealthy, "control"),
  ]
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
struct Collected {
  ids : Array[Int32]
  bodies : Array[String]
  /// Response frames of any id kind (int, string, null, unparseable).
  frames : Array[String]
  timed_out : Bool
  eof : Bool
  bad_header : String
}

///|
fn satisfied(ids : Array[Int32], want : Array[Int32]) -> Bool {
  for id in want {
    let mut found = false
    for got in ids {
      if got == id {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
/// Read frames until every wanted id arrived or the deadline expires.  One
/// bounded wait serves both a single request and the two-shutdown control.
async fn collect(
  p : @process.OrphanProcess,
  want : Array[Int32],
  timeout_ms : Int32,
) -> Collected {
  let deadline = now_ms() + timeout_ms.to_int64()
  let ids : Array[Int32] = []
  let bodies : Array[String] = []
  let frames : Array[String] = []
  let mut timed_out = true
  let mut eof = false
  let mut bad_header = ""
  while now_ms() < deadline {
    let left = (deadline - now_ms()).to_int()
    if left <= 0 {
      break
    }
    match read_message(p, left) {
      Msg(body) => {
        let info = @lsp.inspect_response(body)
        if info.is_response() {
          // Record every response frame.  Correlation by integer id is a
          // separate concern; silence is not.
          frames.push(body)
          match info.id {
            Some(id) => {
              ids.push(id)
              bodies.push(body)
              if satisfied(ids, want) {
                timed_out = false
                break
              }
            }
            // id:null, a string id, or another uncorrelatable response.
            None => ()
          }
        }
      }
      Eof => {
        eof = true
        timed_out = false
        break
      }
      TimedOut => break
      BadHeader(h) => {
        bad_header = h
        timed_out = false
        break
      }
    }
  }
  { ids, bodies, frames, timed_out, eof, bad_header, }
}

///|
/// Read a pseudo-file such as /proc/<pid>/stat.  `moonbitlang/x/fs` sizes the
/// read from `stat(2)`, which is 0 for procfs files, so it returns an empty
/// string; `cat` gives a real streaming read.
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
/// Always SIGKILL and reap.  Writing to a wedged server's stdin first makes
/// the normal close path observable; the external `kill` is needed because
/// calling the async cancellation handler value directly does not schedule it.
async fn stop(p : @process.OrphanProcess) -> Int32 {
  p.stdin.close()
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
/// Drive one fresh server through initialize, one trigger and one bounded
/// observation.  Returns a Verdict; the caller owns `stop`.
async fn drive(
  p : @process.OrphanProcess,
  c : CaseSpec,
  timeout_ms : Int32,
) -> Verdict {
  send(p, @lsp.initialize(1, None))
  let init_res = {
    let deadline = now_ms() + timeout_ms.to_int64()
    let mut r = TimedOut
    while now_ms() < deadline {
      let left = (deadline - now_ms()).to_int()
      if left <= 0 {
        break
      }
      match read_message(p, left) {
        Msg(body) =>
          if @lsp.inspect_response(body).id == Some(1) {
            r = Msg(body)
            break
          }
        Eof => {
          r = Eof
          break
        }
        TimedOut => break
        BadHeader(h) => {
          r = BadHeader(h)
          break
        }
      }
    }
    r
  }
  match init_res {
    Msg(body) =>
      if @lsp.inspect_response(body).has_error {
        return verdict(false, "INIT_FAILED", "initialize returned an error")
      }
    Eof =>
      return verdict(false, "INIT_FAILED", "server exited during initialize")
    TimedOut => return verdict(false, "INIT_FAILED", "initialize timed out")
    BadHeader(_) =>
      return verdict(false, "INIT_FAILED", "unreadable initialize frame")
  }
  send(p, @lsp.initialized())
  @async.sleep(30)
  let want : Array[Int32] = match c.setup {
    FormatNth(_) | Hover(_) => [2]
    FrameWedge => [3]
    TwoHealthy => [2, 3]
    HoverThenFormatNth => [2, 3]
  }
  match c.setup {
    FormatNth(content) => send(p, @lsp.format_nth(2, content, 0, false))
    Hover(params) => send(p, @lsp.raw_request(2, "textDocument/hover", params))
    FrameWedge => {
      // The decoder rejects this frame (valid JSON, not a JSON-RPC object).
      send_bytes(p, "Content-Length: 5\r\n\r\n[1,2]")
      @async.sleep(50)
      send(p, @lsp.shutdown(3, Some("{}")))
    }
    TwoHealthy => {
      // Two complete, well-formed requests.  Both must be answered; unlike a
      // second `shutdown`, a non-lifecycle request is always legal here.
      send(p, @lsp.format_nth(2, "fn f() -> Unit {\n  ()\n}\n", 0, false))
      @async.sleep(30)
      send(p, @lsp.format_nth(3, "fn g() -> Unit {\n  ()\n}\n", 0, false))
    }
    HoverThenFormatNth => {
      // The F11 trigger: a scalar `params` wedges the request loop.  The
      // second request is complete and would answer in ~40 ms on a healthy
      // server, so silence for it proves session-level loss.
      send(p, @lsp.raw_request(2, "textDocument/hover", "null"))
      @async.sleep(100)
      send(p, @lsp.format_nth(3, "fn f() -> Unit {\n  ()\n}\n", 0, false))
    }
  }
  let col = collect(p, want, timeout_ms)
  let alive = proc_alive(p.pid)
  let wire = {
    ids: col.ids,
    bodies: col.bodies,
    response_frames: col.frames,
    alive,
    timed_out: col.timed_out,
    eof: col.eof,
    bad_header: col.bad_header,
  }
  evaluate(c.expected, wire)
}

///|
async fn run_case(
  server : String,
  c : CaseSpec,
  timeout_ms : Int32,
) -> (Verdict, Int64) {
  let t0 = now_ms()
  let p = @process.spawn_orphan(
    server,
    ["--stdio"],
    stdin=@process.ProcessInput::FeedFromParent,
    stdout=@process.ProcessOutput::Collect,
    stderr=@process.ProcessOutput::Collect,
    cwd="/tmp",
  )
  // defer-equivalent: whichever path drive takes, stop() runs exactly once.
  let v = drive(p, c, timeout_ms) catch {
    _ => verdict(false, "DRIVER_ERROR", "unexpected exception while driving")
  }
  let _ = stop(p)
  let result = v
  (result, now_ms() - t0)
}

///|
fn usage() -> Unit {
  println(
    "usage: lspregress [--moon-lsp PATH] [--timeout-ms N] [--only case1,case2]",
  )
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
async fn main {
  let args = @env.args()
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None => "/home/user"
  }
  let server_raw = match arg_value(args, "--moon-lsp") {
    Some(s) => s
    None => join(join(home, ".moon/bin"), "moon-lsp")
  }
  let server = expand_home(server_raw, home)
  let timeout_ms = match arg_value(args, "--timeout-ms") {
    Some(s) => {
      let n = @string.parse_int(s) catch { _ => -1 }
      if n > 0 {
        n
      } else {
        println("lspregress: --timeout-ms must be a positive integer, got " + s)
        @env.exit(2)
        0
      }
    }
    None => 2000
  }
  let only = match arg_value(args, "--only") {
    Some(s) => parse_only(s)
    None => []
  }
  if args.length() > 1 && (args[1] == "-h" || args[1] == "--help") {
    usage()
    return
  }
  // A missing binary is an operational error (2), never a silent pass and
  // never a per-case failure that could be misread as "defect fixed".
  match check_server(server, fn(p) { @fs.path_exists(p) }) {
    Some(msg) => {
      println("lspregress: " + msg)
      @env.exit(2)
    }
    None => ()
  }
  let all = build_cases()
  let selected : Array[CaseSpec] = []
  if only.length() == 0 {
    for c in all {
      selected.push(c)
    }
  } else {
    for name in only {
      let mut found = false
      for c in all {
        if c.name == name {
          selected.push(c)
          found = true
        }
      }
      if !found {
        println("lspregress: unknown case in --only: " + name)
        @env.exit(2)
      }
    }
  }
  if selected.length() == 0 {
    println("lspregress: no cases selected")
    @env.exit(2)
  }
  let mut passed = 0
  let mut failed = 0
  for c in selected {
    let (v, ms) = run_case(server, c, timeout_ms)
    let expected = c.expected.label()
    let ok_text = if v.ok { "true" } else { "false" }
    let line = "{\"case\":" +
      @lsp.json_quote(c.name) +
      ",\"expected\":" +
      @lsp.json_quote(expected) +
      ",\"observed\":" +
      @lsp.json_quote(v.observed) +
      ",\"ok\":" +
      ok_text +
      ",\"ms\":" +
      ms.to_string() +
      ",\"message\":" +
      @lsp.json_quote(
        if v.ok {
          ""
        } else if v.observed == "PARTIAL_RECOVERY" {
          c.name +
          ": PARTIAL_RECOVERY — the follow-up complete request was answered " +
          "while the first was not; this is queue recovery, not the " +
          "documented session-level defect, so the case is not confirmed (" +
          v.detail +
          ")"
        } else if c.kind == "defect" {
          c.name +
          ": expected " +
          expected +
          ", observed " +
          v.observed +
          " — defect appears fixed; update findings/lsp_probe.md and poc/" +
          (if v.detail == "" { "" } else { " (" + v.detail + ")" })
        } else {
          c.name +
          ": expected " +
          expected +
          ", observed " +
          v.observed +
          " — control regressed; do not trust the gate until this is explained" +
          (if v.detail == "" { "" } else { " (" + v.detail + ")" })
        },
      ) +
      "}"
    println(line)
    if v.ok {
      passed += 1
    } else {
      failed += 1
    }
    // Check the binary once more between cases: a toolchain change or a
    // deleted install mid-run should not turn into a pass for the rest.
    match check_server(server, fn(p) { @fs.path_exists(p) }) {
      Some(msg) => {
        println("lspregress: " + msg)
        @env.exit(2)
      }
      None => ()
    }
  }
  println(
    "{\"ok\":" +
    (if failed == 0 { "true" } else { "false" }) +
    ",\"passed\":" +
    passed.to_string() +
    ",\"failed\":" +
    failed.to_string() +
    "}",
  )
  if failed > 0 {
    @env.exit(1)
  }
}
