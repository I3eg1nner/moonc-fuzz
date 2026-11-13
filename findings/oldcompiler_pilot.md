# Old-compiler pilot (codex option 3) — gated, negative

Goal: use the open-source 2025-03-12 moonc as a *disagreement detector* for
the current closed-source front end, under codex's gates: 90 min build, 45 min
calibration with 50–100 shared-language controls, then targeted comparisons.
Success = one minimized discrepancy with independent evidence that the current
compiler is wrong, or one new reproducible current-version crash/ICE/scaling
defect.  Abandon if a gate fails, if ≥80 % of the first 20 minimized
differences are drift/environment/representation, or if the pilot ends without
a credible candidate.

Harness: `harness/olddiff.py` (`calib`, `diff`, `min`); raw output
`out/olddiff_calib.json`, `out/olddiff.jsonl`, `out/olddiff2.jsonl`,
`out/olddiff3.jsonl`.

## Toolchain build gate — PASS

Host: Ubuntu 22.04.5, 128 cores.  Nothing OCaml-related was installed.

```
apt-get install ocaml-nox ocaml-findlib          # 4.13.1 + findlib 1.9.1
# old compiler needs In_channel/Out_channel (OCaml 4.14):
curl -L https://github.com/ocaml/ocaml/archive/refs/tags/4.14.1.tar.gz
./configure --prefix=/opt/ocaml-4.14.1 && make -j32 world.opt && make install
# findlib 1.9.6 against 4.14.1
./configure -bindir /opt/ocaml-4.14.1/bin \
  -sitelib $(/opt/ocaml-4.14.1/bin/ocamlc -where) \
  -config /opt/ocaml-4.14.1/etc/findlib.conf -mandir /opt/ocaml-4.14.1/man
make all && make install
# dune >= 3.0: system apt has 2.9.1, so build 3.24.2 from source
PATH=/opt/ocaml-4.14.1/bin:$PATH make release -j32
# old compiler
cd /data/audit/moonbit-compiler
PATH=/opt/ocaml-4.14.1/bin:<dune>/_build/install/default/bin:$PATH \
  dune build -p moonbit-lang
```

Result: `_build/default/src/moon0_main.exe`, `-v` =
`v0.1.20250312+a7a1e9804`; clean build, no source repair, ~6 min wall total
(well inside the 90 min gate).  `dune build` exit 0, 0 errors.

## Calibration gate — PASS

Both compilers check a single dependency-free file in a temp dir:

```
old: moon0_main.exe check -no-mi -pkg cal/p c.mbt
new: ~/.moon/bin/moonc check -no-mi -pkg cal/p \
       -i ~/.moon/lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi c.mbt
```

68 controls (**47 accept / 21 reject**), all 68 match the expected accept/reject
outcome on **both** compilers (`out/olddiff_calib.json`).  The shared subset
covers literals, arithmetic/precedence, comparisons, `&&`/`||`, if/while/for,
`let`/`let mut`, recursion, string literals and `+`, int/bool/string matches,
or-patterns, guards, enum payloads, structs, tuples and nested tuple patterns,
field shadowing, labelled arguments and argument order, and 21 rejection controls (type mismatch, unbound names,
arity, missing/duplicate struct fields, non-exhaustive/extra match arms,
unknown labels, ill-typed calls, syntax errors).

### Drift found during calibration (excluded from the shared set; not defects)

| construct | old (2025-03) | new (2026-11) | classification |
|---|---|---|---|
| `-x`, `!a` | needs `moonbitlang/core/int` / `core/bool` imported; reject without prelude | accept with bundled prelude | environment/prelude drift |
| `fn id[T](...)` vs `fn[T] id(...)` | old accepts only the former | new accepts only the latter | syntax evolution |
| optional args `y? : Int = 1` | old parses `y?` as `Option` and rejects default | new requires the default form | semantics evolution |
| `priv fn` | old rejects (`priv fn` not a shared form) | new rejects (`E3005`) | not a shared feature; no removal claim |
| `abort("x")` | old rejects without core | new accepts with prelude | prelude drift |
| `Int?` / `Option` | old accepts `Int?` without core | new needs prelude import | prelude drift |

No matching old core `.mi` bundle **was found** for this compiler tag (the
`v0.1.20250312+a7a1e9804` GitHub release/tag is absent; only recent
`moonbit-wasm.tar.gz` assets exist), so the shared subset is deliberately
builtin-only.  The widened generator additionally exercises recursive enums,
`mut` struct fields, deep tuple patterns, labelled-argument order and field
shadowing; those constructs are not all in the 68-control calibration set.  Richer prelude-dependent programs cannot be compared without
drift dominating the signal.

## Differential runs — zero disagreements

| run | records | distinct sources | SAME_ACCEPT | SAME_REJECT | NEW_ACCEPT / NEW_REJECT / NEW_CRASH |
|---|---:|---:|---:|---:|---:|
| first clean run (`olddiff2.jsonl`) | 2,000 | 665 | 800 | 1,200 | 0 / 0 / 0 |
| widened (`olddiff3.jsonl`; recursive types, deep patterns, labels, mutable fields) | 1,500 | 494 | 787 | 713 | 0 / 0 / 0 |
| **total** | **3,500** | **1,159** | **1,587** | **1,913** | **0** |

The 88 widened cases whose expectation was “accept” but which **both**
compilers reject are all `deep_tuple_pat`; the generator emitted a pattern such
as `((((a, c), c), c), c)` that binds `c` four times, which is correctly
invalid.  They are an expectation bug in the generator, not a compiler
disagreement, and do not affect the zero-disagreement result (both rejected).

An earlier 600-case run is excluded: 75/600 were `NEW_ACCEPT` only because the
generator used the new `fn[T]` syntax, which the old parser rejects
(syntax drift, not a typechecker disagreement).

No current-version crash, ICE, timeout or silent failure appeared on any
old-accepted input.  The 3,500 shared-subset programs are exactly the
constructs both snapshots agree on by construction, so this is a bounded
agreement result, not evidence of general front-end equivalence.

## Verdict

* Build gate: **PASS** (no repair, ~6 min).
* Calibration gate: **PASS** (68/68).
* Success criterion: **not met** — no minimized discrepancy, no new crash/ICE,
  no scaling anomaly attributable to the current compiler.
* The four-hour clock was **not** exhausted (build + calibration + 3,500
  differential records took well under an hour), so the time-based clause is
  not the operative one.  Option ③ is closed early because the decisive
  limitation is structural: without a matching old core the shared subset is
  builtin-only, and 3,500 records produced zero disagreements.  Spending the
  remaining hours on the same builtin-only subset would not change the answer.
* Scope of the result: `check` agreement establishes acceptance agreement on
  the shared subset, not semantic equivalence or general front-end
  conformance.  The old compiler remains a useful drift detector for
  syntax/prelude calibration, but not a productive oracle for this snapshot
  pair.

Fallbacks per the external review: `build-interface` source-vs-interface
client check, then `gen-test-info` metadata consistency checks.  Remaining
unobserved entrances stay as a separate, hypothesis-driven campaign.
