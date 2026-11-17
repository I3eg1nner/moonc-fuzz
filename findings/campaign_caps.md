# Bounded campaign growth: parent pool and persisted evidence

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`,
`moonc v0.10.20+65efd5b93`. Code: `moonbit/cmd/fuzz/main.mbt`,
`moonbit/cmd/fuzz/fuzz_wbtest.mbt`. This closes the scaling warning in
`README.md` §8 ("多小时的 campaign 必须先限制/采样行为证据和父本池").

## Problem being closed

The 60 s / 16-worker calibration measured `it=48880`, `corpus=45546`,
`persisted=44342`, ~88,775 files and 437 MB. Both costs are linear in
campaign length:

1. `Feedback.entries` grew one parent per novel observation, and
   `feedback_pick` scans that array once per iteration, so parent selection
   was O(campaign).
2. `persist_source` / `persist_behavior` / `persist_coverage` wrote files for
   every retained input, so the file tree was O(campaign) as well.

Linearly extrapolated to two hours that is ~10M files. This patch makes both
costs explicit and bounded. It does **not** change what the campaign executes:
mutations, T1/T2/T3 calls, crash/ICE/diff classification and all coverage
semantics are untouched. It changes what is **retained** (parents) and what is
**written as evidence**, with counters that say so.

## Parent pool cap: `--parent-cap N`

Default: `PARENT_CAP_DEFAULT = 20000`. `0` retains no parents (workers still
mutate seeds); negative values clamp to 0. The cap is campaign-wide and counts
content hashes, so the same input observed twice is one parent.

### Replacement policy

`feedback_upsert` keeps the existing admission rules: a new content hash is
added, an existing hash unions its function set and bumps energy (ceiling 64).
What is new is what happens when `entries.length() == cap`:

- the victim is the parent with the **lowest energy**;
- equal energies are broken by the **oldest admission sequence** (`Parent.seq`),
  so the victim does not depend on array slot history;
- the newcomer is always admitted in the victim's slot, so a saturated pool
  keeps turning over instead of freezing;
- `index` is updated in the same operation: `index.remove(victim.hash)` before
  `index.set(new_hash, victim_slot)`. There is no dangling index; every retained
  entry's hash maps to its own slot and `index.length() == entries.length()`
  (asserted by tests).
- the eviction scan is O(cap) and only runs when the pool is full. Combined with
  the cap this bounds parent-selection cost at O(20000) per iteration instead of
  O(campaign length).

Eviction never depends on an RNG: given the same admission sequence and the same
energy-decay sequence it produces the same survivors. Energy decay is driven by
the existing splitmix RNG (`--seed` + worker id), so a replay with the same
`--seed` and the same input stream reproduces the survivor set exactly (tested).

### Evicted content cannot silently return

The driver never reads its own `<out>/corpus` back into `Feedback`; persisted
sources are replay evidence (`--seed-dir <run>/corpus` is an explicit, fresh
campaign), not a resumed parent pool. Within a campaign, evicted hashes are also
kept in `tombstones` with a bounded FIFO ring of `cap` entries, and
`feedback_upsert` refuses a re-offered hash while it is remembered. The ring
keeps memory O(cap); the guarantee covers the most recent `cap` evictions, which
is the window in which the driver re-observes a just-evicted content. This makes
the on-disk-corpus question moot: there is no silent scan path at all.

### Counters

`summary.json` (and the run in general) reports:

| field | meaning |
|---|---|
| `parent_cap` | effective cap (after clamping) |
| `parents_seen` | distinct inputs admitted at least once, seeds included; invariant `parents_seen == parents_retained + parents_evicted` |
| `parents_retained` | current `Feedback.entries.length()` (equals the historical `corpus` field) |
| `parents_evicted` | number of replacement events |

Seeds are admissions: the startup seed load goes through `feedback_upsert`, so a
cap smaller than the seed corpus evicts during startup (deterministically, the
oldest equal-energy seeds first). `corpus` keeps its old meaning — the number of
retained parents — and now equals `parents_retained`.

## Persisted evidence cap: `--persist-cap N`

Default: `PERSIST_CAP_DEFAULT = 2000` distinct inputs. `0` writes no
non-candidate evidence; negative values clamp to 0.

The budget unit is one **input content hash**, because every evidence file is
keyed by that hash:

- `corpus/<sha1>.mbt` — the source itself;
- `corpus/behavior/<sha1>/<reason>.json` — at most two reasons
  (`behavior`, `behavior_t2`), rewritten in place;
- `corpus/coverage/<stage>/<outcome>/<input>_<config>.json` — at most
  3 stages × 4 outcomes = 12 paths per input, rewritten on replay.

Bounding inputs therefore bounds the whole evidence tree. `persist_admit`
checks the budget before writing a new input:

- already-persisted input → rewrite the same path, no budget charge;
- non-candidate request at the cap → no write, `persist_skipped += 1`,
  `persist_saturated = true`;
- candidate (crash/ICE/fmt finding/diff witness) → **forced**, never dropped,
  `persist_candidates += 1` (a subset of `persist_written`).

`persist_written` counts every input written (budgeted + forced).
`persist_skipped` counts refused non-candidate *requests*, not distinct inputs,
so it can exceed the number of distinct skipped sources when a skipped input is
traced again.

After saturation the campaign keeps executing and keeps counting: T1/T2/T3,
`coverage_adds`, `new_edges`, `coverage_records` (in-memory evidence) and every
follow-up counter keep moving. Only new on-disk evidence stops.

### Worst-case file bound with the defaults

Per persisted input: 1 source + ≤2 behaviour records + ≤12 coverage sidecars =
15 files. So

```
corpus files <= 15 * persist_written
total files  <= 15 * persist_written
                + 1 manifest + 1 summary + 1 trace_failures.jsonl
                + (duration_s / 2 + 1) stats.jsonl lines
                + findings (signature-deduplicated; see audit)
```

With `--persist-cap 2000` that is ≤30,000 corpus files plus findings, instead of
the extrapolated ~10M.

## Unbounded-file audit (every per-input/per-event writer)

| # | writer | path | multiplicity | status |
|---|---|---|---|---|
| 1 | `persist_admit` | `corpus/<sha1>.mbt` | 1 per input | **capped** by `--persist-cap`; candidates forced |
| 2 | `persist_behavior` | `corpus/behavior/<sha1>/<reason>.json` | ≤2 per persisted input | bounded by the persist cap (path is per input, rewritten) |
| 3 | `persist_coverage` | `corpus/coverage/<stage>/<outcome>/<input>_<cfg>.json` | ≤12 per persisted input | bounded by the persist cap (per `(input,config,stage,outcome)`) |
| 4 | `@corpus.save_finding` for T1/T2/fmt/diff | `findings/<stage>/<kind>/<sig>/{in.mbt,meta.json}` | 1 dir per distinct signature | signature-deduplicated: T1/T2 sig = `stage|kind|detail|rc` (low-cardinality compiler defect), diff sig = verdict/stages/kinds/outputs. **fmt signatures include the input hash**, so with `--fmt-check` they are per input — see "still unbounded" |
| 5 | REPARSE extra | `findings/fmt/REPARSE/<sig>/formatted.mbt` | 1 per fmt REPARSE finding | same as #4 (fmt only) |
| 6 | `trace_apply` failure log | `trace_failures.jsonl` | 1 line per failed trace | **capped at `TRACE_FAILURE_LOG_MAX = 2048` lines**; `trace_failures_logged` / `trace_failures_skipped` report it, `trace_failed` still counts every failure |
| 7 | worker T3 snapshot | `trace_cores/<sha1>.core` | 1 per T3 attempt | **ephemeral**: deleted when the trace settles (`trace_apply`), when queued work is dropped, and when `trace_submit` refuses the task. Live cores ≤ trace queue + in-flight, independent of duration |
| 8 | monitor | `stats.jsonl` | 1 line per 2 s | bounded by `duration_s / 2` (+1), not by input count |
| 9 | plan/summary | `manifest.json`, `summary.json` | exactly 1 each | constant |
| 10 | worker scratch | `/tmp/mbtfuzz_mb/<tag>/w<id>/in.mbt`, `out_wasm.core`, fmt outputs | fixed names, overwritten every iteration, per worker | bounded by `--workers` |

Note on #7: the `.core` snapshots used to be retained after the trace. They are
inputs to the link step of a T3 trace, not evidence, so deleting them after use
removes a large unbounded artifact without changing any trace scheduling share
or result. A finished run now has an empty `trace_cores/` directory.

## What is still unbounded

- **`findings/fmt/**` with `--fmt-check`.** T1/T2/diff findings are deduplicated
  by a low-cardinality signature, but the fmt signatures deliberately include
  the input hash (`fmt-hang|<src>`, `fmt-err|...|<src>`, `fmt-idem|<a>|<b>`,
  `fmt|detail|<src>`, REPARSE), so one directory per distinct input can be
  written. It is bounded only by campaign length. We did **not** cap it because
  findings are candidate evidence and the requirement is that candidates are
  never dropped; `--fmt-check` is off by default. If fmt evidence must be
  bounded in a future multi-hour campaign, the signature must stop including the
  input hash (losing per-input reproduction) or candidate evidence needs an
  explicitly agreed sampling policy.
- **In-memory per-campaign maps** are not files and are unchanged:
  `TraceUniverse.evidence` (one `FuncSet` per completed trace key),
  `TraceUniverse.rewarded`, `TraceQueue.seen`, and the per-worker
  `unique_inputs` / `unique_t2_inputs` / `unique_t2_ok_inputs` /
  `sigs` / `diag_families` maps whose lengths are the existing summary
  counters. Bounding them would change the meaning of existing `summary.json`
  fields, which this patch must not do. They are O(campaign) in memory (tens of
  bytes per entry); the file and parent-selection explosions are gone.
- **Recall of retained evidence is bounded by design**: after the persist cap,
  sources for later inputs are not written, so `--seed-dir <out>/corpus` replays
  only the persisted subset (≤ `persist_written`), and after the parent cap the
  pool holds only the energy-ranked survivors. This is the intended trade: the
  campaign now says "I retained at most N inputs", not "I retained everything".

## What is explicitly *not* changed

- Function coverage semantics, the historical 7,916 / 26,611 = 29.75% number,
  `coverage_adds`, `relative_new`, `by_key`, `observed_funcs`, `baseline_*`.
- Edge bonus weights (`32 / 6 / 8 / 64`), `EDGE_CAP_DEFAULT = 200000`, edge
  saturation behaviour, trace scheduling shares and the bounded trace queue.
- Existing `summary.json` field names and meanings. The new fields are additive.
- Crash/ICE/diff detection, classification and findings layout.

## Tests

`moon test --target native`: 237 total, 237 passed (232 existing + 5 new).
New tests:

- `parent pool cap evicts and keeps the index consistent` — 108 admissions at
  cap 8: retained 8, seen 108, evicted 100, `by_key`/index consistent, oldest
  equal-energy admissions evicted, re-offered remembered evictee refused.
- `parent pool cap evicts the lowest-energy parent` — energy 32/6/1/1 at cap 3:
  the 1-energy parent is evicted, not the newest.
- `parent pool survivors are deterministic for a seed and input stream` —
  200 admissions + RNG-driven energy decay at cap 32, two runs with seed 99
  produce identical sorted survivor arrays.
- `evidence cap skips non-candidates but never candidates` — cap 2; third
  non-candidate is skipped and counted, `persist_saturated` set; a `save_crash`
  ICE witness is still written, counted as `persist_candidates`, and the
  skipped source has no file; re-persisting an admitted input neither skips nor
  double-counts.
- `coverage sidecars stop at the budget but evidence keeps counting` — cap 1;
  first trace writes its sidecar, second is skipped, and both remain in
  `coverage_records`.

## Measured before/after (tiny smoke, serial 1 worker)

All runs: one `moon` process at a time, one campaign worker, one (idle) trace
worker, 5 seconds, seed 7, tracing disabled. Files counted with
`find <out> -type f | wc -l`.

**Before** (`HEAD`/`main` driver, no caps):

```bash
moon run cmd/fuzz -- --root /data/audit/mbtfuzz \
  --out /tmp/mbtfuzz_caps_before --run-id smoke_before \
  --workers 1 --duration 5 --trace-t1 0 --trace-t2 0 --trace-t3 0 \
  --trace-workers 1 --seed 7
```

```json
{"it":282,"corpus":1539,"persisted":201}
```

`it=282`, 405 files, 2.0 MB.

**After, defaults** (`--parent-cap 20000`, `--persist-cap 2000`):

```bash
moon run cmd/fuzz -- --root /data/audit/mbtfuzz \
  --out /tmp/mbtfuzz_caps_smoke --run-id smoke_default \
  --workers 1 --duration 5 --trace-t1 0 --trace-t2 0 --trace-t3 0 \
  --trace-workers 1 --seed 7
```

```json
{"it":248,"corpus":1520,"persisted":182,
 "parent_cap":20000,"parents_seen":1520,"parents_retained":1520,
 "parents_evicted":0,"persist_cap":2000,"persist_written":182,
 "persist_skipped":0,"persist_candidates":0,"persist_saturated":false}
```

367 files, 1.9 MB (a second identical run: `it=264`, 385 files, 2.0 MB; the
`it` difference is the 5-second wall clock and process scheduling, not the
caps). At this scale the caps are not reached, so behavior is the same as
before: every novel behaviour is admitted and persisted.

**After, deliberately tiny caps** (`--parent-cap 8 --persist-cap 5`):

```bash
moon run cmd/fuzz -- --root /data/audit/mbtfuzz \
  --out /tmp/mbtfuzz_caps_smoke --run-id smoke_tiny \
  --workers 1 --duration 5 --trace-t1 0 --trace-t2 0 --trace-t3 0 \
  --trace-workers 1 --parent-cap 8 --persist-cap 5 --seed 7
```

```json
{"it":339,"corpus":8,"persisted":5,
 "parent_cap":8,"parents_seen":1550,"parents_retained":8,
 "parents_evicted":1542,"persist_cap":5,"persist_written":5,
 "persist_skipped":207,"persist_candidates":0,"persist_saturated":true}
```

13 files, 60 KB (5 sources + 5 behaviour records + `manifest.json`,
`summary.json`, `stats.jsonl`). 1338 seeds were loaded, so startup alone evicted
1330 of them; `1550 = 8 + 1542` holds, and the execution count is 339 — the caps
retained fewer inputs, they did not execute fewer.

Both commands exited 0.

### Traced path (extra validation)

A third 5 s run exercised coverage sidecars, the failure-log counter and T3 core
cleanup with `--trace-t1 20 --trace-t2 50 --trace-t3 100 --p-deep 100
--baseline-seeds 1 --parent-cap 50 --persist-cap 3`:

```json
{"trace_completed":3,"trace_dropped":36,"coverage_records":3,
 "parent_cap":50,"parents_seen":1483,"parents_retained":50,
 "parents_evicted":1433,"persist_cap":3,"persist_written":3,
 "persist_skipped":149,"persist_saturated":true}
```

11 files, 84 KB, `trace_cores/` left empty (all snapshots deleted), exit 0. The
baseline traces and the candidate trace all ran; only some evidence was
retained. Coverage sidecar writes for already-persisted inputs still happen
after saturation; writes for new inputs are skipped and counted.

## Validation

Serial, from `moonbit/` on `agent/caps`:

```
moon test --target native   # 237 total, 237 passed
moon check                  # 0 warnings
moon fmt                    # applied
moon fmt --check            # clean
```
