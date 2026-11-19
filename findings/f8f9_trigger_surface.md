# F8 / F9 trigger surfaces: from one witness to a condition list

Date: 2026-11-19. Pin: `moonc v0.10.20+65efd5b93`, `moon 0.1.20261104`,
Linux x86_64. Script: `scripts/probe/icesurface.sh` (`OUT=/tmp/icesurf`).

## The gap this closes

F8 and F9 were reported as single witnesses with prose conditions copied from
the upstream reports. That is enough to say "this fails"; it is not enough to
say why, and it is not enough for a maintainer to recognise the same defect in
a different shape. F7 went through this exercise earlier
(`findings/f7_trigger_surface.md`) and two of its stated conditions turned out
to be wrong. The same treatment is applied here: build the cross product, keep
the controls, and let the table decide.

## Method

`moon run` single-file scripts cannot express either defect (F8 needs a module
dependency on `moonbitlang/async`, F9 needs a native stub and a `moon.pkg`
`options` block), so the sweep is a shell driver that materialises one real
module per case and runs the toolchain command that actually fails:

- F8: `moon test --target js --build-only` (fail is in `moonc link-core`);
- F9: `moon test --target native --build-only`, plus `--release` and
  `moon build --target native` as controls.

Verdicts are classified from the log: `Assertion failed` → ICE-assert,
`Machine_error(kind=unsupported` → ICE-unsupported, any other non-zero → error,
otherwise ok. Every case keeps its full log; the tables below are the TSV the
script prints.

## F8 — async `raise?` callback after a suspension

| # | async fn | suspension | callback return type | call position | verdict |
|---|---|---|---|---|---|
| a | yes | `@aio.pause()` | `T? raise?` | after | **ICE-assert** |
| b | yes | `@aio.pause()` | `T?` | after | ok |
| c | yes | `@aio.pause()` | `T raise?` | after | **ICE-assert** |
| d | yes | `@aio.pause()` | `T` | after | ok |
| e | yes | none | `T? raise?` | — | ok |
| f | yes | `@aio.pause()` | `T? raise?` | before | ok |
| g | no | none | `T? raise?` | — | ok |
| h | yes | `@aio.pause()` | no callback | — | ok |

What the table settles:

- **Required: the callback's type carries `raise?`** (a and c fail; b and d
  pass). The optionality of the callback's return (`T?` vs `T`) is irrelevant —
  only the error mode matters. This corrects the phrasing "a `raise?` callback
  returning an optional"; the optional part is decoration.
- **Required: the call happens after a suspension point** (a fails, e and f
  pass). A suspension alone (h) is not enough, and `raise?` alone (g) is not.
- **Not required: being `async` by itself, or the function's own return type.**
  Case g is synchronous and links; the failing function returns `T?` in a and
  `T` in c, so its return type is not the trigger.
- One operational note: the first version of case g returned `T?` while calling
  a `raise?` callback. That is a source error (`[4122] Function with error can
  only be used inside a function with error types in its signature`), which the
  classifier recorded as `error`, not `ok`. A control that does not compile is
  not a control; the signature was fixed and the case re-run.

## F9 — native stub with a `V128` parameter

| # | stub signature | debug inline-test link | release inline-test link | `moon build` |
|---|---|---|---|---|
| a | `(UInt64, V128)` param, called | **ICE-unsupported** | ok | n/a |
| b | returns `V128`, called | ok | ok | n/a |
| c | `(UInt64, Int)` param, called | ok | ok | n/a |
| d | `(UInt64, Double)` param, called | ok | ok | n/a |
| e | `(UInt64, V128)` declared, never called | ok | ok | n/a |

What the table settles:

- **Required: `V128` in parameter position** (a fails; b — `V128` only as the
  return type — passes; c and d — scalar parameters — pass). The defect is not
  "V128 anywhere", it is "aggregate argument in the stub wrapper".
- **Required: a reachable call site.** Declaring the `extern "C"` function
  without calling it (e) links; the wrapper shell is only lowered for a call
  that survives to link.
- **Required: debug mode.** `--release` links the same program.
- `moon build --target native` is **n/a, not a control**: the package has no
  `pkgtype`, so there is nothing to link and the command succeeds vacuously.
  The F9 README's "check and build succeed" is true but says nothing about the
  ICE; only the test link exercises `finish_stub_wrapper_shell`.
- Narrowing found while reading the log: the failing link is the **inline**
  (internal) test driver. The blackbox test driver for the same package links
  and produces an executable. That is a sharper statement than "test-mode link
  fails" and tells a maintainer where to look first.

## Consequences

- The minimal F8 witness can be stated as a condition pair rather than a
  four-line snippet plus caveats: *an `async` function that suspends and then
  calls a callback whose type carries `raise?`*. Any of {no suspension, call
  before the suspension, non-`raise?` callback} removes the crash.
- The F9 class is broader than the PoC suggested: it is not specific to
  `@v128.f32x4_const` or to `f32x4`; any `extern "C"` stub whose *parameter*
  is a vector type hits it when called from a debug test link.
- Both tables are single-run observations per case, not a statistical claim.
  They belong to the "characterisation" category in
  `findings/methodology.md` §2: the rows are chosen to separate explanations,
  not sampled to estimate a rate.

## Limits

- One pin, one host. A fix may land with a different condition list; these
  tables describe `moonc v0.10.20+65efd5b93` only.
- F8 was swept on `js` only (`wasm`/`native` are said to fail identically in the
  PoC; not re-checked here). F9 is native by definition.
- The F8 sweep needs `moonbitlang/async@0.22.9` to resolve. A machine without
  the registry cache or network access will fail every row as `error`, which is
  visibly different from the mixed table above.
- No minimisation of the C stub or of the async case was attempted; the goal
  was the condition list, not the smallest witness.

## Reproduction

```bash
scripts/probe/icesurface.sh /tmp/icesurf     # ~2 min, 23 runs
# per-case logs: /tmp/icesurf/f8/<case>.log, /tmp/icesurf/f9/<case>/<mode>.log
```
