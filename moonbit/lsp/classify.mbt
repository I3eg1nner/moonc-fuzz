///|
/// What the probe observed, after the timeout/exit oracle has run.
#derive(Eq, Debug)
pub(all) enum Outcome {
  Ok
  ErrorResponse
  Hang
  FlakyHang
  FlakyCrash
  Crash
  InitHang
  /// Intentionally incomplete frame (declared Content-Length > bytes sent):
  /// no response is expected, so this is excluded from hang counts.
  Incomplete
  /// A complete frame was followed by bytes that cannot start a valid frame,
  /// or a malformed frame poisoned the input loop so a later complete request
  /// was never processed.  Distinct from HANG: the stream, not one request,
  /// is stuck.
  Desync
  FlakyDesync
  /// Server is alive and silent while a frame is legitimately incomplete.
  /// Excluded from defect counts as EXPECTED_WAIT.
  Stall
  /// Advertised-method probe name that this binary does not implement
  /// (-32601/-32603 and absent from `initialize` capabilities).
  Unsupported
}

///|
pub extend Outcome with Eq::{not_equal, equal}

///|
pub extend Outcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyntheticOutcome with Eq::{not_equal, equal}

///|
pub extend SyntheticOutcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Outcome::to_string(self : Outcome) -> String {
  match self {
    Ok => "OK"
    ErrorResponse => "ERROR_RESPONSE"
    Hang => "HANG"
    FlakyHang => "FLAKY_HANG"
    FlakyCrash => "FLAKY_CRASH"
    Crash => "CRASH"
    InitHang => "INIT_HANG"
    Incomplete => "INCOMPLETE"
    Desync => "DESYNC"
    FlakyDesync => "FLAKY_DESYNC"
    Stall => "STALL"
    Unsupported => "UNSUPPORTED"
  }
}

///|
/// Synthetic wire observation used by the pure classifier tests.
#derive(Eq, Debug)
pub(all) enum SyntheticOutcome {
  /// A response with the matching id arrived; `true` means no `error` key.
  Response(Bool)
  /// No response within the timeout and the process was still alive.
  TimeoutAlive
  /// No response and the process had exited with this code.
  TimeoutDead(Int32)
  /// The process exited without a request being outstanding (e.g. `exit`).
  Exited(Int32)
}

///|
pub fn classify(wire : SyntheticOutcome) -> Outcome {
  match wire {
    Response(true) => Ok
    Response(false) => ErrorResponse
    TimeoutAlive => Hang
    TimeoutDead(_) => Crash
    Exited(code) => if code == 0 { Ok } else { Crash }
  }
}

///|
/// Stage-aware classification: a hang while waiting for `initialize` means the
/// server never became usable, which is reported separately.
pub fn classify_stage(wire : SyntheticOutcome, initializing : Bool) -> Outcome {
  let o = classify(wire)
  let is_hang = match o {
    Hang => true
    _ => false
  }
  if initializing && is_hang {
    InitHang
  } else {
    o
  }
}

///|
/// Normalized crash signature: negative exit codes are signals.
pub fn crash_signature(rc : Int32) -> String {
  if rc < 0 {
    "crash:signal:" + (-rc).to_string()
  } else {
    "crash:exit:" + rc.to_string()
  }
}

///|
/// Normalized signature for the summary.  Stable outcomes get an empty
/// signature so only actionable shapes stand out.
pub fn signature(outcome : Outcome, rpc_method : String, rc : Int32) -> String {
  match outcome {
    Hang | FlakyHang => "hang:" + rpc_method
    Crash | FlakyCrash => crash_signature(rc)
    Desync | FlakyDesync => "desync:" + rpc_method
    _ => ""
  }
}

///|
/// Apply the 3/3 reproducibility rule.  `count` is the number of fresh
/// processes that exhibited the candidate outcome out of `attempts` total.
pub fn confirm(candidate : Outcome, attempts : Int32, count : Int32) -> Outcome {
  match candidate {
    Hang => if attempts >= 3 && count == attempts { Hang } else { FlakyHang }
    Crash => if attempts >= 3 && count == attempts { Crash } else { FlakyCrash }
    Desync =>
      if attempts >= 3 && count == attempts {
        Desync
      } else {
        FlakyDesync
      }
    other => other
  }
}
