# Codex independent defect verification

Date: 2026-11-13.  Access: `HTTPS_PROXY=http://127.0.0.1:7890`, Codex
`workspace-write` sandbox, no tracked source edits by the reviewer.
Prompt: `findings/codex_defect_prompt.md`; raw answer:
`findings/codex_defect_review_raw.md`; raw command records:
`findings/codex_defect_results/`.

Installed toolchain observed by the reviewer:

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104
```

The reviewer ran from fresh copies where cache could matter (F2, F6), removed
`_build`, checked input bytes with `xxd`, and ran controls that should not
trigger.  One initial attempt was blocked by a `bwrap` namespace failure before
the toolchain started; it was excluded.

## Verdict

All submitted PoCs reproduced the stated abnormal behavior.  No false positive
was found from a nonexistent file, wrong cwd, missing core library, or stale
`_build` cache.

| Defect | Verdict | Evidence | Caveat |
|---|---|---|---|
| F1 | REAL | 3/3 SIGSEGV, rc 139 | file has **50** `1` tokens, not 49; 48/49 clean |
| F1b | REAL | 3/3 SIGSEGV, rc 139 | same top frames support same error path, not proven same root |
| F2 | REAL | 3/3 `moon check` rc 1, `Char.chr` | `syncheck` alone 3/3 rc 0 |
| F2b | REAL | 3/3 build-package rc 199, `Char.chr` | full flags needed; independent module also reproduces |
| F3 | REAL | 2/2 rc 134, SIGABRT, OOM | only bounded 6 GiB run; no claim of infinite growth |
| F4 | REAL | 3/3 rc 199, `Basic_utf8_decode.MalFormed` | file is 40 B |
| F4b | REAL | 3/3 same decoder exception | same exception class, not proven same root |
| F5 | REAL | 3/3 syncheck 0, fmt 0, reparse 2/E3001 | formatter round-trip defect; original program does not typecheck |
| F6-min | REAL | 3/3 `moon build --target native` rc 255, exact ICE | link-time diagnostic/tooling defect |
| F6 external | REAL | 3/3 rc 1, same signature | bridge native link only; no miscompile |
| P1 | REAL | median 1.585 s -> 15.348 s (9.68x) | two points do not establish asymptotic complexity |

## Key controls

- F1: 48/49 numeric tokens and trailing newline -> rc 2; 50 tokens -> SIGSEGV.
- F2: `\中` -> ICE; replacing with `\n` -> rc 0.
- F2b: `\` + U+200B -> rc 199; `\n` control -> rc 0; independent module also
  rc 1 with `moon check`.
- F3: 19 B valid source -> rc 0 in 0.009 s; malformed input -> ~5.4 GiB RSS
  under the 6 GiB cap.
- F4: valid UTF-8 control -> rc 0; invalid bytes -> decoder ICE.
- F4b: replacing invalid bytes with U+FFFD -> ordinary E3001/E3002, no ICE.
- F5: `+y` -> `~+` reparse failure; `-y` control passes.
- F6: no `#export_name` -> rc 0; `#export_name` with `Int32` field -> rc 0.
- F6 external: package-scoped `src` build/test pass; module and bridge native
  links fail; JS tests pass.

## Corrections applied after review

- F1 token boundary corrected to 50; 49 is clean.
- F1/F4 byte sizes corrected in the PoC docs; F4 is 40 B.
- F1b/F2b/F4b wording downgraded from "same root cause" to "same crash /
  exception class; root identity not proven".
- F2b README now contains the full `build-package` command.
- F3 uncapped 8.2 GiB/20 s figure marked as an earlier observation, not re-run.
- F5 historical matrix marked as recorded data, not re-verified by the PoC.
- F6-min line count corrected from 12 to 10; expected rc 2 no longer asserted
  as an interface requirement.
- P1 reported as a measured 9.68x from 1024 to 2048, not an asymptotic class.
- `scripts/reproduce_all.sh` was hardened to assert expected rc and signature
  and to exit nonzero on failure.

## Remaining limits

- Root-cause identity and number of independent defect classes are not proven
  by black-box reproduction.
- F3 termination and unbounded-growth behavior were not tested.
- P1's complexity order and whole-package `moon fmt` behavior were not tested.
- F5's historical full matrix was not re-run.
- No evidence supports memory-corruption exploitation, runtime miscompilation,
  or a remote attack surface.
