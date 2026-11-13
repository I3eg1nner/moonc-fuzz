# F4b: second invalid-UTF-8 `.mbt.md` witness (same root as F4)

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.

Found by the MoonBit byte-level fuzzer on 2026-11-13.  The file is a mutated
`.mbt.md` containing invalid UTF-8 bytes at offset 6140 (`0x85 0x8b ... 0x92`).

```
moonc syncheck doc.mbt.md      # rc=199 ICE: Moonc.Basic_utf8_decode.MalFormed
```

Same root cause as F4 (invalid UTF-8 reaches `Basic_utf8_decode.MalFormed`
instead of a clean input diagnostic); kept as a separate witness because the
byte-level fuzzer can reproduce and replay it without Python.
