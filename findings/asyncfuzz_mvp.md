# asyncfuzz MVP — async state-machine feature generator

Pinned toolchain: `moon 0.1.20261104 (940aa18)` / `moonc v0.10.20+65efd5b93`,
`moonbitlang/async@0.22.9` from the offline cache.  Target: `native` only.

`moonbit/asyncgen` is a pure generator package (model, renderer, signature
normaliser); `moonbit/cmd/asyncfuzz` is the driver.  Every case is rendered as a
standalone MoonBit module (`moon.mod`, `lib/moon.pkg`, `lib/lib.mbt`,
`lib/lib_test.mbt`) and compiled in its own directory, so one compiler crash
cannot contaminate the next case.

## Design

- **Generator, not mutator.**  A curated feature matrix is materialised
  deterministically; case IDs encode the ordinal and all axis values, e.g.
  `c037-optraiseopt-bef-for-c-fn`.  Re-enumeration is byte-identical.
- **One module per case.**  `lib/lib.mbt` holds the generated async function
  (or a marker for test-only cases); `lib/lib_test.mbt` holds one `async test`
  that forces linking and asserts the expected callback result.
- **Driver.**  For each case the four stages below run in order; the first
  non-zero stage is recorded with its raw signature.  A crash signature is a
  candidate, an infra/network failure is discarded, and a plain test assertion
  failure is `test_fail` (program behaviour, not a compiler signature).
- **Known-positive calibration first.**  The F8 control is executed before the
  searched cases.  Its signature is checked against
  `known_f8_signature() = "moonc.ml:125623:29-35|Assertion failed"` and reported
  as `known_f8`, never as a new finding.
- **Candidate protocol.**  A non-F8 crash signature triggers three re-runs in
  fresh directories plus controls that remove `@aio.pause()` and, for
  `raise?` shapes, change `raise?` to `raise`.  A candidate is reported only if
  it is stable; root cause is not claimed.  This path was not triggered by the
  runs below (no non-F8 signature was observed).

## Matrix axes and size

| axis | values | count |
|---|---|---|
| callback shape | `(Int) -> T?`, `(Int) -> T? raise`, `(Int) -> T? raise?`, `(Int) -> T`, `() -> Unit` | 5 |
| suspension | none, before, inside, after | 4 |
| control | straight, for, while, break, continue, early return, try/catch, nested async call | 8 |
| type | generic `T`, concrete `Int` (`Unit` is always concrete) | 2 |
| entry | exported async function + blackbox test, async test only | 2 |

Nominal Cartesian product: 5 × 4 × 8 × 2 × 2 = **640**.  The matrix is
deliberately curated to **82 rows** (81 searched cases + 1 F8 control), well
inside the ~40–100 budget asserted by the unit tests:

| axis | distribution (82 rows) |
|---|---|
| shape | opt 17, optraise 16, optraiseopt 18, plain 15, unit 16 |
| suspension | none 18, before 24, inside 20, after 20 |
| control | straight 14, for 15, while 15, break 15, continue 15, earlyret 3, try 2, nested 3 |
| type | generic 34, concrete 48 |
| entry | fn 77, test 5 |

## Stage semantics

| # | command | meaning |
|---|---|---|
| 1 | `moon check --target native` | type-check the generated package |
| 2 | `moon build --target native` | build the library |
| 3 | `moon test --target native --build-only` | build and **link** the blackbox test binary |
| 4 | `moon test --target native` | run the test |

Stages stop at the first failure.  Classification:

- `ok` — all four stages return 0.
- `known_f8` — crash signature equals (or shares the location prefix of) the
  F8 key.
- `new_candidate` — any other compiler crash signature; only then are the
  three fresh re-runs and the two controls executed.
- `test_fail` — stage 4 returns non-zero without a crash signature (generated
  assertion mismatch).
- `invalid` — stages 1–3 return non-zero without a crash signature.
- `infra` / `timeout` — network/dependency markers or the per-stage timeout;
  excluded from evidence (none occurred).

Signature normalisation canonicalises `File "moonc.ml", line L, characters
A-B` to `moonc.ml:L:A-B|message`, and also recognises `Machine_error`,
`assert_failure`, signals (`signal:-11`), OCaml exceptions, stack overflow and
OOM.  Test assertion text is intentionally *not* a signature.

## F8 calibration result

Control `c081-optraiseopt-bef-straight-g-fn` rendered exactly the known shape:

```moonbit
///|
pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}
```

and its test forces the link:

```moonbit
///|
async test "c081-optraiseopt-bef-straight-g-fn" {
  let r = @lib.pick(x => if x == 1 { Some(x) } else { None })
  assert_eq(r, Some(1))
}
```

Observed, `--target native --limit 12`:

| field | value |
|---|---|
| status | **`known_f8`** (`reproduced: true`) |
| failing stage | **`test-build-only`** (`moon test --target native --build-only`) |
| rc | **1** (the `moon` driver maps the ICE to 1) |
| signature | **`moonc.ml:125623:29-35\|Assertion failed`** |
| elapsed, all stages | 1,079 ms |

Raw failure: `moonc link-core` aborts with the ICE banner
`Oops, the compiler has encountered an unexpected situation.` followed by
`Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed`.
`moon check` and `moon build` both return 0, matching the documented F8 shape:
type-check and codegen succeed, only the linked test binary crashes.

## Observed results — required run

Command (sequential, 120 s per stage, no parallel jobs):

```
cd moonbit
moon run cmd/asyncfuzz -- --out /tmp/asyncfuzz_run --target native --limit 12
```

`matrix=82 selected=12 ran=12 duration=16,603 ms`; counts: `ok=12`; no new
signature.  The control is written to `results.jsonl` first, then the twelve
selected cases.

| case | kind | status | stage | rc | signature | ms |
|---|---|---|---|---|---|---|
| `c081-optraiseopt-bef-straight-g-fn` | f8_control | known_f8 | test-build-only | 1 | `moonc.ml:125623:29-35\|Assertion failed` | 1079 |
| `c000-opt-np-straight-g-fn` | case | ok | test | 0 | — | 1222 |
| `c001-optraise-np-straight-g-fn` | case | ok | test | 0 | — | 1243 |
| `c002-optraiseopt-np-straight-g-fn` | case | ok | test | 0 | — | 1236 |
| `c003-plain-np-straight-g-fn` | case | ok | test | 0 | — | 1236 |
| `c004-unit-np-straight-c-fn` | case | ok | test | 0 | — | 1239 |
| `c005-opt-np-straight-c-fn` | case | ok | test | 0 | — | 1248 |
| `c006-optraiseopt-np-straight-c-fn` | case | ok | test | 0 | — | 1241 |
| `c007-plain-np-straight-c-fn` | case | ok | test | 0 | — | 1241 |
| `c008-opt-np-straight-c-test` | case | ok | test | 0 | — | 1223 |
| `c009-optraise-np-straight-c-test` | case | ok | test | 0 | — | 1231 |
| `c010-optraiseopt-np-straight-c-test` | case | ok | test | 0 | — | 1227 |
| `c011-plain-np-straight-c-test` | case | ok | test | 0 | — | 1210 |

## Full-matrix sweep (supplementary)

To check whether the first twelve cases were representative, the whole matrix
was run once (also sequentially):

```
moon run cmd/asyncfuzz -- --out /tmp/asyncfuzz_full --target native --limit 82
```

`selected=82 ran=82 duration=106,235 ms`; counts: **`ok=72`, `known_f8=10`,
`test_fail=0`, `new_signatures=[]`**.

All ten selected F8 hits share the single signature above and are *not*
candidates: they are `optraiseopt` cases where a pause precedes the `raise?`
callback call — straight (`c081`), for/while/break/continue with the pause
before or inside the loop (`c037`, `c038`, `c040`, `c041`, `c043`, `c044`,
`c046`, `c047`) and the nested async call (`c079`).  The calibration control is
an eleventh, out-of-selection observation of the same signature.  This is the
same known F8 defect at a wider set of state-machine shapes, not a new
signature; the prefix-aware `is_known_f8` classifier deliberately labels all of
them `known_f8`.

One generator-fidelity bug was found and fixed during this sweep: `continue`
skips `i = 0`, so the last callback receives `i = 2`, but the rendered tests
expected the last iteration index to be 1 (10 `test_fail` rows).  `expected_index`
now returns 2 for `CtrlContinue` (and 3 for the `plain` callback, which adds
one), with a unit test asserting the rendered expectations.  The table above is
from the re-run after that fix; no compiler signature changed.

## Infra exclusions

- Dependency resolution is offline: generated modules import
  `moonbitlang/async@0.22.9`; the shared cache is exposed as
  `moonbit/.mooncakes` (a symlink) and is git-ignored, never staged.
- No registry, download or network path is exercised; `moon update` and
  toolchain upgrades were not run.
- The driver nevertheless treats registry/download/TLS/HTTP/DNS markers and
  per-stage timeouts as `infra`/`timeout`, so a future networked run cannot be
  counted as compiler evidence.  None occurred here: 0 infra, 0 timeouts.

## Limitations

- **Single host, single target.**  One Linux/x86_64 machine and `native` only;
  no `js`/`wasm` sweep, although the F8 PoC fails on all three link targets.
- **Small matrix.**  82 curated rows out of a nominal 640; loop trip counts are
  2–3, and only one callback call site / one pause per function.
- **`wasm-gc` is unsupported** by the F8 reproducer package, so it is excluded
  from the matrix rather than reported as a pass.
- **No scheduler integration yet.**  `@aio.pause()` is the only suspension
  primitive; there are no timers, channels, cancellation, multi-task
  interleaving or runtime-latency measurements.  The driver measures compile
  wall time only ("async runtime timing" is not probed).
- **Shallow oracle.**  Generated tests assert only small callback results;
  they are not a semantic differential against an interpreter.
- **Signature-based F8 suppression.**  Any future ICE at the same
  `moonc.ml:125623` location is classified `known_f8`; a genuinely new defect
  that lands on the same assertion would be masked.
- **Candidate controls were not exercised** in these runs because no non-F8
  crash signature appeared; their behaviour is covered only by unit tests of
  classification, not by a live candidate.
