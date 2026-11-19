# F7 trigger surface: mapping the defect instead of re-finding it

Date: 2026-11-19
Pin: `moonc v0.10.20+65efd5b93`, `moon 0.1.20261104`, Linux x86_64

## The gap this closes

The project could already say "F7 reproduces" and had a 160-case feature
matrix that flagged it. It could not say *what exactly* triggers it. The PoC
README even carried two wrong conditions:

- "the struct has an `Int` field plus an enum field" — an `Int` field is not
  required (two enum fields trigger);
- "whose payload is a non-null GC reference (`String` / `Array[Int]`)" — a
  `Ref(Int)` payload triggers identically.

Neither error mattered for "is this a bug", and both mattered for "is this the
same bug as upstream #1322, and how small can the witness be". So the defect
was mapped as a cross product rather than re-found as a sample.

## Method

`moonbit/scriptgen` renders standalone scripts and `cmd/scriptfuzz` runs them
through `moon run ... --target native`, classifying with the shared oracle
layer. Two families:

- **grid** — 36 points: payload kind (`String`, `Array[Int]`, `Int`) x
  container (`Array`, `Array[Array]`, struct field) x construction
  (`literal`, `push`) x `#valtype` on/off. The `plain` half is a negative
  control: a control that does not compile means the renderer is broken and no
  row can be trusted.
- **boundary** — 12 fixed probes that each separate two competing
  explanations, with the expected outcome recorded next to the source.

Script mode was used because F7's own PoC is a script; the same shape also
fails in package mode (`featfuzz` L0080-L0084 fail at `moon build`), which was
checked separately so the result is not a script-mode artefact.

## Grid result

36 cases: 30 pass, 6 ICE, 0 invalid, 18/18 controls pass, 2 distinct
signatures (the ICE and `ok`).

The six failures are exactly `{String, Array[Int], Int} x {Array, struct
field} x push`. Two observations that changed the characterisation:

- **payload type is irrelevant** — `Ref(Int)` fails like `Ref(String)`;
- **`Array[Array[E]]` never fails**, because the inner array is built from a
  non-empty literal, so no *empty* `Array[E]` is ever allocated.

## Boundary result

| # | shape | expectation | observed |
|---|---|---|---|
| b01 | one scalar field | pass | pass |
| b02 | one `String` field | pass | pass |
| b03 | one enum field | pass | pass |
| b04 | `Int` + enum, payload `Int` | **ICE** | **ICE** |
| b05 | `String` + enum | **ICE** | **ICE** |
| b06 | `Int` + nullary-only enum | pass | pass |
| b07 | `Int` + `Bool` | pass | pass |
| b08 | `Int` + `String` | pass | pass |
| b09 | two payload enums, no `Int` | **ICE** | **ICE** |
| b10 | three fields incl. enum | **ICE** | **ICE** |
| b11 | `Int` + two-variant enum (`A \| B(String)`) | pass | pass |
| b12 | `Int` + two-variant enum (`A \| B(Int)`) | pass | pass |

12/12 match, 0 mismatches, 0 control failures, 5.7 s.

## Characterisation

> In native debug, allocating an **empty** `Array[E]` is not lowered when `E`
> is a `#valtype` type that contains a **non-null GC reference**. A
> single-constructor enum with a payload has exactly that representation; a
> two-variant enum is nullable (the tag covers a null case), and a bare
> `String` field is nullable too. A one-field `#valtype` struct is represented
> as the field itself, so it never needs an array-slot initialiser.

The error text itself names the condition (`uninitialized non-null GC ref
arrays are not lowered`); the table is the evidence that the condition is
about the *element representation*, not about the payload's type, the field
count beyond two, or where the array lives.

This also explains the "literal passes / push fails" split: a non-empty
literal is pre-sized, so slots are written rather than zero-initialised.

## Corrections applied

- `poc/f7_valtype_array_ice/minimal.mbt` — 7-line witness with `Ref(Int)`.
- `poc/f7_valtype_array_ice/README.md` — corrected conditions, the twelve-row
  control table, and an explicit note that the two earlier claims were too
  narrow.

## What it is worth upstream

Not a new root cause: same `lower_array_make` assertion as open #1322. What it
adds is a smaller witness, a corrected scope (payload-independent), and a
control set that says which neighbouring shapes are *not* affected. That is
what a maintainer needs to decide whether the fix is "handle this
representation" or "handle zero-initialisation generally".

No comment was posted: upstream contact requires explicit approval.

## Claim limits

- One pin, one host, `native` target. `--release` passes; `wasm`, `wasm-gc`
  and `js` pass. Nothing here is a miscompile — it is a rejected lowering.
- "Non-null GC ref" is inferred from observed behaviour plus the compiler's
  own message, not from the compiler source. The mechanism sentence is a
  hypothesis that fits all 48 measured points (36 grid + 12 boundary).
- The boundary probes are line-level textual scripts; they do not vary
  generics, FFI, or async, so the map covers the aggregate-layout corner only.
- `b11`/`b12` pass is a statement about this pin. An upstream change in how
  two-variant enums are represented would flip them without fixing anything;
  that is why the table is documentation, not a hard gate.
