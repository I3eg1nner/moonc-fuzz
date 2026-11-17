# Native four-cell feasibility (wasm-only adapter boundary)

Date: 2026-11-17. Toolchain: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`.

## Observation

`moon test -p moonbitlang/core/argparse --target native --debug --dry-run -v`
produces three command families:

```
moonc build-package ... -target native -g -O0 ...
moonc link-core ... -target x86_64-unknown-linux-gnu -g -O0 ...
/usr/bin/cc ... libmoonbitrun.o ... __moonbit_link_core__/*.o libruntime.a ...
```

The native link is a two-stage path: `link-core` emits a MoonBit object, then
`cc` links it with runtime objects. There is no `moonrun` step.

## Why the current four-cell adapter does not apply

- Current `optdiff --four-cell` calls `link-core` and then `moonrun`; native ends
  with `cc` and a host executable.
- The native C runtime is compiled by `cc` with `-O2`; the MoonBit core/object
  can be O0/default, but the runtime optimization is not part of that toggle.
- Target spelling is `x86_64-unknown-linux-gnu`, not `wasm`/`wasm-gc`.
- The `cc` object list, runtime archive and rpath need a native link/run adapter
  with its own evidence and failure classification.
- Reusing the wasm four-cell logic here would silently compare the wrong
  artifact or omit the final link/run.

## Decision

Native/LLVM four-cell is **not** claimed as covered. A future native adapter
must:

1. capture the exact `link-core` and `cc` argv;
2. keep the MoonBit O0/default toggle separate from the fixed C runtime `-O2`;
3. run the produced executable with the same working directory/environment;
4. compare full observation, rc, timeout and truncation;
5. retain a known-positive native control before treating zero candidates as
   meaningful.

This is a scope boundary, not a compiler defect.
