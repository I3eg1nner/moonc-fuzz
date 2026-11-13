# Finding validation — five runs per reported defect

Harness: `harness/validate_findings.py`; raw data `out/validation.json`.
Each finding was reproduced five times with a fixed command, a 15 s timeout and,
where relevant, a 6 GiB `RLIMIT_AS` so a reproduction cannot take down the host.

| finding | canonical command | 5-run result | notes |
|---|---|---|---|
| **F1** | `cd poc/f1_moon_pkg_segv && moonc syncheck moon.pkg` | **5/5 SIGSEGV** (`rc=-11`) | peak RSS ≈14.3 MiB; input 101 B |
| **F2** | `cd poc/f2_lex_escape_ice && moon check` | **5/5 ICE banner**, `rc=1` | `Invalid_argument("Char.chr")`; the `moon` driver maps the ICE to rc 1 (not 199). `moonc syncheck` alone is parser-only and returns 0, so the driver path is required |
| **F3** | `cd poc/f3_parser_oom && moonc syncheck cmd/main.mbt` with RLIMIT_AS 6 GiB | **5/5 hit 5.2–5.7 GiB**, `rc=timeout` or `SIGABRT(-6)` | uncapped control: 8.2 GiB in 20 s and still growing (19 B input); earlier observation, not re-run in the independent review |
| **F4** | `cd poc/f4_invalid_utf8 && moonc syncheck doc.mbt.md` | **5/5 ICE**, `rc=199` | `Basic_utf8_decode.MalFormed`; 40 B |
| **F5-a** | `cd poc/f5_prefix_plus && moonc syncheck u.mbt` | **5/5 rc=0** | prefix `+` parses |
| **F5-b** | `moonc check -no-mi -pkg f5/p -i prelude.mi u.mbt` | **5/5 rc=2** | `The value identifier ~+ is unbound` |
| **F5-c** | `moonfmt u.mbt -o u1.mbt && moonc syncheck u1.mbt` | **5/5**: formatted output contains `~+`, re-parse rc=2 (`E3001`) | printer emits an unlexable internal name |
| **P1** | interpolation k=1024 / k=2048, `moonfmt`, 5 runs | **1,576 ms / 15,072 ms** median | plain-string controls **7.5 ms / 6.2 ms**; same binary, same host |
| **F6** | `cd pkg && moon test --target native` on `WeiR-h/moonldif@0.7.6` | **5/5 + 3/3 clean-fixture runs**, driver rc=1 | `Machine_error(... reject_export_type_containing_unsupported_callback ...)`; module-wide `moon build --target native` fails with the same signature (rc=255), while package-scoped `moon build --target native src` succeeds. Not test-mode-only; still a diagnostic/tooling defect, not a miscompile |

All six reported findings are reproducible 5/5 under the stated caps.  F2's
exit code is the driver's mapping; the ICE banner is the discriminator.  F3's
uncapped RSS measurement is a control, not part of the five capped runs.

Reproduce:

```
python3 harness/validate_findings.py --out out/validation.json
```
