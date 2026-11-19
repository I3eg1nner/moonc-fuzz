# Correction draft for #1322 — NOT SUBMITTED

Target: <https://github.com/moonbitlang/moonbit-docs/issues/1322>
Kind: correction to our own comment of 2026-11-19
(<https://github.com/moonbitlang/moonbit-docs/issues/1322#issuecomment-6996920436>)
Approval: **required before posting** — nothing has been posted.

## Why

That comment said "two-variant enums and bare `String` fields are nullable and
pass". A later sweep found counter-examples: the variant *order* decides.

| enum declaration | observed |
|---|---|
| `{ A; B(Int) }` | passes |
| `{ A(Int); B }` | **ICE** |
| `{ B(Int); A }` | **ICE** |
| `{ A(Int); B(Int) }` | **ICE** |

Same variants, same struct layout, different order. The rule that fits all
fifteen probes: a payload-carrying variant declared first (or no payload-free
variant at all) gives the non-null representation.

Also worth adding to the same comment: scaling the struct from 1 to 63 fields
does not change the failure or its signature, and nesting the enum inside a
plain struct suppresses the trigger entirely.

## Draft text

---

A correction to my comment above, and two results from a follow-up sweep.

The statement "two-variant enums … are nullable and pass" is only true when
the payload-free variant is declared **first**. The variant order decides:

```moonbit
enum K { A; B(Int) }   // compiles
enum K { A(Int); B }   // same variants, ICE
```

`{ B(Int); A }` also fails, and `{ A(Int); B(Int) }` (no payload-free variant)
fails too. All fifteen probes in my table fit this rule: the enum is a non-null
reference when a payload-carrying variant comes first, or when no variant is
payload-free.

Two more data points, in case they help scope the fix:

- struct size does not change the outcome: 1, 2, 3, 7, 15, 31 and 63 fields
  all fail with the same `lower_array_make` signature, and all pass at 0
  fields (single-field collapse);
- nesting suppresses it: if the enum lives in a plain struct used as a
  `#valtype` field, every size up to 63 fields compiles, so the condition is
  about the element's own layout rather than reachable references.

---

## Before posting

- [ ] re-run `cmd/scriptfuzz --family boundary` (15 probes) and
      `cmd/scalefuzz` on the pin of the day
- [ ] confirm #1322 is still open and our earlier comment is still the last one
- [ ] post as a comment, not a new issue
