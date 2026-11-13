# Python -> MoonBit migration: evidence and acceptance

Date: 2026-11-13.  Toolchain: `moon 0.1.20261104 (940aa18)`, `moonc
v0.10.20+65efd5b93 (2026-11-05)`, installed with `moon upgrade` under a pty
(the non-interactive run aborted with `not a terminal`; same version was
already latest).

## What is now the default path

`moonbit/` contains the operational harness.  The root `run.sh` now invokes the
MoonBit fuzzer by default; `./run.sh py ...` keeps the Python reference.

| workflow | MoonBit entry point |
|---|---|
| trace -> function set | `cmd/trace2funcs` |
| coverage set algebra | `cmd/cov` |
| mutation | `mutate/` |
| T1/T2 campaign | `cmd/fuzz` |
| invalid-UTF-8 campaign | `cmd/bytefuzz` |
| wasm/js + wasm/native differential | `oracle/`, `cmd/diffprobe` |
| known-defect regression | `cmd/regress` |
| migration gate | `cmd/accept` |

No MoonBit package imports Python.  Python remains an independent reference
for `symbolize.py` and for archived pilots (`syntax_boundary`, `olddiff`,
`iface`, `typegen`).

## Tests and gate

```
cd moonbit
moon test        # 54 passed, 0 failed
moon check       # 0 warnings, 0 errors
moon run cmd/accept -- /data/audit/mbtfuzz
# {"ok":true,...} exit 0
```

`cmd/accept` checks: pinned `moonc`; `moon test`; `moon check`; 12/12
regressions; exact synthetic trace JSON; real QEMU F4 trace -> 599 functions
matched against a Python-golden fixture; coverage union `func_count=3`; all 25
runnable templates reach `run` on wasm and js with equal output; a tampered
expected trace must differ.  Any failure exits nonzero.

## Parity

| trace | Python funcs / time | MoonBit funcs / time | sets |
|---|---:|---:|---|
| core `check`, 101 MB | 1,864 / 1.80 s | 1,864 / 0.48 s | equal |
| `build-package`, 95 MB | 1,354 / 1.67 s | 1,354 / 0.44 s | equal |
| invalid UTF-8, 25 MB | 599 / 0.44 s | 599 / 0.15 s | equal |

Timings are release native on the same host, one run each; the 4x claim is
limited to this trace converter, not whole-project throughput.
Coverage union on `out/cov_funcs_seeds.json` + `out/cov_replay_check.json`:
Python 6,547, MoonBit 6,547, exact.  `cov/` also matched 40 random set arrays
and 60 report rows in a temporary differential run by the subagent.

## Campaigns run by the MoonBit driver

| mode | iterations | T2 | unique new signatures | notes |
|---|---:|---:|---:|---|
| mbt, body-only | 126,497 | 20,958 | 16 | 0 crashes |
| moon.pkg | 223,043 | 0 | 64 | 799 duplicate SIGs -> 1 unique (F1b) |
| .mbt.md | 83,317 | 0 | 32 | 0 crashes |
| .mbti | 111,707 | 0 | 1,443 | 0 crashes |
| moon.mod | 139,934 | 0 | 32 | 0 crashes |
| templates, wasm/js diff | 77,638 | 17,084 | 32 | only F2b ICE |
| templates, wasm/native diff | 36,215 | 7,926 | 16 | one native abort-vs-wasm-trap candidate, triaged as non-miscompile |
| formatter round-trip/idempotence | 270k+ T1-OK | 0 | — | 0 new formatter class |
| bytefuzz .mbt.md | 81,570 | 0 | 1 | 41,118 crashes collapse to F4 family |

These are execution counts, not distinct semantic tests.

## New witnesses (grouped; not claimed as new classes)

* **F1b**: 672 B malformed `moon.pkg` map, SIGSEGV; same top frames as F1; root identity not proven
  (`next_segment_head` / `report_failed_to_parse`).
* **F2b**: `\` + U+200B accepted by `syncheck`, `build-package` ICE
  `Invalid_argument("Char.chr")`.
* **F4b**: second invalid-UTF-8 `.mbt.md`, `Basic_utf8_decode.MalFormed`.
* **F6-min**: F6 reduced from 12 MB / 689 files to a 10-line single
  `foreign_library` package; `moon build --target native` suffices.  A matrix
  (private/public/array/option/alias/enum/generic/nested, plus two controls)
  shows the trigger is exported-signature reachability of a closure type;
  controls build with rc=0.  Still one diagnostic/tooling defect, not a
  miscompile.

## Boundaries

* Coverage is symbol-level over `camlMoonc*` (7,916 / 26,611 = 29.75%), not
  source-line, branch, or feasible-code coverage.
* No claim that the remaining functions are unreachable.
* No claim of compiler correctness or codegen maturity; the differential
  templates are a bounded sample and can share wrong answers.
* F1b/F2b/F4b are grouped with F1/F2/F4 provisionally; stack similarity is not
  proof of one root cause.
* Incremental/cache invalidation, interface producer/consumer interactions,
  package-level diagnostics and optimized cross-backend semantics remain
  follow-up surfaces (ranked in `findings/codex_review_5.md`).
