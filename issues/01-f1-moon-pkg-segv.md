---
title: "ICE: SIGSEGV in `moonc syncheck` on a malformed `moon.pkg`"
labels: bug, ICE
tracker: moonbitlang/moonbit-docs (ice.md)
---

### Description

`moonc syncheck moon.pkg` segfaults with no output (rc 139) on a 101-byte
ASCII file. The trigger depends on the token count and on the file not ending
with a newline:

| input | result |
|---|---|
| `s(` + 49 literals, no trailing newline | rc 2, parse errors |
| `s(` + 50 literals, no trailing newline (101 B) | SIGSEGV |
| `s(` + 50 literals, trailing newline | rc 2 |
| `s(` + 50 identifiers instead of number literals | rc 2 |

The same file used as a package manifest through the `moon` driver does not
crash: `moon build` reports a normal parse error (rc 255). The crash is on the
explicit `moonc syncheck` path.

### Code

- Target: irrelevant

```bash
printf 's(' > moon.pkg
printf '1,%.0s' $(seq 49) >> moon.pkg
printf '1' >> moon.pkg
wc -c moon.pkg        # 101
moonc syncheck moon.pkg
echo $?               # 139
```

gdb backtrace (no symbols beyond `camlMoonc*`):

```
#0 camlMoonc__next_segment_head_71310
#1 camlMoonc__report_failed_to_parse_71498
#2 camlMoonc__loop_71725
#3 camlMoonc__fun_428987
#4 camlMoonc__surround_71668
#5 camlMoonc__fun_429097
#6 camlMoonc__parse_apply_72880
#7 camlMoonc__parse_statement_72979
#8 camlMoonc__loop_71725
#9 camlMoonc__parse_statements_72989
#10 camlMoonc__moon_pkg_of_tokens_72993
#11 camlMoonc__parse_from_string_inner_429709
```

A second input, found independently by mutation (672 B: a truncated
`import { ... } for "wbtest"` block followed by an unterminated
`options(... targets: { ... })` map), hits the same top frames. Dropping the
last map entry turns it into a clean rc 2.

### Environment

- moonc: v0.10.20+65efd5b93 (2026-11-05)
- moon: 0.1.20261104 (940aa18 2026-11-04)
- OS: Linux x86_64, Ubuntu 24.04
- 3/3 reproductions for both inputs

### Error output

No stderr; the process dies with SIGSEGV and rc 139.

### Notes

This is a memory-safety bug in the parse-error path, but I have not proven the
root cause: the public 2025-03 source snapshot does not correspond to this
binary, so the crash site is known only from symbols and frames.

Reproducers and boundary experiments:
<https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f1_moon_pkg_segv> and
<https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f1b_pkg_map_segv>.
