# Comment on upstream #1322 — POSTED

Target: <https://github.com/moonbitlang/moonbit-docs/issues/1322>
Kind: supplementary comment, not a new issue
Language: English (issue is English)
Status: **posted 2026-11-19**, approved by the maintainer of this repo.
Live: <https://github.com/moonbitlang/moonbit-docs/issues/1322#issuecomment-6996920436>
The text below is what was posted, with one render fix: `A \| B(Int)` inside a
code span became `A` / `B(Int)` to avoid a pipe-in-table artefact.

## Why we are commenting

#1322 is still open and still reproduces on the current pin, so this is a
supplement, not a duplicate. Three things are worth adding:

1. it is not fixed as of `moonc v0.10.20+65efd5b93`;
2. a 7-line witness with a **`Ref(Int)` payload**, which shows the payload type
   is not part of the condition;
3. a control table that narrows the condition to the *element representation*
   ("non-null GC ref") rather than the payload's type.

Everything in the table below was measured on this pin; the one mechanism
sentence is marked as a guess.

## Draft text

---

Still reproduces on `moonc v0.10.20+65efd5b93` (2026-11), Linux x86_64. Two
additions: a smaller witness, and controls that place the condition in the
element's representation rather than the payload type.

Minimal — the payload is `Int`, not a GC reference:

```moonbit
enum K { A(Int) }

#valtype
struct E {
  id : Int
  k : K
}

fn main {
  let xs : Array[E] = []
  xs.push({ id: 0, k: K::A(0) })
}
```

Same `lower_array_make` error. Controls (native, debug):

| shape | result |
| --- | --- |
| one-field `#valtype` (scalar, `String`, or enum) | passes |
| `Int` + `Bool`, `Int` + `String` | passes |
| `Int` + nullary enum, or two-variant enum (`A \| B(Int)`) | passes |
| `Int` + single-constructor payload enum (`A(Int)`, `A(String)`, `A(Array[Int])`) | **fails** |
| two payload enums, no `Int` field; or the record nested in a struct | **fails** |
| non-empty literal `[{ ... }]` | passes |

Payload type is irrelevant: `A(Int)` fails like `A(String)`. A
single-constructor payload enum behaves as a non-null reference, while
two-variant enums and bare `String` fields are nullable and pass. One-field
structs pass, so two fields are needed. Only empty array creation fails:
literals pass, `push`/`makei`/`map`/`filter`/`slice` fail. It also fails in
package mode at plain `moon build --target native`, so a regression test needs
no test target.

I have not read the compiler source; the representation sentence is an
inference from 48 measured shapes.

---

## Pre-post checks (done 2026-11-19T01:32Z)

- [x] `minimal.mbt` still fails with `lower_array_make` on
      `moonc v0.10.20+65efd5b93`
- [x] `cmd/scriptfuzz --family boundary`: 12/12 match, 0 mismatches
- [x] #1322 open, 0 comments, unchanged since 2026-10-08
- [x] posted as a comment, not a new issue
