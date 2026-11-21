#!/usr/bin/env bash
# Replay package-level semantic regressions: baseline passes, each mutant
# fails with the recorded assertion.  USER-CODE changes, not moonc defects.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REG="$ROOT/regressions/pkg_semantic"
TMP=${1:-/tmp/pkg_reg_replay}
rm -rf "$TMP"; mkdir -p "$TMP"
total=0
for pkgname in f8_30 ldif_30; do
  dir="$REG/$pkgname"
  [ -d "$dir" ] || continue
  file=$(python3 -c "import json;print(json.load(open('$REG/packages.json'))['$pkgname']['file'])")
  argv=$(python3 -c "import json;print(json.load(open('$REG/packages.json'))['$pkgname']['test_argv'])")
  run() {
    rm -rf "$TMP/w"; cp -a "$dir/pkg" "$TMP/w"; rm -rf "$TMP/w/_build"
    cp "$1" "$TMP/w/$file"
    ( cd "$TMP/w" && timeout 180 moon $argv > "$TMP/out.txt" 2>&1 ); echo $?
  }
  rc=$(run "$dir/baseline.mbt")
  [ "$rc" = "0" ] || { echo "$pkgname baseline failed rc=$rc"; tail -3 "$TMP/out.txt"; exit 1; }
  echo "$pkgname baseline: pass"
  for w in "$dir"/witnesses/*; do
    rc=$(run "$w/source.mbt")
    [ "$rc" != "0" ] || { echo "$pkgname/$w unexpectedly passed"; exit 1; }
    assert=$(python3 -c "import json;print([x['assertion'] for x in json.load(open('$dir/manifest.json')) if x['witness']=='$(basename $w)'][0])")
    grep -qF -- "$assert" "$TMP/out.txt" || { echo "$pkgname/$w missing assertion"; head -2 "$TMP/out.txt"; exit 1; }
    total=$((total+1))
  done
done
echo "replayed $total witnesses: ok"
