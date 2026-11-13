# codex review 3 — old-compiler pilot and interface fallback

Prompt: `/tmp/codex_prompt3.txt`; run 2026-11-12 via the 7890 proxy
(`codex exec -s read-only -C /data/audit/mbtfuzz --skip-git-repo-check -`).
This log records the verdicts and the point-by-point verification, including
the corrections that changed our numbers.

## codex verdicts (condensed)

1. **ACCEPT abandoning option ③; REJECT extending it via `compile` or
   new-only syntax.**  The calibrated subset produced no disagreement and no
   current-version failure candidate; downstream stages or expected syntax
   rejections would not strengthen the oracle.  Qualification: the four-hour
   clause needs elapsed-time evidence, and the “≥80 % of first 20 minimized
   differences” clause was not demonstrated (the 75 excluded cases were one
   syntax-drift family).
2. **ACCEPT one final capped `build-interface` pilot; REJECT `gen-test-info`
   now.**  Oracle: build P from source → textual public interface →
   `build-interface` → second `.mi`; identical clients must get identical
   accept/reject against both artifacts, including expected rejections;
   fault-control the oracle with a deliberately altered signature.  100–200
   package/client pairs; success = one minimized mismatch attributable to
   interface emission/reconstruction/import, or a new crash/ICE; abandon after
   30 min setup or 2 h without a candidate; do not roll into metadata testing.
3. **Numerical/scope corrections** (see verification table).

## Verification of codex's corrections

| # | codex claim | check | result |
|---|---|---|---|
| 1 | calibration is 47 accept / 21 reject, not 48/20 | counted `out/olddiff_calib.json` | **confirmed** (47/21); doc fixed |
| 2 | saved controls do not substantiate every claimed feature (recursive enums, mut fields, deep tuple patterns) | those are in the widened generator, not the 68 controls | **confirmed**; calibration vs generation now separated |
| 3 | 3,500 generated cases contain 1,159 distinct source texts | dedup over `olddiff2+3` | **confirmed** (1,159); doc fixed |
| 4 | 88 widened expected-accept cases were jointly rejected, all `deep_tuple_pat`, repeated `c` bindings | grouped by family; sample binds `c` four times | **confirmed**; generator expectation bug, both compilers correctly reject |
| 5 | `check` agreement is acceptance agreement, not semantic equivalence | scope statement | **confirmed**; wording fixed |
| 6 | “no matching old bundle exists” overstates the search | only GitHub releases/tags were queried | **confirmed**; changed to “none was found” |
| 7 | `priv fn` as “removal” needs old-acceptance evidence | old rejects it too (not a shared form) | **confirmed**; table now says both reject, no removal claim |
| 8 | “763 commands” in the prior review is wrong; entrance table reports 763 functions from one probe | `findings/entrances.md:102` is a `Moonc.*` count | **confirmed**; `codex_review_2.md` corrected |
| 9 | four-hour stopping condition requires timing evidence | pilot ended after ~1 h; no clock claim | **confirmed**; doc now states the structural reason (builtin-only subset) instead of the time clause |

## Net effect

* Option ③ closed as **abandoned, no credible candidate**; 3,500 records /
  1,159 distinct programs, zero disagreements; the 88 “expected accept”
  rejections are a local generator bug and were inspected, not a compiler
  signal.
* Interface pilot executed under the prescribed oracle: calibration + fault
  control passed; 150 packages / 2,278 client checks produced zero
  mismatches and zero crashes.  One tooling-dialect observation
  (`mooninfo` opaque-type text is rejected by `build-interface`; `type S`
  normalization fixes it) is recorded as an observation, not a defect.
* Campaign closed; no automatic roll into `gen-test-info`.
