# xdiff MVP: cross-backend execution differential

Status: layout family swept over the whole curated matrix (160/160 cases),
async family moved to a test-driver comparison in `findings/xdiff_async.md`,
no new defect claimed.

The staged oracles (`cmd/featfuzz`, `cmd/asyncfuzz`) prove that generated
feature cases *build* (and that native test linking fails for F7/F9). They never
look at what the generated program prints. `cmd/xdiff` closes that gap for the
layout family: one generated source tree per case, built for several targets,
then executed, with stdout and exit status compared across the targets that
actually built.

## Design

Package: `moonbit/cmd/xdiff/` (executable), imports `featuregen`, `asyncgen`,
`exec`, `corpus`, `moonbitlang/x/fs`.

```
xdiff --out ABS_DIR [--family layout|async]
      [--targets wasm-gc,wasm,js,native] [--limit N] [--timeout-ms N]
      [--jobs N] [--only ID[,ID...]] [--keep]
```

`--family layout` is the exec-mode differential described below.
`--family async` has no `main` to execute, so it compares the generated test
driver's per-test outcomes instead; that mode is documented separately in
`findings/xdiff_async.md`. `--only` accepts a comma-separated id list so a
non-prefix sample (or a single calibration case) can be selected in one run.

For each selected case:

1. Render a fresh package directory under `<out>/cases/<case-id>` (layout:
   `moon.mod`/`moon.pkg`/`lib.mbt`/`main.mbt`/`main_test.mbt` from
   `featuregen.render_package`; async: `asyncgen.render_package`).
2. For each target in the requested order, serially (layout family; the async
   family runs `moon test` instead, see below):
   * `moon build --target T` in that directory (this is what produces `main`);
   * locate the artifact under `_build/<T>/debug/build/` (`.wasm` for wasm and
     wasm-gc, `.js` for js, `.exe` for native; `.wasm.map` is skipped);
   * execute it: `moonrun <artifact>` for `wasm`/`wasm-gc`, `node <artifact>`
     for `js`, the artifact itself for `native`.
3. Compare only targets that built and ran. A build/link failure is terminal
   for that target; its empty stdout is never compared as if it were output.

`--targets` defaults to `wasm-gc,wasm,js`. `--jobs` is accepted for CLI
symmetry, clamped to 2, but the driver has no concurrent path: all builds run
serially, because the host this was developed on was previously overloaded by
concurrent `moon` processes.

Why `moon build` + explicit run instead of `moon run .`: `moon run` collapses
build and execution into one exit status, so a link ICE and a program exit
cannot be told apart. The separate build stage preserves that boundary (and
reuses the same artifact path convention as `moon build`'s artifact list).

## Comparison rule

* **stdout**: normalized by stripping trailing spaces, tabs, `\r` and `\n`
  only at the very end of the captured text. Leading and interior whitespace is
  preserved exactly; a two-line output cannot equal a one-line output. Raw
  stdout is recorded verbatim up to 1 MiB, and the digest is SHA-1 of the *raw*
  stdout, so a trailing-newline-only difference is visible in the digest even
  though it compares equal.
* **exit status**: compared exactly (`rc`), including negative signal
  conventions from `exec.run_isolated`. A target that ran with `rc=3` is still
  `executed=true`, class `RUN_RC`; it participates in the comparison.
* **missing targets**: a target that timed out or failed to build is excluded
  from the comparison. If exactly one target executed, the case is
  `SINGLE_TARGET`, never a false divergence. Zero executed targets gives
  `NO_RUN` (or `INFRA`/`BUILD_FAIL`/`KNOWN_LINK_ICE`/`ICE`/`TIMEOUT` when a
  failure class is present).
* **verdict precedence**: `OUTPUT_MISMATCH` (two executed targets differ, by
  normalized stdout or rc) > `ICE` (unknown compiler crash) >
  `KNOWN_LINK_ICE` (F7/F8/F9 upstream signature) > `TIMEOUT` >
  `SINGLE_TARGET` > `BUILD_FAIL` > `INFRA` > `ALL_EQUAL` > `NO_RUN`.
  A known ICE is never counted as a mismatch; a case with two equal outputs and
  a known-ICE third target is `KNOWN_LINK_ICE`.
* **known signatures** are matched textually on build/link stderr:
  `lower_array_make` (F7, upstream #1322), `finish_stub_wrapper_shell` (F9,
  upstream #1344), `moonc.ml:125623` (F8, upstream #1340). Everything else that
  looks like a compiler crash is `ICE` with a normalized signature
  (`build:error:<first Error: line>` / `Machine_error` / `assert_failure` /
  signal number).

## Output files

`results.jsonl` — one line per case: id, index, verdict, and per target
`stage` (`build`/`run`), `rc`, `executed`, `class`, `signature`, raw-stdout
digest, short stdout (700 B), short stderr, artifact path, elapsed ms.

`summary.json` — schema `xdiff/1`, per-class counts, executions per target,
distinct signatures with occurrence counts, `known_ice` entries, and a
`mismatches` array containing every observation (stdout up to 2 KiB) for each
`OUTPUT_MISMATCH` case.

Case directories are deleted unless `--keep` is passed or the case is a
mismatch/ICE/known-ICE candidate.

## The run that was performed

Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`, `moonc
v0.10.20+65efd5b93 (2026-11-05)`. Default debug build (`moon build` without
`--release`). All runs serial.

Pilot A — 24-case layout prefix + forced F7 seed/control, 3 targets:

```
moon run cmd/xdiff -- --out /tmp/xd_pilot1 --family layout --limit 24 \
  --targets wasm-gc,wasm,js --timeout-ms 120000
```

26 cases, 78 target builds, 78 executions, 26/26 `ALL_EQUAL`, 0 mismatches,
0 ICE, 0 build failures, 0 timeouts. Wall clock 9.6 s.

Pilot B — same selection plus `native`, four targets:

```
moon run cmd/xdiff -- --out /tmp/xd_pilot3 --family layout --limit 24 \
  --targets wasm-gc,wasm,js,native --timeout-ms 180000
```

* selected: 26 cases (24-case prefix + `L0080-vt-push-int_enum_string` and its
  plain-struct control `L0085-plain-push-int_enum_string`)
* executions: wasm-gc 26, wasm 26, js 26, native 25 (104 attempted, 103 ran)
* counts: `ALL_EQUAL` 25, `KNOWN_LINK_ICE` 1, `OUTPUT_MISMATCH` 0, `ICE` 0,
  `BUILD_FAIL` 0, `TIMEOUT` 0, `INFRA` 0, `SINGLE_TARGET` 0, `NO_RUN` 0
* wall clock 22.6 s, user 49.5 s

F7 seed/control, run individually to exercise the classifier:

```
moon run cmd/xdiff -- --out /tmp/xd_f7 --only L0080-vt-push-int_enum_string \
  --targets native --keep --timeout-ms 180000
moon run cmd/xdiff -- --out /tmp/xd_f7c --only L0085-plain-push-int_enum_string \
  --targets native --keep --timeout-ms 180000
```

* `L0080-vt-push-int_enum_string` (F7 shape: `#valtype` struct `Int` + enum
  with `String` payload, `Array[Entry]` push): native build/`link-core` fails,
  `rc=255`, class `KNOWN_LINK_ICE`, signature `known_f7:lower_array_make`
  (upstream #1322). The other three targets ran and agreed (`ALL_EQUAL`).
* `L0085-plain-push-int_enum_string` (same fields and op without `#valtype`):
  native builds and runs, all four targets `ALL_EQUAL`. This is the control
  proving the F7 failure is tied to `#valtype`, not to the field shape or the
  driver.

Native-inclusive smaller run (prefix 8 + controls) reproduced the same result:
9 `ALL_EQUAL`, 1 `KNOWN_LINK_ICE`, 8.6 s wall.

Async probe (historical): the build-based async path was `NO_RUN` because
async packages have `supported_targets = "wasm+js+native"` and contain only a
library plus tests — no `main`, so `moon build` emits no artifact. That path is
no longer used: the async family now runs `moon test --target T` and compares
the test driver's report. See `findings/xdiff_async.md` for the rule, the
6-case run (18 target runs, 5 `ALL_EQUAL`, 1 F8 `KNOWN_LINK_ICE`, 0 status
mismatches) and its limitations.

### Full layout matrix sweep (this revision)

The bounded 26-case pilots above were extended to the **whole curated matrix**,
four targets, one serial invocation:

```
xdiff.exe --out /tmp/xd2_layout_final --family layout \
  --targets wasm-gc,wasm,js,native --timeout-ms 180000
```

* selected 160 cases, 640 target builds attempted, 620 executed
  (wasm-gc 160, wasm 160, js 160, native 140)
* counts: `ALL_EQUAL` **140**, `KNOWN_LINK_ICE` **20**, `OUTPUT_MISMATCH` 0,
  `ICE` 0, `BUILD_FAIL` 0, `TIMEOUT` 0, `INFRA` 0, `SINGLE_TARGET` 0,
  `NO_RUN` 0
* distinct signatures: 1 — `known_f7:lower_array_make`, 20 occurrences, all
  `target=native`, all `rc=255`, all at build/link
* wall clock 2 m 18.0 s (user 5 m 03.9 s, sys 2 m 54.6 s); the sweep was run
  twice (once before the async changes, once with the committed binary) with
  identical counts

The 20 known-ICE cases are **four** field-shape families × 5 operations
(`push`, `makei`, `map`, `filter`, `slice`), not two:

| family | frozen cases | ops |
|---|---|---|
| `int_enum_string` | L0080–L0084 | 5 |
| `int_enum_array_int` | L0090–L0094 | 5 |
| `int64_enum_string_array_int` | L0140–L0144 | 5 |
| `int_bool_enum_array_int_string` | L0150–L0154 | 5 |

Their `plain-*` controls (L0085–L0089, L0095–L0099, L0145–L0149,
L0155–L0159) are `ALL_EQUAL` on all four targets, so the failure tracks
`#valtype`, not the field shape or the driver. Every other case (140) is
`ALL_EQUAL` on all four targets, including the 20 cases where native alone
fails to link the `vt-*` shape.

## Mismatches

None. `summary.json` for Pilot B and for the full 160-case sweep both have
`"mismatches": []` and `"OUTPUT_MISMATCH": 0`. Because no output divergence
appeared in 620 executed target-runs, the required "re-run 3× in fresh
directories plus a control" procedure was not triggered. The F7 plain-struct
control above is the control for the known-ICE classifier, not for a mismatch.

## Known-ICE labels

* `known_f7:lower_array_make` — native build/link of the 20 `vt-*` cases above
  (4 field-shape families × 5 ops), upstream #1322. Not a new finding.
* `known_f8:moonc.ml:125623` — now exercised for real by the async test-driver
  mode: the matrix's flagged `f8_control` async case fails `link-core` on js,
  wasm **and** native under `moon test`, and is labelled `KNOWN_LINK_ICE`
  without being compared (`findings/xdiff_async.md`). Upstream #1340.
* `known_f9:finish_stub_wrapper_shell` is still recognized by the classifier but
  not exercised: it needs an `extern "C"`/`V128` layout case, which is not in
  the curated matrix. Its label is unit-tested only.

## Limitations / what remains unproven

* **Sample**: the full 160-case curated layout matrix was run on four targets,
  so the layout counts above cover every curated case, not a prefix. This is
  still a claim about *those* 160 rendered cases only, not about the compiler as
  a whole; the generator itself is not fuzzed here.
* **Debug only**: `moon build` defaults to debug. Native release/LLVM
  optimization paths (`moonc` `-O2`, `link-core` with different flags) are not
  exercised, and the F7 failure is known to be debug-specific.
* **wasm-gc vs wasm semantics**: both are executed with `moonrun`, which runs
  the GC and WASI module shapes. They are not a spec-level wasm engine
  differential, and `wasm` here is the repo's existing WASI pipeline, not an
  independent runtime.
* **stdout-only oracle**: stderr is captured but only used for classification,
  never compared; programs that write diagnostics to stderr could diverge
  silently. No stdin, no argv, no environment variation, no filesystem side
  effects are compared.
* **Timeouts**: build and run each get `--timeout-ms` (180 s in the pilots). A
  timeout is excluded from comparison, so a backend that hangs could hide an
  output divergence rather than report one.
* **Async**: the test-driver differential in `findings/xdiff_async.md` covers 6
  of 82 async cases and compares only the driver's per-test report; no `main` is
  synthesized, so async cases are still not compared on program stdout.
* **Host safety**: `--jobs` never runs more than one `moon` process in this
  implementation despite accepting the flag; the serial behavior is the only
  one tested.
