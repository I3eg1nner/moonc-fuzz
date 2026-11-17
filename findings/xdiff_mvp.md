# xdiff MVP: cross-backend execution differential

Status: MVP, bounded sample, no new defect claimed.

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
      [--jobs N] [--only ID] [--keep]
```

For each selected case:

1. Render a fresh package directory under `<out>/cases/<case-id>` (layout:
   `moon.mod`/`moon.pkg`/`lib.mbt`/`main.mbt`/`main_test.mbt` from
   `featuregen.render_package`; async: `asyncgen.render_package`).
2. For each target in the requested order, serially:
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

Async probe:

```
moon run cmd/xdiff -- --out /tmp/xd_async --family async --limit 2 \
  --targets wasm-gc --keep
```

2 cases, both `NO_RUN`: `moon build --target wasm-gc` succeeds but emits no
artifact because async packages have `supported_targets = "wasm+js+native"`
and, more importantly, contain only a library plus tests — no `main`. A
manual `moon test --target wasm --build-only` (and `js`) in the rendered
directory compiled successfully against the offline
`moonbitlang/async@0.22.9`, so dependency resolution works; executing async
test drivers on multiple backends was not implemented in this MVP.

## Mismatches

None. `summary.json` for Pilot B has `"mismatches": []`. Because no output
divergence appeared, the required "re-run 3× in fresh directories plus a
control" procedure was not triggered. The F7 plain-struct control above is the
control for the known-ICE classifier, not for a mismatch.

## Known-ICE labels

* `known_f7:lower_array_make` — native build/link of the F7 seed, upstream
  #1322. Not a new finding.
* `known_f9:finish_stub_wrapper_shell` and `known_f8:moonc.ml:125623` are
  recognized by the classifier but were not exercised by this sample: F9
  requires an `extern "C"`/`V128` case and F8 is an async case, and neither is
  in the 24-case layout prefix. Their labels are unit-tested only.

## Limitations / what remains unproven

* **Bounded sample**: 26 of 160 layout cases, chosen as a prefix plus the two
  F7 calibration cases. This is not a correctness claim about the other 134
  cases or about the compiler as a whole.
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
* **Async**: no execution differential; only rendering/build resolution was
  probed. The async matrix's `EntryFn` cases need a synthesized `main` (generic
  type parameters, `raise`/`raise?` effects) before they can be run as programs.
* **Host safety**: `--jobs` never runs more than one `moon` process in this
  implementation despite accepting the flag; the serial behavior is the only
  one tested.
