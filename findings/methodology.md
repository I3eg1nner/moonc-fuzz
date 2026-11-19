# Methodology: how much a silent oracle is worth

Date: 2026-11-19. Toolchain: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. Host: Linux x86_64, single machine. Code:
`moonbit/cmd/oraclestat/main.mbt`, `moonbit/judge/`.

This note exists because "we did not find a defect in N cases" is not a
result until you say what N is worth, and "the oracle stayed silent" is not
evidence until you say what the oracle can see. Every number below is
reproducible with the command printed next to it; nothing here is a claim that
the compiler is correct.

## 1. Definitions

| Term | Meaning here |
|---|---|
| observation | one execution of a toolchain command, reduced to `stage, rc, timed_out, wall_ms, cpu_ms, frames, expects_frames, alive_after, stdout, stderr` |
| oracle | a predicate over one observation that returns zero or one finding; seven are registered (`crash`, `busy_hang`, `blocked_stall`, `timeout_plain`, `missing_frames`, `nonzero_silent`, `orphan_leak`) |
| finding | an oracle's verdict, carrying severity `defect`, `suspicious` or `infra` |
| defect | a finding whose severity is `defect`; a syntax or type error is a failed experiment, not a defect |
| hit (TP) | an oracle fires on an observation labelled defect |
| false alarm (FP) | an oracle fires on an observation labelled benign |
| case | one generated input run through one stage on one target |

Two consequences are load-bearing:

1. **A negative result is conditional.** "No defect in 269 cases" means "no
   defect *visible to these seven oracles* in 269 cases". An oracle blind to a
   defect class silently converts it into a clean run. This is why §2 comes
   before §5.
2. **A defect count is per signature.** 41,118 crashes with one signature are
   one finding, not 41,118. Signature collapse is a feature (it is what makes
   novelty a usable signal), but it means "crashes found" and "defects found"
   are different quantities.

## 2. Oracle sensitivity and false alarms (decision level)

`oraclestat` runs every oracle against the labelled probe matrix in
`moonbit/judge/probes.mbt` (19 fixtures copied from reproduced defects and
their controls).

```bash
cd moonbit && moon build --target native
./_build/native/debug/build/cmd/oraclestat/oraclestat.exe --clean 1 --broken 1 --root /tmp/ostat
```

| Oracle | Positives | Hits | Controls | False alarms |
|---|---:|---:|---:|---:|
| `crash` | 3 | 3 | 1 | 0 |
| `busy_hang` | 1 | 1 | 1 | 0 |
| `blocked_stall` | 2 | 2 | 2 | 0 |
| `timeout_plain` | 1 | 1 | 1 | 0 |
| `missing_frames` | 1 | 1 | 2 | 0 |
| `nonzero_silent` | 1 | 1 | 1 | 0 |
| `orphan_leak` | 1 | 1 | 1 | 0 |

10/10 positives fire, 0/9 controls fire. The honest reading is narrow: five
oracles have **one** positive each, so this table proves they *can* fire, not
that they fire on most members of their class. The compensating evidence is
different in kind: `accept` gate `regressions_12` replays twelve real defects
through the real toolchain, and gate `oracle_fpr` (below) checks the silent
direction on real builds.

## 3. Decision boundaries

Thresholds are step functions, so each one has a concrete location. These are
the vectors printed by `oraclestat`, with `Y`/`N` = fires/does not:

```text
crash/rc=[0:N 1:N 2:N 134:N 139:N 255:N -6:Y -11:Y]
crash/markers=[ice:Y oom:Y exn:Y stack:Y assert:Y stdout-ice:N ... stdout-assert:N]
busy_hang/cpu_ms(wall=3000,alive)=     0:N 50:N 500:N 1400:N 1500:Y 1600:Y 3000:Y
blocked_stall/cpu_ms(wall=3000,alive,owes)= 0:Y 50:Y 500:Y 1400:Y 1500:N 1600:N 3000:N
blocked_stall/cpu_ms(not alive)=       0:N ... 3000:N
blocked_stall/cpu_ms(no output owed)=  0:N ... 3000:N
timeout_plain/cpu_ms(wall=3000,dead)=  0:Y 50:Y 500:Y 1400:Y 1500:N 1600:N 3000:N
missing_frames/frames=[0:Y 1:N 2:N]
nonzero_silent/rc=[0:N 1:Y 2:Y]
orphan_leak/alive=[false:N true:Y]
```

What this buys, stated precisely:

- Busy and blocked are **complementary at exactly `cpu_ms*2 >= wall_ms`**, and
  both are off when the child is dead or when no output is owed. There is no
  gap and no overlap in the tested range, so one timeout cannot be counted as
  three synonyms.
- `crash` does **not** treat `rc=139` as a signal. Shell-style `128+signal`
  exits are a positive code; only `rc<0` is a signal. A classifier that
  accepted 139 would double-count the same SIGSEGV that already arrives as -11.
- Compiler markers are stderr-only. The stdout controls are the same five
  strings, and all are `N`; a fuzzed program printing "Oops, the compiler has
  encountered" cannot manufacture an ICE.
- `missing_frames` fires only at `frames=0` with `expects_frames=true`; one or
  more frames silences it.

Limitation: the sweep points are coarse (0/50/500/1400/1500/1600/3000 ms), so
the vectors locate the boundary to within the step, not to the millisecond.
That is enough because the boundary is defined by an integer comparison, not
measured.

## 4. End-to-end false positives on real builds

The question this answers: on runs where nothing is wrong, how often does the
pipeline cry defect? The corpus is 27 generated programs from `@numgen.cases()`
(pure arithmetic/string programs), each compiled as a standalone package, in
two flavours: as written (must build clean) and with an appended type error
(must fail with a diagnostic). Five configurations:

```bash
for cfg in "check wasm-gc" "build wasm-gc" "build js" "build native" "test native"; do
  set -- $cfg
  ./_build/native/debug/build/cmd/oraclestat/oraclestat.exe \
    --stage $1 --target $2 --clean 27 --broken 27 \
    --root /tmp/ostat_$1_$2 --json /tmp/ostat_$1_$2.json
done
```

| Configuration | Clean runs | Broken runs | Defects | Mislabelled | ms/observation |
|---|---:|---:|---:|---:|---:|
| `check` wasm-gc | 27 | 27 | 0 | 0 | 61.9 |
| `build` wasm-gc | 27 | 27 | 0 | 0 | 74.2 |
| `build` js | 27 | 27 | 0 | 0 | 73.9 |
| `build` native | 27 | 27 | 0 | 0 | 469.9 |
| `test` native (`--build-only`) | 27 | 27 | 0 | 0 | 475.9 |
| **total** | **135** | **135** | **0** | **0** | — |

270 real toolchain runs, zero false alarms. With zero events in 270 trials the
95% upper bound on the false-positive rate is the rule-of-three value
`3/270 = 1.1%` (the exact Clopper-Pearson bound `1-0.025^(1/270)` is 1.4%;
this document uses the more conservative of the two, which weakens rather than
strengthens the claim).

Three caveats, in decreasing order of importance:

1. **The hang oracles are barely exercised here.** Clean and broken builds
   never time out, so `busy_hang`, `blocked_stall` and `timeout_plain` receive
   no real negatives from this corpus — only the decision-level controls of §3.
   The false-positive rate above is a statement about the build path.
2. **The 27 sources are reused across configurations**, so the 270 runs are
   correlated samples of 27 programs. The bound is a bound for this corpus, not
   for "MoonBit programs".
3. **LSP has six real controls, not a corpus.** The three stall/hang defects
   (F10/F11/F12) are asserted *to still reproduce* by gate `lsp_regress_6`;
   the benign LSP runs in the PoC transcripts (empty `params`, `params: []`,
   a normal `hover`) are hand-run controls. A large LSP negative corpus is the
   main measurement gap in this document.

## 5. Negative results and what they bound

Each row is a family of cases in which no *new* defect appeared. The bound is
`3/n` at 95%, conditional on the oracles of the time seeing that defect class.

| Family | Cases | New defects | 95% upper bound | Source |
|---|---:|---:|---:|---|
| Native layout / FFI / async matrix | 269 | 0 | 1.1% | `findings/feature_probe_negative.md` |
| Async timeout / cancel / combinators | 55 | 0 | 5.5% | `findings/async_cancel_probe.md` |
| Layout four-cell differential (builds) | 640 | 0 mismatches | 0.47% | `findings/xdiff_mvp.md` |
| Async per-test status differential | 18 | 0 mismatches | 16.7% | `findings/xdiff_async.md` |
| Semantic differential (27 programs × 2–3 targets) | 54 builds | 0 mismatches | 5.6% | `findings/semantic_diff.md` |
| Defect-seeded mutants | 254 | 0 new signatures | 1.2% | `findings/seed_mutation.md` |
| Integer bit-pattern pairs | 23,920 | 0 mismatches | 0.013% | `findings/semantic_diff.md` |
| IR/template programs, 12,096 executions | 12,096 | 0 new | 0.025% | `findings/ir_fourcell.md` |
| Real packages, four-cell (8,849 test IDs) | 8,849 | 0 mismatches | 0.034% | `findings/improvement_evaluation.md` |

Reading rules that keep this table honest:

- **The bound is about the rate observed, not the rate that exists.** A class
  the oracles cannot see has rate 0 in this table by construction. The 269-case
  row, for instance, was generated from a hand-written feature matrix; it says
  nothing about features nobody wrote a case for.
- **Small n gives useless bounds.** 18 builds bound nothing (16.7%); those rows
  are listed to be visibly weak, not to be cited.
- **Zero mismatches in a differential is stronger than zero defects in a
  crash oracle**, because equality is a total predicate over the outputs that
  were produced: it fails on any difference, not only on a difference someone
  predicted. This is why the four-cell and semantic rows carry more weight per
  case than the crash-oriented rows.

## 6. Cost model

Cost per observation is dominated by process spawn plus the compiler's own
work, not by mutation. Measured on this host, one standalone package:

| Stage | Target | ms/observation | observations/hour |
|---|---|---:|---:|
| `check` | wasm-gc | 61.9 | 58,200 |
| `build` | wasm-gc | 74.2 | 48,500 |
| `build` | js | 73.9 | 48,700 |
| `build` | native | 469.9 | 7,660 |
| `test --build-only` | native | 475.9 | 7,570 |

Campaign throughput from the instrumented 60 s / 16-worker calibration:
`it=48880`, i.e. ~815 iterations/s wall for text-mutation work whose stage mix
is mostly T1 (`findings/feedback_loop.md` §3.3.1). That number is a throughput
measurement, not a defect-finding rate.

The campaign ledger (`findings/migration_moonbit.md`) totals **1,149,921
iterations** across nine drivers and produced **16 reproduced defect entries**
(13 independent defects + 3 same-signature witnesses). The ledger counts *new
diagnostic signatures*, not defects, and the two must not be divided into each
other: 1,443 new signatures in the `.mbti` campaign yielded no defect at all,
because every one was a parse or type error. Attribution of the 16 entries is
spread across the drivers (F1/F1b from `moon.pkg` mutation, F2/F2b from body
mutation, F4 from byte-level `.mbt.md`, F5 from formatter round-trip, F6 from a
third-party package, F7/F9/F10–F12 from targeted probes), which is the point:

| Strategy | Cases | Outcome | Yield |
|---|---:|---|---:|
| Blind byte mutation (`.mbt.md`) | 81,570 | 41,118 crashes, 1 signature | 1.2e-5 |
| Blind body mutation | 126,497 | 16 new signatures, 0 crashes | — |
| Random `moon.pkg` mutation | 223,043 | 64 new signatures → 1 unique after dedup | — |
| `.mbti` mutation | 111,707 | 1,443 new signatures, 0 defects | 0 |
| Feature matrix probe (curated) | 269 | 0 new | 0 |
| Four-cell differential on real packages | 640 builds | 0 mismatches | 0 |
| Targeted layout generator (`scalefuzz`) | 36 | 21 defects, 2 distinct signatures | 0.58 |
| Targeted semantic differential | 27 | 0 mismatches | 0 |

The observable span is **four orders of magnitude** between blind mutation
(one defect per ~80,000 iterations) and a generator built around a known
trigger (two signatures in 36 cases). The cost implication follows directly:

```text
cost per defect  =  (1 / yield) x  cost per observation
blind byte work  =  81,570 x 74 ms   ~=  6,000 CPU-seconds  (1.7 CPU-hours)
targeted layout  =  18 x 470 ms      ~=  8 CPU-seconds per signature
```

So "run more samples" is not the lever it looks like. At the blind rate one
more defect costs CPU-hours, and 99.97% of the crashes observed in the
`.mbt.md` campaign collapsed into one already-known signature (41,118 crashes →
F4); the same input mutation keeps re-deriving the same root cause. The levers
that did work were oracle strength (a new predicate over a new observation
field: `cpu_ms` separating busy from blocked) and generators that make a
*structurally* new input (F7/F8/F9), not larger volumes of the same shape.

## 7. What would change these conclusions

Stated as falsifiers so a reader can check them against future work:

- **The 10/10 hit rate** would be invalidated by an oracle that stays silent on
  a defect class it claims to cover; the cheapest test is one more independent
  positive per oracle (five oracles currently have one).
- **The 0/270 false alarms** would be invalidated by any finding on a clean
  build; the gate `oracle_fpr` is the regression net for that.
- **The negative bounds** would be invalidated by a defect found in a family
  with a small n (e.g. a semantic mismatch the equality oracle missed because
  both backends produced the same wrong output — equality cannot see that, and
  no bound in §5 covers it).
- **The cost model** would be invalidated by a toolchain change that makes
  process spawn much cheaper (the 74 ms floor is spawn + core resolution, not
  the generated program).

## 8. Reproduction

```bash
cd moonbit
moon build --target native
# decision matrix + boundaries + 8/8 false-positive gate
./_build/native/debug/build/cmd/oraclestat/oraclestat.exe --clean 8 --broken 8 --root /tmp/ostat
# the full 270-run measurement of §4
for cfg in "check wasm-gc" "build wasm-gc" "build js" "build native" "test native"; do
  set -- $cfg
  ./_build/native/debug/build/cmd/oraclestat/oraclestat.exe --stage $1 --target $2 \
    --clean 27 --broken 27 --root /tmp/ostat_$1_$2 --json /tmp/ostat_$1_$2.json
done
```

The counters are `defects` (false alarms) and `unexpected` (corpus
misclassification); a non-zero `unexpected` means the measurement is void, not
that a defect was found.
