# F6-min: native export of a closure-containing type (single package, 10 lines)

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.

This is the minimized trigger for F6.  It needs no third-party package and
fails at `moon build --target native`, not only in test mode.

```
cd poc/f6_native_export_closure_min
moon build --target native      # rc=255, ICE banner
```

Signature:

```
Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback";
  message="the Native backend cannot export types containing closures")
```

Minimization steps:

| variant | result |
|---|---|
| 12 MB `WeiR-h/moonldif@0.7.6`, `moon test --target native` | ICE |
| two packages (`lib.Cursor` + bridge `Handle`) | ICE |
| one package `Handle { priv f : (Int32)->Int32 }` + `#export_name` fn | **ICE** |
| same struct, no exported function | rc=0 |
| same struct + plain `pub fn` (no `#export_name`) | rc=0 |
| closure field made public | still ICE when exported |

So the trigger is: a `foreign_library` package exports (`#export_name`) a
function whose parameter/return type reaches a closure type, even behind a
private field.  A clean unsupported-target diagnostic is expected instead of an
ICE; this PoC does not prescribe the exact exit code.  This is a
diagnostic/tooling defect, not a miscompile.
