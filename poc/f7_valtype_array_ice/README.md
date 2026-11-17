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

The trigger needs all of:

1. target `native` in **debug** (`-g -O0`);
2. a `#valtype` struct;
3. the struct has an `Int` field plus an enum field whose payload is a non-null
   GC reference (`Kind::Ref(String)` or `Kind::Ref(Array[Int])`);
4. the struct is stored in `Array[Entry]` through the growable `push` path.

Controls observed on the same host:

| variant | native debug |
|---|---|
| `#valtype` struct with only `kind : Kind` | pass |
| `#valtype` struct with `id : Int; s : String` | pass |
| `#valtype` struct with `id : Int; kind : Kind` where `Kind { A; B(String) }` | pass |
| same but `Kind { Ref(String) }` | **ICE** |
| same but `Kind { Ref(Array[Int]) }` | **ICE** |
| same layout without `#valtype` | pass |
| `native --release` | pass |

This is a diagnostic/tooling defect: the source type-checks, but the native
debug linker reports an internal unsupported lowering path instead of a
source-level diagnostic. It does not by itself demonstrate a miscompile.

## Upstream

Matches open upstream report
[#1322](https://github.com/moonbitlang/moonbit-docs/issues/1322)
(`Machine_of_clam_lower.lower_array_make`,
`uninitialized non-null GC ref arrays are not lowered`). It is reproduced here
against the repository's pinned toolchain, not claimed as a new upstream root
cause.
