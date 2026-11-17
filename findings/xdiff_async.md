# xdiff async: comparing async cases through the test driver

Status: implemented, bounded 6-case sample (18 target runs), 1 known upstream
ICE (F8), 0 status mismatches, 0 rc-only mismatches. No new defect claimed.

`cmd/xdiff --family async` originally produced `NO_RUN` for every case: async
packages render only `lib/lib.mbt` + `lib/lib_test.mbt` (no `main`) and declare
`supported_targets = "wasm+js+native"`, so `moon build` succeeds but produces no
executable artifact to run and compare. The async family now compares the
**test driver's own report** instead: `moon test --target T` is run three times
and the per-test outcome table plus the printed counts are compared.

## Why the test driver

* The rendered async case has exactly one blackbox test, named after the case
  id (`async test "<case-id>" { ... }`), so a test-outcome differential is the
  natural execution oracle for this family.
* `moon test` already runs the same compile/link pipeline as `moon build` and
  then executes under `moonrun` (wasm), `node` (js) or the native exe, which is
  the same backend matrix the layout family uses. The failure surface that
  matters here (F8 link ICE) happens during the test link, so it is observed
  rather than hidden.
* No `main` is synthesised. Inventing an entry point for generic, `raise`/`raise?`
  async functions would test a different program than the generated case.

## The comparison rule (test-driver mode)

For each selected async case, for each target in the requested order, serially:

```
moon test --target <T> -v --no-parallelize
```

captured as one process (`stdout`, `stderr`, `rc`, elapsed). `-v` is required:
without it `moon test` prints only the final `Total tests:` line and no per-test
names. `--no-parallelize` keeps the test *binaries* serial; it does not change
the outcome set.

Parsed from stdout (pure code in `cmd/xdiff/testparse.mbt`):

```
[pkg] test lib/lib_test.mbt:2 ("c000-opt-np-straight-g-fn") ok
[pkg] test lib/lib_test.mbt:4 ("...") failed: ... FAILED: `Some(1) != Some(2)`
Total tests: 1, passed: 0, failed: 1.
```

* **per-test status**: the name is taken between the first `("` and the
  following `")`; the status word after it is normalised to `pass` / `fail` /
  `skip` (`failed:` and `ok` are the two shapes the driver actually emits;
  anything else becomes `other:<word>` so it still compares). The table is
  encoded as `name=status;name2=status` with the names **sorted**, because the
  driver does not preserve file order (it can execute tests in reverse). Two
  targets compare equal iff the canonical string is byte-identical.
* **printed counts**: `Total tests: N, passed: N, failed: N.` is parsed with the
  same shape `cmd/optdiff` uses (`Total tests:` prefix, then `leading_int` after
  `passed:` / `failed:`). Counts from several packages are summed; the renderer
  emits exactly one package.
* **executed**: a target takes part in the comparison only when the driver
  printed a summary with `total > 0`. This keeps a backend that silently has no
  async test entry (`Total tests: 0`, e.g. wasm-gc) out of the comparison
  instead of comparing "zero outcomes" against "one outcome".
* **rc**: compared exactly, but *after* status and counts, and it has its own
  weaker verdict.

Verdict precedence for the async family:

```
TEST_STATUS_MISMATCH   per-test table or printed counts differ between executed targets
TEST_RC_MISMATCH       table and counts agree, only the process rc differs (weak)
ICE                    unknown compiler crash
KNOWN_LINK_ICE         F7/F8/F9 upstream signature; never compared
TIMEOUT                build/test timed out
SINGLE_TARGET          exactly one target produced a test outcome
BUILD_FAIL             driver never started and no known/unknown ICE marker
INFRA                  registry/download failure marker
NO_TESTS               no target produced a single test
ALL_EQUAL              all executed targets agree
NO_RUN                 nothing selected / no observation
```

Two deliberate details:

1. **Known-ICE exclusion.** If a target fails to link with a known signature it
   never produced a test outcome, so it cannot be a divergence. The case is
   labelled `KNOWN_LINK_ICE` even when only one target hit it — the label names
   the real blocker, which is more useful than `SINGLE_TARGET`, and it is never
   counted as a mismatch.
2. **rc-only is weaker.** A target whose table and counts are identical but
   whose exit status differs is `TEST_RC_MISMATCH`, not
   `TEST_STATUS_MISMATCH`. This is a separate class on purpose: the driver's
   exit status also reflects harness-level conditions, so it is not the same
   evidence as a per-test disagreement.

## CLI

```
xdiff --out ABS_DIR --family async --only ID[,ID...] \
      --targets js,wasm[,native] [--timeout-ms N] [--keep]
```

`--only` now accepts a comma-separated list (single id keeps its old meaning),
so a bounded non-prefix sample can be run in one invocation and land in one
`results.jsonl`. Async runs should **not** include `wasm-gc`: the generated
package declares `wasm+js+native`, and wasm-gc yields `Total tests: 0`
(`NO_TESTS`), which is recorded rather than compared. `--keep` retains every
case directory; without it, only mismatch/ICE/KNOWN_LINK_ICE cases are kept.

## Reuse, not a second runner

* `run_test_target` (`driver.mbt`) calls the same `@exec.run_isolated` used by
  the exec path, with the same `--timeout-ms` and output cap (256 KiB for test
  mode; `moon test` prints the whole `moonc link-core` argv on an ICE, ~17 KiB
  in the F8 case, and the signature is near the end of it).
* The same `classify_build_failure`/`known_ice_label` classifier labels the F8
  link failure; the same `TargetObs` record carries the observation, extended
  with `test_statuses`, `tests_total/passed/failed`, `tests_unparsed`.
* `async_verdict_of` is a sibling of `verdict_of` (exec mode): the *runner* is
  shared, the *comparison surface* differs, which is why the verdict functions
  are separate.
* `summary.json` records `"mode":"test-driver"` and a comparison block
  (`test_status_compared`, `printed_counts_compared`, `rc_compared`,
  `only_executed_targets_compared`), so an async summary cannot be mistaken for
  an exec summary.

## Unit tests

15 new pure tests (28 in `cmd/xdiff` total, no compiler or child process):

* all-pass blob → one `pass`, counts `1/1/0`;
* one-fail blob → `fail` kept with the case name, counts `1/0/1`;
* per-test table is order-insensitive (two permutations, same canonical form);
* malformed output: empty blob has no counts and no statuses; a truncated test
  line is counted as `unparsed`; unrelated warnings are ignored, not counted;
* `Total tests: 0` → zero counts, no invented result;
* verdicts: all-equal → `ALL_EQUAL`; one test flipped → `TEST_STATUS_MISMATCH`;
  missing test on one target → `TEST_STATUS_MISMATCH`; counts-only divergence →
  `TEST_STATUS_MISMATCH`; rc-only → `TEST_RC_MISMATCH`;
* known-ICE exclusion: all-KNOWN_LINK_ICE and one-ran/one-known-ICE both label
  `KNOWN_LINK_ICE`, never `SINGLE_TARGET`/mismatch; unknown `ICE` outranks it;
* missing target cannot diverge: one executed + one `NO_TESTS` → `SINGLE_TARGET`,
  all `NO_TESTS` → `NO_TESTS`, no summary → `BUILD_FAIL`, empty → `NO_RUN`;
* `--only` list selection picks exactly the requested async cases (including
  the `f8_control` flag);
* async summary renders `mode=test-driver`, the new class, and per-observation
  `test_statuses`/`tests_failed` in the mismatch detail.

## The run that was performed

Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`, `moonc
v0.10.20+65efd5b93`, debug builds, all runs serial, one `moon` process at a time.
Binary used directly (`moon build --target native cmd/xdiff` once, then
`_build/native/debug/build/cmd/xdiff/xdiff.exe`) so no `moon` wrapper idles
while the driver runs.

Six cases: three straight-line shapes (`opt` generic, `optraiseopt` generic,
`unit` concrete), two loop shapes (`opt` + suspension inside + `break`,
`unit` + suspension before + `for`), and the F8 control. Chosen with `--only`
so the control is included without running the whole 82-case async matrix.

```
xdiff.exe --out /tmp/xd2_async_final --family async \
  --only c000-opt-np-straight-g-fn,c002-optraiseopt-np-straight-g-fn,\
c004-unit-np-straight-c-fn,c020-opt-in-break-g-fn,\
c061-unit-bef-for-c-fn,c081-optraiseopt-bef-straight-g-fn \
  --targets js,wasm,native --timeout-ms 180000 --keep
```

* selected 6 cases, 18 target-runs attempted, 15 executed (5/5/5 per target),
  3 excluded (the F8 control's three link failures)
* counts: `ALL_EQUAL` 5, `KNOWN_LINK_ICE` 1, `OUTPUT_MISMATCH` 0,
  `TEST_STATUS_MISMATCH` 0, `TEST_RC_MISMATCH` 0, `ICE` 0, `BUILD_FAIL` 0,
  `TIMEOUT` 0, `INFRA` 0, `SINGLE_TARGET` 0, `NO_TESTS` 0, `NO_RUN` 0
* wall clock 9.0 s (user 20.4 s, sys 16.6 s)

Per-case detail (all five non-control cases are identical across the three
targets, one test each):

| case | js | wasm | native | verdict |
|---|---|---|---|---|
| `c000-opt-np-straight-g-fn` | pass, 1/1/0 | pass, 1/1/0 | pass, 1/1/0 | `ALL_EQUAL` |
| `c002-optraiseopt-np-straight-g-fn` | pass, 1/1/0 | pass, 1/1/0 | pass, 1/1/0 | `ALL_EQUAL` |
| `c004-unit-np-straight-c-fn` | pass, 1/1/0 | pass, 1/1/0 | pass, 1/1/0 | `ALL_EQUAL` |
| `c020-opt-in-break-g-fn` | pass, 1/1/0 | pass, 1/1/0 | pass, 1/1/0 | `ALL_EQUAL` |
| `c061-unit-bef-for-c-fn` | pass, 1/1/0 | pass, 1/1/0 | pass, 1/1/0 | `ALL_EQUAL` |
| `c081-optraiseopt-bef-straight-g-fn` (F8 control) | link ICE, rc=1 | link ICE, rc=1 | link ICE, rc=1 | `KNOWN_LINK_ICE` |

`tests:a/b/c` is `total/passed/failed`; every executed target's canonical table
was `<case-id>=pass`.

A separate one-target probe confirms the `NO_TESTS` path live:

```
xdiff.exe --out /tmp/xd2_async_wg_final --family async \
  --only c000-opt-np-straight-g-fn --targets wasm-gc --timeout-ms 180000
```

→ `NO_TESTS` (wasm-gc prints `Warning: no test entry found.` and
`Total tests: 0, passed: 0, failed: 0.`), excluded from comparison.

## Known-ICE labelling (F8)

`c081-optraiseopt-bef-straight-g-fn` is the matrix's flagged `f8_control`
(`pub async fn[T] pick(select : (Int) -> T? raise?) -> T?` invoked after one
`@aio.pause()`). On all three targets `moon test` fails during `link-core`:

```
Error: failed to link asyncfuzz/c081-.../lib (js, blackbox test): ... moonc link-core ...
Oops, the compiler has encountered an unexpected situation.
Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed
```

`rc=1`, no `Total tests:` line, class `KNOWN_LINK_ICE`, signature
`known_f8:moonc.ml:125623` (upstream #1340). Note this is a **test-link-only**
failure: `moon build --target js/wasm/native` on the same source succeeds (that
is why the old build-based async path saw only `NO_RUN`). The control therefore
exercises the known-ICE exclusion exactly as intended: the case is labelled,
never compared, and never reported as a mismatch. A grep of
`stderr` for the three known signatures (`lower_array_make`,
`finish_stub_wrapper_shell`, `moonc.ml:125623` / `line 125623`) happens before
the generic ICE bucket, so this cannot leak into `TEST_STATUS_MISMATCH`.

## Mismatches

None. `summary.json` has `"mismatches": []`; the required "re-run 3× in fresh
directories plus a control" procedure was not triggered for the async family.
No async case in this sample failed a test on any target, so `TEST_STATUS_MISMATCH`
and `TEST_RC_MISMATCH` are covered by unit tests only, not by a live
observation.

## Limitations / what remains unproven

* **Bounded sample**: 6 of 82 async matrix cases (3 straight, 2 loop, 1 control).
  Every non-control case has exactly one assertion (`opt`/`optraiseopt` shapes
  compare the callback result; `unit` only checks that the call returns). This
  is not a claim about the other 76 cases, about `try`/`catch`, `early return`,
  `continue`, nested async calls, or `EntryTest` cases.
* **stdout/test-status only**: the compared surface is the driver's stdout
  report. Program `stderr`, `stdin`, argv, environment, timing/scheduling and
  filesystem effects are not compared. `moon test` merges compiler warnings and
  the `moonc link-core` argv into stderr; stderr is used only for
  classification, never compared.
* **Test names must be unique per case**: the table is keyed by test name, and
  two tests with the same name in one package would collapse (last wins). The
  renderer emits one uniquely named test, so this is not reachable today.
* **wasm and wasm-gc both run under moonrun.** `wasm` is the WASI shape,
  `wasm-gc` has no async test entry at all; neither is an independent wasm
  engine differential.
* **Debug only**: `moon test` defaults to debug. Release/`-O2` and the native
  release link path are not exercised (F7/F8 are known to be debug-specific).
* **`-v` output is a CLI contract, not an API.** The parser depends on the
  `[pkg] test <loc> ("<name>") <status>` line and on
  `Total tests: N, passed: N, failed: N.`; a future toolchain that changes
  either shape would degrade to `NO_RUN`/`unparsed` rather than to a wrong
  mismatch (there is a test for the malformed case), but the report counts would
  silently empty out.
* **Host safety**: one `moon`/`moonrun`/`node` process at a time; `--jobs` is
  accepted and clamped, but there is no concurrent path and none is tested.
