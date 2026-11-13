# Evidence package — moonc black-box testing (2026-11-12)

This is the consolidated, reviewer-facing evidence package: what was measured,
with which denominator, what reproduces, and what is explicitly *not* claimed.
It is not a paper; it is the artifact set a paper would cite.

## 1. Subject and environment

| item | value |
|---|---|
| compiler | `moonc v0.10.20+65efd5b93` (2026-11-05), closed source, ELF non-PIE, unstripped, OCaml 4.14 native |
| toolchain | `moon 0.1.20261104 (940aa18)` |
| binary | sha256 `ec9d278b…`, 23,432,224 B |
| host | 128 cores, 1 TB RAM, Ubuntu 22.04; no `perf`; AFL++ 5.04a QEMU mode |
| measurement | `afl-qemu-trace -d exec` → PCs → `nm` symbols, per-child `wait4` RSS |

## 2. Coverage headline (frozen)

> For moonc `v0.10.20+65efd5b93` (SHA256 `ec9d278b…`), replaying the listed
> `moon`-generated command sets observed **7,916 of 26,611 `camlMoonc*`
> function symbols = 29.75 %**.  This is symbol-level coverage of that binary
> under those commands, not source-line, branch, or feasible-code coverage.

Provenance (the “moving denominator” is now explicit):

| union | size | % | definition |
|---|---:|---:|---|
| four entrances | 7,097 | 26.67 % | check ∪ build ∪ testbuild ∪ link |
| + release | 7,412 | 27.85 % | + build_rel ∪ testbuild_rel |
| + targets/flags | 7,591 | 28.53 % | + native ∪ llvm ∪ cov_flag |
| + `link_rel` | 7,660 | 28.79 % | all 11 replay artifacts |
| + real/mix corpora | 7,847 | 29.49 % | 7,591 ∪ funcs_real ∪ funcs_mix |
| **+ corpora + `link_rel`** | **7,916** | **29.75 %** | **frozen headline** |
| + third-party (lower bound) | 7,958 | 29.90 % | third-party build-package traces, 128 MiB cap |

Audit (`findings/cov_audit.md`): 30,465 text symbols, 0 zero-size, 1 alias,
1 overlap; 51.2 M PCs, 1,533 (0.003 %) gap PCs, all CRT — **0 `camlMoonc`
attribution differences**; two rounds give identical per-command sets.  Replay
outcomes: check 299/299 and build 130/130 rc=0; 16 test-replay rc=199 were
parallel-ordering artifacts (missing `.core`), re-run rc=0.

Per-subsystem attribution is **not** claimed as ground truth: unique-name
attribution covers only ~17 % of symbols, 47.5 % unmatched.  The unmatched
bucket is reported explicitly.

## 3. Defects (all validated 5/5)

| id | class | minimal input | 5-run result |
|---|---|---|---|
| F1 | SIGSEGV in `moon.pkg` parser | 101 B | 5/5 SIGSEGV |
| F2 | lexer ICE `Invalid_argument("Char.chr")` | 38 B | 5/5 ICE (`moon check` rc=1) |
| F3 | parser memory blow-up | 19 B | 5/5 reach 5.2–5.7 GiB under 6 GiB cap; uncapped 8.2 GiB/20 s is an earlier observation, not re-run in review |
| F4 | `.mbt.md` invalid UTF-8 ICE | 40 B | 5/5 rc=199 |
| F5 | prefix `+` → unlexable `~+`; formatter output not re-parseable | 66 B | 5/5: parse 0 / check 2 / fmt+reparse 2 |
| P1 | `moonfmt` interpolation ~9.7× from 1024 to 2048 | 13 KB | 5-run medians 1,576 ms (k=1024), 15,072 ms (k=2048); plain-string controls 7.5/6.2 ms |
| F6 | native export/link ICE on closure-containing exported types | `WeiR-h/moonldif@0.7.6` | 5/5 + 3/3 `Machine_error(unsupported … reject_export_type_containing_unsupported_callback)`; module-wide native build fails the same way, package-scoped `src` build succeeds; minimized to a 10-line single-package repro (`poc/f6_native_export_closure_min/`), controls build |

POC directories `poc/f1…f5`; validation table `findings/validation.md`.
F2/F4 are error-path ICEs; F1/F3 are tiny-input robustness failures; F5/P1 are
tooling, not miscompiles.

## 4. Oracle sensitivity and bounded negatives

| experiment | scale | result |
|---|---|---:|
| semantic differential (7 families, 4 backends, independent references) | 27,095 checks/events | 0 discrepancies (injected faults were caught; bounded claim) |
| boundary mutation | 19,935 cases | 0 ICE/crash/timeout/silent; 2.34 % parse-accepted |
| type-directed generation | 240 programs | +0 functions |
| bootstrap mutation | seeds 5,289 → gen0 4,636 → gen1 3,904 | +0 functions |
| old compiler differential (2025-03) | 3,500 records / 1,159 sources | 0 disagreements (no matching old core) |
| interface round-trip | 150 packages / 2,278 clients | 0 mismatches |
| printer probe | 43 constructs | 0 re-parse failures; only normalizations |
| 20-dim scaling | 19 dims × k≤512 | only P1; no new anomaly |
| config/document mutation | 14,000 cases | 0 anomalies |

These are *bounded* negatives, not correctness proofs.

## 5. External validity (third-party)

12 independent mooncakes packages × 5 backends: **60/60 builds rc=0**.
Cross-backend tests: **3,503/3,503 pass on wasm/wasm-gc/js** (10 packages);
native exposes F6 plus package/environment issues; LLVM test runner unavailable.
Build-package coverage union 4,455 (16.74 %), **+42** over the frozen baseline
(7,958 = 29.90 %); traces are capped, so this is a lower bound.  Runnable tests
are blocked by core-API drift for older packages (e.g. `run_async_main`), so
the miscompile arm needs version-pinned packages with runnable tests.

## 6. Baselines (retrospective; not a controlled comparison)

| arm | observed | caveat |
|---|---|---|
| structural/package campaign | 608,257 exec / 300 s / 96 workers; T2 30.8 %, T3 1.5 % | different corpus/cores |
| AFL++ QEMU | 13,320 exec / 300 s / 8 instances; queue 120→248, +760 edges (+1.8 %) | edge ids for unions are unreliable unless `AFL_QEMU_OLD_COVERAGE` |
| coverage on sampled 100 inputs | T2 corpus 5,089 funcs (16.8 %) vs AFL queue 3,807 (12.1 %) | sample, not per-CPU-hour union |

No claim of general superiority over AFL: harnesses, budgets and corpora are
not equal.  A controlled 4-arm × 2-stratum × 20×6 h comparison remains future
work (≈960 core-hours).

## 7. Threats to validity (what a reviewer will attack)

1. **Denominator**: 26,611 includes 8,038 anonymous closures and 4,200 Menhir
   actions; the headline says “function symbols of this binary”, not feasible
   code.  Per-subsystem numbers carry the 17 % attribution caveat.
2. **Replay loss**: outcomes were discarded historically; now recorded.
   Capped traces are lower bounds.  Killed/timed-out commands are labelled.
3. **Symbolization**: size-bounded check shows 0.003 % gap PCs, all CRT; no
   `camlMoonc` difference.
4. **Phase attribution**: 68.4 M vs 71.5 M TB is two workloads, not a phase
   decomposition (README §5 wording corrected).
5. **Finite-corpus compression**: greedy 232 inputs covering all known
   functions ≠ saturation of unseen behaviour.
6. **Drift**: old compiler / third-party tests are snapshot-sensitive;
   disagreements are triaged as drift, not defects.
7. **Mixed units**: the 27,095 semantic figure mixes operations and events;
   the old-compiler 3,500 records are 1,159 distinct sources.
8. **Independence**: F5/P1 are tooling; root-cause independence of F1–F4 is
   not claimed.

## 8. Claims

**Supported**: reproducible tiny-input robustness failures (F1–F4); a native
export/link ICE (F6); a
formatter/printer round-trip defect and a formatter complexity anomaly (F5,
P1); bounded semantic agreement across 7 families/4 backends; entrance
selection matters (`link-core` +1,154 functions); tested text mutations add
zero functions; third-party code builds on all five backends.

**Not supported / not claimed**: compiler correctness or codegen maturity;
“most remaining functions are unreachable”; general AFL superiority; uniform
compiler-bug detection rate from the semantic injections; six independent root
causes.

## 9. Reproduction map

```
README.md                     # main report; §3.3 coverage, §4 defects, §6 campaigns
findings/cov_audit.md         # symbolization / replay / union provenance
findings/validation.md        # F1–F5/P1 5× table
findings/thirdparty.md        # 12 packages × 5 backends, coverage lower bound
findings/probes_2026-11-12.md # printer / 20-dim scaling / config negatives
findings/semantics.md         # 7 families, 27,095, 0 discrepancies
findings/oldcompiler_pilot.md # 3,500 / 1,159, 0 disagreements
findings/interface_pilot.md   # 2,278 clients, 0 mismatches
findings/codex_review_4.md    # metric/planning review and corrections
harness/{cov_audit,replay_outcomes,validate_findings,fmt_probe,scale_probe,config_fuzz}.py
```
