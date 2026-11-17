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
7 hand samples + 50 random, seed 1: 57/57 ok
7 hand samples + 50 random, seed 2: 57/57 ok
7 hand samples + 50 random, seed 3: 57/57 ok
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

- Four-cell is wasm-gc only.
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
