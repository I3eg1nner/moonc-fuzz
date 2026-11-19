# azhzx/qbe.mbt as a corpus: measured, not assumed

Date: 2026-11-19
Corpus: <https://github.com/azhzx/qbe.mbt> at `2e1f3e5` (v0.44.0, 2026-11-08)
Pin: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, Linux x86_64

## Verdict

It is **not** a tool for finding MoonBit compiler bugs: MoonBit's native
backend does not go through QBE, so this project cannot compile MoonBit
programs for us and cannot replace `moonc` in any oracle.

It **is** the hardest third-party corpus this project has run, and that has
value for a different reason: it is a 188-file, 1.5 MB MoonBit compiler with
native C stubs, `moonbitlang/async` imports, a C ABI and its own 549-test
suite. Every corpus we used before was either generated code or a small
library package.

## Measured

| check | result |
|---|---|
| `moon check --target native` | 0 errors, 340 warnings (their code predates our pin's derive syntax) |
| `moon build --target native` | fails in *their* stub, see below |
| `moon test --target native` after the stub patch | **549 / 549**, 0 failed |
| `moon test --target wasm-gc` | does not build: `@stdio.stdout` / `@stdio.stderr` are not available on that target |

Warm run is ~1 s; cold run is roughly 3 minutes including the clone.

## The one real bug it produced

`native/native_stub.c` uses `RTLD_DEFAULT` without defining `_GNU_SOURCE`,
so `cc` on glibc rejects it:

```
native_stub.c:226:36: error: 'RTLD_DEFAULT' undeclared
```

This is a portability bug in the corpus, not in `moonc`. The probe script
patches the clone (idempotently) and never touches the source repository.
Not filed upstream; outbound contact needs approval.

## How it should be used

- **Upgrade canary.** Before and after any toolchain bump, run
  `scripts/probe/qbe_corpus.sh` and require 549/549. It exercises FFI,
  native stubs, async imports and a much larger module graph than
  `cmd/accept` does, in about a second when warm.
- **Not in `cmd/accept`.** It needs the network on a cold run and a writable
  `/tmp`; a hermetic gate must not depend on either.
- **Not as a cross-backend differential.** The corpus is native-only by
  construction (`stdio` is unavailable on `wasm-gc`), so it cannot feed
  `cmd/xdiff`.

## What it does not give us

- It cannot be fuzzed to find MoonBit bugs: it is an *input* to `moonc`, not
  an oracle. Fuzzing *it* (mutating `.ssa` inputs, diffing against reference
  QBE) would find bugs in qbe.mbt, which is a different project.
- Its own differential suite compares QBE output against vendored C QBE. That
  is a strong oracle for QBE, and none of it touches the MoonBit compiler.

## One idea worth stealing

Their verification compares **every debug stage** against the reference, not
just the final artifact. Our differential oracles compare final behaviour, so a
miscompile that cancels out later is invisible. MoonBit has no reference
implementation to diff stages against, which is why we use cross-backend
comparison instead — but the "compare intermediates, not just outputs" posture
is the right default and is why their 409/409 claim is stronger than a
pass/fail suite.
