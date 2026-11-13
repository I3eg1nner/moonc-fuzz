---
title: "ICE: native link rejects an exported closure-containing type with an ICE instead of a diagnostic"
labels: bug, ICE, moonc
tracker: moonbitlang/moonbit-docs (ice.md)
filed: https://github.com/moonbitlang/moonbit-docs/issues/1368
---

### Description

A 10-line package fails at native link with an internal compiler error:

```
Error: Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback";
  message="the Native backend cannot export types containing closures")
```

The package declares `pkgtype(kind: "foreign_library")` and exports one
function with `#export_name`. Its parameter type is a struct with a private
closure field. Removing `#export_name` makes the same package build (rc 0), so
the trigger is exporting a type that reaches a closure, not the struct itself.

Expected: a normal "unsupported for native export" diagnostic with a source
location. An ICE with a mangled internal name is not actionable from a user
package.

This is a diagnostic/tooling defect, not a miscompile: the package's `.core`
is produced, the JS target is unaffected, and the same module builds once the
export attribute is removed.

### Code

- Target: native (x86_64-unknown-linux-gnu)

`moon.mod`:

```
name = "f6min"
version = "0.1.0"
```

`moon.pkg`:

```
pkgtype(kind: "foreign_library")
```

`main.mbt`:

```moonbit
pub struct Handle {
  priv f : (Int32) -> Int32
}

#export_name("f6min_next")
pub fn next(h : Handle) -> Unit {
  ignore(h)
}
```

```bash
moon build --target native
echo $?      # 255
```

### Environment

- moonc: v0.10.20+65efd5b93 (2026-11-05)
- moon: 0.1.20261104 (940aa18 2026-11-04)
- OS: Linux x86_64, Ubuntu 24.04
- 3/3 reproductions

### Error output

```
Oops, the compiler has encountered an unexpected situation.
...
Error: Machine_error(kind=unsupported; who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback"; message="the Native backend cannot export types containing closures")
```

The failure happens in `moonc link-core`, i.e. after the package's own compile
step.

### Notes

Controls, all on the same file: no `#export_name` → rc 0; plain `pub fn`
instead of an exported one → rc 0. An external 12 MB package
(`WeiR-h/moonldif@0.7.6`) hits the same signature through `moon test --target
native`, while a `src`-scoped native build of that package succeeds; that
larger case is available in the reproducer directory but is not needed here.

Reproducer: <https://github.com/I3eg1nner/moonc-fuzz/tree/main/poc/f6_native_export_closure_min>.
