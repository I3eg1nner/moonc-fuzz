---
title: "ICE: invalid UTF-8 in a `.mbt.md` file reaches Basic_utf8_decode.MalFormed"
labels: bug, ICE
tracker: moonbitlang/moonbit-docs (ice.md)
---

### Description

A `.mbt.md` file whose MoonBit code fence contains raw invalid UTF-8 bytes
crashes `moonc syncheck` with `Moonc.Basic_utf8_decode.MalFormed` (rc 199).
The same file also crashes `moonc build-package`.

The `.mbt` path does not crash on this toolchain: a source file containing
`de ad be ef` returns the normal diagnostic `3001 Could not read the file
because it contains invalid UTF-8 streams`. So the decoder failure is specific
to the `.mbt.md` path.

This is related to #861, which reported `Moonc.Basic_utf8.MalFormed` for
`.mbt` files on v0.6.18. On v0.10.20 the `.mbt` path is clean and the exception
module has been renamed, but `.mbt.md` still reaches the decoder.

Expected: the same 3001 diagnostic, or any normal input error, instead of an
ICE.

### Code

- Target: irrelevant

`doc.mbt.md` is 40 bytes. Hexdump:

```
00000000: 2320 740a 0a60 6060 6d62 740a 666e 2066  # t..```mbt.fn f
00000010: 2829 207b 206c 6574 2073 203d 2022 fffe  () { let s = "..
00000020: 2220 7d0a 6060 600a                      " }.```.
```

Generate it and run:

```bash
printf '# t\n\n```mbt\nfn f() { let s = "' > doc.mbt.md
printf '\xff\xfe' >> doc.mbt.md
printf '" }\n```\n' >> doc.mbt.md
wc -c doc.mbt.md      # 40

moonc syncheck doc.mbt.md
echo $?               # 199
```

### Environment

- moonc: v0.10.20+65efd5b93 (2026-11-05)
- OS: Linux x86_64, Ubuntu 24.04
- 3/3 reproductions

### Error output

```
Oops, the compiler has encountered an unexpected situation.
This is a bug in the compiler.
...
Error: Moonc.Basic_utf8_decode.MalFormed
```

### Notes

A second witness, found by byte-level mutation, is a 6.7 KB `.mbt.md` with
invalid bytes at offset 6140; it produces the same exception class. It is kept
as a separate file because it replays without any generator script.

Reproducers: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f4_invalid_utf8>
and <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f4b_invalid_utf8_2>.
