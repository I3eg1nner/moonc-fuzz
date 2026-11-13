---
title: "`moon fmt` prints unary plus as `~+`, producing code that cannot be re-parsed"
labels: bug, moonfmt
tracker: moonbitlang/moonbit-docs (normal bug report)
filed: https://github.com/moonbitlang/moonbit-docs/issues/1369
---

### Description

`moonc syncheck` accepts unary `+`:

```moonbit
fn f(y : Int) -> Int { +y }
fn main { println(f(1).to_string()) }
```

Typing then reports the internal name (`[4021] The value identifier ~+ is
unbound`), and `moonfmt` writes it back as `~+(y)`. Re-parsing the formatted
file fails:

```
[E3001] Lexing error: unrecognized character "~" (U+007E)
```

So `moon fmt` turns a file it can parse into a file it cannot parse. The same
happens for `+(1)`, `+(y)`, `x ++ y` and `x + ++y`; `+1` folds to `1`, and
unary-minus controls (`-y`, `-(y)`, `-1`, `x + -y`) are unaffected.

Expected: keep `+y` in the output (if unary plus is meant to be supported), or
reject it at parse time with a normal diagnostic. The formatter should not
emit a token the lexer rejects either way.

### Code

- Target: irrelevant

`u.mbt`:

```moonbit
fn f(y : Int) -> Int { +y }
fn main { println(f(1).to_string()) }
```

```bash
moonc syncheck u.mbt          # rc 0
moon check u.mbt              # rc 1, 4021 ~+ unbound
moonfmt u.mbt -o u1.mbt       # rc 0
moonc syncheck u1.mbt         # rc 2, E3001

cat u1.mbt
# fn f(y : Int32) -> Int32 {
#   ~+(y)
# }
```

`moonfmt` also rewrites `Int` to `Int32` in this standalone mode; that part is
expected and unrelated.

### Environment

- moonc / moonfmt: v0.10.20+65efd5b93 (2026-11-05)
- moon: 0.1.20261104 (940aa18 2026-11-04)
- OS: Linux x86_64, Ubuntu 24.04
- 5/5 reproductions

### Error output

```
u1.mbt:3:3-3:4 [E3001] Lexing error: unrecognized character "~" (U+007E)
```

### Notes

This is a syntax round-trip defect, not a semantic one: the original file
parses, so the claim is limited to the formatter/printer path. A larger matrix
of parse-accepted mutants shows the same signature, but this report only
depends on the committed sample.

Reproducer: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f5_prefix_plus>.
