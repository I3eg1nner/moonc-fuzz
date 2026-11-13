# Interface-emission consistency pilot (codex fallback) — negative

Goal: after option ③ was abandoned, run one capped pilot on the
`build-interface` round trip under the oracle the external review specified:
build package P from source, emit its textual public interface, rebuild that
interface into a second `.mi`, and require identical accept/reject outcomes for
identical external clients checked against the two artifacts.  Success = one
minimized reproducible mismatch attributable to interface
emission/reconstruction/import, or a new reproducible crash/ICE.  Abandon
after 30 min of setup if the basic round trip or fault controls cannot work,
otherwise after 2 h without a credible candidate.

Harness: `harness/iface.py` (`calib`, `run`, `report`); results
`out/iface.jsonl` (mismatches only, empty), summary `out/iface_summary.json`.

## Oracle setup — PASS (≈15 min)

```
# build P: source -> p.mi (p.core is a by-product)
moonc build-package -pkg iface/p -i <prelude.mi> -o p.core lib.mbt
# emit the textual public interface
mooninfo -format text -no-alias p.mi -o p.mbti
# rebuild the interface into a second .mi
moonc build-interface -pkg iface/p -i <prelude.mi> -o p2.mi p.mbti
# identical clients against each artifact
moonc check -no-mi -pkg iface/client -i p.mi -i <prelude.mi> c.mbt
moonc check -no-mi -pkg iface/client -i p2.mi -i <prelude.mi> c.mbt
```

Import alias is the last package segment (`@p`).  Calibration fixture
(`pub fn add`, labelled `pub fn label(x~)`) plus three clients gave
accept/accept, reject/reject, reject/reject on both `.mi`s.  **Fault control**
changed `add(Int32, Int32)` to `add(Int32)` in the `.mbti`: `build-interface`
still succeeded and the previously accepting client became rejected, so the
oracle detects a real interface change rather than just comparing bytes.

## Differential — 150 packages, 2,278 client checks, zero mismatches

Generator: 5-package cycle of function-only packages with builtin types
(2-arg Int, Bool, String, tuple return, labelled arg, 0-arg, generic
`pub fn[T] id`, optional `y? : Int = 1`, 3-arg) plus a fixed abstract-type
family (`pub struct S { priv v : Int }` + `s_make` / `s_get`).  Clients include
correct calls and expected rejections (arity, wrong type, missing/unknown
label, unknown name).

| metric | value |
|---|---:|
| packages built | 150 |
| of which abstract-type packages | 30 |
| client checks | 2,278 |
| SAME_ACCEPT | 880 |
| SAME_REJECT | 1,398 |
| IFACE_ACCEPT_ONLY / IFACE_REJECT_ONLY | 0 / 0 |
| IFACE_CRASH / ICE / timeout | 0 |
| interface-text differences (`mooninfo` of rebuilt `.mi`) | 0 |

Every client that used the represented public API got the same outcome against
the source-built `.mi` and the rebuilt `.mi`; every expected rejection was
rejected by both.

## Observation (tooling dialect gap, not claimed as a defect)

For an opaque public type, `mooninfo -format text` emits

```
pub struct S {
  // private fields
}
```

and `moonc build-interface` rejects exactly that text: `E4032 The type S is
undefined` (signatures are emitted before the type block) and `E4157 Non
abstract type is not supported in building the mbti file`.  Replacing the block
with a top-level `type S` declaration makes `build-interface` succeed (rc 0),
after which clients agree with the source-built interface.  All 30 abstract
packages (30/30) needed this normalization; the 120 function-only packages
needed none.

This is a concrete incompatibility between the two shipped tools' textual
dialects.  It is recorded as an observation, not a compiler defect: the
intended workflow for the text form (human-readable `moon info` output vs the
interface-first authoring dialect accepted by `build-interface`) is not
documented in the artifacts we have, and the pipeline works after a one-line
normalization.

## Verdict

* Setup/fault-control gate: **PASS**.
* Success criterion: **not met** — no mismatch, no crash, no ICE; the oracle
  was sensitive to a deliberate signature change, so this is a real negative
  rather than a blind one.
* Capped pilot closed after ≈1.5 h.  Per the external review, the campaign
  stops here; it does not roll into `gen-test-info` metadata testing
  automatically.
* Scope: interface round-trip for function signatures (including labels,
  generics, optional args) and opaque types, checked through client
  acceptance; not code generation, not trait-bound interfaces, not default
  argument values beyond the accept/reject behaviour tested.

## Reproduce

```
python3 harness/iface.py calib     # fixture + arity fault control
python3 harness/iface.py run --n 150
python3 harness/iface.py report
```
