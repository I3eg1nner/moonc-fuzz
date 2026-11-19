# Scale sweep: size is not the axis, declaration order is

Date: 2026-11-19
Pin: `moonc v0.10.20+65efd5b93`, Linux x86_64
Driver: `cmd/scalefuzz`, generator `moonbit/scalegen`

## Why

Three open upstream ICEs sit in the aggregate-layout corner (#1322 / F7,
#1340 / F8, #1344 / F9) and two of the filed hypotheses are threshold-shaped:
a 22-bit layout offset, and link-core recursion depth. The 160-case feature
matrix held struct size at zero to four fields, so **size was the axis it never
varied**. This sweep varies only that: 0, 1, 2, 3, 7, 15, 31, 63 scalar fields
in front of the aggregate that carries the GC reference.

Four shapes per size:

| shape | what it does |
|---|---|
| `record` | scalars + a payload enum, the F7 shape |
| `nested` | scalars + a plain struct that itself holds the enum |
| `arr2` | `Array[Array[E]]`: the empty allocation is one level out |
| `manyvar` | scalars + an enum with 64 payload variants and no nullary variant |

Each case builds at `moon build --target native`; if it survives, the driver
also runs `moon test --build-only` so the link stage is reached. One non-valtype
control per shape.

## Measured

36 cases, 24.7 s, **21 defects, 15 clean, 0 control failures, 2 distinct
signatures**.

| shape | fields 0 | 1 … 63 |
|---|---|---|
| `record` | pass | **ICE** (same signature at every size) |
| `arr2` | pass | **ICE** (same signature) |
| `nested` | pass | pass |
| `manyvar` | pass | **ICE** (same signature) |

Conclusions, in order of confidence:

1. **Size is not an axis here.** 63 fields fails exactly like 1 field, with
   the same `lower_array_make` signature. At these sizes there is no offset or
   depth threshold in this corner; the earlier threshold hypotheses are not
   supported by the data.
2. **Nesting suppresses the trigger entirely.** A `#valtype` struct whose
   GC-carrying field is a nested plain struct never fails, at any size. So the
   condition is about the *element's own layout*, not about reachable
   references through other structs.
3. `fields = 0` passes for every shape: the struct collapses to one field,
   which is the single-field form that already didn't trigger.
4. `manyvar` fails at every size — which contradicted the then-current
   characterisation ("two-variant enums are nullable, therefore pass").

## What the sweep actually found: declaration order

Point 4 forced a direct experiment:

| enum declaration | result |
|---|---|
| `{ A; B(Int) }` | pass |
| `{ A; B(String) }` | pass |
| `{ A(Int); B }` | **ICE** |
| `{ B(Int); A }` | **ICE** |
| `{ A(Int); B(Int) }` | **ICE** |

Same variants, same field layout, different order — different compilation
outcome. The rule that fits all fifteen boundary probes: the enum is a
non-null GC reference when a payload-carrying variant is declared **first**
(or when no variant is payload-free); declaring the payload-free variant first
gives the nullable form and compiles.

Two consequences:

- the characterisation in `findings/f7_trigger_surface.md` and
  `poc/f7_valtype_array_ice/README.md` was too coarse and is corrected there;
- the comment posted on #1322 says "two-variant enums … are nullable and
  pass". That is only true for nullary-first declarations. A correction is
  drafted in `issues/10-f7-order-correction.md`; nothing has been posted.

Whether the order dependence is itself a defect is a judgement call: the ICE
is already the defect (it should be a source diagnostic or a supported
lowering). What order dependence adds is evidence that the lowering decision
keys off the first variant's representation rather than the type as a whole,
which is exactly the kind of detail a maintainer needs to reproduce and fix it.

## Claim limits

- Fields up to 63, four shapes, one pin, native debug only. A threshold above
  63 is not excluded; 63 was chosen because the size classes up to there are
  the ones a layout would branch on.
- "Nesting suppresses" is measured for one nesting style (a plain struct with
  the enum). Deeper nesting, arrays of structs, and generics were not swept.
- The 36 cases produce only two signatures, so the sweep cannot distinguish
  "same root cause" from "same message". It does establish that the visible
  failure does not change with size.
- `manyvar`'s 64 variants are all `(Int)`; payload type was not part of this
  sweep.
