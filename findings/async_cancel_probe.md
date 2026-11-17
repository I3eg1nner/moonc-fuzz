# Async cancellation / timeout / combinator probe: no new signature

Date: 2026-11-17. Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`,
`moonc v0.10.20+65efd5b93 (2026-11-05)`. Host: Linux x86_64, single machine,
load average ~13 during the run. Worktree branch: `agent/asynccancel`.

This is a **negative** result. A 55-case, serially executed matrix over
`moonbitlang/core/async` timeout, cancellation and combinator state machines
produced **no new compiler-crash signature**. The only crash in the matrix is
the already-known F8 `link-core` assertion (`moonc.ml:125623`, upstream #1340),
re-hit here through two control shapes.

The axis is new relative to the existing `asyncgen` matrix: that matrix varied
callback shape, pause position and simple control flow. This probe drives the
runtime state machines themselves — timer expiry, task cancellation,
`protect_from_cancel`, and `all`/`any` cancellation propagation.

## 1. Method

Each case is a complete one-file MoonBit package written to a fresh directory
(`/tmp/ac_probe/matrix/<case_id>`), then driven through four stages per target:

```
moon check     --target T -j 1
moon build     --target T -j 1
moon test      --target T -j 1 --build-only
moon test      --target T -j 1
```

* Targets, in order: `native`, then `js` and `wasm` only if the case passed
  every native stage. `wasm-gc` is deliberately excluded (the `@aio` package
  used by the F8 controls does not support it).
* Every failure is recorded at the **first failing stage** with its rc and a
  normalized signature. A stage timeout is 60 s (`TIMEOUT` if hit).
* **Strictly serial**: one `moon` process at a time, `-j 1` on every command,
  no background jobs. This avoids the parallel-`moon` contention hazard
  documented in `findings/feature_probe_negative.md` §3.
* The runner is `scripts/probe/async_cancel_probe.py` (scratch-only, not part
  of the MoonBit build); the compact per-case result is
  `findings/async_cancel_probe_results.jsonl`. Each case module is 8–20 lines,
  has `moon.mod` / `moon.pkg`, imports `moonbitlang/core/async`, and adds
  `moonbitlang/async@0.22.9` as `@aio` only for the two F8 controls.

The core API was read from `/home/user/.moon/lib/core/async/` before
generation; no signature was guessed:
`with_timeout(Int32, async () -> X, error?~)`,
`with_timeout_opt(Int32, async () -> X) -> X?`, `all(ArrayView[async () -> X])`,
`any(ArrayView[async () -> X], allow_failure?~)`, `with_task_group`,
`TaskGroup::spawn`, `Task::wait`, `Task::try_wait`, `Task::cancel`,
`handle_cancellation`, `protect_from_cancel`, `sleep`, `pause`,
`is_being_cancelled`.

The frozen matrix is `scripts/probe/async_cancel_probe.py`; it regenerates
every module and re-runs the same command sequence.

## 2. Matrix actually run

55 cases. Counts per family:

| Family | Cases | What it varies |
|---|---:|---|
| `F1_with_timeout` | 12 | body returns immediately; one `pause()`; pause loop; short `sleep`; throw before timeout; throw after pause; expire during `sleep`; expire during pause loop; `defer` on timeout; custom `error=`; F8 `raise?` callback **inside** `with_timeout`; F8 callback bare (control) |
| `F2_with_timeout_opt` | 7 | `Some` immediate; `Some` after pause; `None` on expire; `None` on pause loop; body raises; `protect_from_cancel` cleanup returns `Some`; timeout nested inside timeout |
| `F3_all_any` | 11 | `all` over 1 / 2 / 5 closures (mixed immediate+`pause`, all-pause), one branch raises, sibling cancellation on raise; `any` over 1 / 2 / 5 mixed, failure without `allow_failure`, failure with `allow_failure` |
| `F4_cancel` | 9 | cancel during `sleep`; cancel with `handle_cancellation`; cancel **before first suspension**; cancel **after completion**; cancel twice; child error cancels sibling; `with_timeout` vs `protect_from_cancel`; timeout cancels `all`; cancel a nested task group |
| `F5_nested` | 8 | `with_timeout` around `all`; `all` of `with_timeout`; `any` with raising branch; `with_timeout` around `any`; `any` of `with_timeout`; outer timeout shorter; inner timeout shorter; `all` inside `any` |
| `F6_control` | 8 | bare pause loop, bare `all`, bare `any`, bare task cancel, task wait without cancel, bare `sleep`, synchronous map, synchronous throw |

The two F8 controls are the only cases using `@aio`; everything else uses
`moonbitlang/core/async` only. Cases `tw_11`/`tw_12` are controls for the
already-known F8 signature (one wraps the callback in `with_timeout`, one does
not); they are not counted as a new finding.

Case IDs and per-target outcomes (P = all four stages rc=0; `F8` = fails at
`test-build` with the known assertion):

| Family | Cases and native / js / wasm |
|---|---|
| F1 | `tw_01` P/P/P, `tw_02` P/P/P, `tw_03` P/P/P, `tw_04` P/P/P, `tw_05` P/P/P, `tw_06` P/P/P, `tw_07` P/P/P, `tw_08` P/P/P, `tw_09` P/P/P, `tw_10` P/P/P, `tw_11` F8/–/–, `tw_12` F8/–/– |
| F2 | `to_01`…`to_07` all P/P/P |
| F3 | `al_01`…`al_06`, `an_01`…`an_05` all P/P/P |
| F4 | `cx_01`…`cx_09` all P/P/P |
| F5 | `nx_01`…`nx_08` all P/P/P |
| F6 | `ct_01`…`ct_08` all P/P/P |

`–` means "not attempted": native-first stops the target sequence on native
failure. The known F8 signature was separately confirmed on `js` and `wasm`
for `tw_12` with `moon test --build-only` (rc 1, same assertion).

Total primary-matrix stage invocations: **642** (218 native + 212 js + 212
wasm). Sum of stage wall times 225.6 s; native is slower only because each
fresh module pays first-build cost, and the two F8 link failures take ~4 s.

## 3. Results by family and target

| Family | native attempted / passed | js attempted / passed | wasm attempted / passed |
|---|---:|---:|---:|
| F1_with_timeout | 12 / 10 | 10 / 10 | 10 / 10 |
| F2_with_timeout_opt | 7 / 7 | 7 / 7 | 7 / 7 |
| F3_all_any | 11 / 11 | 11 / 11 | 11 / 11 |
| F4_cancel | 9 / 9 | 9 / 9 | 9 / 9 |
| F5_nested | 8 / 8 | 8 / 8 | 8 / 8 |
| F6_control | 8 / 8 | 8 / 8 | 8 / 8 |
| **Total** | **55 / 53** | **53 / 53** | **53 / 53** |

"Passed" means all four stages rc=0, including actual test execution at the
last stage. No case timed out; no `TIMEOUT` row exists.

## 4. Crash signatures

Exactly one distinct crash signature occurred.

| Signature | Stage | rc | Cases | Known? |
|---|---|---:|---|---|
| `Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed` | native `moon test --build-only` (`link-core`) | 1 | `tw_11_raise_q_inside`, `tw_12_raise_q_bare` | **known: F8**, upstream #1340 |

Observed tail (both cases, all three targets for `tw_12`):

```
Error: failed to link probe/tw_11_raise_q_inside (native, inline test): ...
Oops, the compiler has encountered an unexpected situation.
Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed
```

This is the same signature as `poc/f8_async_raise_ice/`; wrapping the `raise?`
callback in `with_timeout` changes the call context but not the signature, so
it remains **known**, not new. `tw_11` was re-run 3/3 times in fresh copies
(delete directory/`_build` each time): native `test-build`, rc 1, same
signature every time. `tw_12` was also re-run 3/3 natively with the same
result.

No `Machine_error`, `lower_array_make`, `finish_stub_wrapper_shell`, SIGSEGV,
SIGABRT, `Stack_overflow`, OOM or other ICE banner appeared. In particular,
none of the timeout/cancellation/combinator shapes produced a compiler crash
on `js` or `wasm`.

## 5. Diagnostic-only failures and serial re-checks

There was **one** diagnostic-only failure in the whole matrix, and it was a
probe bug, not a compiler defect:

| Case | Stage/target | First result | Serial re-check |
|---|---|---|---|
| `nx_07_inner_shorter` | native `check` | rc 1, `diag:[4014]` "Expr Type Mismatch" | generator annotation was wrong (`with_timeout` vs `with_timeout_opt` nesting); case corrected, then 3/3 fresh-copy runs pass all stages on native/js/wasm |

No `[4021]`, `[0055]`, `[4122]`, `[4024]` or similar contention diagnostics
appeared, because every command ran serially with `-j 1`. There is therefore
no diagnostic-only compiler result to explain away.

## 6. Infra exclusions

* `wasm-gc` skipped by design (F8/@aio targets are `js+native+wasm`).
* Native builds are the default **debug** builds; no release build was probed.
* The two F8 controls were not carried to `js`/`wasm` in the primary matrix
  (native-first rule). A targeted `--build-only` check on `tw_12` shows the
  same known assertion on `js` and `wasm` (rc 1), so this is coverage, not a
  fourth signature.
* `@aio` is `moonbitlang/async@0.22.9` from the offline cache and is used only
  for the two F8 controls; all other cases avoid the third-party package.
* `tw_10_custom_error` asserts that *an* error is raised, not the identity of
  the custom error value (the abstract `Error` type cannot be pattern-matched
  in the probe package). This weakens semantic verification, not crash
  coverage.
* Only rc / terminal stage / signature were compared. Test stdout is not
  compared here; assertions inside each case are the semantic check.

## 7. Limitations

* Bounded sample: 55 hand-curated cases from one matrix; a negative result does
  not prove the compiler correct outside these shapes.
* Single host, single pinned toolchain, debug builds, native-first.
* Timer-based cases are timing-sensitive. The design uses 10× margins
  (e.g. 50 ms timeout vs 500 ms sleep), and all passed, but a heavily loaded
  host could turn an expected `None` into a different scheduling interleaving.
* `any` returns whichever branch wins; the cases accept any branch value in the
  legal set rather than asserting a fixed winner.
* Cancellation coverage is API-level (`Task::cancel`, timeout-driven
  cancellation, task-group failure). It does not cover IO cancellation or
  external event-loop cancellation paths.
* Only two `raise?` shapes are included, and only as known-signature controls;
  this is not a re-probe of the F8 axis.

## 8. Conclusion

No new compiler signature was found. The timeout, `with_timeout_opt`,
`all`/`any`, `Task::cancel`, `handle_cancellation`, `protect_from_cancel` and
nested-combinator state machines all check, build, link and execute on native,
`js` and `wasm` for this 55-case sample. The only crash is the known F8
`link-core` assertion, re-hit deterministically through a new wrapper shape
and therefore still labelled **known**. No PoC was created and `moonbit/`
source was not modified.
