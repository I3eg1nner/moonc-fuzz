///|
/// A single observation of one staged invocation.  This is the whole input to
/// the oracle layer: everything an oracle is allowed to look at is here, so
/// verdicts are reproducible from a log line and cannot depend on hidden
/// driver state.
///
/// `cpu_ms` is deliberately separate from `wall_ms`.  It is the discriminator
/// between a busy loop (F10: 100% CPU, never answers) and a blocked read
/// (F11/F12: ~0% CPU, never answers).  Collapsing both into "timeout" loses
/// the only evidence that identifies the defect class.
pub(all) struct Observation {
  stage : String
  rc : Int32
  timed_out : Bool
  wall_ms : Int64
  cpu_ms : Int64
  stdout : String
  stderr : String
  /// Structured output units produced by this input (LSP frames, JSON lines,
  /// test cases reported).  Zero is meaningful, not "unknown".
  frames : Int32
  /// Whether this input is *supposed* to produce at least one frame.  A
  /// probe that legitimately prints nothing must set this to false, otherwise
  /// the missing-frame oracle becomes a false-positive machine.
  expects_frames : Bool
  /// True if the child was still alive when the harness stopped reading it.
  alive_after : Bool
}

///|
pub fn observation(
  stage : String,
  rc : Int32,
  timed_out : Bool,
  wall_ms : Int64,
  cpu_ms : Int64,
  frames : Int32,
  expects_frames : Bool,
  alive_after : Bool,
  stdout : String,
  stderr : String,
) -> Observation {
  {
    stage,
    rc,
    timed_out,
    wall_ms,
    cpu_ms,
    stdout,
    stderr,
    frames,
    expects_frames,
    alive_after,
  }
}

///|
/// How much a finding should cost the project if ignored.
pub(all) enum Severity {
  /// A wrong answer or a crash in the artifact under test.
  Defect
  /// Worth a human look; could be a defect or could be a slow machine.
  Suspicious
  /// Harness problem.  Never counted as a product defect.
  Infra
}

///|
pub fn severity_name(s : Severity) -> String {
  match s {
    Defect => "defect"
    Suspicious => "suspicious"
    Infra => "infra"
  }
}

///|
pub(all) struct Finding {
  oracle : String
  class : String
  severity : Severity
  signature : String
  detail : String
}

///|
pub fn Finding::to_json(self : Finding) -> String {
  let b = StringBuilder()
  b.write_string("{\"oracle\":\"")
  b.write_string(escape(self.oracle))
  b.write_string("\",\"class\":\"")
  b.write_string(escape(self.class))
  b.write_string("\",\"severity\":\"")
  b.write_string(severity_name(self.severity))
  b.write_string("\",\"signature\":\"")
  b.write_string(escape(self.signature))
  b.write_string("\",\"detail\":\"")
  b.write_string(escape(self.detail))
  b.write_string("\"}")
  b.to_string()
}

///|
fn escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '"' {
      b.write_string("\\\"")
    } else if c == '\\' {
      b.write_string("\\\\")
    } else if c == '\n' {
      b.write_string("\\n")
    } else if c == '\r' {
      b.write_string("\\r")
    } else if c == '\t' {
      b.write_string("\\t")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// The oracle vocabulary.  Adding a class of defect means adding a variant
/// here plus a probe in `probes.mbt`; the injection matrix fails until both
/// exist, so an oracle cannot ship unmeasured.
pub(all) enum OracleKind {
  /// Recognised crash markers and signal exits.
  Crash
  /// Timed out while burning CPU: a loop that never terminates.
  BusyHang
  /// Timed out with almost no CPU, process still alive, output owed but
  /// absent: a blocked read or a deadlock.
  BlockedStall
  /// Timed out for some other reason; too weak to call a defect on its own.
  TimeoutPlain
  /// Exited successfully while owing output, and produced none.
  MissingFrames
  /// Non-zero exit with no diagnostic at all: the user cannot act on it.
  NonzeroSilent
  /// Child survived the harness: a leak in the runner, not in the artifact.
  OrphanLeak
}

///|
pub fn kind_name(k : OracleKind) -> String {
  match k {
    Crash => "crash"
    BusyHang => "busy_hang"
    BlockedStall => "blocked_stall"
    TimeoutPlain => "timeout_plain"
    MissingFrames => "missing_frames"
    NonzeroSilent => "nonzero_silent"
    OrphanLeak => "orphan_leak"
  }
}

///|
pub fn kind_severity(k : OracleKind) -> Severity {
  match k {
    Crash => Defect
    BusyHang => Defect
    BlockedStall => Defect
    MissingFrames => Defect
    TimeoutPlain => Suspicious
    NonzeroSilent => Suspicious
    OrphanLeak => Infra
  }
}

///|
/// One registered oracle: a name, what it means, and how bad it is.
pub(all) struct OracleSpec {
  id : String
  kind : OracleKind
  note : String
}

///|
pub fn spec(kind : OracleKind, note : String) -> OracleSpec {
  { id: kind_name(kind), kind, note, }
}

///|
/// The full registry.  Order is stable so reports diff cleanly.
pub fn registry() -> Array[OracleSpec] {
  [
    spec(
      Crash,
      "compiler/harness crash markers, OOM, stack overflow, signal exit",
    ),
    spec(BusyHang, "wall-clock timeout with >=50% CPU: non-terminating loop"),
    spec(BlockedStall, "timeout with <50% CPU, still alive, output owed"),
    spec(TimeoutPlain, "timeout not explained by either hang shape"),
    spec(MissingFrames, "exit 0 while owing output and producing none"),
    spec(NonzeroSilent, "positive exit with no diagnostic text"),
    spec(OrphanLeak, "child alive after a non-timeout run"),
  ]
}

///|
/// Recognised crash classes, or `None`.  Kept byte-compatible with
/// `exec.classify` so a campaign can switch over without changing signatures.
fn crash_class(obs : Observation) -> String? {
  // Compiler markers are stderr-only.  A fuzzed program is free to print
  // "Oops..." on stdout, and letting that count would manufacture ICEs.
  let t = obs.stderr
  if t.contains("Oops, the compiler has encountered") {
    return Some("ICE")
  }
  if t.contains("out of memory") ||
    t.contains("Out_of_memory") ||
    t.contains("Cannot allocate memory") ||
    t.contains("Memprof") {
    return Some("OOM")
  }
  if t.contains("Fatal error: exception") {
    return Some("OCAML_EXN")
  }
  if t.contains("Stack overflow") || t.contains("Stack_overflow") {
    return Some("STACK")
  }
  if t.contains("Assert_failure") {
    return Some("ASSERT")
  }
  if obs.rc < 0 {
    return Some("SIG")
  }
  None
}

///|
/// The low-cardinality part of a crash signature: the first `Error:` line.
/// Two different ICEs share a class but not this string, which is what makes
/// "new signature" a usable novelty signal.
pub fn error_line(obs : Observation) -> String {
  let t = obs.stderr + "\n" + obs.stdout
  for line in t.split("\n") {
    let s = line.trim()
    if s.has_prefix("Error: ") {
      let v = s[7:]
      return if v.char_length() > 160 {
        v[0:160].to_owned()
      } else {
        v.to_owned()
      }
    }
  }
  ""
}

///|
/// True if the text carries any diagnostic a user could act on.
pub fn has_diagnostic(obs : Observation) -> Bool {
  let t = obs.stderr + "\n" + obs.stdout
  if t.contains("Error:") || t.contains("error:") {
    return true
  }
  // JSON diagnostics: {"level":"error"...} or a `code` field.
  for line in t.split("\n") {
    let s = line.trim()
    if s.has_prefix("{") && (s.contains("\"error\"") || s.contains("\"Error\"")) {
      return true
    }
  }
  false
}

///|
fn busy(obs : Observation) -> Bool {
  obs.timed_out && obs.cpu_ms * 2 >= obs.wall_ms
}

///|
fn stalled(obs : Observation) -> Bool {
  obs.timed_out &&
  obs.cpu_ms * 2 < obs.wall_ms &&
  obs.alive_after &&
  obs.expects_frames
}

///|
/// Run one oracle against one observation.  Returns at most one finding:
/// oracles are intentionally non-overlapping so a single observation cannot
/// inflate the defect count by firing three synonyms.
pub fn check(s : OracleSpec, obs : Observation) -> Array[Finding] {
  let out : Array[Finding] = []
  match s.kind {
    Crash =>
      match crash_class(obs) {
        Some(c) => {
          let detail = error_line(obs)
          out.push({
            oracle: s.id,
            class: c,
            severity: kind_severity(s.kind),
            signature: "crash|" + c + "|" + detail,
            detail,
          })
        }
        None => ()
      }
    BusyHang =>
      if busy(obs) {
        out.push({
          oracle: s.id,
          class: "hang/busy",
          severity: kind_severity(s.kind),
          signature: "hang/busy|" + obs.stage,
          detail: "cpu=" +
          obs.cpu_ms.to_string() +
          "ms wall=" +
          obs.wall_ms.to_string() +
          "ms",
        })
      }
    BlockedStall =>
      if stalled(obs) {
        out.push({
          oracle: s.id,
          class: "stall/blocked",
          severity: kind_severity(s.kind),
          signature: "stall/blocked|" +
          obs.stage +
          "|frames=" +
          obs.frames.to_string(),
          detail: "cpu=" +
          obs.cpu_ms.to_string() +
          "ms wall=" +
          obs.wall_ms.to_string() +
          "ms frames=" +
          obs.frames.to_string(),
        })
      }
    TimeoutPlain =>
      if obs.timed_out && !busy(obs) && !stalled(obs) {
        out.push({
          oracle: s.id,
          class: "timeout/plain",
          severity: kind_severity(s.kind),
          signature: "timeout/plain|" + obs.stage,
          detail: "cpu=" +
          obs.cpu_ms.to_string() +
          "ms wall=" +
          obs.wall_ms.to_string() +
          "ms",
        })
      }
    MissingFrames =>
      if !obs.timed_out && obs.expects_frames && obs.frames == 0 && obs.rc == 0 {
        out.push({
          oracle: s.id,
          class: "silence/ok",
          severity: kind_severity(s.kind),
          signature: "silence/ok|" + obs.stage,
          detail: "exit 0, owed output, frames=0",
        })
      }
    NonzeroSilent =>
      if !obs.timed_out &&
        obs.rc > 0 &&
        obs.stderr.trim().is_empty() &&
        !has_diagnostic(obs) {
        out.push({
          oracle: s.id,
          class: "err/silent",
          severity: kind_severity(s.kind),
          signature: "err/silent|" + obs.stage + "|rc=" + obs.rc.to_string(),
          detail: "rc=" + obs.rc.to_string() + ", no diagnostic",
        })
      }
    OrphanLeak =>
      if obs.alive_after && !obs.timed_out {
        out.push({
          oracle: s.id,
          class: "leak/alive",
          severity: kind_severity(s.kind),
          signature: "leak/alive|" + obs.stage,
          detail: "child survived a completed run",
        })
      }
  }
  out
}

///|
pub fn check_all(
  specs : Array[OracleSpec],
  obs : Observation,
) -> Array[Finding] {
  let out : Array[Finding] = []
  for s in specs {
    for f in check(s, obs) {
      out.push(f)
    }
  }
  out
}

///|
/// Pairwise oracle: the same source evaluated two ways must agree.  Kept
/// separate from the single-observation oracles because "agree" is not a
/// property of one run.
pub(all) enum PairKind {
  /// One side terminates, the other does not.
  TimeoutAsymmetry
  /// Exit codes differ.
  StatusAsymmetry
  /// Stdout differs while status agrees.
  StdoutAsymmetry
}

///|
pub fn pair_name(k : PairKind) -> String {
  match k {
    TimeoutAsymmetry => "pair/timeout"
    StatusAsymmetry => "pair/status"
    StdoutAsymmetry => "pair/stdout"
  }
}

///|
/// Compare two observations of the same input.  `left`/`right` are labels
/// such as backend names; they appear verbatim in the signature so a report
/// says *which* pair diverged.
pub fn compare(
  left : String,
  right : String,
  lo : Observation,
  ro : Observation,
) -> Array[Finding] {
  let out : Array[Finding] = []
  let tag = left + "!=" + right
  if lo.timed_out != ro.timed_out {
    out.push({
      oracle: "pair",
      class: pair_name(TimeoutAsymmetry),
      severity: Defect,
      signature: pair_name(TimeoutAsymmetry) + "|" + tag,
      detail: "left timed_out=" +
      lo.timed_out.to_string() +
      " right timed_out=" +
      ro.timed_out.to_string(),
    })
    // A timeout already explains any status difference; reporting both would
    // double-count one divergence.
    return out
  }
  if lo.rc != ro.rc {
    out.push({
      oracle: "pair",
      class: pair_name(StatusAsymmetry),
      severity: Defect,
      signature: pair_name(StatusAsymmetry) +
      "|" +
      tag +
      "|" +
      lo.rc.to_string() +
      "/" +
      ro.rc.to_string(),
      detail: "rc " + lo.rc.to_string() + " vs " + ro.rc.to_string(),
    })
  } else if lo.stdout != ro.stdout {
    out.push({
      oracle: "pair",
      class: pair_name(StdoutAsymmetry),
      severity: Defect,
      signature: pair_name(StdoutAsymmetry) + "|" + tag,
      detail: "stdout differs at equal status",
    })
  }
  out
}
