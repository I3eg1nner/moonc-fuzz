# Exact QEMU-TB block and edge coverage

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`,
`moonc v0.10.20+65efd5b93`. Source: `moonbit/trace/trace.mbt`.

This note defines the exact block/edge counters now emitted by
`summarize_trace` and `cmd/trace2funcs`. They are **QEMU translation-block
(TB) coverage**, not source-level line coverage, source-level basic-block
coverage, or source branch coverage.

## Definitions

Input is one QEMU `-d exec` log plus an `nm -n` symbol table. `parse_trace_pc`
extracts one guest PC per `Trace ... [host/PC/tb]` line. Let the parsed PC
sequence be

```
p0, p1, ..., p(n-1)
```

in log order. Malformed lines are ignored; they do not create entries and do
not break the adjacency of the surrounding parsed entries.

| Field | Exact definition |
|---|---|
| `total_tb` | Number of parsed TB entries, including entries whose PC does not map to a symbol. Unchanged. |
| `mapped_tb` | Number of parsed entries whose PC maps to a symbol. Unchanged. |
| `unique_pc` | `|{ p_i }|`: number of distinct raw guest PCs. |
| `mapped_unique_pc` | `|{ p_i : func_of(p_i) is Some }|`: number of distinct PCs that map. |
| `edges` | `|{ (p_i, p_(i+1)) : 0 <= i < n-1 }|`: distinct consecutive TB transitions. The first parsed entry contributes no edge. |
| `mapped_edges` | `|{ (p_i, p_(i+1)) : both endpoints map }|`. |
| `func_depth[f].blocks` | `|{ p_i : func_of(p_i) = f }|`: distinct mapped PCs attributed to function `f`. |
| `func_depth[f].edges` | `|{ (p_i, p_(i+1)) : func_of(p_i) = func_of(p_(i+1)) = f }|`: distinct TB transitions wholly inside `f`. |

`func_depth` is sorted by function name with the same sort as `funcs`, so the
output is deterministic. Cross-function transitions count in global `edges` and
`mapped_edges` but never in any per-function `edges`.

## How it is computed

The implementation uses exact keys, not a probabilistic bitmap:

- distinct PCs are stored in a set keyed by the full `UInt64` PC;
- distinct transitions are stored in a set whose key is the injective decimal
  string `"<pc0>,<pc1>"` (decimal PC text contains no comma);
- distinct intra-function transitions are counted only when the transition is
  new in the mapped-edge set **and** both endpoint functions are equal. The
  symbol table fixes each PC's function, so a pair's intra/cross status cannot
  change between occurrences.

No PC or pair is hashed down to a smaller lossy integer, so two different PCs or
transitions cannot collide in these sets. (The underlying `Map` may use hashing
for lookup, but it compares exact keys and resolves collisions.)

Usage:

```bash
cd moonbit
moon run cmd/trace2funcs -- nm.txt exec.log out.json
```

`cmd/trace2funcs` appends the new fields after the existing ones:

```json
{
  "tool": "qemu-exec-trace+nm-moonbit",
  "text_lo": 16,
  "text_hi": 48,
  "symbols": 3,
  "total_tb": 5,
  "mapped_tb": 4,
  "func_count": 2,
  "funcs": ["a", "b"],
  "unique_pc": 4,
  "mapped_unique_pc": 3,
  "edges": 4,
  "mapped_edges": 3,
  "func_depth": [
    {"func": "a", "blocks": 2, "edges": 1},
    {"func": "b", "blocks": 1, "edges": 1}
  ]
}
```

## Short example

Given `nm.txt`:

```
0000000000000010 T a
0000000000000020 T b
```

and parsed PC sequence `0x10, 0x18, 0x20, 0x20, 0x99` (the `accept_fixtures`
trace):

```
pairs: (10,18) (18,20) (20,20) (20,99)
maps:  10->a  18->a  20->b  20->b  99->none
```

- `total_tb = 5`, `mapped_tb = 4`
- `unique_pc = 4` (`10,18,20,99`), `mapped_unique_pc = 3` (`10,18,20`)
- `edges = 4` (four distinct pairs)
- `mapped_edges = 3` (`(20,99)` has one unmapped endpoint)
- function `a`: `blocks = 2` (`10,18`), intra edges `= 1` (`10->18`)
- function `b`: `blocks = 1` (`20`), intra edges `= 1` (`20->20`)

The `(20,20)` self-transition is a real consecutive TB pair; it is retained.

## What these numbers prove

Within the limits of the input trace, they prove exactly which guest TB start
PCs executed and which consecutive TB transitions were observed at least once.
They are precise, reproducible, and comparable across runs of the same compiler
binary and symbol table:

- `unique_pc - mapped_unique_pc` is the number of distinct unmapped PCs;
- `func_depth[f].blocks` is a lower bound on distinct executed TB entries in
  `f`, and a lower bound on source constructs folded into those TBs;
- `func_depth[f].edges` records observed intra-function TB transitions, which
  is strictly more structural information than "function `f` ran";
- set differences on PCs/edges between two runs are exact: a PC or pair present
  in one run and absent in the other was not observed in the first/second trace,
  with no bitmap-collision ambiguity.

## What these numbers do not prove

- **Not source line coverage.** There is no source file/line/column mapping in
  this pipeline. A PC is attributed to the nearest preceding `nm` text symbol.
- **Not source basic-block coverage.** QEMU forms TBs for its own translation
  purposes; one TB may contain several source statements and several source
  branches, and one source basic block may be split across TBs.
- **Not source branch coverage.** `edges` counts TB transitions, not taken/not
  taken outcomes of source-level conditional branches. There is deliberately no
  "branches covered / total branches" denominator.
- **No completeness denominator.** Only executed TBs appear. Untaken paths are
  invisible; `edges` is a count of observed distinct transitions, not a ratio.
- **No proof of correctness or absence of bugs.** Coverage says which code paths
  were exercised, not that they behaved correctly.
- **Not comparable across different QEMU/TCG versions or trace options.** TB
  formation, chaining, and instruction decoding can change the PC sequence even
  for the same guest program.
- **Function attribution is approximate.** `SymTab` uses the nearest preceding
  `T/t/W/w` symbol; local labels, aliases, and symbol-table gaps can fold code
  into the wrong function. PCs outside `[text_lo, text_hi]` or before the first
  symbol are unmapped.
- **Interpreter/dynamic-loader PCs may be present.** Unmapped PCs are counted in
  `total_tb`/`unique_pc`/`edges`, which is intentional, but they are not
  compiler functions.
- **Trace collection limits apply.** A truncated or failed `-d exec` log yields
  a partial sequence; `trace/collect.mbt` already rejects empty/oversized/failed
  collections. This module summarizes whatever lines it is given.

## QEMU/TB caveats

- `-d exec` logs TB executions, not basic blocks in the source language.
  TB boundaries depend on the guest ISA, TCG version, and translation options.
- A TB may be entered at its start PC; this pipeline keys blocks by that start
  PC. It does not see fall-through inside a TB, so an intra-TB conditional is
  not represented as a source edge.
- Repeated execution of the same TB is deduplicated for `unique_pc` and
  `edges`; `total_tb` preserves raw execution count.
- The first parsed TB has no predecessor in the log, even if the program was
  entered from a caller not present in the same log. Its incoming edge is
  therefore not counted.
- TB chaining may affect whether the next TB is logged as a separate `exec`
  event in other QEMU configurations. Use the same QEMU invocation when
  comparing runs.
