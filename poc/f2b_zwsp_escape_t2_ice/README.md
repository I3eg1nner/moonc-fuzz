# F2b: backslash + U+200B is accepted by T1 and crashes T2 (`Char.chr`)

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.

Found by the MoonBit differential/template campaign on 2026-11-13.  This is a
new witness for the F2 invalid-escape family, and it isolates a phase split:

```
moonc syncheck main.mbt          # rc=0  (T1 accepts it)
moonc build-package main.mbt ... # rc=199 ICE: Invalid_argument("Char.chr")
```

Minimal input is `fn main { let s = "\<U+200B>" }` where `<U+200B>` is the
zero-width space.  F2 used a CJK character and `moon check`; this witness uses
a format character and reaches `build-package`.  Both end in the same OCaml
`Char.chr` exception, so this is the same root cause (invalid escape code point
is not rejected by the lexer), not a new one.

The correct behaviour is a clean lexer diagnostic (rc=2), not acceptance at T1
followed by an ICE at T2.
