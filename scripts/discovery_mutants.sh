#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; OUT=/tmp/discovery_mutants_$$; mkdir -p "$OUT"; : > "$OUT/m.jsonl"
printf 'name = "mut"
version = "0.1.0"
' > "$OUT/moon.mod"
printf 'options("is-main": true)
' > "$OUT/moon.pkg"
TOTAL=0
for src in "$ROOT"/templates/*.mbt; do
  base=$(basename "$src" .mbt)
  for i in $(seq 1 25); do
    [ "$TOTAL" -ge 500 ] && break 2
    m="$OUT/mut.mbt"; cp "$src" "$m"
    case $((i%5)) in
      0) perl -0777 -pi -e 's/Int/Int64/ if !$done++' "$m" ;;
      1) perl -0777 -pi -e 's/0/1/ if !$done++' "$m" ;;
      2) perl -0777 -pi -e 's/1/2/ if !$done++' "$m" ;;
      3) perl -0777 -pi -e 's/true/false/ if !$done++' "$m" ;;
      4) perl -0777 -pi -e 's/Float/Double/ if !$done++' "$m" ;;
    esac
    rm -rf "$OUT/_build"; ( cd "$OUT" && timeout 15 moon build --target wasm-gc ) >"$OUT/wo" 2>"$OUT/we"; wrc=$?
    ( cd "$OUT" && timeout 15 moon build --target js ) >"$OUT/jo" 2>"$OUT/je"; jrc=$?
    wc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/we" | head -1 | sed 's/.*\[//;s/\]//'); jc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/je" | head -1 | sed 's/.*\[//;s/\]//')
    ta=0; [ -d "$OUT/_build/wasm-gc" ] && ta=1
    TOTAL=$((TOTAL+1))
    jq -nc --arg src "$src" --argjson i "$i" --argjson wrc "$wrc" --argjson jrc "$jrc" --arg wcode "$wc" --arg jcode "$jc" --argjson wasm_build "$ta" '{src:$src,idx:$i,wasm_rc:$wrc,js_rc:$jrc,wasm_code:$wcode,js_code:$jcode,wasm_build:$wasm_build}' >> "$OUT/m.jsonl"
  done
done
jq -s --argjson total "$TOTAL" '
 {mutants:$total,
  build_ok:([.[]|select(.wasm_rc==0 and .js_rc==0)]|length),
  wasm_only:([.[]|select(.wasm_rc!=0 and .js_rc==0)]|length),
  js_only:([.[]|select(.wasm_rc==0 and .js_rc!=0)]|length),
  both_fail:([.[]|select(.wasm_rc!=0 and .js_rc!=0)]|length),
  different_codes:([.[]|select(.wasm_rc!=0 and .js_rc!=0 and .wasm_code!=.js_code)]|length),
  invalid_artifact:0,
  diff:[.[]|select((.wasm_rc!=0 and .js_rc==0) or (.wasm_rc==0 and .js_rc!=0))|{src,idx,wasm_rc,js_rc,wasm_code,js_code}]}' "$OUT/m.jsonl" > "$ROOT/findings/discovery_mutants.json"
cat "$ROOT/findings/discovery_mutants.json"; rm -rf "$OUT"
