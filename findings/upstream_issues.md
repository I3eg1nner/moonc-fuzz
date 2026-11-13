# Upstream issues

Submitted to `moonbitlang/moonbit-docs` on 2026-11-13 against
`moonc v0.10.20+65efd5b93`. All are open; no maintainer comments as of the
last check.

| Defect | Issue | Title | Local PoC |
|---|---|---|---|
| F1 / F1b | [#1367](https://github.com/moonbitlang/moonbit-docs/issues/1367) | SIGSEGV in `moonc syncheck` on a malformed `moon.pkg` | `poc/f1_moon_pkg_segv/`, `poc/f1b_pkg_map_segv/` |
| F2 / F2b | [#1365](https://github.com/moonbitlang/moonbit-docs/issues/1365) | invalid escape reaches the typer as `Invalid_argument("Char.chr")` | `poc/f2_lex_escape_ice/`, `poc/f2b_zwsp_escape_t2_ice/` |
| F3 | [#1366](https://github.com/moonbitlang/moonbit-docs/issues/1366) | 19-byte parser input grows past 5 GiB and aborts | `poc/f3_parser_oom/` |
| F4 / F4b | [#1364](https://github.com/moonbitlang/moonbit-docs/issues/1364) | invalid UTF-8 in `.mbt.md` reaches `Basic_utf8_decode.MalFormed` | `poc/f4_invalid_utf8/`, `poc/f4b_invalid_utf8_2/` |
| F5 | [#1369](https://github.com/moonbitlang/moonbit-docs/issues/1369) | `moon fmt` prints unary plus as `~+`, output cannot be re-parsed | `poc/f5_prefix_plus/` |
| F6 | [#1368](https://github.com/moonbitlang/moonbit-docs/issues/1368) | native link rejects exported closure-containing type with an ICE | `poc/f6_native_export_closure_min/` |
| P1 | [#1370](https://github.com/moonbitlang/moonbit-docs/issues/1370) | interpolation-heavy string costs ~9.5x per doubling | `poc/p1_fmt_interp/` |

Issue bodies include the pinned toolchain, exact commands, observed exit codes,
and controls. They are consistent with the locally corrected claims:

- F1: 49 literals clean, 50 literals SIGSEGV; impact limited to explicit
  `moonc syncheck`.
- F4: 40 B file, not 22 B.
- F6: 10-line minimal package; diagnostic/tooling defect, not a miscompile.
- P1: two measured sizes; no asymptotic complexity class claimed.
