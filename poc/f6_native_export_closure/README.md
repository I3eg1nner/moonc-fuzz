# F6: native export of a closure-containing type (external package)

Pinned: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`.

The 12 MB `WeiR-h/moonldif@0.7.6` tree is intentionally not committed.  Fetch
it into `assets/`:

```
cd /path/to/repo
./scripts/fetch_assets.sh
cd assets/f6_external/moonldif
moon test --target native
echo $?          # 1
```

Expected signature:

```
Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback";
  message="the Native backend cannot export types containing closures")
```

Controls: `moon test --target native src` passes 66/66; `moon test --target js`
passes 66/66.  Module-wide `moon build --target native` also fails with the same
signature; this is not test-mode-only, and it is a diagnostic/tooling defect,
not a miscompile.  The minimal 12-line repro is
[`../f6_native_export_closure_min/`](../f6_native_export_closure_min/).
