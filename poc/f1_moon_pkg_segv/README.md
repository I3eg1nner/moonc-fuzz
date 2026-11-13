# F1: malformed `moon.pkg` segfaults `moonc syncheck`

Pinned: `moonc v0.10.20+65efd5b93 (2026-11-05)`.

```
cd poc/f1_moon_pkg_segv
moonc syncheck moon.pkg
echo $?          # 139 / SIGSEGV
```

Input is 101 B of ASCII, no trailing newline: `s(` followed by 50 `1` tokens.
`50` tokens triggers; 48 and 49 are clean rc=2.  A trailing newline also
suppresses the crash.  Stack top:

```
camlMoonc__next_segment_head_71310
camlMoonc__report_failed_to_parse_71498
```

The root cause is a hypothesis (error-recovery path), not proven.  Confirmed
impact is this explicit `syncheck` invocation; valid source files in the same
directory still build/check normally.
