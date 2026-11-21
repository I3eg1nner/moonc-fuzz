#!/usr/bin/env bash
# Replay package-level semantic regressions: baseline must pass, each mutant
# must fail with the recorded assertion.  These are USER-CODE semantic
# changes, not moonc defects.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REG="$ROOT/regressions/pkg_semantic"
TMP=${1:-/tmp/pkg_reg_replay}
rm -rf "$TMP"; mkdir -p "$TMP"
run() { # file expected_rc
  cp -a "$REG/pkg" "$TMP/w"; rm -rf "$TMP/w/_build"
  cp "$1" "$TMP/w/repro/repro.mbt"
  ( cd "$TMP/w" && timeout 120 moon test --target js > "$TMP/out.txt" 2>&1 ); echo $?
}
rc=$(run "$REG/baseline.mbt")
[ "$rc" = "0" ] || { echo "baseline failed rc=$rc"; cat "$TMP/out.txt"; exit 1; }
echo "baseline: pass"
n=0
for w in "$REG"/witnesses/*; do
  rc=$(run "$w/source.mbt")
  [ "$rc" != "0" ] || { echo "witness $w unexpectedly passed"; exit 1; }
  assert=$(python3 -c "import json;d=json.load(open('$REG/manifest.json'));print([x['assertion'] for x in d if x['witness']=='$(basename $w)'][0])")
  grep -qF "$assert" "$TMP/out.txt" || { echo "witness $w missing assertion: $assert"; head -3 "$TMP/out.txt"; exit 1; }
  n=$((n+1))
done
echo "replayed $n witnesses: ok"
