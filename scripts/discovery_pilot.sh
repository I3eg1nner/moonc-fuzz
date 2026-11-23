#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; OUT=/tmp/discovery_pilot_$$; mkdir -p "$OUT"
LIST="$OUT/pkgs.txt"; : > "$LIST"
for r in "$HOME/.moon/lib" "$HOME/.mooncakes" "$ROOT/poc" "$ROOT/oracle_cases" "$ROOT/regressions"; do
  [ -d "$r" ] || continue
  find "$r" -name moon.mod -type f 2>/dev/null | while read f; do
    d=$(dirname "$f"); echo "$d"
  done >> "$LIST"
done
sort -u "$LIST" -o "$LIST"; N=$(wc -l < "$LIST")
attempt=0; wfail=0; jfail=0; invalid=0; clean=0; tw=""; tj=""
while read d; do
  case "$d" in */_build/*|*/.mooncakes/*|*/witness/*) continue;; esac
  cp -r "$d" "$OUT/pkg" 2>/dev/null || continue
  rm -rf "$OUT/pkg/_build" "$OUT/pkg/.mooncakes" "$OUT/pkg/target" "$OUT/pkg/witness"
  t0=$(date +%s%N)
  ( cd "$OUT/pkg" && timeout 20 moon build --target wasm-gc ) >"$OUT/wo" 2>"$OUT/we"; wrc=$?
  t1=$(date +%s%N); [ "$wrc" = 0 ] && tw="$tw$(( (t1-t0)/1000000 ))\n"
  t2=$(date +%s%N)
  ( cd "$OUT/pkg" && timeout 20 moon build --target js ) >"$OUT/jo" 2>"$OUT/je"; jrc=$?
  t3=$(date +%s%N); [ "$jrc" = 0 ] && tj="$tj$(( (t3-t2)/1000000 ))\n"
  attempt=$((attempt+1))
  [ "$wrc" != 0 ] && wfail=$((wfail+1))
  [ "$jrc" != 0 ] && jfail=$((jfail+1))
  if grep -q 'CompileError' "$OUT/we" "$OUT/je" 2>/dev/null && grep -q 'WebAssembly.Module' "$OUT/we" "$OUT/je" 2>/dev/null; then invalid=$((invalid+1)); else clean=$((clean+1)); fi
  rm -rf "$OUT/pkg"
done < "$LIST"
printf '%b' "$tw" | sort -n > "$OUT/tw"; printf '%b' "$tj" | sort -n > "$OUT/tj"
WOK=$(wc -l < "$OUT/tw"); JOK=$(wc -l < "$OUT/tj")
WMED=$(awk 'NR==int((NR+1)/2){print}' "$OUT/tw"); JMED=$(awk 'NR==int((NR+1)/2){print}' "$OUT/tj")
jq -n --argjson N "$N" --argjson attempted "$attempt" --argjson wasm_fail "$wfail" --argjson js_fail "$jfail" --argjson webassembly_module "$invalid" --argjson wasm_ok "$WOK" --argjson js_ok "$JOK" --argjson wasm_median "$WMED" --argjson js_median "$JMED" --arg note "build scan; no witness/triage" '{N:$N,attempted:$attempted,wasm_fail:$wasm_fail,js_fail:$js_fail,webassembly_module:$webassembly_module,wasm_ok:$wasm_ok,js_ok:$js_ok,wasm_ms_median:$wasm_median,js_ms_median:$js_median,note:$note}' > "$ROOT/findings/discovery_pilot.json"
cat "$ROOT/findings/discovery_pilot.json"
