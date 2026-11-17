# Stage summary: what this harness now covers, and what it does not

Date: 2026-11-17. Toolchain pinned at `moon 0.1.20261104`,
`moonc v0.10.20+65efd5b93`, `moonrun 0.1.20261104`. Host: Linux x86_64,
single machine.

This note consolidates the state after the coverage/feature-detection phase. It
is deliberately written so that every number can be traced to a document in
`findings/` and re-derived from a command in the repository. Nothing here is a
claim that the compiler is correct.

## 1. Gates

| Gate | Result |
|---|---|
| `moon test --target native` | 237 / 237 pass |
| `moon check` | 0 warnings |
| `moon fmt --check` | clean |
| `moon run cmd/accept -- <root>` | 10 / 10 checks ok |

The acceptance gate includes the pinned-toolchain check, 12 defect regressions,
an exact synthetic trace comparison, a real QEMU trace with the frozen 599
function set, coverage-union algebra, 25 template differentials, and a negative
control.

## 2. What was added in this phase

| Area | Artifact | What it does |
|---|---|---|
| Exact coverage | `trace/` + `findings/exact_block_coverage.md` | QEMU-TB block/edge counters: `unique_pc`, `mapped_unique_pc`, `edges`, `mapped_edges`, per-function `func_depth` |
| Coverage in evidence | `collect.mbt` + `findings/exact_coverage_wiring.md` | `TraceResult` carries the counters and exact edge keys; sidecar records counts and scopes |
| Coverage in scheduling | `cmd/fuzz` + `findings/edge_feedback.md` | edge novelty is an additive bonus strictly below function novelty; 200k key cap with sticky `edge_saturated` |
| Feature generation (layout) | `featuregen/`, `cmd/featfuzz` + `findings/featfuzz_mvp.md` | 160 curated native layout cases, staged oracle |
| Feature generation (async) | `asyncgen/`, `cmd/asyncfuzz` + `findings/asyncfuzz_mvp.md` | 82-row async matrix with the F8 case as a labelled control |
| Cross-backend execution | `cmd/xdiff` + `findings/xdiff_mvp.md`, `findings/xdiff_async.md` | same source executed on wasm-gc/wasm/js/native, stdout+rc compared; async compared through per-test status |
| Candidate verification | `cmd/verify` + `findings/verify_tool.md` | fresh copy per repeat, 3/3 stability, control package, JSON verdict |
| Resource bounds | `cmd/fuzz` + `findings/campaign_caps.md` | parent pool cap with deterministic eviction, persisted-evidence cap, bounded trace-failure log and core retention |

## 3. Evidence, with the interpretation each number supports

### 3.1 Coverage depth

| Measure | Value | Supports |
|---|---|---|
| Function-symbol coverage | 7,916 / 26,611 = 29.75% (historical union) | about 70% of compiler function symbols were never executed by the collected corpora |
| TB-level counters | `unique_pc`, `edges`, `mapped_edges`, `func_depth` | which TB start PCs and TB transitions a run exercised, exactly and reproducibly |
| Edge feedback | 6 s smoke: `edge_keys=41485`, `new_edges=3652` | the mechanism is live; saturation path verified with `--edge-cap 64` |

The function coverage denominator contains 8,038 anonymous closures and 4,200
Menhir actions. TB coverage is **not** source line, source basic block or
source branch coverage, and this repository reports no branch percentage.

### 3.2 Cross-backend execution

| Run | Builds | Executed | Result |
|---|---:|---:|---|
| Layout, 160 cases × 4 targets | 640 | 620 | 140 `ALL_EQUAL`, 20 `KNOWN_LINK_ICE`, **0 `OUTPUT_MISMATCH`** |
| Async, 6 cases × 3 targets | 18 | 15 | 5 `ALL_EQUAL`, 1 `KNOWN_LINK_ICE` (F8), 0 status mismatch |

The 20 known link ICEs are native-only `lower_array_make` (F7). They span four
field-shape families × five array operations
(`int_enum_string`, `int_enum_array_int`, `int64_enum_string_array_int`,
`int_bool_enum_array_int_string`), and every family's plain-struct control is
`ALL_EQUAL` on all four targets. This is a correction to an earlier note that
said "two families".

### 3.3 Feature probes (both negative)

| Probe | Cases | Distinct non-zero signatures | New |
|---|---:|---|---|
| Native layout/FFI/async matrix (`findings/feature_probe_negative.md`) | 269 | 3, all known (F7 8, F9 15, F8 12) | none |
| Async timeout/cancel/combinator (`findings/async_cancel_probe.md`) | 55 | 1, known (F8, 2 stage records) | none |

Both probes were run serially. The first probe initially produced many
diagnostic-only failures (`[4021]`, `[0055]`, …); every sampled family returned
`rc=0` when re-run serially in a clean copy, so those were contention
artifacts, not language restrictions and not compiler defects. That hazard is
documented because it will silently corrupt any parallel campaign's numbers.

### 3.4 Real-package four-cell differential

| Target | Valid packages | Artifacts | Test IDs | Confirmed candidates |
|---|---:|---:|---:|---:|
| wasm-gc | 94 | 162 | 8,849 | 0 |
| native | 111 | 184 | 9,249 | 0 |
| js | 103 | 173 | 9,031 | 0 |

Mechanism liveness was checked separately: wasm-gc code sections differ in
162/162 artifacts across arms, native in 37/45 core pairs, js in 173/173
outputs. So the harness is not a no-op; the corpora simply produced no
state change.

### 3.5 Other negative evidence

- 23,920 const-vs-runtime integer expression pairs (`Int`, `Int64`, `UInt64`)
  across 8 target/mode configurations: 0 mismatches.
- IR v1 and v2, 12,096 cases each: 0 compiler errors; the generator's
  structural diversity is only 9 coarse shapes.
- Unicode/string/error/generic/closure/loop probes: byte-identical across all
  8 configurations.

## 4. Defect inventory

| ID | Kind | Status |
|---|---|---|
| F1, F1b | `moon.pkg` SIGSEGV | reproduced 3/3, root cause not proven |
| F2, F2b | lexer escape ICE / stage split | reproduced 3/3 |
| F3 | parser OOM under a 6 GiB cap | reproduced 2/2 |
| F4, F4b | invalid UTF-8 in `.mbt.md` | reproduced 3/3 |
| F5 | prefix `+` syntax round-trip | reproduced 5/5, scoped to round-trip |
| F6 | native export closure link failure | reproduced 3/3 |
| P1 | formatter interpolation cost | two-point measurement only |
| F7 | native debug `#valtype` + GC-ref enum array lowering ICE | open upstream #1322 |
| F8 | async suspension + `raise?` callback link assertion | open upstream #1340 |
| F9 | native debug `V128` extern stub wrapper ICE | open upstream #1344 |

F7/F8/F9 are link-time compiler crashes, not miscompiles. They are the three
signatures that every probe in §3.3 re-hits, which makes them usable positive
controls and useless as new findings.

## 5. What is not established

- **No claim of compiler correctness.** Zero candidates means "this bounded
  corpus produced no observed difference", not "no defect exists".
- **No branch/line coverage.** TB transitions are a QEMU artefact and are not a
  source CFG. There is no denominator for source branches.
- **Coverage keys do not transfer.** Edge keys are specific to one `moonc`
  binary plus one `nm -n` symbol table.
- **Bounded retention.** After `--parent-cap` only energy-ranked survivors can
  be parents; after `--persist-cap` new non-candidates are not written to disk
  (candidates always are). Caps change what is retained, not what is executed.
- **No campaign-scale discovery run.** Edge feedback is verified as a live
  mechanism on a 6 s smoke, not as an improvement in discovery rate.
- **Single host, debug-biased.** Native results are mostly debug; release
  swaps the assert implementation, so release is not a substitute for O0.
- **wasm and wasm-gc both execute under `moonrun`.** They are not independent
  engines, so an error shared by that runtime would be invisible.
- **stdout/test-status only** in the cross-backend comparison; stderr, stdin
  and argv are not compared.
- **Async sample sizes are small** (82-row matrix, 6 executed differentially,
  55 cancellation cases); `wasm-gc` is excluded for async because the `@aio`
  package does not support it.

## 6. Recommended next axes, ranked

1. **Feature interaction rather than enumeration.** Async methods on
   `#valtype` records, `raise?` closures captured by async state machines,
   generic FFI wrappers, exported closures with aggregate captures. The
   enumeration axes are demonstrably saturated (two negative probes).
2. **Multi-hour campaign with the new caps, with a pre-registered metric.**
   The caps make this safe (405 files → 13 files at tiny caps in a 5 s test),
   but the metric must be stated before the run: new signatures per CPU-hour,
   not iteration count.
3. **Real-package corpora that actually use the hard features.** The 111
   native packages produced 0 candidates because their tests are ordinary unit
   tests; a corpus restricted to packages using `#valtype`, async cancellation
   or FFI would be a different experiment.
4. **Release-mode differential on the same source.** Debug and release lower
   differently, and the F7/F9 family disappears in release; nothing has
   systematically compared release-mode execution across backends.

Do not spend more budget on: more arity permutations, more field-count
permutations, more `V128` positions, more `pause` positions, or more
same-template IR seeds. All four are measured-saturated.
