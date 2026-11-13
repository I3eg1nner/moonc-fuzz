You are an independent verifier. The project /data/audit/mbtfuzz claims a set of compiler defects in the closed-source MoonBit compiler `moonc`. Your job is to determine whether each reported defect is REAL, or a false positive caused by a broken PoC, wrong working directory/flags, stale build state, missing module, or a harness/script bug.

Do not trust the README or the finder's narrative. Inspect the actual PoC files and independently run the commands. You may build and create temporary files, but do not modify tracked source files. Return a per-defect verdict with concrete evidence.

Pinned toolchain claimed:
  moon 0.1.20261104 (940aa18 2026-11-04)
  moonc v0.10.20+65efd5b93 (2026-11-05)
  moonrun 0.1.20261104
First run `moon version --all` and `moonc -v` and record what is actually installed.

Defects to verify (read `poc/<id>/README.md` for the intended command):
- F1:  poc/f1_moon_pkg_segv/moon.pkg; from that cwd, `moonc syncheck moon.pkg`; expected SIGSEGV rc 139.
- F1b: poc/f1b_pkg_map_segv/moon.pkg; same; expected SIGSEGV, same top frames as F1.
- F2:  poc/f2_lex_escape_ice; `rm -rf _build && moon check`; expected rc 1 and `Invalid_argument("Char.chr")`.
- F2b: poc/f2b_zwsp_escape_t2_ice; build-package command in README; expected syncheck 0, build-package rc 199 with `Char.chr`.
- F3:  poc/f3_parser_oom; `prlimit --as=6442450944 -- moonc syncheck cmd/main.mbt`; expected rc 134 / out-of-memory under the cap. Do NOT run uncapped.
- F4:  poc/f4_invalid_utf8/doc.mbt.md; `moonc syncheck doc.mbt.md`; expected rc 199, `Basic_utf8_decode.MalFormed`.
- F4b: poc/f4b_invalid_utf8_2/doc.mbt.md; same.
- F5:  poc/f5_prefix_plus/u.mbt; syncheck 0; moonfmt to a temp file; re-syncheck expected rc 2, `E3001`, formatted output contains `~+`.
- F6-min: poc/f6_native_export_closure_min; `moon build --target native`; expected rc 255 and `reject_export_type_containing_unsupported_callback`.
- F6 external: assets/f6_external/moonldif (already extracted; otherwise run scripts/fetch_assets.sh); `moon test --target native`; expected rc 1, same signature.
- P1: poc/p1_fmt_interp; generate k=1024 and k=2048, measure `moonfmt` 3 runs at each size and a plain-string control; expected superlinear growth (~10x per doubling). Report actual numbers, no need to demand an exact threshold.

For each defect:
1. Run the canonical command at least 3 times (except F3/P1 where the cap/time cost requires judgment; explain).
2. Record exact cwd, command, rc, signal, and the discriminating stderr substring.
3. Run at least one CONTROL that should not trigger:
   - F1: 48 vs 49 `1` tokens; trailing newline.
   - F2: valid escape in the same file shape; or valid `moon check`.
   - F3: a normal 19-byte source; 48 tokens? Use bounded runs only.
   - F4: a valid UTF-8 `.mbt.md`.
   - F5: unary minus / valid program.
   - F6: no `#export_name`, and `#export_name` with no closure field.
4. Check the input bytes with `xxd`/`file` when encoding is relevant (F2, F4, F4b).
5. Determine whether any failure is simply the harness passing a nonexistent file, wrong package name, wrong target, missing prelude/core path, or a stale `_build` cache. Re-run from a fresh copy if suspicious.
6. For F1b, inspect whether stack similarity is enough to call it the same root cause; do not overclaim.
7. For F6, verify whether the failure is a link-time diagnostic/tooling ICE rather than a miscompile; check package-scoped build/test controls if feasible.
8. For F5/P1, distinguish parser/formatter behavior from an invalid PoC invocation.

Also review `scripts/reproduce_all.sh` for false-positive traps: does it mask a failure, run in the wrong cwd, leave stale `_build`, or print rc without propagating it? The question is whether the defects are real, not whether the script exits 0.

Output:
- Verdict table: defect | REAL / NOT REPRODUCED / MISATTRIBUTED / INCONCLUSIVE | evidence (rc/signature) | caveat.
- A short section per defect with exact commands and observed outputs.
- A list of any claim in the PoC READMEs that is unsupported by your run.
- A final risk assessment: which defects are safe to publish as-is, which need wording changes, and which need more work.

Be adversarial. A non-crashing clean diagnostic is not a defect; a crash caused by our own invocation error is not a defect. Return Chinese prose with exact command/rc evidence.
