# Comment draft for upstream #1322 — NOT SUBMITTED

Target: <https://github.com/moonbitlang/moonbit-docs/issues/1322>
Kind: supplementary comment, not a new issue
Language: English (issue is English)
Approval: **required before posting** — nothing has been posted.

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

Still reproduces on the current toolchain, so this is not fixed by
`moonc v0.10.20+65efd5b93` (2026-11-05, `moon 0.1.20261104`), Linux x86_64.

Two things that may help scope the fix: a smaller witness, and a control set
that shows the condition is about the element's representation rather than the
payload type.

Minimal (7 lines; the payload is `Int`, not a GC reference):

```moonbit
enum K {
  A(Int)
}

#valtype
struct E {
  id : Int
  k : K
}

fn main {
  let xs : Array[E] = []
  xs.push({ id: 0, k: K::A(0) })
  println(xs.length())
}
```

`moon run minimal.mbt --target native` fails with the same
`lower_array_make` error. Controls on the same pin (all native, debug):

| variant | result |
| --- | --- |
| `#valtype` struct with one field (scalar, `String`, or the enum) | passes |
| `id : Int` + `b : Bool` | passes |
| `id : Int` + `s : String` | passes |
| `id : Int` + nullary-only enum (`enum K { A }`) | passes |
| `id : Int` + two-variant enum (`A \| B(String)` or `A \| B(Int)`) | passes |
| `id : Int` + single-constructor enum with payload (`A(Int)`, `A(String)`, `A(Array[Int])`) | **fails** |
| two payload enums, no `Int` field | **fails** |
| `id : Int` + `kind : K` nested in another struct, then `wrapper.items.push(...)` | **fails** |
| same shape, non-empty literal `[{ ... }]` | passes |
| `push`, `Array::makei`, `map`, `filter`, `slice` | **fail** |

What that pins down:

- the payload type does not matter — `A(Int)` fails exactly like `A(String)`;
- a single-constructor enum with a payload appears to be represented as a
  non-null reference, while a two-variant enum is nullable and passes; a bare
  `String` field is nullable too and passes;
- a one-field `#valtype` struct passes, so the array layout needs at least two
  fields;
- only *empty* array creation fails; a non-empty literal is fine. This is
  consistent with the `uninitialized ... arrays are not lowered` message and
  with the `unsafe_make_uninit` variant you already reported.

It also reproduces outside script mode: a package whose `lib.mbt` builds an
empty `Array[Entry]` fails at plain `moon build --target native`, with no test
target involved, if that is more convenient for a regression test.

I have not read the compiler source; the representation sentence above is an
inference that fits all 48 measured shapes, not a claim about the
implementation.

---

## Before posting

- [ ] re-run `poc/f7_valtype_array_ice/minimal.mbt` and
      `cmd/scriptfuzz --family boundary` on the pin of the day; if any row
      flipped, update the table instead of posting it stale
- [ ] confirm the target issue is still open and has no comment covering this
- [ ] keep the comment as a comment on #1322; do not open a new issue
- [ ] post only after explicit approval
