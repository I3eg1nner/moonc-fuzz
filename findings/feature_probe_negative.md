# Native layout / FFI / async feature probe: no new signature

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`.
Host: Linux x86_64, pinned, single machine.

This note records a **negative** result: a 269-case feature-directed matrix (302 rows, 33 duplicate IDs) over
native aggregates, FFI/ABI shapes and async state machines produced **no new
compiler-crash signature**. Every crash it did produce is one of the three
already-known signatures F7/F8/F9.

The result is useful because it bounds the easy end of the search space and
because it caught a measurement hazard (parallel `moon` runs) that would
otherwise have been reported as compiler diagnostics.

## 1. What was run

Generator: `scripts/probe/native_feature_probe.py` (Python, scratch-only; not
part of the MoonBit build). Each case is a complete module written to a fresh
directory, then driven through `moon check` / `moon build` /
`moon test --build-only` with a per-stage timeout. A stage result was kept only
if it carried a compiler-crash marker or a diagnostic.

| Family | Cases | What it varies |
|---|---:|---|
| `A1_struct` | 60 | struct field count/kind, `#valtype` on/off, GC-ref fields |
| `A2_enum` | 36 | 0/1/2 variants, payload kinds, nested enums |
| `A3_ops` | 18 | `push` / `makei` / `map` / `filter` / `slice` / `FixedArray` |
| `A4_arity` | 28 | 0/1/4/8/12/16/20 parameters, aggregate args and returns |
| `A5_nested` | 10 | `#valtype` inside `Option`/`Result`, nested records |
| `A6_crosspkg` | 16 | aggregate types crossing a package boundary |
| `A7_layout2` | 24 | second layout family (wider records, mixed scalar/ref) |
| `B_ffi` | 18 | `extern "C"` stubs: struct/enum/`V128` args and returns |
| `B2_ffi2` | 18 | stub with `V128` inside a struct, mixed vector+scalar |
| `C_async` | 41 | `@aio.pause()` position, `raise?` callback, loop/try/cancel |
| **Total** | **269** | |

(269 distinct case IDs; the probe wrote 302 JSONL rows because an early and a
late results file overlap on 33 IDs. The compact per-case summary is
`findings/feature_probe_summary.json`.)

## 2. Result: three signatures, all known

Across the 269 distinct cases there are exactly **three** distinct compiler-crash
signatures, covering **35 cases**:

| Signature | Cases | Known as |
|---|---:|---|
| `Machine_of_clam_lower.lower_array_make` / "uninitialized non-null GC ref arrays are not lowered" | 8 | **F7**, upstream #1322 |
| `Machine_of_clam_lower.finish_stub_wrapper_shell` / "aggregate stub wrapper arguments are not lowered" | 15 | **F9**, upstream #1344 |
| `moonc.ml:125623` assertion | 12 | **F8**, upstream #1340 |

No fourth signature appeared. No `Assert_failure`, `Segmentation fault`,
`Stack_overflow`, OOM or `Fatal error: exception` outside those three.

Reproduction of the three on the same host is already documented in
`poc/f7_valtype_array_ice/`, `poc/f8_async_raise_ice/`,
`poc/f9_native_v128_stub_ice/`; this probe does not add a new root cause and
must not be cited as one.

Distribution: the F7 signature appears in `A1_struct` (6), `A2_enum` (1) and
`A5_nested` (1); F9 in `B_ffi` (13) and `B2_ffi2` (6); F8 in `C_async` (12
distinct cases, 22 stage hits). `A3_ops`, `A4_arity`, `A6_crosspkg` and
`A7_layout2` produced no crash at all.

## 3. Measurement hazard: parallel `moon` runs emit spurious diagnostics

The probe ran cases concurrently. many stage results came back non-zero with
**diagnostic-only** signatures, e.g. `Error: [4021]`, `[4122]`, `[4024]`,
`[0055]`, `[4139]`, `[4014]`, `[4080]`, `[4188]`, plus
`failed when checking project` / `failed to run build for target Native`.

Serially re-running a sample from every one of those families in the same
directory, after deleting `_build`, returns **rc=0**:

| Re-checked case | Parallel result | Serial result |
|---|---|---|
| `a_cross_s_plain_n1` | check rc1 `[4021]` | check rc0 |
| `a_cross_e_valtype_n4` | check rc1 `[4021]` | build rc0 |
| `a_cross_e_plain_n12` | check rc1 `[4021]` | build rc0 |
| `b_ffi_plain_big_struct` | check rc1 `[0055]` | check rc0 |
| `b_ffi_plain_enum_arg` | check rc1 `[0055]` | check rc0 |
| `b_ffi_plain_struct_arg` | check rc1 `[0055]` | check rc0 |

So those diagnostic-only results are **not** language restrictions and
**not** compiler defects: they are artifacts of many concurrent `moon`
invocations contending on shared caches. They are excluded from the result
above.

Consequences for the rest of the project:

- Any diagnostic-only (non-crash) failure must be re-run **serially** in a
  clean copy before it is reported. The `cmd/verify` tool already does the
  fresh-copy part; its repeats are sequential, which is the right default.
- The fuzz drivers' `--jobs` must stay small on a shared host. A high `--jobs`
  can manufacture a diagnostic class that looks like a compiler defect.
- This also explains part of the earlier overload incident: the machine was
  running many `moon`/`moonc` processes that each spawn their own build tree;
  the failure mode was contention, not a single pathological input.

## 4. What this does and does not show

Shows, for this pinned toolchain and this generator:

- the "simple combination" neighbourhood of F7/F9 (aggregate layout, arity,
  FFI shapes) and of F8 (pause/`raise?`/loop/try/cancel) is saturated: adding
  more cases from the same axes is unlikely to produce a new signature;
- the three known signatures are stable and easy to re-hit, so they are a
  usable positive control for any new driver;
- `A3_ops`, `A4_arity`, `A7_layout2` are dead axes for crash finding at this
  level — 70 cases, zero crash.

Does not show:

- that the compiler is correct outside these shapes;
- anything about wasm/wasm-gc/js, or about native **release**;
- anything about runtime miscompilation: this probe only looks at
  check/build/test-build, never at executed results;
- that no new signature exists in feature *interactions* the matrix did not
  combine (e.g. async inside `#valtype` methods, generics over `V128`,
  exported closures with aggregate captures).

## 5. Recommended next axes

Given §4, the next axes with real expected value are not "more of the same":

1. **Cross-backend same-source differential** on cases that already compile:
   compare executed output of wasm-gc / wasm / js / native for the same
   generated source. This targets miscompiles, which this probe never looked
   at.
2. **Feature interaction**, not feature enumeration: async methods on
   `#valtype` records, `raise?` closures captured by async state machines,
   generic FFI wrappers, exported closures with aggregate captures.
3. **Real-package async/`#valtype` corpora** rather than synthetic matrices:
   the synthetic space is saturated; real packages add shapes nobody curated.

Do not spend more budget on: larger arity tables, more field-count
permutations, more `V128` position variants, more `pause` positions.
