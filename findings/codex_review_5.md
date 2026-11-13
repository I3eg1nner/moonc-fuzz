# Codex review 5 — MoonBit migration architecture / new-defect surfaces

Date: 2026-11-13.  Model: Codex default (gpt-5.4 unavailable under this
account).  Access: `HTTPS_PROXY=http://127.0.0.1:7890`, read-only, prompt in
`/tmp/codex_prompt.md`, raw answer `/tmp/codex_review5.txt`.

## Verdict

Keep the architecture, make MoonBit the operational default, but do not call
the migration complete until the acceptance/replay/evidence gaps are closed.
The highest-value work is reliable acceptance and evidence capture, not porting
the remaining Python line count.  Python should stay for independent semantic
references, archived pilots and plotting.

## P0/P1 issues raised, and what we did

| # | Codex finding | Action |
|---|---|---|
| 1 | Oracle builds/links keep `rc=-999`, `same` ignores stage/stderr; two failures can compare equal | Added `oracle.outcomes_agree`; a successful run is compared by rc+stdout, two failures by failure class only. Injected-fault tests added. |
| 2 | Formatter nonzero exits and second-pass failures ignored | Fuzzer now records formatter timeout, reparse failure and non-idempotence; 27 万+ T1-OK campaigns found no new formatter class. |
| 3 | Finding storage drops raw stdout/stderr; text inputs always `case.mbt`; signatures collapse signals | `meta_json` now stores `stderr_tail`/`stdout_tail` and diff findings store `wasm_detail`/`js_detail`; JSON is escaped. |
| 4 | Regression does not fail the process; F6 optional | `cmd/regress` now exits 1 on any failure and has 12 mandatory rows; F6 uses a 10-line fixture with no third-party download. |
| 5 | P1 only one size; F5 diagnostic/F4b absent | P1 now measures k=512/1024/2048 (5/5/3 runs), ratios 25.4 / 317.4 / 3015.4, gate >5. F5 diagnostic and F4b added. |

## Acceptance gate added

`moonbit/cmd/accept` (new) runs, without Python:

1. toolchain pin `v0.10.20+65efd5b93`;
2. `moon test --target native` (54 tests) and `moon check`;
3. `cmd/regress` 12/12;
4. exact synthetic trace JSON;
5. real QEMU F4 trace -> 599 functions, compared to a Python-golden set;
6. coverage union fixture `func_count=3`;
7. all 25 runnable templates reach `wasm run` and `js run` with equal output;
8. a tampered expected trace must differ.

It exits nonzero on any failure.  This is the proposed minimum artifact Codex
asked for: one documented MoonBit entry point that runs, saves/replays and
evaluates a bounded campaign without invoking Python.

## Claims narrowed after review

* F1 title changed from “out-of-bounds read” to “SIGSEGV, root cause
  undetermined”.  Impact narrowed to explicit `moonc syncheck moon.pkg`; a
  valid source file in the same directory does **not** crash `build-package`
  or `check`.  The IDE/LSP exploitation sentence was removed as unverified.
* F6 corrected in `validation.md`, `thirdparty.md`, `evidence_package.md`,
  `README.md`: module-wide native build also fails; package-scoped `src` build
  succeeds.  Not test-mode-only, still a diagnostic/tooling defect.
* F6 minimized from 12 MB / 689 files to 12 source lines in one
  `foreign_library` package (`poc/f6_native_export_closure_min/`), with a
  control matrix: no exported function or plain `pub fn` -> rc=0.
* README now states 29.75% is symbol-level coverage of `camlMoonc*`, and 4x is
  trace-converter speed, not whole-project throughput.
* F1b/F2b/F4b are labeled additional witnesses provisionally grouped with
  F1/F2/F4, not new root-cause classes.

## Still open (from Codex's 7-day plan)

1. Incremental/cache invalidation: warm vs clean edit sequences, target
   switches, failed-build recovery.  No MoonBit driver yet.
2. Interface producer/consumer matrix with visibility/opaque/type-alias
   interactions beyond the archived Python pilot.
3. Native export/test matrix beyond the F6 trigger (nesting through
   records/enums/aliases/generics, debug/release, foreign-library exports).
4. Package integration diagnostics (`moon check/build/test`, conditional
   targets, dependency diamonds), not only malformed `moon.pkg` parsing.
5. Release/optimized cross-backend semantics (current oracle is O0).
6. Ordinary-run memory cap and descendant-termination assertion in `exec`.
