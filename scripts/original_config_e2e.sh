#!/bin/bash
# J2b: real package campaign must save the failure scene and replay from it.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT="/tmp/mbtfuzz_original_e2e_$$"; mkdir -p "$OUT"
"$BIN" --out "$OUT" --duration 5 --workers 1 \
  --pkg-seed "$ROOT/regressions/package_seeds/double" \
  --pkg-file pkgB/b.mbt \
  --pkg-argv "build --target wasm-gc" >"$OUT/fuzz.out" 2>"$OUT/fuzz.err"
W=$(find "$OUT" -type d -path '*/findings/*/original' | head -1 | xargs -r dirname)
if [ -z "$W" ] || [ ! -f "$W/original/manifest.json" ] ||
   [ ! -f "$W/original/paths.json" ] || [ ! -f "$W/original/argv.json" ] ||
   [ ! -f "$W/original/expected.json" ]; then
  jq -n '{e2e:0,reason:"missing original structured files"}'; rm -rf "$OUT"; exit 1
fi
# manifest: all listed files must match and be non-empty.
ok=1
for f in moon.mod moon.pkg source.mbt argv.txt argv.json paths.json expected.json; do
  [ -s "$W/original/$f" ] || ok=0
done
for key in moon_mod moon_pkg source argv paths expected; do
  file=$(case "$key" in moon_mod) echo moon.mod;; moon_pkg) echo moon.pkg;; source) echo source.mbt;; argv) echo argv.json;; paths) echo paths.json;; expected) echo expected.json;; esac)
  want=$(jq -r --arg k "$key" '.[$k]' "$W/original/manifest.json")
  got=$(sha1sum "$W/original/$file" | awk '{print $1}')
  [ "$want" = "$got" ] || ok=0
done
MOON=$(jq -r '.moon' "$W/capsule.json")
SRC_REL=$(jq -r '.source' "$W/original/paths.json")
MOD_REL=$(jq -r '.moon_mod' "$W/original/paths.json")
PKG_REL=$(jq -r '.moon_pkg' "$W/original/paths.json")
PIN=$(cat "$W/original/pin.json")
if [ "${TAMPER_PIN:-0}" = 1 ]; then
  printf '%s' "$PIN" | sed 's/"pin_hash":"[^"]*"/"pin_hash":"deadbeef"/' > "$W/original/pin.tamper"
  PIN=$(cat "$W/original/pin.tamper")
fi
PIN_HASH=$(jq -r '.pin_hash' <<<"$PIN")
CUR_HASH=$(printf '%s|%s' "$(moon --version 2>/dev/null)" "$(moonc -v 2>/dev/null)" | sha1sum | awk '{print $1}')
# saved pin hash is the authoritative one; if it differs, refuse replay.
PIN_REFUSED=0
if [ "$PIN_HASH" != "$CUR_HASH" ]; then PIN_REFUSED=1; fi
ENVJSON=$(cat "$W/original/env.json")
CWD=$(jq -r '.cwd' "$W/original/paths.json")
EXP_RC=$(jq -r '.rc' "$W/original/expected.json")
if [ "${TAMPER_EXPECTED:-0}" = 1 ]; then EXP_RC=0; fi
EXP_OUT=$(jq -r '.stdout' "$W/original/expected.json")
EXP_ERR=$(jq -r '.stderr' "$W/original/expected.json")
EXP_CODES=$(grep -oE 'Error: \[[0-9]+\]' <<<"$EXP_ERR" | sort -u | tr '\n' ',')
EXP_FAIL=$(grep -E 'FAILED|test .* failed' <<<"$EXP_ERR" | head -1)
mapfile -t ARGV < <(jq -r '.[]' "$W/original/argv.json")
replay() {
  local srcfile="$1" d="$2"; rm -rf "$d"; cp -r "$W/original/pkg" "$d"
  mkdir -p "$(dirname "$d/$SRC_REL")"
  cp "$srcfile" "$d/$SRC_REL"
  cp "$W/original/moon.mod" "$d/$MOD_REL" 2>/dev/null || true
  if [ -n "$PKG_REL" ]; then mkdir -p "$(dirname "$d/$PKG_REL")"; cp "$W/original/moon.pkg" "$d/$PKG_REL"; fi
  local mh pathv homev
  mh=$(jq -r '.MOON_HOME' <<<"$ENVJSON")
  pathv=$(jq -r '.PATH' <<<"$ENVJSON")
  homev=$(jq -r '.HOME // ""' <<<"$ENVJSON")
  ( cd "$d/${CWD:-.}" && timeout 60 env "MOON_HOME=$mh" "HOME=$homev" "PATH=$pathv" "$MOON" "${ARGV[@]}" ) >"$d/out" 2>"$d/err"; echo $? > "$d/rc"
}
matched=0; baseline_mismatch=0
if [ "$PIN_REFUSED" = 1 ]; then
  jq -n --argjson e2e 0 --argjson pin_refused 1 --arg reason "pin hash mismatch" '{e2e:$e2e,pin_refused:$pin_refused,reason:$reason}'
  rm -rf "$OUT"; exit 1
fi
for i in 1 2 3; do
  replay "$W/original/source.mbt" "$OUT/r$i"
  rc=$(cat "$OUT/r$i/rc")
  got_codes=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/r$i/err" | sort -u | tr '\n' ',')
  got_fail=$(grep -E 'FAILED|test .* failed' "$OUT/r$i/err" | head -1)
  if [ "$rc" = "$EXP_RC" ] && [ "$got_codes" = "$EXP_CODES" ]; then
    if [ -z "$EXP_FAIL" ] || [ "$got_fail" = "$EXP_FAIL" ]; then matched=$((matched+1)); fi
  fi
done
# Negative control: baseline source must not reproduce the failing rc.
replay "$W/baseline.mbt" "$OUT/rbase"
brc=$(cat "$OUT/rbase/rc")
bcode=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/rbase/err" | sort -u | tr '\n' ',')
if [ "$brc" != "$EXP_RC" ] || [ "$bcode" != "$EXP_CODES" ]; then baseline_mismatch=1; fi
e2e=0; [ "$ok" = 1 ] && [ "$matched" = 3 ] && [ "$baseline_mismatch" = 1 ] && e2e=1
jq -n --argjson e2e "$e2e" --argjson replayed 3 --argjson matched "$matched" \
  --argjson baseline_mismatch "$baseline_mismatch" --arg manifest_ok "$([ "$ok" = 1 ] && echo 1 || echo 0)" \
  '{e2e:$e2e,replayed:3,matched:$matched,baseline_mismatch:$baseline_mismatch,manifest_ok:$manifest_ok}'
rm -rf "$OUT"
[ "$e2e" = 1 ]
