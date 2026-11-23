#!/bin/bash
# J2b: real package campaign must save original/ and replay 3/3.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT="/tmp/mbtfuzz_original_e2e_$$"; mkdir -p "$OUT"
"$BIN" --out "$OUT" --duration 5 --workers 1 \
  --pkg-seed "$ROOT/regressions/pkg_semantic/f8_30/pkg" \
  --pkg-file repro/repro.mbt \
  --pkg-argv "test --target js --build-only" >"$OUT/fuzz.out" 2>"$OUT/fuzz.err"
W=$(find "$OUT" -type d -path '*/findings/*/original' | head -1 | xargs -r dirname)
if [ -z "$W" ] || [ ! -f "$W/original/moon.mod" ] || [ ! -f "$W/original/moon.pkg" ] \
  || [ ! -f "$W/original/source.mbt" ] || [ ! -f "$W/original/argv.txt" ] \
  || [ ! -f "$W/original/manifest.json" ]; then
  jq -n '{e2e:0,reason:"missing original files"}'; rm -rf "$OUT"; exit 1
fi
# Manifest sha1 check.
ok=1
for f in moon.mod moon.pkg source.mbt argv.txt; do
  want=$(jq -r --arg f "$f" '.[$f]' "$W/original/manifest.json")
  got=$(sha1sum "$W/original/$f" | awk '{print $1}')
  [ "$want" = "$got" ] || ok=0
done
# Replay snapshot 3x in fresh dirs.
matched=0; first=""
for i in 1 2 3; do
  d="$OUT/r$i"; rm -rf "$d"; cp -r "$W/pkg" "$d"
  cp "$W/original/source.mbt" "$d/repro/repro.mbt"
  ( cd "$d" && timeout 60 moon test --target js --build-only ) >"$d/out" 2>"$d/err"; rc=$?
  sig=$(grep -F 'Assertion failed' "$d/err" | head -1)
  if [ -z "$first" ]; then first="$rc|$sig"; fi
  [ "$rc|$sig" = "$first" ] && matched=$((matched+1))
done
jq -n --argjson e2e "$([ "$ok" = 1 ] && [ "$matched" = 3 ] && echo 1 || echo 0)" \
  --argjson matched "$matched" --arg witness "$W" \
  '{e2e:$e2e,replayed:3,matched:$matched,witness:$witness}'
rm -rf "$OUT"
[ "$ok" = 1 ] && [ "$matched" = 3 ]
