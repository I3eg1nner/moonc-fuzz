# Exact TB edge novelty in fuzz scheduling

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`,
`moonc v0.10.20+65efd5b93`. Code: `moonbit/trace/collect.mbt`,
`moonbit/cmd/fuzz/main.mbt`. This closes the scheduling TODO in
`findings/exact_coverage_wiring.md`.

## What changed

- `TraceResult` now carries `edge_keys : Array[String]`, the exact, sorted,
  deduplicated `"<pc0>,<pc1>"` set for TB transitions whose **both** endpoints
  map to a symbol. `collect` gets the counters and the keys from one
  `scan_trace` pass; `edge_keys(...).length() == mapped_edges` still holds.
- `TraceUniverse` (the campaign driver) now has a bounded `edge_seen` map, a
  configurable `edge_cap`, a sticky `edge_saturated` flag, and a `new_edges`
  counter. `edge_universe_add` is a real membership-based set difference: it
  returns how many keys in this trace were not already in the campaign set.
- Every complete trace updates `edge_seen`, including baseline (U0) traces.
  Baseline keys seed the universe but do **not** increment `new_edges`; that
  counter accumulates only non-baseline (candidate) additions, so it measures
  the signal actually offered to scheduling rather than seed coverage.
- `feedback_upsert` takes `new_edges` and adds the edge bonus. Existing
  function-set union, `by_key`, `coverage_adds`, `relative_new`, and parent
  selection are otherwise untouched.
- Coverage sidecars now record `trace_edge_keys` (this trace's key count) and
  `edge_novel` (did this trace add at least one key at completion). The key set
  is never written to the sidecar or to `summary.json`.
- `summary.json` gains `edge_keys`, `edge_cap`, `edge_saturated`, and
  `new_edges`. No existing field is renamed or reinterpreted. The historical
  function-coverage headline (7,916 / 26,611 = 29.75%) is unchanged and is not
  recomputed by this patch.

## Exact bonus weights

Constants in `cmd/fuzz/main.mbt`:

| constant | value | meaning |
|---|---:|---|
| `FUNC_NOVELTY_BONUS` | 32 | at least one new `camlMoonc*` function |
| `KNOWN_FUNC_BONUS` | 6 | no new function, but the input still covers functions |
| `EDGE_NOVELTY_BONUS` | 8 | at least one new exact TB edge key |
| energy ceiling | 64 | unchanged pre-existing cap |

`bonus = base + (if new_edges > 0 { 8 } else { 0 })`, where
`base = 32` if `added > 0`, else `6` if the input's function set is non-empty,
else `1`. Resulting cases:

| input | energy/bonus |
|---|---:|
| new functions only | 32 |
| new functions **and** new edges | 40 (additive) |
| new edges only, function set non-empty | 6 + 8 = 14 |
| new edges only, no function at all | 1 + 8 = 9 |
| neither | 1 (new) / 6 (known functions) |

Function coverage stays primary: the edge term (8) is strictly smaller than
function novelty (32), and an edge-only input cannot reach the top tier. The
`1 + energy` selection weight and the 64 ceiling are unchanged.

A candidate is rewarded at most once per `(input_hash, config_hash, stage)`
via the existing `rewarded` map. Re-observing the same trace adds no edge keys
and therefore no second bonus. If an input adds only edges, `trace_apply_delta`
now calls `feedback_upsert` even when the function delta is zero; the function
set logic is still updated exactly as before.

## Cap and saturation

- Default: `EDGE_CAP_DEFAULT = 200000`, overridable with `--edge-cap N`
  (negative values clamp to 0). The cap is campaign-wide, not per stage or per
  outcome.
- Insertion checks the cap before each new key. At capacity, the next
  genuinely new key sets `edge_saturated = true`; from then on
  `edge_universe_add` returns 0 and adds nothing. Retained keys are never
  evicted, and already-seen keys are still recognized.
- A trace that crosses the cap may contribute a partial prefix of its keys
  (the array is sorted); the saturation flag makes that explicit. After
  saturation `new_edges` is 0, by construction, for every later trace.
- Why 200k: one real `moonc` T1 trace in the smoke run had 28,332 mapped
  transitions and one T2 trace had 37,376. A cap below one trace would
  saturate during U0 and make the novelty signal meaningless. 200k keys is
  roughly 10-20 MB at worst (heap strings plus map overhead) and leaves room
  for several traces of real novelty while still bounding campaign memory.
- Why a cap at all: the edge universe is much larger than the function set.
  Uncapped, a multi-hour campaign would retain one heap string per distinct
  TB transition forever. Saturation is an explicit recall bound, not a silent
  approximation.

`edge_keys` in `summary.json` is the number of **retained** keys, not the
number of distinct edges ever observed. `new_edges` is the number of keys
added by non-baseline traces; it is not `edge_keys - baseline_edges`, because
keys overlap across traces and because saturation stops counting.

## Two different scopes (do not compare the numbers)

`functions` / `coverage_funcs` use the historical `camlMoonc*` filter.
`edge_keys` / `edge_seen` / `new_edges` use the **all-mapped** rule: a
transition counts when both endpoints map to any symbol, including `main`,
stdlib helpers, and non-`camlMoonc` support code. Consequently:

- an input can add edges without adding a single `camlMoonc*` function, and
  that is exactly the case the 9 or 14 bonus is for;
- `edge_keys` must be compared with `mapped_edges`, never with
  `coverage_funcs_count`;
- the 29.75% headline remains a function-coverage number and says nothing
  about edge coverage.

The universe is also campaign-wide across T1/T2/T3: an edge first seen in a
T1 trace is not novel in a later T2 trace. This is intentional ("first
observation in this campaign"), but it means the signal is not per-stage
independent. `config_hash` is effectively constant within a campaign, so the
keys are not mixed across compiler binaries in one run.

## Persisted evidence

Per `(input_hash, config_hash, stage, outcome)` sidecar, in addition to the
existing counters:

```json
{
  "unique_pc": 24257,
  "mapped_unique_pc": 21130,
  "edges": 42385,
  "mapped_edges": 37376,
  "trace_edge_keys": 37376,
  "edge_novel": true,
  "tb_counter_scope": "latest_trace",
  "func_scope": "camlMoonc*",
  "edge_scope": "mapped_both_endpoints"
}
```

`trace_edge_keys` is this trace's key count (equal to `mapped_edges` by
construction); `edge_novel` is the boolean answer to "did this trace add any
key to the campaign universe when it completed". The keys themselves are not
persisted. Records are rewritten on replay, so the counters and the boolean
describe the latest trace for that key, consistent with `tb_counter_scope`.

## What is still not claimed

- TB transitions are **not** source CFG edges or branches. A QEMU TB boundary
  is a translation artifact; none of these numbers may be reported as branch
  coverage.
- Keys (`"<pc0>,<pc1>"`) are PC values from one `moonc` binary and one
  `nm -n` symbol table. A toolchain or binary change invalidates cross-run
  unions; keys stay exact within one binary but comparability does not
  transfer.
- Saturation means edge recall is bounded: after the cap is hit, genuinely new
  edges are no longer rewarded and `edge_saturated` says so. The run cannot
  claim it saw every edge.
- `new_edges` counts candidate traces that completed before a failed baseline
  was known to have failed; those candidates are still unrewarded (existing
  U0 rule) but their edge observations remain in the universe. It is a
  coverage-growth counter, not a count of reward events.
- No per-input edge key set is retained, so a sidecar cannot reconstruct which
  keys an input hit. Replay would need the trace log or a new capped on-disk
  store.
- This is an additive scheduling hint, not evidence that edge feedback finds
  more bugs. No discovery campaign was run (host is under a strict serial
  budget); the smoke run only proves the plumbing and counters.
- Blocks still have only a count (`unique_pc`), not a retained set; "new
  blocks" is still not computable from persisted evidence.

## Tests

`moon test --target native`: 232 total, 232 passed (228 existing + 4 new).
New tests:

- `edge universe dedups, caps, and saturates without evicting` — insert,
  duplicate, exact-cap, cap-exceeded, sticky saturation, retained keys.
- `edge-only novelty earns a smaller bonus than function novelty` — exact
  weights 9/32/40 and strict inequality.
- `an edge-only trace is admitted and rewarded small, exactly once` — real
  `trace_apply` path, `new_edges` count, sidecar `trace_edge_keys` /
  `edge_novel`, no double reward on replay.
- `edgeless traces keep edge counters at zero and do not panic` — buffered
  candidate plus baseline with no mapped transitions.

The existing sidecar-shape test was extended to assert `trace_edge_keys` and
`edge_novel`.

## Smoke result

Serial, one `moon` process at a time, 1 campaign worker and 1 trace worker,
6 seconds (not a discovery run). Command, from `moonbit/`:

```
moon run cmd/fuzz -- --root /data/audit/mbtfuzz \
  --out /tmp/mbtfuzz_covedge_smoke --run-id smoke_edges_v2 \
  --workers 1 --duration 6 --trace-t1 100 --trace-t2 0 --trace-t3 0 \
  --trace-workers 1 --baseline-seeds 1 --seed 13
```

Relevant `summary.json` fields:

```json
{"trace_completed":3,"baseline_done":2,"baseline_state":"complete",
 "edge_keys":41485,"edge_cap":200000,"edge_saturated":false,
 "new_edges":3652,"coverage_adds":235,"relative_new":235}
```

The three sidecars carried, respectively,
`trace_edge_keys=28332, edge_novel=true` (baseline T1),
`37376, true` (baseline T2), and `33078, true` (candidate T2, 3,652 keys new
to the campaign).

A second run with `--edge-cap 64` exercised saturation in vivo:

```json
{"edge_keys":64,"edge_cap":64,"edge_saturated":true,
 "new_edges":0,"trace_completed":3,"baseline_done":2}
```

No crash, no trace failure; both runs exited 0. Full native tests, `moon check`
(0 warnings), and `moon fmt --check` were run serially afterwards.
