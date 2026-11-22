# Nested unary minus on `Int`/`Int64` min: `moonfmt` prints an out-of-range literal

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonfmt` from `moonc v0.10.20+65efd5b93`. Host: Linux x86_64.

Status: **candidate**, 3/3 reproduced; not filed upstream; not in
`regressions_13`. This is a formatter round-trip/validity defect, not a
miscompile claim, and not proven independent of F5.

## Discovery

This came out of the issue→oracle pilot (`findings/issue_oracle_pilot.md`):
the F5-derived formatter oracle (format → reparse → format → run) was extended
from the 25 templates to generated syntax. One generated case,
`-(-2147483648)`, formatted to `--2147483648`; the original runs, the
formatted file does not build.

## Minimal witness (36 B)

`poc/f13_fmt_nested_minus/main.mbt`:

```moonbit
fn main { println(-(-2147483648)) }
```

Commands and results:

```text
moonc syncheck main.mbt                 rc 0
moon run main.mbt --target wasm-gc -q   rc 0, stdout "-2147483648"

moonfmt main.mbt -o f.mbt               rc 0
# f.mbt:
# fn main {
#   println(--2147483648)
# }

moon run f.mbt --target wasm-gc -q      rc 1
# [4095] Integer literal 2147483648 is out of range
```

The same failure occurs on `js` and `native`; it is a typecheck/build error,
not a backend-specific runtime issue. `moonc syncheck f.mbt` still returns 0,
so this is not a lexer/parser error.

## Idempotence

```text
moonfmt main.mbt -o f.mbt   -> println(--2147483648)
moonfmt f.mbt    -o f2.mbt  -> println(2147483648)
```

Both `f.mbt` and `f2.mbt` fail to build. Even for a non-min literal the printer
is unstable: `-(-3)` → `--3` → `3` (valid, but not idempotent).

## Boundary

| source | formatted | builds? |
|---|---|---|
| `-(-3)` | `--3` | yes |
| `-(-2147483647)` | `--2147483647` | yes |
| `-(-2147483648)` | `--2147483648` | **no** (E4095) |
| `-(-9223372036854775808L)` | `--9223372036854775808L` | **no** (E4095) |
| `-(-0x80000000)` | `--0x80000000` | yes |
| `-(-0x8000000000000000L)` | `--0x8000000000000000L` | yes |
| `-(-(2147483647 + 1))` | unchanged | yes |

Only a **negative decimal minimum literal** under nested unary minus becomes an
out-of-range positive decimal literal. Hex literals and expression operands do
not; the formatter preserves the parentheses around the expression.

## Classification

- **Defect**: valid input → formatter output that no longer typechecks.
- **Not a miscompile**: no claim that the compiler computes a wrong value.
- **Relation to F5**: F5 is `moonfmt` unary plus → `~+`, failing at `E3001`
  lexing. This is unary minus → `--…`, failing at `E4095` typecheck. It may be
  the same printer parenthesization decision, but that is unproven. Keep it as
  a candidate until triage.
- Severity: medium/low; edge-case literal, but a formatter must not invalidate
  valid source.

## Limits

- One pin, one host.
- No source-level root cause (printer precedence/parenthesization) was proven.
- No upstream issue/comment was posted.
- Formal regression integration is deferred until triage decides whether it is
  a distinct signature from F5.
