# MoonBit harness — operational default

This module is the MoonBit implementation of the fuzzing/analysis stack.  It is
not a toy port: it runs the same closed-source `moonc` under the same flags and
produces the same coverage/defect evidence as the Python reference.  Python is
kept for independent semantic references, archived pilots and plotting.

Toolchain pinned for the recorded results:

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
```

## Packages

| package | role |
|---|---|
| `trace/` | `nm -n` symbol table + QEMU `-d exec` trace -> function set |
| `cov/` | JSON function-set algebra, union/intersection/diff, greedy minimization, report rows |
| `mutate/` | structure-aware MoonBit mutator, deterministic splitmix64 RNG |
| `exec/` | async child-process runner with hard timeout |
| `corpus/` | seed walking, SHA-1, first-writer-wins finding storage |
| `oracle/` | wasm/js and wasm/native build+link+run differential |
| `cmd/trace2funcs` | offline trace converter |
| `cmd/cov` | coverage JSON CLI |
| `cmd/fuzz` | T1/T2 campaign driver (mbt, moon.pkg, moon.mod, .mbt.md, .mbti, .mbtx) |
| `cmd/bytefuzz` | byte-level fuzzer for invalid UTF-8 |
| `cmd/diffprobe` | one-program differential probe |
| `cmd/regress` | 12-case defect regression (F1-F6, P1) |
| `cmd/accept` | falsifiable migration gate |
| `cmd/f6matrix` | F6 native-export boundary matrix (9 shapes + 2 controls) |

## Commands

```bash
cd /data/audit/mbtfuzz/moonbit
moon check
moon test --target native

# One bounded campaign, no Python in the loop.
moon run cmd/fuzz --target native -- \
  --root /data/audit/mbtfuzz --out /data/audit/mbtfuzz/out/mb_campaign \
  --mode mbt --workers 48 --duration 120 --p-deep 50 --body-only

# Invalid-UTF-8 campaign.
moon run cmd/bytefuzz --target native -- \
  --root /data/audit/mbtfuzz --out /data/audit/mbtfuzz/out/mb_bytes \
  --mode mbtmd --workers 16 --duration 60

# Real trace parity / set algebra / 12 regressions / 25-template oracle.
moon run cmd/accept --target native -- /data/audit/mbtfuzz
```

`cmd/accept` exits nonzero if any gate fails: pinned toolchain, `moon test`,
`moon check`, 12 known defects, exact synthetic trace JSON, real F4 trace (599
functions, compared to a Python-golden fixture), coverage union, and every
runnable template reaching `run` on both wasm and js with equal output.

## Measured parity

* `trace2funcs` vs Python on three real traces: exact set equality at
  1,864 / 1,354 / 599 functions; release native is ~4x faster on the 101 MB
  check trace (0.48 s vs 1.80 s).
* `cov` vs Python: 40 random set arrays and 60 report rows exact.
* `oracle`: all 25 `templates/*.mbt` agree on wasm and js.
* `regress`: 12/12 rows, including the 12-line F6 native-export repro.
* Campaigns: 126k mbt (20,958 T2), 223k moon.pkg, 83k .mbt.md, 111k .mbti,
  140k moon.mod; new witnesses F1b/F2b/F4b are grouped with F1/F2/F4, not
  claimed as new root causes.

## Boundaries

* Coverage is symbol-level over `camlMoonc*`, not source-line/branch/feasible
  code coverage.
* Python remains the reference for `syntax_boundary`, `olddiff`, `iface`,
  `typegen` and other archived pilots; those are not yet on the default path.
* The differential oracle compares a declared output contract (rc + stdout +
  failure class).  It does not prove that two agreeing backends are correct.
