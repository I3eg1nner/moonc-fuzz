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

## Packages

| Package | Role |
|---|---|
| `trace/` | `nm -n` symbol table + QEMU `-d exec` trace → function set |
| `cov/` | JSON function-set algebra, union/intersection/diff, greedy minimization |
| `mutate/` | structure-aware mutator, deterministic splitmix64 RNG |
| `exec/` | async child-process runner with hard timeout |
| `corpus/` | seed walking, SHA-1, finding storage |
| `oracle/` | wasm/js and wasm/native build + link + run differential |
| `cmd/trace2funcs` | offline trace converter |
| `cmd/cov` | coverage JSON CLI |
| `cmd/fuzz` | T1/T2 campaign driver (mbt, moon.pkg, moon.mod, .mbt.md, .mbti, .mbtx) |
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

# One bounded campaign.
moon run cmd/fuzz -- \
  --root .. --out ../out/mb_campaign \
  --mode mbt --workers 48 --duration 120 --p-deep 50 --body-only

# Invalid-UTF-8 campaign.
moon run cmd/bytefuzz -- \
  --root .. --out ../out/mb_bytes \
  --mode mbtmd --workers 16 --duration 60

# Acceptance: tests, build, regressions, trace parity, oracle.
moon run cmd/accept -- ..
```

`cmd/accept` exits nonzero if any of its 10 gates fails: pinned toolchain,
`moon build`, `moon test`, `moon check`, 12 regressions, exact synthetic trace
JSON, real F4 trace (599 functions against a Python-golden fixture), coverage
union, 25-template wasm/js oracle, and a negative control. It does not invoke
Python.

## Measured results

- `trace2funcs`: exact set equality with Python on three real traces
  (1,864 / 1,354 / 599 functions). Release native is about 4× faster on the
  101 MB check trace (0.48 s vs 1.80 s).
- `cov`: set-algebra fixtures and the 6,547-function union match Python.
- `oracle`: all 25 `templates/*.mbt` reach `run` on wasm and js with equal output.
- `regress`: 12/12, including the 10-line F6 native-export repro.
- Campaigns: 126k mbt, 223k moon.pkg, 83k .mbt.md, 111k .mbti, 140k moon.mod.
  F1b/F2b/F4b are extra witnesses grouped with F1/F2/F4, not new root causes.

## Boundaries

- Coverage is symbol-level over `camlMoonc*`, not source-line, branch or
  feasible-code coverage.
- `syntax_boundary`, `olddiff`, `iface`, `typegen` and the Python reference
  live on the `python-reference` branch, outside the main build.
- The differential oracle compares a declared output contract (rc, stdout,
  failure class). Agreement between two backends does not prove correctness.
