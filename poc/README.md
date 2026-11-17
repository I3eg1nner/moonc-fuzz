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
| F7 | [`f7_valtype_array_ice/`](f7_valtype_array_ice/) | `moon run repro.mbt --target native` | native debug link ICE, `lower_array_make` |
| F8 | [`f8_async_raise_ice/`](f8_async_raise_ice/) | `moon test --target js` (also wasm/native) | `link-core` assertion after async suspension |
| F9 | [`f9_native_v128_stub_ice/`](f9_native_v128_stub_ice/) | `moon test --target native` | native debug stub-wrapper ICE for `V128` |
| P1 | [`p1_fmt_interp/`](p1_fmt_interp/) | `./generate.sh 2048` then 5x `moonfmt` | ~10x per doubling |

Run all local PoCs:

```
./scripts/reproduce_all.sh
```

F6's 12 MB third-party package is intentionally **not committed**; fetch it
with `scripts/fetch_assets.sh` (uses `moon add WeiR-h/moonldif@0.7.6`).


## Open upstream defects reproduced here

F7, F8, and F9 are **not** part of the fixed F1–F6 set.  They reproduce open
upstream reports on the pinned toolchain and are kept as regression evidence:

- F7 matches [#1322](https://github.com/moonbitlang/moonbit-docs/issues/1322)
  (`lower_array_make` / `uninitialized non-null GC ref arrays are not lowered`).
- F8 matches [#1340](https://github.com/moonbitlang/moonbit-docs/issues/1340)
  (`link-core` assertion when an async function calls a `raise?` parameter
  after a suspension).
- F9 matches [#1344](https://github.com/moonbitlang/moonbit-docs/issues/1344)
  (`finish_stub_wrapper_shell` for an `extern "C"` taking `V128`).

All three are compiler/link-time crashes, not claims of miscompilation.  An
independent Codex run (three repeats each, with negative controls) is archived
in `findings/codex_open_ice_review.md`; it also corrected the F9 README claim
about `moon test --build-only`.

They are excluded from `scripts/reproduce_all.sh` because that script asserts the
F1–F6 fixed behavior; run the commands in each PoC README directly.
