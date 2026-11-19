#!/usr/bin/env bash
# Prove that a frozen toolchain archive is usable, not just downloadable.
#
# Usage: scripts/verify_toolchain_archive.sh ARCHIVE
#
# Checks, in order:
#   1. the extracted binaries report the pinned versions;
#   2. moon-builds a package with no dependencies (compiler + core bundle);
#   3. moon-builds this repository (needs the registry index and `.mooncakes`).
# A failure at (1) or (2) means the archive is broken; a failure at (3) means
# dependency resolution is incomplete, which is a weaker but reportable result.
set -euo pipefail

ARCHIVE=${1:?usage: verify_toolchain_archive.sh ARCHIVE.tar.gz}
[ -f "$ARCHIVE" ] || { echo "no such archive: $ARCHIVE" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$ARCHIVE" -C "$tmp"
root=$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)
export MOON_HOME="$root"
export PATH="$root/bin:$PATH"

echo "== versions =="
moon version --all
moon version --all | grep -q "moonc v0.10.20+65efd5b93" || {
  echo "pin mismatch in archive" >&2
  exit 1
}

echo "== no-dependency package =="
mkdir -p "$tmp/tiny"
printf 'name = "repro/tiny"\nversion = "0.1.0"\n' > "$tmp/tiny/moon.mod"
printf 'pkgtype(kind: "executable")\n' > "$tmp/tiny/moon.pkg"
printf 'fn main {\n  println("ok")\n}\n' > "$tmp/tiny/main.mbt"
( cd "$tmp/tiny" && moon build --target native )
echo "tiny: ok"

repo=$(cd "$(dirname "$0")/.." && pwd)
echo "== repository build ($repo/moonbit) =="
( cd "$repo/moonbit" && moon build --target native 2>&1 | tail -2 )
echo "repo: ok"
