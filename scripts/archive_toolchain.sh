#!/usr/bin/env bash
# Freeze the pinned toolchain into a single archive.
#
# Why this exists: `cli.moonbitlang.com` serves only `latest`.  Every versioned
# path we tried answers 403, so once upstream moves, `moon 0.1.20261104` cannot
# be installed again and the evidence in this repository stops being replayable.
# The archive is the fallback: a tarball that restores a working `MOON_HOME`.
#
# Usage: scripts/archive_toolchain.sh [OUT_DIR]
#
# Output: $OUT_DIR/moonbit-<moon version>-<os>-<arch>.tar.gz plus .sha256
#
# Excluded on purpose (none of it is needed to build or test this repo, and all
# of it doubles the download):
#   bin/moondoc, bin/moonc-prove, bin/moonsearch   documentation/prover/search
#   lib/why3                                       prover support library
#   lib/registry                                   re-fetchable dependency mirror
# Nothing from lib/core is excluded: the prebuilt core bundle in
# lib/core/_build is *required* (the toolchain does not rebuild core from
# source on first use; a restored archive without it fails with "input
# .../bundle/bigint/bigint.mi missing").
#   lib/prelude_proof*, lib/core/*/_build          proof artefacts
set -euo pipefail

OUT_DIR=${1:-/tmp}
HOME_MOON=${MOON_HOME:-$HOME/.moon}
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
version=$("$HOME_MOON/bin/moon" version | head -1 | awk '{print $2}')
name="moonbit-${version}-${os}-${arch}"

if [ ! -x "$HOME_MOON/bin/moonc" ]; then
  echo "no toolchain at $HOME_MOON" >&2
  exit 2
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
root="$stage/$name"
mkdir -p "$root/bin" "$root/lib"

cp -a "$HOME_MOON/bin/." "$root/bin/"
rm -f "$root/bin/moondoc" "$root/bin/moonc-prove" "$root/bin/moonsearch"

cp -a "$HOME_MOON/lib/core" "$root/lib/core"
cp -a "$HOME_MOON/lib/runtime" "$root/lib/runtime"
for f in "$HOME_MOON"/lib/*.a "$HOME_MOON"/lib/*.o; do
  [ -e "$f" ] && cp -a "$f" "$root/lib/"
done
if [ -d "$HOME_MOON/include" ]; then
  cp -a "$HOME_MOON/include" "$root/include"
fi
# Dependency resolution needs the registry *index* (a module named in moon.mod
# is rejected as "not found in the registry" without it).  The download cache
# is not frozen: a module that is already in `.mooncakes/` is used from there,
# and anything else needs `moon update` with network access.
if [ -d "$HOME_MOON/registry/index" ]; then
  mkdir -p "$root/registry"
  cp -a "$HOME_MOON/registry/index" "$root/registry/index"
  [ -d "$HOME_MOON/registry/symbols" ] && cp -a "$HOME_MOON/registry/symbols" "$root/registry/symbols"
fi

# Record what was frozen, so a restored archive can be checked without trusting
# the file names.
{
  echo "# frozen $(date -u +%Y-%m-%dT%H:%M:%SZ) from $HOME_MOON"
  "$HOME_MOON/bin/moon" version --all
  for b in moon moonc moonrun moon-lsp moonfmt mooninfo; do
    [ -x "$root/bin/$b" ] && sha256sum "$root/bin/$b"
  done
} > "$root/MANIFEST.txt"

mkdir -p "$OUT_DIR"
tar -C "$stage" -czf "$OUT_DIR/$name.tar.gz" "$name"
( cd "$OUT_DIR" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )
ls -lh "$OUT_DIR/$name.tar.gz" "$OUT_DIR/$name.tar.gz.sha256"
