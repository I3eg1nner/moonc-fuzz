---
title: "`moon fmt`: interpolation-heavy string costs ~9.5x more per doubling (1.6 s -> 15 s)"
labels: bug, performance
tracker: moonbitlang/moonbit-docs (normal bug report)
---

### Description

Formatting one function whose string literal contains `k` interpolation
segments (`\{i}`) grows much faster than the input:

| k | bytes | moonfmt wall time | peak RSS |
|---:|---:|---:|---:|
| 1024 | 6.6 KB | 1.56–1.61 s | ~21 MB |
| 2048 | 13.2 KB | 14.8–15.3 s | ~23 MB |

That is about 9.5x for 2x input. A plain string of the same byte size formats
in about 7 ms, so the cost tracks the number of segments rather than the input
size.

Expected: roughly linear in the number of segments. At minimum, 13 KB of input
should not take 15 s to format.

### Code

- Target: irrelevant

```bash
gen() {
  printf 'fn f() -> String { "'
  for ((i = 0; i < $1; i++)); do printf '\\{%d}' "$i"; done
  printf '" }\n'
}

gen 2048 > p.mbt
wc -c p.mbt
/usr/bin/time -f '%e s %M KB' moonfmt p.mbt -o out.mbt
```

### Environment

- moonfmt / moonc: v0.10.20+65efd5b93 (2026-11-05)
- OS: Linux x86_64, Ubuntu 24.04
- 3 runs per size; medians 1.60 s and 15.08 s

### Error output

None; the formatter exits 0 and the output is correct.

### Notes

Two sessions gave 1.576/15.072 s and 1.60/15.08 s medians. Two sizes are not
enough to identify a complexity class, so this report only claims the measured
inputs and the plain-string control, not an asymptotic order.

Reproducer: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/p1_fmt_interp>.
