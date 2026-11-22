# F13 candidate — `moonfmt` drops parentheses around nested unary minus, producing an uncompilable `Int` min literal

Status: **reproducible 3/3** on the pinned toolchain; **not filed upstream**
(no issue/comment), and **not yet in `regressions_13`**. Relation to F5 is
unknown: F5 is unary plus → `~+`; this is unary minus → `--2147483648`.

| item | value |
|---|---|
| toolchain | `moon 0.1.20261104 (940aa18)`, `moonfmt` from `v0.10.20+65efd5b93` |
| input | 36 B `.mbt` |
| command | `moonfmt main.mbt -o f.mbt` |
| observed | formatter rc 0; formatted file then fails typecheck with `E4095 Integer literal 2147483648 is out of range` |
| original | rc 0, prints `-2147483648` |

## Reproduce

```bash
cd poc/f13_fmt_nested_minus

moonc syncheck main.mbt                  # rc 0
moon run main.mbt --target wasm-gc -q    # rc 0, prints -2147483648

moonfmt main.mbt -o f.mbt                # rc 0
cat f.mbt                                # println(--2147483648)
moon run f.mbt --target wasm-gc -q       # rc 1
# Error: [4095] Integer literal 2147483648 is out of range
```

`moonc syncheck f.mbt` still returns 0: the failure is at typecheck/build,
not lexing/parsing. The bug is that the printer turns a valid nested unary
minus into `--2147483648`, whose inner positive literal is out of `Int` range.

A second `moonfmt` pass makes the instability explicit:

```text
moonfmt main.mbt -o f.mbt   -> println(--2147483648)
moonfmt f.mbt   -o f2.mbt   -> println(2147483648)
```

Both `f.mbt` and `f2.mbt` fail to build.

## Boundary table (measured on the same pin)

| source | formatted | builds? | note |
|---|---|---|---|
| `-(-3)` | `--3` | yes | second pass becomes `3`; not idempotent, but valid |
| `-(-2147483647)` | `--2147483647` | yes | inner positive literal still fits |
| `-(-2147483648)` | `--2147483648` | **no** | E4095; `Int` min |
| `-(-9223372036854775808L)` | `--9223372036854775808L` | **no** | E4095; `Int64` min |
| `-(-0x80000000)` | `--0x80000000` | yes | hex path does not hit the decimal range check |
| `-(-0x8000000000000000L)` | `--0x8000000000000000L` | yes | same |
| `-(-(2147483647 + 1))` | `-(-(2147483647 + 1))` | yes | parentheses around an expression are preserved |

The boundary is narrow but real: only a **decimal minimum literal** under a
nested unary minus is turned into an out-of-range positive decimal literal.

## Why this is a defect, not a style choice

The original program is valid and runs; formatting it changes acceptance, not
just layout. A formatter may canonicalize, but it must not turn a valid program
into one that no longer typechecks. The expected behavior is either to preserve
the parentheses (`-(-2147483648)`) or to print the negative literal in a form
that remains valid.

## Relation to F5

F5 ([#1369](https://github.com/moonbitlang/moonbit-docs/issues/1369)) is the
unary-plus formatter bug: `+y` becomes the unlexable `~+(y)`, `moonc syncheck`
fails with `E3001`. This case has a different token sequence (`--…`), a
different failure stage (`E4095` at typecheck), and no `~`. It may share the
same printer decision about dropping parentheses around unary operators, but
that is not proven. Until triaged, call it a **candidate**, not a new root
cause.

## Limits

- One pin, one Linux x86_64 host.
- The report does not claim a source-level root cause; only the formatter
  input/output behavior.
- No upstream issue or comment was posted; F5's issue is only referenced as
  the nearest known formatter defect.
