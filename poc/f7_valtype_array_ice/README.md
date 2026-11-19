# F7: native debug ICE on `Array` of a `#valtype` record containing an enum

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.
Host: Linux x86_64.

## Reproduce

```
cd poc/f7_valtype_array_ice
moon run repro.mbt --target native
```

Expected (and observed) result: the link step prints a compiler ICE banner and
exits nonzero:

```
Error: Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.lower_array_make";
  message="uninitialized non-null GC ref arrays are not lowered";
  function="@_M0MPB18UninitializedArray23unsafe__make__and__blit...EntryE")
```

`--release` succeeds and prints `0`. `wasm`, `wasm-gc`, and `js` also succeed
in both debug and release.

## Minimal trigger

`minimal.mbt` is the smallest witness found: a `#valtype` record with two
fields, one of which is a **single-constructor enum with a payload**.

```
moon run minimal.mbt --target native
```

The trigger needs all of:

1. target `native` in **debug** (`-g -O0`);
2. a `#valtype` struct with **at least two fields** (a one-field struct is
   represented as the field itself and does not reach the array layout);
3. at least one field whose type is a **single-constructor enum with a
   payload** — that representation is a non-null GC reference, which is the
   condition named in the error message;
4. the value reaches an `Array[Entry]` through the growable path (`[]` then
   `push`, or `makei`/`map`/`filter`/`slice`), not through a non-empty
   literal.

The payload **type is irrelevant**: `Ref(Int)` triggers just like
`Ref(String)`. An earlier revision of this file said the payload had to be a
GC reference, and that an `Int` field plus an enum was required. Both claims
were too narrow; the boundary table below is the corrected version, and
`cmd/scriptfuzz --family boundary` reproduces all twelve rows.

| variant | native debug | why |
|---|---|---|
| `#valtype` struct with a single scalar field | pass | no array layout needed |
| `#valtype` struct with a single enum field | pass | same single-field collapse |
| `id : Int` + `b : Bool` | pass | nothing to leave uninitialised |
| `id : Int` + `s : String` | pass | `String` is a *nullable* ref |
| `id : Int` + nullary-only enum | pass | payload-free enum is an immediate |
| `id : Int` + two-variant enum (`A \| B(String)`) | pass | the tag makes it nullable |
| `k : K` + `j : K` (two payload enums, no `Int`) | **ICE** | two fields, non-null refs |
| `id : Int` + `k : K` (payload `Int`) | **ICE** | payload type does not matter |
| `id : Int` + `k : K` (payload `String`, `Array[Int]`) | **ICE** | original shape |
| `id : Int` + `a : Int` + `k : K` | **ICE** | field count above two is fine |
| record behind a struct field, then `items.push(...)` | **ICE** | position of the array does not matter |
| non-empty literal `[{...}]` | pass | pre-sized, never zero-initialised |
| same layout without `#valtype` | pass | |
| `native --release` | pass | |

The same source in **package** mode fails at `moon build` (see
`cmd/featfuzz` cases L0080-L0084), so this is not a script-mode-only artefact.

## Upstream

Matches open upstream report
[#1322](https://github.com/moonbitlang/moonbit-docs/issues/1322)
(`Machine_of_clam_lower.lower_array_make`,
`uninitialized non-null GC ref arrays are not lowered`). It is reproduced here
against the repository's pinned toolchain, not claimed as a new upstream root
cause.
