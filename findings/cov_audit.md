# Coverage measurement audit (codex review 4, action 1)

Motivation: every headline number depends on three unverified assumptions:
PC→function symbolization, replay outcome handling, and which corpus/entry
sets a union contains.  This audit checks them with the same binaries and
artifacts, and freezes an explicit provenance table.

Harness: `harness/cov_audit.py` (symbolization + reproducibility),
`harness/replay_outcomes.py` (return codes / stderr), raw results
`out/cov_audit.json`, `out/{check,build,test}_outcomes.json`.

## A. Symbolization: sound for the `camlMoonc*` denominator

`symbolize.py` maps a PC to the nearest preceding text symbol.  Compared
against an ELF-size-bounded mapping (`nm -S`, PC must lie in
`[addr, addr+size)`):

| check | result |
|---|---|
| text symbols (`nm -S`, T/t/W/w) | 30,465 |
| zero-size text symbols | **0** |
| duplicate-address aliases | 1 |
| overlapping intervals | 1 |
| PCs traced (12 stratified check commands) | 51,248,255 |
| PCs mapping to no function interval but to a naive symbol | **1,533 (0.003 %)** |
| naive-only symbols, unique | 7 — all CRT/startup (`_init`, `_fini`, `frame_dummy`, `register_tm_clones`, `deregister_tm_clones`, `__do_global_dtors_aux`, `caml_startup__code_begin`) |
| naive-only symbols starting with `camlMoonc` | **0** |
| bounded-only symbols | 1 (`caml_program`) |
| per-command function sets, 2 rounds | **identical** |

So for the compiler-function denominator the nearest-preceding mapping and the
size-bounded mapping agree; the only over-attribution is to CRT symbols that
are filtered out anyway.  `nm` symbol types/aliases do not inflate the count.
Recommendation: keep the naive mapper for continuity, add a size-check assert
in `symbolize.py`, and continue to report the denominator as
“`camlMoonc*` function symbols” (26,611), not “functions”.

## B. Replay outcomes: one real ordering artifact, no new defect

`replay.py` discards return codes and stderr.  Re-running each dry-run command
directly (`replay_outcomes.py`, no QEMU) gives:

| log | commands | rc=0 | rc=199 (ICE) | timeout |
|---|---:|---:|---:|---:|
| `moon check` | 299 | **299** | 0 | 0 |
| `moon build` | 130 | **130** | 0 | 0 |
| `moon test --build-only` | 728 | 712 | **16** | 0 |

All 16 `rc=199` are `link-core` commands whose `_build/wasm-gc/debug/test/*.core`
inputs did not exist at the moment the parallel replay ran them; re-running the
same command after the build outputs exist returns 0.  This is a **harness
ordering artifact**, not a compiler defect, but it means the test-entry union
was built over 16 partially-executed commands.  Because a failed command
contributes only the functions reached before the failure, the union is
conservative (not inflated).  Fix: serialize/order commands that depend on
produced artifacts, or replay only `rc==0` commands for outcome claims;
`replay.py` now records `rc`/`stderr`/`timeout` per command.

Separate observation: a **missing input file** (nonexistent path) produces the
ICE banner and `rc=199` with `Error: Sys_error(...)` for `check`,
`build-package`, and `link-core` — in both the current and the 2025-03
compiler.  It is a longstanding diagnostic-quality issue, not a regression, so
it is not added to the defect table; report it only as an observation if a
paper needs an “ICE on user error” example.

## C. Union provenance: four numbers, four different sets

The apparent “moving denominator” is fully explained by set composition:

| union | size | % of 26,611 | definition |
|---|---:|---:|---|
| four entrances | 7,097 | 26.67 % | `check ∪ build ∪ testbuild ∪ link` |
| + release variants | 7,412 | 27.85 % | + `build_rel ∪ testbuild_rel` |
| + targets/flags | **7,591** | **28.53 %** | + `native ∪ llvm ∪ cov_flag` (README headline) |
| + `link_rel` | **7,660** | **28.79 %** | all 11 replay artifacts (replay-union headline) |
| + real & mix corpora | **7,847** | **29.49 %** | 7,591 ∪ `funcs_real` ∪ `funcs_mix` |
| + `link_rel` + corpora | **7,916** | **29.75 %** | 7,660 ∪ `funcs_real` ∪ `funcs_mix` (typegen baseline) |

Difference 7,660−7,591 = **69** functions, exactly what `link_rel` adds.
Unobserved counts are 18,764 for 7,847 and 18,951 for 7,660; 7,916 leaves
18,695.  There is no contradiction, only missing manifests.  Freeze one
headline (recommended: **7,916 / 26,611 = 29.75 %**, maximal documented union,
with the exact file list above) and publish the others as ablations.

## D. Claim wording that survives review

> “For moonc `v0.10.20+65efd5b93` (SHA256 …), replaying the `moon`-generated
> command sets listed in Table X observed 7,916 of 26,611 `camlMoonc*`
> function symbols (29.75 %).  This is symbol-level coverage of that binary
> under those commands; it is not source-line, branch, or feasible-code
> coverage.”

Per-subsystem numbers must carry the attribution confidence: current
name-based attribution covers only ~17 % of symbols reliably, so report the
unmatched 47.5 % explicitly rather than pretending keyword buckets are
architectural truth.

## E. Still open from the audit list

* 50 stratified commands × 3 rounds (this run: 12 × 2) — cheap to extend.
* `-d exec` vs `-d exec,nochain` TB-count comparison (chaining affects TB
  counts, not function sets).
* Coverage impact of the 16 partially-executed link commands (expected small;
  quantify by replaying the successful subset).
* Static-reachability denominator is deliberately **not** attempted: codex
  rejected it as a headline, and the audit shows the naive symbol population
  is already well-defined.
