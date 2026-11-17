# MoonBit harness

MoonBit implementation of the fuzzing and analysis stack. It drives the same
`moonc` binary as the Python reference and produces the same coverage/defect
evidence. The Python implementation is archived on the `python-reference`
branch; the main branch contains no Python.

Recorded toolchain:

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
```

## Install

The module is published on mooncakes.io:

```bash
moon add I3eg1nner/mbtfuzz
```

The CLI drivers are meant to run from a clone, because they need a pinned
`moonc`, the `harness/` fixtures and optional third-party corpora:

```bash
git clone https://github.com/I3eg1nner/moonc-fuzz.git
cd moonc-fuzz/moonbit
moon check && moon test
```

## Packages

| Package | Role |
|---|---|
| `trace/` | `nm -n` symbol table + QEMU `-d exec`; structured `TraceResult` collector |
| `cov/` | JSON function-set algebra, union/intersection/diff, greedy minimization |
| `mutate/` | structure-aware mutator, deterministic splitmix64 RNG |
| `exec/` | async child-process runner with hard timeout and output cap |
| `corpus/` | seed walking, SHA-1, finding storage |
| `oracle/` | wasm/js and wasm/native build + link + run differential |
| `cmd/trace2funcs` | offline trace converter |
| `cmd/cov` | coverage JSON CLI |
| `cmd/fuzz` | T1/T2/T3 campaign driver with dynamic corpus and background trace queue |
| `cmd/bytefuzz` | byte-level fuzzer for invalid UTF-8 |
| `cmd/diffprobe` | one-program differential probe |
| `cmd/regress` | 12-case defect regression (F1–F6, P1) |
| `cmd/f6matrix` | F6 native-export boundary matrix (8 closure shapes + 2 controls) |
| `cmd/accept` | migration acceptance gate |
| `cmd/optdiff` | controlled real-package test differential (link-only / four-cell) |
| `ir/` | small typed IR, interpreter and MoonBit emitter |
| `cmd/irprobe` | IR interpreter vs compiled wasm/js sample oracle |

## Commands

```bash
cd moonbit
moon check
moon test

# One bounded campaign. Each run gets out/<base>/<run-id>/.
moon run cmd/fuzz -- \
  --root .. --out ../out/mb_campaign \
  --mode mbt --workers 48 --duration 120 --p-deep 50 --p-run 10 \
  --trace-t1 20 --trace-t2 70 --trace-t3 10 \
  --trace-workers 3 --trace-queue 32 --trace-cpu 25 --body-only

# Or use the launcher presets: parser, typer, semantic-diff, hybrid.
../run.sh hybrid 8 120

# Invalid-UTF-8 campaign.
moon run cmd/bytefuzz -- \
  --root .. --out ../out/mb_bytes \
  --mode mbtmd --workers 16 --duration 60

# Acceptance: tests, build, regressions, trace parity, oracle.
# Use an absolute repo root; the command currently resolves child binaries
# relative to that root.
moon run cmd/accept -- /data/audit/mbtfuzz

# Controlled link-only optimization differential on a real package test suite.
# --module and --out must be absolute; the source module is copied to
# <out>/module so the experiment does not reuse the source tree's build cache.
moon run cmd/optdiff -- \
  --module /data/audit/mbtfuzz/seeds \
  --out /tmp/optdiff-argparse \
  --packages moonbitlang/core/argparse \
  --target wasm-gc --repeats 3

# Positive control: inject one implementation-level behavior change and verify
# that the real test assertions catch it.
moon run cmd/optdiff -- \
  --module /data/audit/mbtfuzz/seeds \
  --out /tmp/optdiff-fault \
  --packages moonbitlang/core/argparse \
  --fault-check argparse/help_render.mbt 'Usage: ' 'Use: '

# Candidate-chain control: build green A, mutate one implementation file,
# rebuild B, compare the same test IDs. This is expected to exit 1 with a
# non-zero `changed` count; exit 2 means the harness failed to see the change.
moon run cmd/optdiff -- \
  --module /data/audit/mbtfuzz/seeds \
  --out /tmp/optdiff-candidate \
  --packages moonbitlang/core/argparse \
  --candidate-check argparse/help_render.mbt 'Usage: ' 'Use: '

# Four-cell source-identical optimization localization. One package only;
# build/link O0/default arms are compared against B0L0.
moon run cmd/optdiff -- \
  --module /data/audit/mbtfuzz/seeds \
  --out /tmp/optdiff-four \
  --packages moonbitlang/core/argparse \
  --target wasm-gc --four-cell

# Four-cell link-injection control. The mutant package core is substituted only
# in the link-default arms; expected link_changed>0, build_changed=0,
# both_changed>0, candidate=true, exit 1.
moon run cmd/optdiff -- \
  --module /data/audit/mbtfuzz/seeds \
  --out /tmp/optdiff-four-control \
  --packages moonbitlang/core/argparse \
  --target wasm-gc \
  --four-cell-control argparse/help_render.mbt 'Usage: ' 'Use: '

# Small typed-IR prototype: interpreter events vs compiled wasm and js.
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/mbtfuzz_irprobe

# Add 30 deterministic random IR programs in the same subset.
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/mbtfuzz_irprobe \
  --random 30 --seed 1

# Reduce each generated program while preserving type validity, successful
# interpretation and the complete event trace, then recompile/run the reduced
# program and repeat the wasm/js comparison.
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/mbtfuzz_irprobe \
  --random 30 --seed 1 --reduce

# Four-cell IR check: same source, build O0/default × link O0/default; every
# arm must match the interpreter event stream, not merely the other arms.
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/mbtfuzz_irfour \
  --four-cell --random 20 --seed 1

# Failure-category reduction control: preserve type validity, interpreter
# success, the complete event trace, and the four-arm reason vector.
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/mbtfuzz_irreduce \
  --four-cell --reduce-failure --inject-arm B0Ld
```

`cmd/optdiff` currently isolates **link-core** `-O0` only. It copies the source
module, reuses the official test build artifacts, relinks each test wasm with
and without `-O0`, runs the captured `moonrun --test-args` argv, and compares
the complete per-test ID set. It compares semantic test states (`pass` /
`skip` / `fail`), using the generated test metadata to treat panic-named tests
as expected-panic tests. Raw failure text is preserved as evidence but stack
addresses and wasm function indices are not treated as semantic differences.
This is still a bounded interpretation: it does not prove every assertion
category, and unsupported/unknown metadata is not promoted to `SAME`. For
panic-named tests it follows the fixed `moon 940aa18` rule (test name starts
with `panic`, any non-empty message counts as passed); it does not verify the
panic reason. `--fault-check` only proves that the package assertions detect a
deliberate implementation change; it does not yet exercise the full
single-arm-change -> candidate -> exit 1 chain.

The default link-only mode does not isolate `build-package` optimization;
`--four-cell` does. The default link-only mode's `--aa` and source-mutation
candidate control remain separate from the four-cell A/A. Do not describe link-only output as a full optimization
differential. A missing requested test ID, a
duplicate result, a missing `-O0`, a missing runtime command, a timeout, or a
link failure is an error, not a `SAME` result. Exit codes are `0` for a clean
comparison, `1` for a candidate status difference, and `2` for an invalid,
incomplete, or no-change candidate experiment. In link-only mode, `--aa` runs
both link arms with `-O0` as a negative control; in four-cell mode it uses the
repeated B0L0 arm as the A/A check;
`--fault-check` accepts only an assertion failure with a non-empty failed
count, not an arbitrary nonzero compiler/test-runner exit. `--candidate-check`
is the separate end-to-end control: it freezes A, mutates one implementation
file, rebuilds B, and must report a status change and exit 1. It is a harness
control only: it does not prove optimization correctness, and it does not
guarantee metadata consistency if a test structure is mutated.

`--four-cell` keeps one source set and compares `B0L0` (build `-O0`, link
`-O0`), `B0Ld` (build `-O0`, link default), `BdL0` (build default, link
`-O0`), and `BdLd` (both default). The default build arm is produced by
removing `-O0` from the replayed `build-package` argv; it does not use
`moon test --release` and therefore does not switch `assert.mbt` to
`assert_release.mbt`. The four-cell mode accepts a comma-separated package
list; each package gets its own source copy, build tree, evidence and summary,
keyed by the sanitized package name plus a short hash (so `a/b__c` and
`a__b/c` cannot collide). Artifact basenames must be unique within a package;
ambiguity is an error, not a merge. `--repeats N` relinks and reruns every arm N times and rejects
unstable test states (the build arms are built once; link/run are repeated).
`--aa` requires `--repeats >= 2` and uses the repeated B0L0 arm as the A/A
check; an A/A instability is an error. A single candidate still needs
independent confirmation before being called a bug. `--four-cell-control`
remains single-package; it needs a concrete package core to inject, and matches
that core by basename suffix in the link argv (a residual identity boundary).
Duplicate package names in one four-cell run are rejected rather than
overwriting each other.
`--four-cell-control` is a link-injection harness control, not an optimizer
correctness claim. It restricts to artifacts whose link argv actually contains
the package core; artifacts without that core are skipped rather than treated
as a pass.

Minimal runnable example, no campaign required:

```bash
../examples/trace2funcs.sh
```

`cmd/accept` exits nonzero if any of its 10 gates fails: pinned toolchain,
`moon build`, `moon test`, `moon check`, 12 regressions, exact synthetic trace
JSON, real F4 trace (599 functions against a Python-golden fixture), coverage
union, 25-template wasm/js oracle, and a negative control. It does not invoke
Python.

`ir/` is a deliberately restricted prototype, not a MoonBit parser: values are
`Int`, `Bool`, `Unit`, and `Array[Int]`; expressions cover arithmetic,
comparison, `if`, first-order calls, arrays and length; statements cover
mutable locals, array element writes, bounded loops, emits and returns.
Array rebinding is rejected (only `ArraySet`); `Emit` accepts `Int`/`Bool` only;
a bounded loop stops after at most `bound` condition-true iterations, without a
final extra condition evaluation. Division, floats, strings, closures, generics,
traits and trap semantics are excluded. The interpreter fuel is a screening
budget: exhaustion is a failed/invalid sample, not a program result. Locals and
parameters may not shadow functions, `println`, or generated `__` names.
Restricted random generation, trace-preserving reduction and a four-cell IR
probe are connected to `irprobe`. The generator uses one fixed main/helper shape, `size=8` in the probe,
and generates `Index`/`Len` in expression positions, but not nested functions
or array aliasing interactions. `--reduce` is a statement-level, trace-preserving reducer: it
requires type validity, successful interpretation and an identical event
sequence, and removes dead lets/no-op assignments. It is not yet a
compiler-difference reducer; the separate `--reduce-failure` predicate preserves
the original failure class, not merely “no crash.” `--four-cell` compiles the same emitted
source into build O0/default and link O0/default arms and checks each arm
against the interpreter event stream directly. It is wasm-gc only, uses a
writable per-run directory under OUT, must run serially, and currently skips
`--reduce`. “Default” means omitting `-O0`, not explicit `-O2`. Its harness
control `--inject-arm B0Ld` appends a wrong event only to that arm: the row must
show only `B0Ld=false` / `B0Ld_reason="mismatch"` and exit 1; `--inject-arm all`
must make all four arms false and exit 1. Per-arm reasons distinguish
`interpreter`, `write`, `build_O0`, `build_default`, `link`, `run`, `timeout`,
`truncated`, `mismatch`, and `ok`. These are detection-chain controls, not
optimizer defects. `--reduce-failure` additionally preserves the complete
interpreter event trace and the four-arm reason vector, but only deletes
top-level `main` statements; `ok` does not guarantee the statement count
decreased; the fourth hand sample
contains a removable dead `let`, so the control must reduce 2→1 statements and
keep `[ok,mismatch,ok,ok]`. It is validated with an injected arm, so it is
still a harness control, not evidence of an optimizer failure. An all-green
baseline is rejected as `no_failure`; a no-injection run can still find a real
failure.
All-green samples only calibrate connectivity; per-arm booleans require
successful builds and interpreter success as well as matching output. The interpreter is the semantic oracle;
`cmd/irprobe` requires interpreter success, wasm/js rc=0, non-truncated output
and byte-equal event text (including the final newline). It runs four hand
calibration programs plus optional deterministic generated programs
(`--random N --seed S`); the generator only emits this supported subset. Passing these
samples does not establish general compiler correctness or a complete IR.

## Measured results

- Tests: 144 unit tests (`moon test`); GitHub Actions runs `moon check`,
  `moon build`, `moon test`, `moon fmt --check` and the example on every push.
- `trace2funcs`: exact set equality with Python on three real traces
  (1,864 / 1,354 / 599 functions). Release native is about 4× faster on the
  101 MB check trace (0.48 s vs 1.80 s).
- `cov`: set-algebra fixtures and the 6,547-function union match Python.
- `oracle`: all 25 `templates/*.mbt` reach `run` on wasm and js with equal output.
- `regress`: 12/12, including the 10-line F6 native-export repro.
- Campaigns: 126k mbt, 223k moon.pkg, 83k .mbt.md, 111k .mbti, 140k moon.mod.
  F1b/F2b/F4b are extra witnesses grouped with F1/F2/F4, not new root causes.
- Feedback: fast T1/T2/T3 paths only produce candidates. A bounded background
  queue replays the exact argv under QEMU; T2 gets 70% of the trace budget,
  T1 20%, link 10%. In-flight reservations count toward the share; a
  temporarily unschedulable queue waits, it is not cleared. Coverage is keyed
  by `(config, stage, outcome)`, and only a non-empty `Coverage(x) - U` admits
  and rewards a parent. Baseline results are frozen behind a completion
  barrier; a failed or dropped baseline marks U0 incomplete and suppresses
  candidate rewards.
- Persistence: source is stored once as `corpus/<sha1>.mbt`. Coverage evidence
  is one file per `(input_hash, config_hash, stage, outcome)` under
  `corpus/coverage/<stage>/<outcome>/`; behaviour evidence lives under
  `corpus/behavior/<sha1>/` and cannot overwrite coverage. A mixed 10 s smoke
  observed 1,539 baseline functions, 1,689 observed and 150 seed-relative new
  functions with two trace workers.
- Fault injection: a synthetic collector made a T1-only 2 s campaign complete
  304 traces instead of stopping after one. Exit 127 after a valid PC produced
  348 `collector_failed` records, zero accepted/rejected, and zero coverage
  adds. Exit 127 plus `Cannot allocate memory` also stays
  `collector_failed`; exit 199 with the real ICE banner stays
  `compiler_abort`. A delayed-baseline run completed 516 traces with all four
  baseline tasks done and `coverage_adds=0` for seed-duplicate coverage. A
  partial baseline with `observed_funcs=2` emitted `relative_new=null` and
  `coverage_adds=0`.
- Campaign summaries now include `unique_inputs`, `unique_t2_inputs`,
  `unique_t2_ok_inputs`, `unique_diff_inputs`, `diff_attempts`,
  `diff_complete`, `diff_nonempty`, `diagnostic_families`,
  `finding_candidates`, and `finding_duplicates`. `SEED_DIR` lets the launcher
  use an explicit corpus such as `templates/`.

## Boundaries

- Coverage is symbol-level over `camlMoonc*`, not source-line, branch or
  feasible-code coverage.
- `syntax_boundary`, `olddiff`, `iface`, `typegen` and the Python reference
  live on the `python-reference` branch, outside the main build.
- The differential oracle compares a declared output contract (rc, stdout,
  failure class) only after both sides reach `run`; build/link failures are
  classified separately and never reported as `same=true`.
- Coverage is function-level: a new branch inside an already-covered function
  does not increase the set. QEMU execution events are used, not translation
  events. T3 has no seed baseline in the first version. If any baseline task
  fails or is dropped, `baseline_state=incomplete`; `relative_new` is JSON
  `null` and `coverage_adds` stays zero in that run. `observed_funcs` remains
  available for diagnosis.
- Campaign T1/T2/T3 use `run_isolated` (GNU timeout process-group cleanup +
  `prlimit`); raw `@exec.run` call sites remain unisolated. Output is capped
  after collection.

## License

Apache-2.0; see `LICENSE`.
