#!/bin/bash
set -uo pipefail
SCRATCH="${1:?scratch}"; OUT=/tmp/discovery_g3_$$; mkdir -p "$OUT"; : > "$OUT/m.jsonl"; total=0
for d in $(find "$SCRATCH/.mooncakes" -name moon.mod -type f | xargs -n1 dirname | sort); do
  src=$(find "$d" -name '*.mbt' -type f | head -1); [ -n "$src" ] || continue
  cp "$src" "$OUT/backup.mbt"
  for i in $(seq 1 10); do
    [ "$total" -ge 300 ] && break 2
    cp "$OUT/backup.mbt" "$src"
    case $((i%6)) in
      0) perl -0777 -pi -e 's/Int/Int64/ if !$done++' "$src" ;;
      1) perl -0777 -pi -e 's/0/1/ if !$done++' "$src" ;;
      2) perl -0777 -pi -e 's/1/2/ if !$done++' "$src" ;;
      3) perl -0777 -pi -e 's/true/false/ if !$done++' "$src" ;;
      4) perl -0777 -pi -e 's/Float/Double/ if !$done++' "$src" ;;
      5) perl -0777 -pi -e 's/\+/-/ if !$done++' "$src" ;;
    esac
    rm -rf "$d/_build"
    ( cd "$d" && timeout 30 moon build --target wasm-gc ) >"$OUT/wo" 2>"$OUT/we"; wrc=$?
    ( cd "$d" && timeout 30 moon build --target js ) >"$OUT/jo" 2>"$OUT/je"; jrc=$?
    wc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/we"|head -1); jc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/je"|head -1)
    total=$((total+1))
    jq -nc --arg pkg "$d" --argjson i "$i" --argjson wrc "$wrc" --argjson jrc "$jrc" --arg wc "$wc" --arg jc "$jc" --arg first "$(head -1 "$OUT/we")" '{pkg:$pkg,idx:$i,wasm_rc:$wrc,js_rc:$jrc,wasm_code:$wc,js_code:$jc,first:$first}' >> "$OUT/m.jsonl"
  done
  cp "$OUT/backup.mbt" "$src"; rm -rf "$d/_build"
done
jq -s --argjson total "$total" '
{mutants:$total,build_ok:([.[]|select(.wasm_rc==0 and .js_rc==0)]|length),
 wasm_only:([.[]|select(.wasm_rc!=0 and .js_rc==0)]|length),
 js_only:([.[]|select(.wasm_rc==0 and .js_rc!=0)]|length),
 both_fail:([.[]|select(.wasm_rc!=0 and .js_rc!=0)]|length),
 different_codes:([.[]|select(.wasm_rc!=0 and .js_rc!=0 and .wasm_code!=.js_code)]|length),
 diff:[.[]|select((.wasm_rc!=0 and .js_rc==0) or (.wasm_rc==0 and .js_rc!=0))|{pkg,idx,wasm_code,js_code,first}]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_g_mutants.json
cat /data/audit/mbtfuzz/findings/discovery_g_mutants.json; rm -rf "$OUT"
