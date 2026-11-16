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
moon run cmd/accept -- ..
```

Minimal runnable example, no campaign required:

```bash
../examples/trace2funcs.sh
```

`cmd/accept` exits nonzero if any of its 10 gates fails: pinned toolchain,
`moon build`, `moon test`, `moon check`, 12 regressions, exact synthetic trace
JSON, real F4 trace (599 functions against a Python-golden fixture), coverage
union, 25-template wasm/js oracle, and a negative control. It does not invoke
Python.

## Measured results

- Tests: 105 unit tests (`moon test`); GitHub Actions runs `moon check`,
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
