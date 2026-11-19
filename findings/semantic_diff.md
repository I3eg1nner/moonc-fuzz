# Semantic differential: the class every other oracle cannot see

Date: 2026-11-19
Pin: `moonc v0.10.20+65efd5b93`, `moon 0.1.20261104`, Linux x86_64
Driver: `cmd/semdiff`, cases in `moonbit/numgen`

## Why this exists

Every oracle in `judge/` detects a *loud* failure: crash, hang, silence, or a
broken output contract. A miscompile that exits 0 and prints a plausible
answer is invisible to all of them. The only oracle for that class is "the same
program on two backends must print the same bytes".

Before this, the project's differential corpus was `layout` (160 aggregate
shapes) and `async` (82 rows) — **no floating point, no string/UTF-8, no
integer edges**. That is the largest untested surface in the whole project, and
it is exactly where a silent wrong answer would live.

## Design

- 21 programs, each printing labelled lines (`name=value`), so a divergence
  names the operation instead of just "stdout differs".
- Floats are printed as **bit patterns** (`reinterpret_as_uint64`). A
  formatting difference would otherwise masquerade as a semantic one; number
  formatting is checked separately in `num-fmt`.
- Three families plus combinatorial grids:
  - `f64`: NaN propagation/comparison, ±0.0, infinities, rounding ties,
    `to_int` saturation, Int64↔Double precision, min/max with NaN, pow, mod,
    abs/neg.
  - `int`: overflow wrap, negative division/modulo signs, shifts by 0/1/31/32,
    Int64 edges, UInt64 wraparound.
  - `str`: UTF-16 units vs codepoints for ASCII/CJK/emoji/combining marks,
    `get_view` boundaries, `find` offsets, `offset_of_nth_char`, split,
    make/pad_end, compare/prefix/suffix.
- The grids do the heavy lifting: `f64-opgrid` crosses 12×12 values over
  `+ - * /`, `compare`, `min`, `max`; `int-opgrid` crosses 9×9 over
  `+ - * & | ^`, guarded division/modulo, and five shift counts; `str-rep`
  crosses 9×9 strings over `compare`, `==`, `contains`, `has_prefix`.
- Cases are total programs (no traps) so an abort cannot truncate buffered
  output and fake a difference — see the false start below.
- Default targets: `wasm-gc,native`. `js` is available and is run separately.

## Measured

`cmd/semdiff --targets wasm-gc,native`:

| metric | value |
|---|---|
| cases | 21 |
| compared output lines | **687** |
| all equal | 21 |
| mismatches | 0 |
| skipped (did not build) | 0 |
| wall | 13.4 s |

Inputs are deterministic and `--family` / `--only` select a subset, so this
runs as the `semantic_diff` gate in `cmd/accept`.

## The one divergence found — and why it is not a defect

Adding `js` to the comparison (`--targets wasm-gc,js,native`) produces two
mismatches, both from one cause:

```
folded_div00=18444492273895866368   # wasm-gc, native: 0xFFF8... (negative quiet NaN)
folded_div00=9221120237041090560    # js:              0x7FF8... (positive quiet NaN)
```

The constant expression `0.0 / 0.0` is folded at compile time, and the js
folder produces JS's canonical NaN while the other backends produce the
hardware/libm result. Two cases catch it (`nan-array-bits` directly,
`f64-opgrid` through `ys_values()`).

This is **not** a miscompile claim:

- IEEE 754 does not specify the sign or payload of a NaN produced by an
  operation, so both values are quiet NaNs and both are conforming;
- the difference is only observable through bit reinterpretation, not through
  arithmetic, comparison, or formatting (`NaN` prints as `NaN` on all three);
- a program that boxed pointers in NaN payloads would notice, but MoonBit does
  not promise payload preservation.

So the default comparison is two targets, and the js run is a documented
probe. If a future pin makes `js` agree, `nan-array-bits` becomes a plain
control; if `wasm-gc` starts matching js instead, the divergence changed
direction and the doc should say so.

## False start worth recording

The first version of `int-edges` included `Int::min / -1` and `min % -1`.
Native trapped with `SIGFPE` (rc 136) while wasm-gc panicked at the same
operation (rc 1), and the driver reported a stdout mismatch:

```
wasm-gc: 3 lines   native: 1 line
```

The cause was **buffering**, not semantics: native's stdout is block-buffered
when it is a pipe, so the abort discarded lines that wasm-gc had already
flushed. Two lessons, both applied:

1. a semantic case must be total; trapping operations belong in a separate
   trap-parity oracle that compares exit-status classes, not stdout;
2. "stdout differs" is only meaningful for programs that reach their end.

## Claim limits

- 687 compared lines is a bounded sample. It says these operations agree on
  these values; it does not bound the miscompile rate.
- Values are hand-picked (plus the two grids). Random *input* generation would
  be the next step; the generator can already take an array, so this is a
  table change, not an architecture change.
- Two targets. `js` differs on NaN sign; `wasm` (wasi) was not exercised.
- Compares only stdout and exit status. A difference that cancels before
  printing, or that only shows in timing/memory, is out of scope.
- The `f64` cases do not exercise `Float` (f32): the f32 API lives in a
  separate package and needs its own import in every generated program. That
  is the most obvious next expansion.
