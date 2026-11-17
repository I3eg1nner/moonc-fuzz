# Wiring exact QEMU-TB coverage into fuzz evidence

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`,
`moonc v0.10.20+65efd5b93`. Code: `moonbit/trace/collect.mbt`,
`moonbit/trace/trace.mbt`, `moonbit/cmd/fuzz/main.mbt`.

This note covers the additive plumbing step between the exact counters defined
in `findings/exact_block_coverage.md` and the fuzz campaign's persisted
evidence. It deliberately does **not** change scheduling, reward, baseline
logic, or the historical function-coverage headline
(7,916 / 26,611 = 29.75%).

## What is now plumbed

Before this change `collect` called `summarize_trace(...).funcs` and dropped
`unique_pc`, `mapped_unique_pc`, `edges`, and `mapped_edges` on the floor. Now:

- `TraceResult` carries the four counters as `Int32` fields:
  `unique_pc`, `mapped_unique_pc`, `edges`, `mapped_edges`.
- `collect` derives the historic `camlMoonc*` function list and all four
  counters from **one** `summarize_trace` call. The bridge is the private
  `coverage_fields(trace, sym)` helper, which returns
  `(functions, unique_pc, mapped_unique_pc, edges, mapped_edges)`; there is no
  second scan of the trace text.
- `trace.mbt` exposes `pub fn edge_keys(trace, sym) -> Array[String]`, the
  exact, deduplicated, sorted set of `"<pc0>,<pc1>"` keys for transitions whose
  **both** endpoints map to a symbol. It shares the single-scan implementation
  (`scan_trace`) with `summarize_trace`, so the two can never disagree:
  `edge_keys(t, s).length() == summarize_trace(t, s).mapped_edges`.
- The keys are decimal, not hex, and the comma cannot appear in a decimal PC,
  so the encoding is injective. Ordering is the same shortlex `String` sort used
  for function names, hence deterministic.

### Scope: edge keys are all-mapped, not `camlMoonc*`-only

`TraceResult.functions` keeps the historical prefix filter (`camlMoonc*`).
`mapped_edges` and `edge_keys` use the wider rule "both endpoints map to any
symbol". A transition inside `main`, a stdlib helper, or a non-moonc support
function is therefore present in the edge key set while its endpoint names are
absent from `functions`. The two counts are not comparable:
`edge_keys(...).length()` must be compared against `mapped_edges`, never
against `functions.length()`. This is stated in the doc comment on `edge_keys`
and in the persisted `func_scope` / `edge_scope` fields.

`collect` does **not** retain `edge_keys` per trace. Keeping an exact key set
for every `TraceResult` (including buffered baseline results in
`TraceUniverse.pending`) would multiply memory by roughly the number of
distinct transitions per input; the helper is available for offline union and
for a later scheduling change, not for per-input retention yet.

## What is persisted

`cmd/fuzz` extends each coverage sidecar
(`<out>/corpus/coverage/<stage>/<outcome>/<input>_<config>.json`) with:

```json
{
  "coverage_funcs": ["camlMoonc__A", "camlMoonc__B"],
  "coverage_funcs_count": 2,
  "trace_func_count": 1,
  "unique_pc": 4,
  "mapped_unique_pc": 3,
  "edges": 5,
  "mapped_edges": 4,
  "tb_counter_scope": "latest_trace",
  "func_scope": "camlMoonc*",
  "edge_scope": "mapped_both_endpoints"
}
```

The new fields are appended after `coverage_funcs`, so existing consumers that
ignore unknown fields keep working.

Two scopes coexist in one record and must not be conflated:

- `coverage_funcs` is the accumulated **union** of `camlMoonc*` function names
  for that `(input_hash, config_hash, stage, outcome)` key;
- the four TB counters and `trace_func_count` describe only the **latest trace**
  that produced the record (`tb_counter_scope = "latest_trace"`).

No new run-level counter was added. `TraceUniverse` still unions only
`@cov.FuncSet` (function names), so a field such as "new edges this run" would
have no real union behind it; emitting it would be a fake scheduler signal.
Consequently the final `summary.json` is unchanged except that its existing
function-coverage numbers now sit next to evidence that also carries exact TB
counts.

## What is deliberately NOT used for scheduling yet

- `trace_apply_delta`, `feedback_upsert`, `Parent.energy`, baseline U0, and
  `relative_new` still consume function names only.
- `TraceResult.edges` / `mapped_edges` / `unique_pc` / `mapped_unique_pc` are
  diagnostic evidence. They are not read by any reward or selection path.
- No block or edge union exists in `TraceUniverse`; no per-edge novelty is
  computed; no input is selected because it added an edge.
- The 29.75% headline remains a function-coverage number over
  `camlMoonc*` names and is unaffected.

## Memory and size caveats

An edge set is much larger than a function set. In the accept fixture
(`accept_fixtures/trace.log`) 5 parsed TB entries produce 4 distinct transitions
but only 2 function names. Real `moonc` traces are larger and closer to
one distinct edge per two or three TB entries, so a campaign-wide edge union
would be tens to hundreds of times larger than the current function union, and
each key is a heap `String` of roughly 20-24 bytes plus map overhead.

Practical consequences:

- `unique_pc` / `mapped_unique_pc` are cheap counters (they already require the
  PC set during the scan) but the PC set itself is discarded after the scan.
- `edge_keys` allocates the whole key array; it is intended for offline
  analysis of one trace (bounded by `--trace-max-mb`), not for every campaign
  input.
- Persisting the key array per sidecar would inflate evidence storage by orders
  of magnitude compared with `coverage_funcs`; only the counters are persisted.
- A future edge union should be capped (for example by stage/config and by a
  maximum retained key count) or stored on disk keyed by hash, with the exact
  keys available for replay, before it is allowed to drive rewards.

## Remaining gap to true per-edge feedback

1. **No union and no novelty.** The campaign cannot answer "did this input add
   an edge that no earlier input added". `edge_keys` is a building block, but
   `TraceUniverse` has no block/edge set, no union, no delta, and no baseline
   edge total. This is the main TODO for the next pass.
2. **No reward or energy signal.** Even with a union, using it would change
   scheduling and reward; that was explicitly out of scope here.
3. **TB transitions are not source CFG edges.** A QEMU TB boundary is a
   translation artifact, not a source-level branch. Counts must not be reported
   as branch or basic-block coverage.
4. **Keys are binary-specific.** PC values are meaningful only for one
   `moonc` binary and one `nm -n` symbol table. A toolchain change invalidates
   cross-run unions; the keys themselves stay exact, but comparability does not.
5. **Block identity is implied by `unique_pc`, not persisted as a set.** There
   is no per-input block key set, so "new blocks" cannot be computed later from
   the sidecar alone; only the count survives. Adding a block key set has the
   same size concern as edges.

## Validation performed

Serial, on a quiet host:

- `moon test --target native`: 200 tests, 200 passed (195 before + 5 new).
- `moon check`: 0 warnings.
- `moon fmt --check`: clean.
- `moon run cmd/trace2funcs -- accept_fixtures/nm.txt accept_fixtures/trace.log`
  still byte-identical to `accept_fixtures/expected_trace.json`.
- `moon run cmd/accept -- /tmp/mbtfuzz_covwire_agent`: `ok=true`, 9/9 checks,
  including `trace_real_f4` under real QEMU (`qemu_rc=199 expected=599
  actual=599`).

## Follow-up: the scheduling gap is closed

`findings/edge_feedback.md` (2026-11-17) implements the item above: a capped
campaign edge-key universe, a real `new_edges` set-difference counter, an
additive edge-novelty bonus (8, below the unchanged function bonus of 32), and
`edge_keys` / `edge_cap` / `edge_saturated` / `new_edges` in `summary.json`.
This note remains accurate about the state before that change, including the
all-mapped vs `camlMoonc*` scope mismatch and the 29.75% headline.
