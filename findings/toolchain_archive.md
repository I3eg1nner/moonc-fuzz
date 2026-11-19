# Freezing the pinned toolchain

Date: 2026-11-19. Archive:
`moonbit-0.1.20261104-linux-x86_64.tar.gz`, 222,214,904 bytes,
sha256 `4b1aee737cb004df8a220ae6d8fab69646a8a153d72ab969e56735cbae4bee4f`.

## The problem this closes

Every piece of evidence in this repository is stated against a pin:
`moon 0.1.20261104 (940aa18)`, `moonc v0.10.20+65efd5b93`,
`moonrun 0.1.20261104`. That pin cannot be installed from upstream today:

- `https://cli.moonbitlang.com/install/unix.sh` installs `latest` only;
- every versioned path tried under `cli.moonbitlang.com/binaries/<version>/...`
  answers 403, including the exact version string reported by `moon version`;
- there is no public release mirror for the compiler binary that we could find.

So the evidence had an expiry date: the day `latest` moved, "reproduce this on
the pin" became an instruction nobody could follow. A pin that cannot be
restored is a note, not a pin.

## What is frozen

`scripts/archive_toolchain.sh` packs a working `MOON_HOME`:

| Path | Contents | Why |
|---|---|---|
| `bin/` | `moon`, `moonc`, `moonrun`, `moon-lsp`, `moonfmt`, `mooninfo`, `mooncake`, `moon_cove_report`, `moon-wasm-opt`, wasm tools | the toolchain proper |
| `lib/core/` incl. `lib/core/_build/` | core library sources **and the prebuilt bundle** | the toolchain does not rebuild core on first use; without the bundle every build fails with `input .../bundle/bigint/bigint.mi missing` |
| `lib/runtime/`, `lib/*.a`, `lib/*.o` | native runtime, `libtcc1.a`, backtrace shims | native link |
| `include/` | `moonbit.h` and friends | native stubs |
| `registry/index/`, `registry/symbols/` | dependency index | `moon` rejects a `moon.mod` dependency as "not found in the registry" without it |
| `MANIFEST.txt` | `moon version --all` plus per-binary sha256 | lets a restored archive be checked without trusting file names |

Deliberately excluded (regenerable or irrelevant to building and testing):
`bin/moondoc`, `bin/moonc-prove`, `bin/moonsearch`, `lib/why3`,
`registry/cache` (dependency tarballs; `.mooncakes/` or `moon update` supplies
those).

Two things this archive deliberately does **not** do:

- it does not make the *machine* reproducible (glibc, libm, QEMU version for
  the trace work are host properties, not toolchain properties);
- it does not pin the registry index, which is a moving mirror. A module whose
  version is not already in `.mooncakes/` may resolve differently in future.

## Restore

```bash
tar -xzf moonbit-0.1.20261104-linux-x86_64.tar.gz -C /opt/moonbit
export MOON_HOME=/opt/moonbit/moonbit-0.1.20261104-linux-x86_64
export PATH="$MOON_HOME/bin:$PATH"
moon version --all        # must print moonc v0.10.20+65efd5b93
```

`MOON_HOME` must point at the extracted directory itself (the one containing
`bin/` and `lib/`), not at its parent.

## Verification performed

`scripts/verify_toolchain_archive.sh` extracts the archive into a fresh temp
directory and does three things; all three passed on the archive above
(2026-11-19):

| Check | Result |
|---|---|
| `moon version --all` from the extracted tree | `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, `moonrun 0.1.20261104` |
| build a dependency-free package (`moon build --target native`) | ok, `tiny.exe` produced |
| build this repository (`moon build --target native`) | ok, all 22 commands linked |

The first attempt at this archive was wrong in two ways, both caught by that
script rather than by inspection: excluding `lib/core/_build` broke every build
(`bundle/bigint/bigint.mi missing`), and excluding `registry/index` broke
dependency resolution for this repository (`moonbitlang/x` "not found in the
registry"). The archive was rebuilt with both included; the version above is
the verified one.

Per-binary hashes are inside `MANIFEST.txt`; the two that matter for the defect
work are

```text
ec9d278bc212bf47e9ae38457e53635c2d9590aeb3ff1db18356afc8a2872f4f  bin/moonc
5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d  bin/moon-lsp
```

The `moon-lsp` hash matches the one recorded in the F11/F12 PoCs, so the LSP
defects remain checkable against the same binary they were found on.

## Where it lives

Attached to the `v0.1.0` release of
`I3eg1nner/moonc-fuzz` on GitHub. The repository does not track the tarball:
222 MB in git would be paid for on every clone, and release assets are the
right place for a binary artifact.

## What this changes about the claims

- "Reproducible on the pin" is now an executable statement, not a version
  string: the archive restores a compiler that reproduces the 12 defect
  regressions and the 17 acceptance gates.
- The forward-compatibility canary (CI on `latest`) stays separate: the archive
  is how the evidence is re-derived, CI is how we learn that a future toolchain
  breaks the harness.
- It does not extend the evidence's life forever. If the compiler's *runtime*
  dependencies on this host change, the archive's binaries may stop working;
  the archive freezes the compiler, not the operating system.
