# codex review 2 — option ② (syntax boundary) results

Prompt: `/tmp/codex_prompt2.txt`; run 2026-11-12 via
`HTTPS_PROXY=http://127.0.0.1:7890 codex exec -s read-only -C /data/audit/mbtfuzz
--skip-git-repo-check -`.  Full reply preserved in the session log; verdicts and
point-by-point verification below.

## codex verdicts (condensed)

1. **ACCEPT F5/P1 as low-severity tooling defects; REJECT parts of scope and
   complexity claims.**  F5: formatter output not re-parseable + unbound `~+`
   diagnostic; neither is a miscompile.  Hypothesis: unary `+` is a legacy
   parse path without typechecking operation.  Asked for a `+1 / +(1) / +y /
   +(y) / ++y` vs unary-minus matrix.  P1: report “severe super-linear
   interpolation-formatting time”, not `O(k^3.3)`; confirm typecheck of the
   large case, record CPU time, try another width, no need to finish k=4096.
   “P1” = performance finding id, not priority.
2. **ACCEPT (a) stop this campaign and (c) use failure novelty; REJECT
   claiming the original stop rule was met.**  Literal conjunction failed
   (<20,000 cases, a new defect class, a scaling anomaly, `<20 new functions`
   not measured).  Proposed family-level rule based on distinct *defect
   signatures* (minimized trigger / subsystem / invariant / scaling), with
   diagnostic templates as hints only.  Close as “bounded campaign completed;
   two findings triaged”; do not pad to 20,000.
3. **ACCEPT option 3 next, with gates.**  4-hour total pilot: 90 min build
   gate (runnable frontend + parse/typecheck), 45 min calibration (50–100
   shared-language controls incl. expected rejections, dependency-free or
   version-compatible), then targeted precedence/recovery/pattern/generic/
   visibility comparisons.  Success = ≥1 minimized discrepancy with
   independent evidence that the current compiler is wrong, or ≥1 new
   reproducible current-version crash/ICE/scaling defect.  Abandon if a gate
   fails, ≥80 % of first 20 minimized differences are drift/environment/
   representation, or the 4 hours end without a credible candidate.  Fallback:
   `build-interface` source-vs-interface client check, then `gen-test-info`
   metadata consistency; `wasm-ld` needs valid objects first.  Notes
   `gen-test-info` is underexplored (763 commands, +29 functions), not
   unobserved.
4. **REJECT several numeric/evidentiary claims.**  Listed below; all checked
   against the artifacts.

## Verification of codex's corrections

| # | codex claim | check | result |
|---|---|---|---|
| 1 | “71 includes `OK`; 70 non-OK templates” | `len(first)=71` incl. `OK` | **confirmed** |
| 2 | “57 `E3002` signatures, not 61” | counter over template prefixes | **confirmed** (57) |
| 3 | “index 19,520 is zero-based → 19,521st case” | `first_seen` stores 0-based `i` | **confirmed** |
| 4 | “`.` duplication 12/17; 13/17 is `.`→`,`” | matrix: dup 12/17, conf 13/17 | **confirmed**; doc fixed |
| 5 | “`+` confusion is `+`→`-`, so not prefix plus” | `x +- y` is binary `+` with unary `-`; check=0 | **confirmed**; doc fixed |
| 6 | “8 dimensions reach 4096; match arms stop at 512” | `gen_series` caps match arms at 512 | **confirmed** |
| 7 | “‘linear parser’ overclaimed” | slopes near 0 over 8–19 ms | **confirmed**; reworded to “no super-linear growth in tested range” |
| 8 | “forked Python inflates `ru_maxrss`; floor ~40,600 KiB in the mutation run” | `/bin/true` under harness = 8,048 KiB floor; mutation max 42,488 KiB | **partially confirmed**: floor exists (8,048 KiB), but the 42,488 KiB max is a real case above it; for `syncheck` the harness value matches `/usr/bin/time -v` (17,408–17,416 vs 17,416 KiB), so the 17.4 MB figure is not inflated |
| 9 | “42,488 KiB ≈ 43.5 MB / 41.5 MiB, not 42.5 MB” | unit conversion | **confirmed**; fixed |
| 10 | “output bytes 13,250→13,257; identify the 13,266 fixture” | scale row 13,250→13,257; CLI fixture (different wrapper) 13,250→13,266 | **confirmed**; doc now quotes the scale row and flags the separate CLI fixture |
| 11 | “controls cheap, not uniformly flat (concat 7.4→18.0 ms)” | probe rows | **confirmed**; reworded |
| 12 | “4,096/8,192 completion estimates are extrapolations” | only `>25 s` measured at 4,096 | **confirmed**; labelled |
| 13 | “stop rule not met / ‘met with margin’ unsupported” | literal rule needs 20,000, <20 functions, no anomaly | **confirmed**; verdict rewritten, codex rule adopted |
| 14 | “F5 matrix needed; `+1` may fold” | matrix in `out/f5_matrix.json` | **confirmed**: `+1` folds to `1` (check 0), `+(1)`/`+y`/`+(y)`/`x++y` all check 1 with `~+` unbound and fmt output unlexable; unary minus controls all check 0 |
| 15 | “P1: typecheck large case, CPU time, fixed-width control” | `moon check` 0.08 s on 2,048 segments; `/usr/bin/time -v` 10.24 s user + 16.64 s sys; fixed-width 512→2,048 = 0.35→26.89 s (8.5×/doubling) | **confirmed**; all added |
| 16 | “no width flag test possible” | `moonfmt` exposes only `-o/-w/-i/-file-type` | **confirmed**; documented as untestable |
| 17 | “662 clean corpus does not establish all well-typed programs are unaffected” | scope statement | **confirmed**; reworded to the bounded claim |
| 18 | “`gen-test-info` underexplored (+29 functions from one 763-function probe)” | `findings/entrances.md:102` (763 = single-run `Moonc.*` count, not commands) | **confirmed**, wording corrected |

## Net effect

* F5 and P1 kept, with corrected scope (F5 is a legacy unary-`+` parse path;
  `+1` folds, non-literal leaks `~+`), corrected numbers/units, and new
  confound checks.
* Campaign closed as **bounded campaign completed; two findings triaged**;
  the literal stop rule is recorded as not met, and the family-level
  defect-signature rule is adopted.
* Next action: gated 4-hour old-compiler pilot (option 3).  Gates: 90 min
  build, 45 min calibration, success = one minimized discrepancy with
  independent evidence or one new current-version crash/ICE/scaling defect;
  abandon criteria as in codex verdict 3.

All 18 codex corrections were checked; 17 fully confirmed, 1 partially
confirmed (RSS floor exists but the reported `syncheck` absolute value is
independently corroborated).
