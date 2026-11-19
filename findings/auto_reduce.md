# Automatic reduction: from "interesting crash" to "fileable bug"

Date: 2026-11-19
Status: implemented, gated by `cmd/accept` (`reduce_witness`)

## Why

Every one of the twelve reproduced defects was minimised by hand. That step is
what turns a crash into a bug report, and it was the slowest part of the
pipeline: hours per defect, all of it mechanical. A generator that produces
more candidates does not help if each candidate costs a human afternoon.

## Shape

Two layers, deliberately split:

- `moonbit/reduce` — pure engine. No processes, no files. Decides what to try
  next and records verdicts. 11 tests.
- `moonbit/cmd/minimize` — thin driver. Supplies the only thing the engine
  cannot know: "does this candidate still reproduce the same defect?".

The engine is a **state machine** rather than `reduce(src, predicate)` because
the real predicate spawns the compiler and is `async` in MoonBit, while a
synchronous callback cannot await. Driver inversion also makes the engine
testable with an in-memory predicate, which is why the 11 tests need no
toolchain.

```moonbit
let r = start(original, fuel)
while next_text(r) is Some(cand) {
  verdict(r, run_stage(cand) == baseline)
}
result(r)
```

`next_text` is idempotent: asking twice without a verdict returns the same
candidate, so a caller may retry or log without corrupting state.

## Two phases

1. **Block phase.** Line spans of top-level `{ ... }` blocks, largest first.
   One big cut beats four small ones when both work, and it preserves
   syntactic shape far better than line deletion.
2. **Line phase.** Granularity sweep: partition into `gran` chunks, try
   removing each; accept lowers `gran` (finer), reject doubles it (coarser).
   This is the classic complement-only reduction. It is **not** a minimality
   guarantee, and the doc says so rather than claiming "1-minimal".

The block scanner is line-level and brace-blind: a `{` inside a string or
comment can produce a wrong span. The verdict gate rejects it, which is why
the heuristic is acceptable — a wrong candidate costs one compiler run, never
a wrong result.

## What "same defect" means

Signature = the shared oracle layer's findings (`judge.check_all`), normalized:

- every run of digits becomes `#` (link ICE text embeds byte counts, hashes,
  temp paths);
- whitespace runs collapse;
- truncated to 180 chars.

Without normalization an exact compare would reject every candidate, because
the ICE text changes between runs, and the reducer would silently return the
input unchanged. That failure mode is invisible in a "did it get smaller"
test, so the driver re-runs the final text once and reports `verified`; a
failed verification falls back to the original rather than shipping a witness
that does not reproduce.

A candidate that merely fails *differently* is rejected: signature equality is
required, not "still non-zero".

## Measured

F9 (native `#valtype` v128 stub link ICE, `moon test --build-only`):

| input | lines | result |
|---|---|---|
| `poc/f9_native_v128_stub_ice` as-is | 4 | 4 (already minimal), 12 runs, 1.9 s |
| same PoC with 42 lines of unrelated helpers inlined | 46 | **4**, 29 runs, 4.4 s |

The 46 → 4 case is the one that matters: the reducer found the two-line
`extern "C"` + call shape and discarded every unrelated function, block phase
first. 29 compiler runs is roughly what a careful human needs, in 4 seconds
instead of an afternoon.

The reduced text is byte-identical to the original PoC's `lib.mbt`, which is
the strongest available check: the automated result agrees with the hand-made
one.

## Wiring

`cmd/minimize --dir PATH [--file lib.mbt] [--stage check|build|test] ...`:

- copies the package to `/tmp/mbtfuzz_reduce_<ts>` and never edits the source
  tree (`--keep-workdir` retains it for inspection);
- prints one JSON line: `ok`, `stage`, `baseline`, `before_lines`,
  `after_lines`, `calls`, `exhausted`, `verified`, `ms`, `out`;
- exit 0 reduced and re-verified, 1 baseline passes (nothing to reduce) or
  verification failed, 2 bad usage.

`cmd/accept` runs it on F9 as `reduce_witness` and requires `verified` plus a
`crash|ICE` baseline, so a regression in signature comparison fails the gate
instead of quietly returning the input.

## Claim limits

- **Single file.** The driver reduces one file per run. Multi-file witnesses
  need per-file passes with the other files frozen; that is a loop over this
  tool, not a feature of it, and it is not implemented.
- **Heuristic signature.** Two genuinely different ICEs that differ only in
  digits share a signature, so the reducer can accept a candidate that
  reproduces a *neighbouring* defect. The window is small (the `Error:` text is
  kept verbatim apart from digits) but it is real, and a reduced witness should
  still be eyeballed before filing.
- **No minimality proof.** Complement-only reduction can stop at a local
  minimum that no single chunk removal improves. `after_lines` is an upper
  bound on the minimal size.
- **Cost is linear in runs, not lines.** Each verdict is a full compiler run;
  `--fuel` is the only defence against a pathological input. The F9 run used
  29 of 60.
- The 46 → 4 measurement uses a deliberately buried copy of a known shape. It
  measures the reducer, not the compiler: it is not a new finding.
