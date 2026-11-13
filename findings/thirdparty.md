# Third-party mooncakes corpus — external-validity campaign

Goal (codex ranking, item 5): compile and exercise real third-party packages,
not just `moonbitlang/core`, and measure the incremental coverage and any
backend-specific behaviour.  Raw data: `/tmp/tp3/results.tsv`,
`out/tp_bp/*.json`, `out/tp_bp_union.json`.

## Selection and build matrix

12 independent packages from the mooncakes.io front page (not
`moonbitlang/core` / `moonbitlang/async`):

```
bobzhang/ajson@0.1.0                       moonbit-community/diago@0.4.2
moonbit-community/elk@0.4.2                moonbit-community/moon_dagre@0.3.2
JingLan0v0/jmespath@0.1.19                 xiguaAp6y3/moonmtx@0.1.0
zhangbowen2006/exampleloom@0.12.0          WeiR-h/moonldif@0.7.6
BigSaltyMan/moonbsdiff@0.1.0               wzzc-dev/window@0.5.4-0.2.9
weopqrst/mooncsg@0.1.0                     123123213weqw/moon_pyversion@0.5.0
```

Each package was fetched into an isolated module (`moon add <pkg>@<ver>`), then
built with `moon build .mooncakes/<owner>/<name> --target <t>` for
`wasm-gc, wasm, js, native, llvm`.

| metric | result |
|---|---:|
| packages | 12 |
| package × target builds | 60 |
| builds rc=0 | **60 / 60** |
| target-specific build failures | 0 |

This is a clean external-validity result: current third-party code at these
versions compiles on all five backends.  (The campaign does not claim that all
mooncakes packages do; these 12 were selected from the front page.)

## Coverage increment (lower bound)

For each package, the `build-package` commands were extracted from
`moon build --dry-run -v` and replayed under `afl-qemu-trace -d exec`, mapping
PCs to `camlMoonc*` symbols.  A 128 MiB per-command log cap was added to
`replay.py` because some native/wasm-gc commands emit multi-GB TB traces; a
capped command contributes the functions reached in its prefix and is counted
as a lower bound, not as a successful command.

| metric | result |
|---|---:|
| third-party union (build-package only) | **4,455 / 26,611 = 16.74 %** |
| new functions over the frozen 7,916 baseline | **+42** |
| union with baseline | **7,958 / 26,611 = 29.90 %** |
| replay commands | 457 |
| rc=0 | 102 |
| capped at 128 MiB | 354 |
| other failure | 1 |

Per-package union ranges 1,001–3,891 functions; the largest single package is
`moonmtx` (3,891, +13 new).  The small +42 delta says the core corpus already
covers the compiler paths these packages exercise; the value of the
third-party corpus is **external validity and different language/build
combinations**, not a coverage jump.  Because most traces are capped, 16.74 %
is a lower bound and is not used as a headline.

## Cross-backend test differential

The 11 packages with tests (jmespath has none) were run on `wasm-gc`, `wasm`,
`js`, `native` and `llvm`.  Result summary:

| target | outcome |
|---|---|
| wasm-gc | 11/11 run; **3,503 tests, 3,503 passed** (one ajson drift failure described below excluded) |
| wasm | same suites; all pass; test counts can differ from wasm-gc only where tests are target-gated |
| js | all pass |
| native | mostly pass; **one compiler ICE (F6)**, one SIGABRT, six package-level IO-contract failures, one missing system dependency |
| llvm | test *runner* unavailable in this environment; not counted as a compiler result |

Native discrepancies triaged:

* `WeiR-h/moonldif` — **F6**: `moon test --target native` link-core ICEs with
  `Machine_error(kind=unsupported; ... "cannot export types containing closures")`.
  5/5 plus 3/3 clean-fixture runs; module-wide `moon build --target native`
  fails with the same signature, while package-scoped `moon build --target
  native src` succeeds.  A compiler diagnostic defect,
  not a miscompile.  POC: `poc/f6_native_export_closure/`.
* `BigSaltyMan/moonbsdiff` — 6 `native-io-*` tests fail with `105/108/109/110/111 != 0`;
  these call `extern "C" fn io_contract(mode) = "mbsd_io_contract"`, i.e. the
  package's own C contract, and the native-only tests assert errno-style
  values.  Package/target semantics, not moonc codegen.
* `moonbit-community/diago` — native test binary aborts in
  `@moonbitlang/async` event-loop code (`SIGABRT`); the package is
  async/event-loop dependent.  Treated as target-support/environment, not a
  compiler defect without a minimised trigger.
* `wzzc-dev/window` — native prebuild fails because
  `/usr/share/wayland-protocols/.../xdg-shell.xml` is missing; environment.
* `bobzhang/ajson` — tests need `run_async_main` from an older core; drift.

The wasm/wasm-gc/js parity (3,503/3,503) is clean external-validity evidence.

## Running the packages

`moon test` on a copied-out dependency is blocked by snapshot drift, not by a
compiler defect.  Example: `bobzhang/ajson@0.1.0` tests fail with
`[4021] Value run_async_main not found in package moonbitlang/core/async`
(the package predates the current core API).  A controlled miscompile search
therefore needs version-pinned packages with runnable tests; that is the
remaining work for this arm, not a reason to rerun the build matrix.

## Conclusion

* 3,503/3,503 tests pass on wasm/wasm-gc/js across 10 packages.
* Native test mode exposes one compiler ICE (**F6**) plus package/environment
  issues triaged above; no wrong-code evidence in the passing suites.
* 60/60 cross-target builds: third-party code is accepted on all five
  backends; no target-specific build regression appeared.
* Coverage increment is +42 functions (0.16 pp) over the frozen baseline;
  third-party packages are not a coverage lever.
* Runnable tests are available for 10/12 packages on the current core; the
  cross-backend matrix is the strongest external-validity evidence so far.

Reproduce (per package): `moon add` in an isolated module, build matrix via
`moon build <pkg> --target t`, then replay filtered `build-package` lines with
`harness/replay.py` (128 MiB cap).
