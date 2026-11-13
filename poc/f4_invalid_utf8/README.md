# F4: invalid UTF-8 in `.mbt.md` reaches the decoder ICE

Pinned: `moonc v0.10.20+65efd5b93`.

```
cd poc/f4_invalid_utf8
moonc syncheck doc.mbt.md
echo $?          # 199
```

22 B Markdown file with a raw `0xff 0xfe` byte pair inside a MoonBit code
fence.  Stderr contains `Moonc.Basic_utf8_decode.MalFormed`; expected is a
clean input diagnostic, not an ICE.  F4b is a second, byte-fuzzed witness.
