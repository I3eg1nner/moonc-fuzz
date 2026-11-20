# OOM candidate triage: input-triggered, but the same class as F3

Date: 2026-11-20. Candidate from the 30-minute soak (commit `ba3a39b`):
`/tmp/p03_soak/soak30/findings/t1/OOM/558d85552a72d365/in.mbt` (4,171 B).
Pin unchanged: `moonc v0.10.20+65efd5b93`.

The candidate's `meta.json` was malformed (`"status":"candidate""`) because it
was written by the pre-fix binary. That is a known bug from P0-1/P0-3, fixed in
`ba3a39b`; it does not affect the input itself.

## Reproducibility

Fresh copies, one per run, `moonc syncheck -error-format json in.mbt` under a
2 GiB address-space cap:

| run | rc | max RSS | wall |
|---|---|---:|---:|
| 1 | 134 (SIGABRT) | 1.86 GB | 4.7 s |
| 2 | 134 | 1.86 GB | 4.7 s |
| 3 | 134 | 1.86 GB | 4.7 s |

3/3, same input bytes, same limit. `stderr` carries `Fatal error: out of
memory` and `Command terminated by signal 6`.

## Is it the input or the limit?

The memory cap was raised until the abort point moved with it:

| cap | max RSS | wall | outcome |
|---:|---:|---:|---|
| 2 GiB | 1.86 GB | 4.7 s | abort |
| 4 GiB | 3.72 GB | 9.2 s | abort |
| 8 GiB | 7.47 GB | 21.3 s | abort |
| 32 GiB | 30.2 GB | 75.2 s | abort |

RSS tracks the cap and the process always dies at the cap, never finishing.
That is the signature of **unbounded growth**, not of a program that needs a
large fixed working set slightly above 2 GiB. A 4 KiB input does not have a
legitimate 30 GiB working set at any phase.

Controls:

- a normal 4 KiB source: rc 0, RSS in the tens of MB;
- the same input with the final `[` line removed: rc 2 (ordinary parse error),
  no OOM;
- hand variants that drop `..a`, or the outer `[`, or the `for` line: rc 2.

So the trigger needs the specific malformed construct, not "any syntax error"
and not "any 4 KiB file".

## Minimisation

Line-level ddmin (`/tmp/oomtriage/ddmin.py`, property = OOM at 512 MiB) took
151 lines → 4 lines in 23 probes. Hand reduction on the remaining token groups
produced a 54-byte witness:

```moonbit
fn f() {
  [
    for x in if c { [..a]
[
```

Confirmed 3/3 at 512 MiB, and at 6 GiB it reaches 5.66 GB (14.2 s) before
aborting. It is not proven minimal: dropping `..a` or the outer `[` removes the
effect, but no systematic character-level search was run.

## What it is (and is not)

This is **the same symptom class as F3**: `moonc syncheck`'s parser error
recovery does not advance, so memory grows without bound on malformed source.
F3's documented minimal witness is 19 B (`fn r(){y(for in ]` + newline + `[`);
ours is a 54 B fragment of otherwise plausible MoonBit source. Both are
`moonc syncheck`, both abort with `Fatal error: out of memory`, and both keep
growing with the cap.

The root-cause identity is **not proven**: the compiler is closed-source, we
have no stack, and "same symptom + same entry point" is not the same as "same
non-advancing production". So this is recorded as an **F3-family witness**, not
as a new F-number, exactly the rule the project uses for F1b/F2b/F4b.

`moon check` on the same source did not reproduce the OOM in the bounded test
(it exited before reaching the parser on this file layout), so the confirmed
impact is limited to the explicit `moonc syncheck` path - the same limitation
F1 already carries.

## Action taken

- `poc/f3_parser_oom/wild.mbt`: the 54 B witness.
- `cmd/regress`: new row `F3b_parser_oom_wild` (2 GiB cap, expect OOM) so the
  class stays covered by a witness that looks like real code, not only by the
  19 B adversarial one.
- `cmd/accept`: `regressions_12` → `regressions_13`.
- No upstream issue (forbidden in this round), no pin change, no
  `confirmed` claim.

## Limits

- Single host, single pin. The 32 GiB run is a property of this machine's RAM;
  the conclusion only needs "grows until it dies", which the 2/4/8/32 GiB
  series shows.
- Root identity with F3 is an inference, not a proof.
- The 54 B witness is not proven minimal; a character-level ddmin could shrink
  it further.
- The candidate was found by a T1 timeout/OOM path under a 2 GiB cap; the
  soak's other candidate (`candidate_witnesses=1`) was this one.
