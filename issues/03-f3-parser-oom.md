---
title: "ICE: 19-byte parser input grows past 5 GiB and aborts (`moonc syncheck`)"
labels: bug, ICE
tracker: moonbitlang/moonbit-docs (ice.md)
---

### Description

`moonc syncheck` on a 19-byte file aborts with `Fatal error: out of memory`.
With `RLIMIT_AS` set to 6 GiB it reaches 5.66 GiB peak RSS after 15.3 s and
dies with SIGABRT (rc 134). Without a cap, an earlier run reached 8.2 GiB in
20 s and was still growing; that control was not repeated.

The input is 19 bytes, so memory use is not bounded by input size. Any caller
that runs `syncheck` on untrusted input inherits the exhaustion.

Expected: an ordinary parse error (rc 2) with bounded memory.

### Code

- Target: irrelevant

```bash
printf 'fn r(){y(for in ]\n[' > main.mbt
wc -c main.mbt      # 19

# Do not run uncapped on a shared machine.
prlimit --as=6442450944 -- moonc syncheck main.mbt
echo $?             # 134
```

### Environment

- moonc: v0.10.20+65efd5b93 (2026-11-05)
- OS: Linux x86_64, Ubuntu 24.04
- 2/2 capped runs in the latest session; 5/5 in an earlier capped series

### Error output

```
Fatal error: out of memory
```

Process terminated by SIGABRT (rc 134). `/usr/bin/time` reports
`15.33 s`, `MAXRSS=5660616 KB`.

### Notes

The growth rate and whether the process terminates without a cap are not
characterized, so this report only claims that the capped run exhausts the
cap. The 19-byte input is reproduced verbatim above; no trailing newline after
`[`.

Reproducer: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f3_parser_oom>.
