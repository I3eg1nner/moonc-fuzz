# F1b: second malformed-`moon.pkg` segfault trigger (same root cause as F1)

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.

Found by the MoonBit fuzz driver on 2026-11-13 (`--mode pkg`, 32 workers), then
line-minimized from 1,802 B to 672 B while preserving `SIGSEGV`.

```
cd poc/f1b_pkg_map_segv
moonc syncheck moon.pkg        # SIGSEGV, rc=-11
```

The crash has the same top frames as F1:

```
camlMoonc__next_segment_head_71310
camlMoonc__report_failed_to_parse_71498
camlMoonc__parse_map_elem_72891
camlMoonc__parse_map_72879
```

So this is a **new witness / input shape for the F1 family**, not a new root
cause: the malformed-package error path still segfaults.  The minimized input is
a truncated `import { ... } for "wbtest"` block followed by an unterminated
`options(... targets: { ... })` map.  The last map entry is required for the
crash; dropping it turns the result into a clean rc=2 parse error.
