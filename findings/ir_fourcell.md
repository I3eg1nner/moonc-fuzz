# Restricted IR four-cell calibration and real-package controls

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`.
This note records calibration and control evidence only; it is not a compiler
correctness claim.

## IR four-cell

`cmd/irprobe --four-cell` emits one IR program, builds it with and without
`-O0`, crosses link O0/default, and compares every arm against the interpreter
event stream. The current subset is Int/Bool/Unit/Array[Int], with bounded
loops, arrays, aliasing, `if`, first-order calls, `choose`, and branch-state
merges. Division, floats, strings, closures, generics, traits and traps are
excluded.

Observed:

```
8 hand samples + 50 random, seed 1: 58/58 ok
8 hand samples + 50 random, seed 2: 58/58 ok
8 hand samples + 50 random, seed 3: 58/58 ok
(historical before adding the eighth sample: 7 hand + 50 random = 57/57)
errors=0, exit=0
```

Negative-result scope: this only covers the current generator shape and
samples. It does not establish general IR or compiler correctness.

## Real package four-cell

Commands used `seeds/` as the complete module source and copied it to an
independent output tree.

```
3 packages (argparse,json,bigint) --four-cell --repeats 2 --aa
9 artifacts, 0 candidates, 0 errors, exit 0

6 packages (argparse,json,string,sorted_set,hashmap,bigint) --four-cell --repeats 1
17 artifacts, 0 candidates, 0 errors, exit 0
```

## Real-package positive control

```
--four-cell-control argparse/help_render.mbt 'Usage: ' 'Use: '
1 artifact, changed=156, candidates=1, errors=0, exit=1
inner row: link_changed=78, build_changed=0, both_changed=78
```

This proves the real-package detection chain reacts to an injected
link-default behavior change. It is not an optimizer defect: the mutant core is
substituted only by the harness.

## Boundaries

- Four-cell supports wasm-gc and wasm; native/LLVM is not covered.
- `default` means omitting `-O0`, not explicit `-O2`.
- The IR generator uses one main shape plus `add`/`choose`; no nested functions.
- The reducer only deletes top-level `main` statements; `ok` does not imply a
  smaller program.
- No new `moonc` defect was found in these runs.

## Empty test artifacts

Some packages (`moonbitlang/core/int`, `double`, `bytes`, `array`, `option`,
`result`) emit an internal/white-box link artifact with valid metadata but zero
tests. `optdiff` now skips such an artifact only when metadata explicitly
contains zero known test IDs; an unknown or non-empty metadata mismatch remains
an error. The six-package batch then produced one artifact per package:

```
6 packages, 6 artifacts, 0 candidates, 0 errors, exit 0
```

## Third real-package batch

```
queue,list,char,hashset,set,priority_queue,bool,tuple
--four-cell --repeats 1
8 packages, 16 artifacts, 0 candidates, 0 errors, exit 0
```

The argparse link-injection control was rerun on the same HEAD:

```
1 artifact, changed=156, candidates=1, errors=0, exit 1
```

## wasm target four-cell

The same three-package batch was repeated with `--target wasm` (not only
wasm-gc), using the same build/link O0-default cross:

```
argparse,json,bigint --target wasm --four-cell --repeats 2 --aa
9 artifacts, 0 candidates, 0 errors, exit 0
```

Control on the same target:

```
argparse --target wasm --four-cell-control ...
1 artifact, changed=156, candidates=1, errors=0, exit 1
```

Scope: this shows the target path is wired and the injected link-default
change is still detected. It is not a separate optimizer-correctness result.

## IR wasm target

The IR four-cell was also run with `--target wasm`:

```
8 hand + 50 random, seed 1: 58/58 ok
errors=0, exit=0
```

Injection control on wasm:

```
--target wasm --inject-arm B0Ld
7/7 cases show only B0Ld_reason=mismatch; exit=1
```

This is target-wiring and detection-chain evidence, not a new optimizer
correctness result.

## Second mechanism control (json)

To avoid relying on one argparse snapshot path, the link-default control was
repeated on `moonbitlang/core/json`:

```
--four-cell-control json/json.mbt 'buf <+ "true"' 'buf <+ "TRUE"'
1 artifact
changed=12
link_changed=6
build_changed=0
both_changed=6
candidates=1, errors=0, exit=1
```

This is still a harness injection, but it exercises a different package and a
JSON serialization path rather than the argparse help renderer.

## 12k random shards

To check whether the first 1k result was seed-specific, 12 independent shards
were run with seeds 10000, 11000, ..., 21000:

```
shard s0..s11: 1,008 cases each (8 hand + 1,000 random)
total: 12,096 cases
all four arms reason=ok: 12,096/12,096
errors=0
per-shard wall time: 330-335 s (serial)
```

This is still the same generator shape: the 1,000-random-per-shard programs
have the same fixed `main` template and only 9 coarse structural combinations.
The result strengthens the negative evidence for this template; it does not
establish general IR or compiler correctness, and it is not 12,096 independent
program shapes.

## Dynamic-index template (v2)

The generator now adds a len-bound dynamic index and element write in the
loop body (`a[i]` after `i < Len(a)`). 12 shards, seeds 30000..41000:

```
12,096 cases
all four arms reason=ok: 12,096/12,096
errors=0
per-shard wall time: 338-345 s
dynamic `a[i]` present: 2,076 / 12,000 random cases (17.3%)
arrays: 8,429 / 12,000; Len: 8,324 / 12,000; alias: 4,230 / 12,000
```

Still no compiler difference. This adds one genuinely new array path, but the
overall template remains fixed; the result is negative evidence for this shape,
not general IR correctness.
