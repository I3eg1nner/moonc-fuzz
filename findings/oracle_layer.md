# Oracle layer: defect verdicts are measured, not assumed

Date: 2026-11-19
Status: implemented, gated by `cmd/accept` (`oracle_sensitivity`)

## The observation that forced this

Twelve reproduced defects, sorted by how they were found:

| How it was found | Defects |
|---|---|
| read an upstream issue | F8, F9, F10 |
| hand-designed feature matrix | F7 (featfuzz later reproduced it) |
| predicate "output was owed and never arrived" | F11, F12 |
| campaign (`cmd/fuzz`, IR probes, xdiff, real packages) | **none** |

The four largest campaigns executed tens of thousands of inputs and found
nothing. The single most productive artefact in the project is a one-line
predicate. That is an oracle problem, not a sample-size problem, and it cannot
be fixed by running the same oracles longer.

## What the layer is

`moonbit/judge` is a pure package: one `Observation` in, zero or more
`Finding`s out. No process spawning, no file IO, so the whole injection matrix
is deterministic.

```moonbit
pub(all) struct Observation {
  stage : String
  rc : Int32
  timed_out : Bool
  wall_ms : Int64
  cpu_ms : Int64          // the hang discriminator, see below
  stdout : String
  stderr : String
  frames : Int32          // structured outputs produced
  expects_frames : Bool   // whether this input owes output at all
  alive_after : Bool      // child still alive when we stopped reading
}
```

`cpu_ms` is not decoration. F10 spins at 100% CPU and never answers; F11/F12
block on a read at ~0% CPU and never answer. Wall-clock time alone collapses
both into `HANG` and loses the only field that identifies the defect class.
`expects_frames` is the same idea for silence: a probe that legitimately prints
nothing must not be scored as a missing response.

## Registry

| oracle | severity | fires when | shape copied from |
|---|---|---|---|
| `crash` | defect | ICE / OOM / stack overflow / assert / negative rc | F1, F2, F3 |
| `busy_hang` | defect | timeout and `cpu >= wall/2` | F10 |
| `blocked_stall` | defect | timeout, `cpu < wall/2`, alive, output owed | F11, F12 |
| `timeout_plain` | suspicious | timeout not explained by either shape | slow I/O |
| `missing_frames` | defect | exit 0, output owed, none produced | contract probe |
| `nonzero_silent` | suspicious | positive exit, no diagnostic text | unattributed failures |
| `orphan_leak` | infra | child alive after a completed run | harness bug |

The three "hang" oracles are deliberately non-overlapping: an observation can
fire `busy_hang` or `blocked_stall` or `timeout_plain`, never two of them, so a
single stall cannot inflate the defect count by matching synonyms. The one
intentional double-report is an ICE that also burns CPU: that is two real
properties of one run, and `check_all` reports both.

An `infra` finding never counts as a product defect. `orphan_leak` exists so
runner bugs are named as runner bugs instead of being filed upstream.

## Injection matrix

`judge/probes.mbt` holds 19 fixtures: 12 positives and 7 per-oracle controls,
plus 3 global negatives that every oracle must stay silent on.

Current result (`oracleaudit`, exit 0):

| oracle | positives | caught | controls | false positives |
|---|---|---|---|---|
| crash | 3 | 3 | 4 | 0 |
| busy_hang | 1 | 1 | 4 | 0 |
| blocked_stall | 2 | 2 | 5 | 0 |
| timeout_plain | 1 | 1 | 4 | 0 |
| missing_frames | 1 | 1 | 5 | 0 |
| nonzero_silent | 1 | 1 | 4 | 0 |
| orphan_leak | 1 | 1 | 4 | 0 |

The point of the table is the middle column. A silent oracle is only evidence
if it has been shown to speak: an oracle with zero positives is reported
`UNPROVEN` and fails the gate, and one that misses a known shape is `BLIND`.
There is no way to add an oracle that "passes" vacuously.

Deliberate controls worth naming:

- `control/crash-marker-on-stdout`: a fuzzed program printing the ICE banner on
  stdout must not be scored as a compiler crash. Compiler markers are stderr
  only.
- `control/stall-needs-output-contract`: a low-CPU timeout on an input that
  never owed output is `timeout_plain`, not a deadlock.
- `control/blocked-is-not-busy`: the same wall clock with 8 ms of CPU must not
  match `busy_hang`. This is the F10/F11 separation, tested directly.
- `control/busy-is-not-plain`: `timeout_plain` must not re-report a busy hang.

## Wiring

- `cmd/oracleaudit` prints the table, emits one JSON object, and exits 1 if any
  oracle is unproven, blind, or noisy; 2 if `--json` cannot be written.
- `cmd/accept` runs it as `oracle_sensitivity`, before the expensive stages,
  and requires `proven == registered` and zero false positives.

## Claim limits

- The matrix proves the **classifier**, not the **runner that fills the
  fields**. `cpu_ms`, `frames` and `alive_after` are supplied by the harness;
  a wrong `cpu_ms` would make a correct classifier produce a wrong verdict.
  The campaign wiring is the next step, and it needs its own control: the same
  input run through the new path and the old `behavior_sig` must produce the
  same signature for the known PoCs.
- The fixtures are synthetic observations shaped like the PoCs, not the PoCs
  themselves. They are a lower bound on sensitivity.
- Seven oracles are not a defect taxonomy. They cover crash, non-termination,
  silence, and contract violations. They do **not** cover wrong answers:
  a miscompile with a clean exit and a plausible output only shows up under a
  differential oracle (`judge.compare`), which is implemented but not yet part
  of this matrix.
- Passing this gate means "the oracles can see these classes of defect". It
  says nothing about how often those classes occur in the corpus.

## Adding an oracle

1. add a variant to `OracleKind` and a case in `check`;
2. add at least one positive probe in `probes.mbt` — without it the gate fails
   as `UNPROVEN`;
3. add the control that distinguishes it from its nearest neighbour, or the
   gate will eventually fail as `NOISY`.

Step 3 is the one that gets skipped and the one that keeps the table
meaningful.
