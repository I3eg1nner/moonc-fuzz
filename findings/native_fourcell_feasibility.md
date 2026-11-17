# Native four-cell: from feasibility boundary to adapter

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`.

Status: **implemented** in `cmd/optdiff --target native --four-cell`.
Evidence and results: `findings/native_fourcell.md`.

## Observed command shape

`moon test -p moonbitlang/core/argparse --target native --debug --dry-run -v`
produces three command families:

```
moonc build-package ... -target native -g -O0 ...
moonc link-core ... -target x86_64-unknown-linux-gnu -g -O0 ...
/usr/bin/cc ... libmoonbitrun.o ... __moonbit_link_core__/*.o libruntime.a ...
```

The native link is a two-stage path: `link-core` emits a MoonBit object, then
`cc` links it with runtime objects. There is no `moonrun` step.

## Adapter requirements (all now implemented)

1. capture the exact `link-core` and `cc` argv;
2. keep the MoonBit O0/default toggle separate from the fixed C runtime `-O2`;
3. run the produced executable with the same working directory/environment;
4. compare rc, timeout, truncation, and every test-ID status;
5. retain a known-positive native control before treating zero candidates as
   meaningful.

The adapter expands `$MOON_HOME` in the `cc` argv, pairs `link-core` `.o`
outputs with `cc` `.exe` outputs by artifact stem, parses native test-id ranges,
and keeps a separate native failure classification. The build dimension is not
dropped: default-build cores are rebuilt from the default dry-run plan.

## Historical boundary (resolved)

The earlier version of this note said native was **not** covered because the
wasm adapter called `moonrun` and reused the wrong artifact shape. That was a
scope boundary, not a compiler defect. It is superseded by the implementation;
the only remaining limits are enumerated in `findings/native_fourcell.md`.
