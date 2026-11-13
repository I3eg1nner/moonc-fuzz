---
title: "ICE: invalid escape in a string literal reaches the typer as Invalid_argument(\"Char.chr\")"
labels: bug, ICE, moonc
tracker: moonbitlang/moonbit-docs (ice.md)
filed: https://github.com/moonbitlang/moonbit-docs/issues/1365
---

### Description

A string literal containing a backslash followed by a non-ASCII character is
accepted by the parser and then crashes the next stage:

```moonbit
let s = "\中"
fn main { println(s) }
```

`moonc syncheck main.mbt` returns 0, but `moonc build-package` aborts with
`Invalid_argument("Char.chr")`. A backslash followed by U+200B (zero-width
space) shows the same split: syncheck rc 0, build-package rc 199.

Expected: a lexer diagnostic for the invalid escape, at the stage that reads
the literal, instead of acceptance followed by an ICE.

### Code

- Target: wasm (also reproduces through `moon check`)

`main.mbt` (`\中` is backslash followed by U+4E2D):

```moonbit
let s = "\中"
fn main { println(s) }
```

```bash
moonc syncheck main.mbt
# rc 0, prints {"toplevel":{"fn":1,"let":1},"max-toplevel-span":"1-1"}

moonc build-package main.mbt -o main.core -pkg f2/p -pkg-type executable \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/builtin/builtin.mi:moonbitlang/core/builtin" \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/prelude/prelude.mi:prelude" \
  -pkg-sources f2/p:. -target wasm -g -O0 -workspace-path .
# rc 199, ICE
```

A package containing the same file also ICEs through `moon check` (driver
rc 1), so this is not specific to invoking `moonc` directly.

### Environment

- moonc: v0.10.20+65efd5b93 (2026-11-05)
- moon: 0.1.20261104 (940aa18 2026-11-04)
- OS: Linux x86_64, Ubuntu 24.04
- 3/3 reproductions (both witnesses)

### Error output

```
Oops, the compiler has encountered an unexpected situation.
This is a bug in the compiler.
...
Error: Invalid_argument("Char.chr")
```

### Notes

The second witness is `fn main { let s = "\<U+200B>" }`; its file is 27 bytes,
with `5c e2 80 8b` after the opening quote. It reaches `build-package` without
the `moon` driver, which is why it is included here.

The ICE message does not say where the exception is raised, and the public
2025-03 source snapshot does not match this binary, so this report does not
claim a specific root cause.

Reproducers: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f2_lex_escape_ice>
and <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f2b_zwsp_escape_t2_ice>.
