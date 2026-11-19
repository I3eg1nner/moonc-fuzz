# Seed-driven mutation: the neighbourhood reproduces, it does not discover

Date: 2026-11-19
Status: implemented (`cmd/seedfuzz`), gated for seed reproduction only

## Hypothesis

Hand-designed matrices saturate: once a dimension is enumerated, more cases
buy nothing. The project's own record is blunt about it — 269 feature cases,
55 async cases, 640 cross-backend builds, 23,920 integer pairs, 12,096 IR
programs: zero new defects. The two defects that did come from a campaign came
from an oracle, not from more samples.

The complementary axis is **neighbourhood**: start from a minimal witness that
is already known to break the compiler and mutate *it*, so the budget is spent
where the compiler is demonstrably fragile. That is the standard argument for
corpus-based fuzzing, and it had not been tested here.

## Design

- **Seed = package directory**, not a source file. F9 only reproduces with its
  `native-stub` and `targets` configuration; flattening it into a skeleton
  turns every mutant into a type error. An early version did exactly that and
  produced 6/6 invalid mutants — a nice demonstration of why the validity gate
  matters.
- **Mutation** uses the existing structure-aware engine
  (`mutate.mutate(..., body_only=false)`): block duplication/deletion,
  statement insertion, literal edge cases, identifier renaming, delimiter
  perturbation, and MoonBit-specific ops.
- **Validity gate**: only a `judge` finding with severity `Defect` counts. A
  parse error is an invalid experiment, not a finding, so byte-level damage
  cannot manufacture "new bugs". This is the difference between a fuzzer and a
  random-error generator.
- **Known vs new**: each seed is run once, unmutated, to get its baseline
  signature. A mutant that reproduces that signature is `known` — it is the
  same defect, not a discovery.
- Each candidate is copied to the output directory with a `meta.json`, so any
  hit can be replayed and then fed to `cmd/minimize`.

## Measured

`moon build --target native`, default seeds (F2 escape ICE, F6 native export,
F9 v128 stub):

| campaign | mutants | runs | defects | known | new signatures | invalid | wall |
|---|---|---|---|---|---|---|---|
| build, 3 seeds | 200 | 194 | 52 | 52 | **0** | 148 | 62 s |
| build, 3 seeds (pilot) | 40 | 40 | 13 | 13 | **0** | 27 | 13 s |
| test-build, F9 only | 60 | 60 | 1 | 1 | **0** | 59 | 29 s |

`seed_defects = 2/3`: F2 and F9 reproduce at `build`; F6 does not (its defect
is at a different stage), which is why the seed baseline is measured rather
than assumed.

The validity rate is the interesting second number: 30% of mutants in the
build campaign still produce a *defect*, not a type error. The mutation engine
is therefore not just smashing bytes — it stays inside the language often
enough to be a real test.

## Interpretation

Across 254 mutants, the campaign re-found its seeds' defects 66 times and found
**zero** new defect classes. Both halves matter:

- The positive half says the harness works: mutations do reach the compiler's
  fragile path and the signature comparison is stable enough to recognise it
  (the same 52 defects collapse to one signature, not 52).
- The negative half says the neighbourhood, as explored by *this* operator
  set, is the seed's own bug. Local mutation of a witness mostly re-triggers
  the witness.

That is a claim about this generator, not about the space. The plausible
explanation is that the operators are **feature-local**: they move literals,
blocks and identifiers, but they never introduce a feature the seed does not
already use. A witness for "`#valtype` payload lowering" mutated into another
`#valtype` payload is still the same lowering pass, so the same assertion fires
and the signature does not change.

## What this changes

1. It is a **reproduction / regression-mining** tool now, not a discovery
   engine. Its best use is: given a defect class, generate many triggers, then
   minimise the smallest — that pipeline is already built
   (`seedfuzz` → `minimize`).
2. The next generator iteration is not "more mutants" but **cross-feature
   operators**: inject a feature the seed does not use into its body — make a
   function `async`, add `raise`, change a field to `#valtype`, move a value
   through an FFI stub — while keeping the seed's defect shape. That is the
   combination space the matrices never crossed and the mutation engine never
   reaches.
3. Because 0 new was measured with the *same* oracle layer that found F11/F12,
   the null result cannot be blamed on a weak oracle for crash/hang classes.
   It can still be blamed on missing non-crash oracles (miscompile), which the
   differential oracle covers and this campaign does not use.

## Claim limits

- Three seeds, one toolchain pin, one host, `native` target only.
- 254 mutants is a bounded budget; the confidence interval on "new defect
  rate" is wide. 0/254 gives a 95% upper bound around 1.2% per mutant, not
  "zero".
- `ignored` mixes three different things: mutation was a no-op (~3%), the
  candidate failed to compile, and the candidate compiled but showed no defect
  finding. The table's `invalid` column is that union, not a parse-error rate.
- Signature equality is intentionally strict. Two defects that differ only in
  the compiler's `Error:` text count as new; two triggers of one defect count
  as known. The `known=defects` result is therefore evidence that the
  signatures are *stable*, and evidence about novelty only relative to that
  granularity.
- The F9 campaign's 1/60 defects is not "worse": F9's witness is four lines and
  most mutations break the `extern`/stub pairing outright.
