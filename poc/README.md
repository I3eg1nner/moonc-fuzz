# PoC index

All findings are against the same pinned toolchain:

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104
```

Set `MOONC`/`MOON`/`MOONFMT` or use `$HOME/.moon/bin/...`.

| ID | PoC | canonical command | expected |
|---|---|---|---|
| F1 | [`f1_moon_pkg_segv/`](f1_moon_pkg_segv/) | `moonc syncheck moon.pkg` | SIGSEGV, rc 139 |
| F1b | [`f1b_pkg_map_segv/`](f1b_pkg_map_segv/) | `moonc syncheck moon.pkg` | SIGSEGV, same top frames as F1 |
| F2 | [`f2_lex_escape_ice/`](f2_lex_escape_ice/) | `rm -rf _build && moon check` | rc 1, `Invalid_argument("Char.chr")` |
| F2b | [`f2b_zwsp_escape_t2_ice/`](f2b_zwsp_escape_t2_ice/) | build-package command in README | rc 199, `Char.chr` |
| F3 | [`f3_parser_oom/`](f3_parser_oom/) | `prlimit --as=6442450944 -- moonc syncheck cmd/main.mbt` | OOM / SIGABRT under cap |
| F4 | [`f4_invalid_utf8/`](f4_invalid_utf8/) | `moonc syncheck doc.mbt.md` | rc 199, `Basic_utf8_decode.MalFormed` |
| F4b | [`f4b_invalid_utf8_2/`](f4b_invalid_utf8_2/) | `moonc syncheck doc.mbt.md` | rc 199, same decoder exception class |
| F5 | [`f5_prefix_plus/`](f5_prefix_plus/) | `moonc syncheck u.mbt`; `moonfmt`; re-syncheck | 0; then rc 2 `E3001` |
| F6-min | [`f6_native_export_closure_min/`](f6_native_export_closure_min/) | `moon build --target native` | rc 255, export-closure ICE |
| F6 | [`f6_native_export_closure/`](f6_native_export_closure/) | `scripts/fetch_assets.sh`, then native test | rc 1, same signature |
| P1 | [`p1_fmt_interp/`](p1_fmt_interp/) | `./generate.sh 2048` then 5x `moonfmt` | ~10x per doubling |

Run all local PoCs:

```
./scripts/reproduce_all.sh
```

F6's 12 MB third-party package is intentionally **not committed**; fetch it
with `scripts/fetch_assets.sh` (uses `moon add WeiR-h/moonldif@0.7.6`).
