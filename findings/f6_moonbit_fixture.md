# F6 — native `link-core` ICE on exported closure-containing types (WeiR-h/moonldif 0.7.6)

**Status: verified.** The documented test-mode signature reproduces 3/3. One
scope correction to the earlier F6 notes is recorded below: a module-wide
`moon build --target native` does **not** succeed; the same ICE is reached on
the non-test link path. The package-scoped build (`moon build --target native
src`) does succeed. This remains a compiler diagnostic/tooling defect, not a
miscompile.

| item | value |
|---|---|
| package | `WeiR-h/moonldif@0.7.6` (exact registry version) |
| artifact | `/home/user/.moon/registry/cache/WeiR-h/moonldif/0.7.6.zip` |
| artifact sha256 | `4b956828c87ecb7a6186e464d5d3d646cd25867dc00d960aa16e05ac3105a647` |
| artifact size | 5,616,175 bytes |
| fixture | `/data/audit/mbtfuzz/poc/f6_native_export_closure/moonldif` |
| fixture integrity | 689 files, 12 MB; `diff -r` against a fresh unzip of the cache zip: **no differences**; no source edits |
| `moon` | `0.1.20261104 (940aa18 2026-11-04)` |
| `moonc` | `v0.10.20+65efd5b93 (2026-11-05)` |
| host | Linux x86_64, 128 cores |
| verification date | 2026-11-13 (UTC) |
| network / dependency fetch | none needed; core toolchain was already built. No hang; the whole verification took well under 20 minutes. |

## Commands

```bash
cd /data/audit/mbtfuzz/poc/f6_native_export_closure/moonldif

# 3 test runs, build state deleted before every run
rm -rf _build && moon test --target native

# build checks
moon build --target native          # module-wide (all packages)
moon build --target native src      # library package only
moon build --target native src/bridge
moon build --target js              # control

# target control
moon test  --target native src      # library tests only
moon test  --target js              # full module
```

## Three native test runs

`_build` was removed before each run. Raw stderr is archived byte-for-byte in
`poc/f6_native_export_closure/logs/test-native-run{1,2,3}.out`.

| run | `_build` | rc | exact signature | ICE banner | stderr |
|---:|---|---:|---|---|---|
| 1 | removed | **1** | **yes** (1 match) | yes | 8,852 B |
| 2 | removed | **1** | **yes** (1 match) | yes | 8,852 B |
| 3 | removed | **1** | **yes** (1 match) | yes | 8,852 B |

All three stderr streams are byte-identical:
sha256 `e9934a2ba6f03ff2ff65bf73696599145cdda0e1cbd8ee671dafcdf93df6a396`.
Each run failed in about 1 s at:

```
Error: failed to link WeiR-h/moonldif/bridge (native, inline test): ... moonc link-core ... \
  -test-mode ... \
  -exported_functions moonbit_test_driver_internal_execute,moonbit_test_driver_finish \
  -target x86_64-unknown-linux-gnu -g -O0
```

The compiling of `.mbt` → `.core` succeeds; the failure is in `moonc link-core`
for the `WeiR-h/moonldif/bridge` package (`pkgtype(kind: "foreign_library")`).

### Exact signature

```text
Error: Machine_error(kind=unsupported; who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback"; message="the Native backend cannot export types containing closures")
```

(188 bytes, identical in all three runs.)

### Shortest stderr tail containing the signature

For `moon test --target native` the signature is stderr line 13 of 15, so the
shortest suffix that still contains it is the last **3 lines / 4,274 bytes**
(only the 4,050-byte `Compiler args:` line is abbreviated here; the full line is
in the archived log):

```text
Error: Machine_error(kind=unsupported; who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback"; message="the Native backend cannot export types containing closures")
Compiler args: /home/user/.moon/bin/moonc link-core ... [4,050-byte argument list] ... -exported_functions moonbit_test_driver_internal_execute,moonbit_test_driver_finish -target x86_64-unknown-linux-gnu -g -O0
moonc version: v0.10.20+65efd5b93
```

## Does `moon build --target native` succeed?

**Module-wide: no. Package-scoped library build: yes.** This corrects the
earlier F6/third-party statement that "`moon build` for native succeeds; only
the test-mode export path ICEs".

| command | rc | signature | observation |
|---|---:|---|---|
| `moon build --target native` | **255** | **yes** | fails linking `WeiR-h/moonldif/bridge (native)`; `link-core` has `-main`, **no** `-test-mode`, no test-driver exports |
| `moon build --target native src` | **0** | no | `Finished. moon: ran 1 task`; emits `_build/native/debug/build/moonldif.core` (388,649 B) and `moonldif.mi` |
| `moon build --target native src/bridge` | **255** | **yes** | same failure as module-wide build |
| `moon build --target js` | **0** | no | 3 tasks, including `bridge.js` |
| `moon test --target native src` | **0** | no | `Total tests: 66, passed: 66, failed: 0.` |
| `moon test --target js` | **0** | no | `Total tests: 66, passed: 66, failed: 0.` |

So "native build succeeds" is true only for the library package `src`, not for
the module as a whole. The earlier third-party campaign used the dependency-path
form `moon build .mooncakes/WeiR-h/moonldif --target native`, which returned 0
in this environment **without compiling anything** (the preserved module's
`_build/` contains only `.moon-lock`), so that success is not evidence that the
native link of the module works. The meaningful package-scoped check is
`moon build --target native src` (rc 0, real `.core` produced).

This is not order-dependent: running `moon build --target native` immediately
after a failed `moon test --target native` (without deleting `_build`) also
returns 255 with the same signature.

For `moon build --target native` the signature is stderr line 13 of 19; the
shortest suffix containing it is lines 13–19, ending with the moon wrapper:

```text
Error: Machine_error(kind=unsupported; who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback"; message="the Native backend cannot export types containing closures")
Compiler args: /home/user/.moon/bin/moonc link-core ... [4,050-byte argument list] ... -target x86_64-unknown-linux-gnu -g -O0
moonc version: v0.10.20+65efd5b93
Error: failed to run build for target Native

Caused by:
    failed when building project
```

## Trigger / mechanism

The native backend refuses to export a type whose layout contains a MoonBit
closure. In this package the exported `bridge` type reaches one:

* `src/pagination.mbt:421` — `pub struct ReportCursor` has
  `priv item : (Int32) -> Json` (line 423), i.e. a function-typed field.
* `src/bridge/paging.mbt:192` — `pub struct PagingCursor` has
  `priv cursor : @ldif.ReportCursor?`.
* `src/bridge/pkg.generated.mbti` exports `PagingCursor`; `src/bridge/moon.pkg:7`
  declares `pkgtype(kind: "foreign_library")`.

`Reject_export_type_containing_unsupported_callback` is therefore a legitimate
backend restriction firing during `link-core`; the defect is that it escapes as
an uncaught `Machine_error` (ICE banner), not that the closure was miscompiled.
The non-test module build reaches the same check, so this is not test-mode-only.

## Classification

* **Diagnostic/tooling defect, not a miscompile.**
  * `.mbt` compilation to `.core` succeeds; native `src` build and native
    `src` tests (66/66) succeed; JS build and JS tests (66/66) succeed.
  * Native `bridge` is never linked and no native test binary is produced, so
    there is no wrong-code or wrong-result evidence.
  * Correct behaviour would be a normal user-facing diagnostic such as
    "native cannot export type `PagingCursor`: it contains a closure" with rc 2,
    instead of the "This is a bug in the compiler" banner with rc 1 (test) /
    rc 255 (`moon build`).
* Scope correction for `poc/f6_native_export_closure/README.md` and
  `findings/thirdparty.md`: "`moon build --target native` succeeds" should be
  restated as "`moon build --target native src` succeeds; the module-wide
  native build hits the same bridge link ICE". Those two files were not edited
  as part of this task.

## Evidence files

* `poc/f6_native_export_closure/logs/test-native-run{1,2,3}.out` — 3 native test runs, byte-identical.
* `poc/f6_native_export_closure/logs/build-native-root.out` — module-wide native build failure.
* `poc/f6_native_export_closure/logs/build-native-src.out` — package-scoped native build success.
* `poc/f6_native_export_closure/logs/build-native-bridge.out` — direct bridge native link failure.
* `poc/f6_native_export_closure/logs/test-native-src.out` — native library tests 66/66.
* `poc/f6_native_export_closure/logs/test-js-control.out` — JS tests 66/66.
* `poc/f6_native_export_closure/logs/build-js-control.out` — JS build (3 tasks) success.

## Minimized trigger (2026-11-13)

The 12 MB `WeiR-h/moonldif@0.7.6` fixture is no longer required to reproduce
F6.  A single `foreign_library` package with a closure-containing exported type
is sufficient (`poc/f6_native_export_closure_min/`, 12 source lines):

```moonbit
pub struct Handle {
  priv f : (Int32) -> Int32
}

#export_name("f6min_next")
pub fn next(h : Handle) -> Unit {
  ignore(h)
}
```

```
cd poc/f6_native_export_closure_min
moon build --target native      # rc=255, same Machine_error signature
```

Minimization matrix:

| variant | result |
|---|---|
| full moonldif, `moon test --target native` | ICE |
| two packages (`lib.Cursor` + bridge `Handle`) | ICE |
| one package `Handle { priv f : (Int32)->Int32 }` + `#export_name` | **ICE** |
| same struct, no exported function | rc=0 |
| same struct + plain `pub fn` (no `#export_name`) | rc=0 |
| closure field made public, with `#export_name` | ICE |

Trigger: a `foreign_library` package exports a function whose signature reaches
a closure type, including behind a private field.  Correct behaviour is a clean
unsupported-target diagnostic (rc=2), not an ICE.  This remains a diagnostic /
tooling defect, not a miscompile.  The MoonBit regression gate now uses this
minimal fixture, so F6 coverage no longer depends on a third-party download.

## Native export boundary matrix (2026-11-13)

`moonbit/cmd/f6matrix` generates eight closure shapes plus two controls.
All closure shapes fail with the same signature; controls build:

| variant | rc | result |
|---|---:|---|
| private closure field | 255 | ICE, `closure_export_rejected` |
| public closure field | 255 | ICE |
| `Array[(Int32)->Int32]` | 255 | ICE |
| `Option[(Int32)->Int32]` | 255 | ICE |
| type alias `Cb = (Int32)->Int32` | 255 | ICE |
| enum payload closure | 255 | ICE |
| generic `Box[(Int32)->Int32]` | 255 | ICE |
| nested struct with closure | 255 | ICE |
| no `#export_name` | 0 | built |
| `#export_name` + `Int32` field | 0 | built |

So the rejection is specifically about the **exported signature reachability**:
private fields, aliases, arrays, options, enums, generics and nesting do not
hide the closure from the native export validation.  No additional root-cause
class was found in this matrix; it is still one diagnostic/tooling defect.
