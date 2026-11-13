# codex review 4 — paper-level results, coverage metrics, and next steps

Prompt: `/tmp/codex_prompt4.txt`; run 2026-11-12 via the 7890 proxy
(`codex exec -s read-only -C /data/audit/mbtfuzz --skip-git-repo-check -`).
This log records the verdicts, the point-by-point verification, and the
resulting changes.  It supersedes the P0–P4 plan in the previous turn where
codex disagreed with it.

## codex verdicts (condensed)

1. **Coverage metric**: all-symbol `camlMoonc*` function coverage is the
   primary metric *after calibration*; statically-reachable coverage is
   rejected as a headline denominator (a call-graph hypothesis, not feasible
   code); per-subsystem coverage is secondary only with documented attribution
   and an explicit unknown bucket; TB-work weighting is rejected as a
   completeness metric (it measures overlap with a reference workload); QEMU
   edges are conditional/secondary (stable address pairs, otherwise bitmap
   occupancy, not a percentage of feasible edges); feature/grammar coverage is
   a separate input-space measure with a frozen inventory (attempted vs
   accepted vs exercised).
   Recommended wording: “observed X of Y eligible `camlMoonc*` function
   symbols under the listed commands/configurations; symbol-level coverage of
   that binary, not source/branch/feasible-code coverage.”
2. **Work allocation**: audit the measurement first; do not manufacture a
   reachable denominator. Reject the full target/flag Cartesian product
   (evidence predicts low yield: four targets span 4,599–4,640 functions,
   native +82, coverage flag +97, stacktrace +0); accept third-party packages
   for external validity; diagnostics/config is the highest-priority discovery
   work; serialization only a short pilot; Menhir enumeration capped at a
   2-day feasibility pilot; package mutation conditional; evidence assembly
   continuous.
3. **Gates**: three independent outcomes — exploration (functions/edges),
   validity (fault detection/classification), defects (minimized families).
   Paper-level below 50 % is acceptable if the denominator is explicit,
   comparisons are controlled/repeated with uncertainty, findings reproduce,
   programs/operations/events/backends are counted separately, and feature
   inventory + negative results are documented.  No universal coverage
   threshold.
4. **Framing**: “validated black-box robustness and bounded semantic testing”,
   not coverage maximization.  Defensible claims: entrance selection mattered
   (`link-core` +1,154 functions); text mutation added zero functions;
   robustness failures at 101/9/19/22 bytes; 27,095 semantic checks/events with
   zero discrepancies; coverage and defect discovery are distinct (F5/P1 at
   weak function expansion).  Do not claim correctness/codegen maturity,
   six independent root causes, “most remaining functions unreachable”, or
   general superiority over AFL from unequal harnesses.
5. **Avoid**: full Cartesian matrix; closure-heavy reachability to inflate the
   percentage; a two-week Menhir generator before validating current-language
   relevance; more bootstrap generations; diagnostic-string counts as
   coverage; saturation claims from a minimized corpus; discovery gates based
   only on new functions.

## Verification of codex's factual claims

| # | claim | check | result |
|---|---|---|---|
| 1 | 7,660 / 7,847 / 7,916 need exact manifests; 7,660 vs 7,847 differ by 187 | recomputed all set unions from `out/cov_replay_*.json` + `funcs_*` | **confirmed**; exact composition below |
| 2 | 18,951 unobserved corresponds to 7,660; 7,847 leaves 18,764 | 26,611 − 7,660 / 7,847 | **confirmed** (18,951 / 18,764) |
| 3 | `symbolize.py` uses nearest preceding symbol without ELF size bounds | source line 45–50; `nm -S` audit | **confirmed**; 51.2M PCs, 1,533 gap PCs (0.003 %), all 7 naive-only symbols are CRT, **0** `camlMoonc` differences; 0 zero-size, 1 alias, 1 overlap; no headline change |
| 4 | `replay.py` suppresses return code and stderr | source: `stdout/stderr=DEVNULL`, `except: pass` | **confirmed**; patched to record `rc/stderr/timed_out`; outcomes: check 299/299 rc=0, build 130/130 rc=0, test 712/728 rc=0 |
| 5 | 16 test-replay failures are not compiler defects | 16 rc=199 are `link-core` with missing `.core`; direct re-run rc=0 | **confirmed**: parallel ordering artifact; unions conservative, not inflated |
| 6 | README §5 F1 claim contradicts F1 finding | README says F1 interrupts `moon check/build`; finding says the `moon` driver uses a safe parser | **confirmed**; README fixed |
| 7 | 68.4M/71.5M = 95.6 % overclaims phase attribution | two command workloads, not a phase decomposition; TBs differ in cost, chaining affects counts | **confirmed**; README softened |
| 8 | only ~17 % of symbols have reliable module attribution; 47.5 % unmatched | our earlier unique-name analysis (4,460/26,611 attributed) | **confirmed**; kept as a limitation |
| 9 | 27,095 mixes operations and events; 3,500 records = 1,159 texts | `findings/semantics.md`; dedup in `olddiff2+3` | **confirmed** (already documented in review 3) |
| 10 | `link-core` contributed 1,154 functions | check+build+testbuild 5,943 → +link 7,097 | **confirmed** exactly |
| 11 | 2,870 unobserved Menhir symbols are not 2,870 productions | symbol inventory vs grammar table | **confirmed**; treat as symbol population, not production coverage |
| 12 | F3/P1 valuable even with no function delta | coverage vs defect yield are independent | **confirmed**; reflected in framing |

### Exact union provenance (freezes the “moving denominator”)

| union | size | % of 26,611 | definition |
|---|---:|---:|---|
| four entrances | 7,097 | 26.67 % | check ∪ build ∪ testbuild ∪ link |
| + release variants | 7,412 | 27.85 % | + build_rel ∪ testbuild_rel |
| + targets/flags | **7,591** | **28.53 %** | + native ∪ llvm ∪ cov_flag |
| + `link_rel` | **7,660** | **28.79 %** | all 11 replay artifacts |
| + real & mix corpora | **7,847** | **29.49 %** | 7,591 ∪ funcs_real ∪ funcs_mix |
| + `link_rel` + corpora | **7,916** | **29.75 %** | 7,660 ∪ funcs_real ∪ funcs_mix |

7,660 − 7,591 = **69** (`link_rel`); 7,847 − 7,660 = **187** (different corpus
inclusion); 7,916 − 7,847 = **69** (`link_rel`).  Recommended headline:
**7,916 / 26,611 = 29.75 %**, maximal documented union, with the exact list;
the others become ablations.  Full audit: `findings/cov_audit.md`.

## Changes made

* `harness/replay.py` now records `rc`, `stderr`, `timed_out`, and aggregates
  `rc0/failed/timed_out`; research log updated.
* `harness/cov_audit.py`: size-bounded symbolization, reproducibility, gap
  accounting; `harness/replay_outcomes.py`: direct-execution outcome audit.
* README §3.3 provenance table and claim wording; F1 scope corrected; TB
  phase-attribution softened.
* New findings: `findings/cov_audit.md`, this file.

## Adopted next-step order (codex ranking, adapted)

1. **Measurement audit** — mostly done; extend to 50 commands × 3 rounds and
   `exec` vs `exec,nochain` before publishing TB numbers.
2. **Defect/oracle validation (1–2 days)** — reproduce F1–F5/P1 outside QEMU,
   five runs each, capped resources, fault controls; no coverage delta needed.
3. **Baseline pilot** — 4 arms × 2 strata × 5 × 1 h first (not the full
   960 core-hour design); compare stage reach, outcomes, coverage/defect
   rediscovery.
4. **Diagnostics/config recovery (2–3 days)** — highest discovery priority;
   30–50 behavioral classes, start 20,000 cases; gates: new defect family,
   ≥50 functions, or ≥1 % edge growth.
5. **Third-party mooncakes corpus (2–3 days)** — 10–20 diverse projects;
   external validity regardless of function delta.
6. **Missing mechanisms/serialization (1–2 days)** — build-interface coverage
   replay, wasm-ld/metadata/bundle probes, cap 200 invocations each.
7. **Menhir pilot (≤2 days)** — 100 old productions as witnesses, require
   ≥80 current parse-accepted and ≥50 functions / ≥1 % edges before a week.
8. **Final reproduction/evidence assembly (2–3 days)** — second clean replay,
   manifests, uncertainty, exclusions, limits.
