///|
/// Injection matrix for the oracle layer.
///
/// The claim this file exists to make falsifiable: *an oracle that has not
/// been shown to fire on a known defect is not evidence when it stays silent*.
/// Every probe below is a synthetic observation, but the shapes are copied
/// from defects this project already reproduced, so the matrix doubles as
/// regression evidence for the classifiers themselves.
///
/// Adding an oracle without adding a positive probe here fails the audit:
/// `unproven` is non-empty and `ok` is false.

///|
pub(all) struct Probe {
  label : String
  spec : String
  obs : Observation
  /// true  -> this observation must produce a finding
  /// false -> it must not
  want_hit : Bool
}

///|
fn clean(stage : String) -> Observation {
  observation(stage, 0, false, 120L, 40L, 2, true, false, "ok\n", "")
}

///|
/// Fixtures derived from reproduced defects.  The F-numbers match the PoCs in
/// `poc/` and the write-ups in `findings/`.
pub fn probes() -> Array[Probe] {
  [
    // ---- crash: the four markers we have actually seen ----
    {
      label: "f2/escape-ice",
      spec: "crash",
      obs: observation(
        "build", 1, false, 900L, 700L, 0, false, false, "", "Oops, the compiler has encountered an exception\nError: i32\n",
      ),
      want_hit: true,
    },
    {
      label: "f1/package-sigsegv",
      spec: "crash",
      obs: observation(
        "test-build", -11, false, 400L, 380L, 0, false, false, "", "",
      ),
      want_hit: true,
    },
    {
      label: "f3/parser-oom",
      spec: "crash",
      obs: observation(
        "check", 1, false, 1500L, 1400L, 0, false, false, "", "Fatal error: out of memory\n",
      ),
      want_hit: true,
    },
    {
      label: "control/crash-marker-on-stdout",
      spec: "crash",
      obs: observation(
        "test", 1, false, 200L, 150L, 1, true, false, "Oops, the compiler has encountered an exception\n",
        "",
      ),
      want_hit: false,
    },
    // ---- busy hang: F10, moon-lsp spins at 100% CPU ----
    {
      label: "f10/format-nth-busy",
      spec: "busy_hang",
      obs: observation("lsp", -1, true, 3000L, 2980L, 0, true, true, "", ""),
      want_hit: true,
    },
    {
      label: "control/blocked-is-not-busy",
      spec: "busy_hang",
      obs: observation("lsp", -1, true, 3000L, 8L, 0, true, true, "", ""),
      want_hit: false,
    },
    // ---- blocked stall: F11 scalar params, F12 BOM header ----
    {
      label: "f11/scalar-params-stall",
      spec: "blocked_stall",
      obs: observation("lsp", -1, true, 3000L, 8L, 0, true, true, "", ""),
      want_hit: true,
    },
    {
      label: "f12/bom-header-stall",
      spec: "blocked_stall",
      obs: observation("lsp", -1, true, 3000L, 5L, 0, true, true, "", ""),
      want_hit: true,
    },
    {
      label: "control/stall-needs-output-contract",
      spec: "blocked_stall",
      obs: observation("lsp", -1, true, 3000L, 8L, 0, false, true, "", ""),
      want_hit: false,
    },
    {
      label: "control/stall-needs-live-child",
      spec: "blocked_stall",
      obs: observation("lsp", -1, true, 3000L, 8L, 0, true, false, "", ""),
      want_hit: false,
    },
    // ---- plain timeout: slow but reaped ----
    {
      label: "slow/io-timeout",
      spec: "timeout_plain",
      obs: observation("build", -1, true, 5000L, 20L, 0, true, false, "", ""),
      want_hit: true,
    },
    {
      label: "control/busy-is-not-plain",
      spec: "timeout_plain",
      obs: observation("lsp", -1, true, 3000L, 2980L, 0, true, true, "", ""),
      want_hit: false,
    },
    // ---- silent success while owing output ----
    {
      label: "silence/ok-owes-frames",
      spec: "missing_frames",
      obs: observation("run", 0, false, 90L, 60L, 0, true, false, "", ""),
      want_hit: true,
    },
    {
      label: "control/no-output-expected",
      spec: "missing_frames",
      obs: observation("run", 0, false, 90L, 60L, 0, false, false, "", ""),
      want_hit: false,
    },
    {
      label: "control/clean-with-frames",
      spec: "missing_frames",
      obs: clean("run"),
      want_hit: false,
    },
    // ---- non-zero exit with nothing to read ----
    {
      label: "silent/rc1-empty-stderr",
      spec: "nonzero_silent",
      obs: observation("test", 1, false, 300L, 250L, 0, false, false, "", ""),
      want_hit: true,
    },
    {
      label: "control/rc1-has-error-line",
      spec: "nonzero_silent",
      obs: observation(
        "test", 1, false, 300L, 250L, 0, false, false, "", "Error: boom\n",
      ),
      want_hit: false,
    },
    // ---- runner leak ----
    {
      label: "leak/alive-after-run",
      spec: "orphan_leak",
      obs: observation("run", 0, false, 100L, 80L, 1, true, true, "ok\n", ""),
      want_hit: true,
    },
    {
      label: "control/reaped",
      spec: "orphan_leak",
      obs: clean("run"),
      want_hit: false,
    },
  ]
}

///|
/// Observations that must not trigger *any* oracle.  This is the specificity
/// floor: it catches an oracle that is sensitive but sloppy, which a
/// per-oracle negative list alone would miss.
pub fn global_negatives() -> Array[Probe] {
  [
    { label: "clean/pass", spec: "*", obs: clean("test"), want_hit: false, },
    {
      label: "warn/only",
      spec: "*",
      obs: observation(
        "build", 0, false, 500L, 450L, 1, true, false, "", "warning: unused variable x\n",
      ),
      want_hit: false,
    },
    {
      label: "legit/no-output",
      spec: "*",
      obs: observation("run", 0, false, 40L, 20L, 0, false, false, "", ""),
      want_hit: false,
    },
  ]
}

///|
pub(all) struct Score {
  spec : String
  positives : Int32
  caught : Int32
  negatives : Int32
  false_pos : Int32
  missed : Array[String]
  spurious : Array[String]
}

///|
/// True when this oracle has both a positive probe and perfect behaviour on
/// the whole matrix.  An unproven oracle scores false, never "vacuously true".
pub fn Score::sensitive(self : Score) -> Bool {
  self.positives > 0 && self.caught == self.positives && self.false_pos == 0
}

///|
pub fn Score::to_json(self : Score) -> String {
  let b = StringBuilder()
  b.write_string("{\"oracle\":\"")
  b.write_string(self.spec)
  b.write_string("\",\"positives\":")
  b.write_string(self.positives.to_string())
  b.write_string(",\"caught\":")
  b.write_string(self.caught.to_string())
  b.write_string(",\"negatives\":")
  b.write_string(self.negatives.to_string())
  b.write_string(",\"false_positives\":")
  b.write_string(self.false_pos.to_string())
  b.write_string(",\"sensitive\":")
  b.write_string(if self.sensitive() { "true" } else { "false" })
  b.write_string(",\"missed\":[")
  for i, m in self.missed {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
    b.write_string(m)
    b.write_string("\"")
  }
  b.write_string("],\"spurious\":[")
  for i, m in self.spurious {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
    b.write_string(m)
    b.write_string("\"")
  }
  b.write_string("]}")
  b.to_string()
}

///|
/// Score every oracle against the injection matrix.
pub fn score(
  specs : Array[OracleSpec],
  probes : Array[Probe],
  globals : Array[Probe],
) -> Array[Score] {
  let out : Array[Score] = []
  for s in specs {
    let missed : Array[String] = []
    let spurious : Array[String] = []
    let mut positives = 0
    let mut caught = 0
    let mut negatives = 0
    let mut false_pos = 0
    for p in probes {
      if p.spec == s.id {
        let hit = check(s, p.obs).length() > 0
        if p.want_hit {
          positives += 1
          if hit {
            caught += 1
          } else {
            missed.push(p.label)
          }
        } else {
          negatives += 1
          if hit {
            false_pos += 1
            spurious.push(p.label)
          }
        }
      }
    }
    for p in globals {
      negatives += 1
      if check(s, p.obs).length() > 0 {
        false_pos += 1
        spurious.push(p.label)
      }
    }
    out.push({
      spec: s.id,
      positives,
      caught,
      negatives,
      false_pos,
      missed,
      spurious,
    })
  }
  out
}

///|
/// Aggregate audit result.  `ok` is the gate: every registry entry proven,
/// nothing blind, nothing noisy.
pub(all) struct Audit {
  scores : Array[Score]
  unproven : Array[String]
  blind : Array[String]
  noisy : Array[String]
}

///|
pub fn Audit::ok(self : Audit) -> Bool {
  self.unproven.length() == 0 &&
  self.blind.length() == 0 &&
  self.noisy.length() == 0
}

///|
pub fn audit(
  specs : Array[OracleSpec],
  probes : Array[Probe],
  globals : Array[Probe],
) -> Audit {
  let scores = score(specs, probes, globals)
  let unproven : Array[String] = []
  let blind : Array[String] = []
  let noisy : Array[String] = []
  for s in scores {
    if s.positives == 0 {
      unproven.push(s.spec)
    } else if s.caught < s.positives {
      blind.push(s.spec)
    }
    if s.false_pos > 0 {
      noisy.push(s.spec)
    }
  }
  { scores, unproven, blind, noisy, }
}

///|
pub fn Audit::to_json(self : Audit) -> String {
  let b = StringBuilder()
  b.write_string("{\"ok\":")
  b.write_string(if self.ok() { "true" } else { "false" })
  b.write_string(",\"oracles\":[")
  for i, s in self.scores {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string(s.to_json())
  }
  b.write_string("],\"unproven\":[")
  for i, s in self.unproven {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
    b.write_string(s)
    b.write_string("\"")
  }
  b.write_string("],\"blind\":[")
  for i, s in self.blind {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
    b.write_string(s)
    b.write_string("\"")
  }
  b.write_string("],\"noisy\":[")
  for i, s in self.noisy {
    if i > 0 {
      b.write_string(",")
    }
    b.write_string("\"")
    b.write_string(s)
    b.write_string("\"")
  }
  b.write_string("]}")
  b.to_string()
}
