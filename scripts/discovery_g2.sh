#!/bin/bash
set -uo pipefail
SCRATCH="${1:?scratch}"; OUT=/tmp/discovery_g2_$$; mkdir -p "$OUT"; : > "$OUT/m.jsonl"
find "$SCRATCH/.mooncakes" -name moon.mod -type f | sort | head -"${LIMIT:-150}" > "$OUT/list"
N=$(wc -l < "$OUT/list"); attempt=0; both=0; wonly=0; jonly=0; diffc=0; inval=0; ta=0; tcf=0; diff=0
while read f; do
  d=$(dirname "$f"); rm -rf "$d/_build"
  ( cd "$d" && timeout 30 moon build --target wasm-gc ) >"$OUT/wo" 2>"$OUT/we"; wrc=$?
  ( cd "$d" && timeout 30 moon build --target js ) >"$OUT/jo" 2>"$OUT/je"; jrc=$?
  attempt=$((attempt+1)); [ "$wrc" = 0 ] && [ "$jrc" = 0 ] && both=$((both+1))
  [ "$wrc" != 0 ] && [ "$jrc" = 0 ] && wonly=$((wonly+1))
  [ "$wrc" = 0 ] && [ "$jrc" != 0 ] && jonly=$((jonly+1))
  wc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/we"|head -1); jc=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/je"|head -1); [ "$wc" != "$jc" ] && diffc=$((diffc+1))
  iv=0; wa=0
  if [ "$wrc" = 0 ]; then
    while read -r wasm; do [ -n "$wasm" ] || continue; wa=$((wa+1)); node -e 'const fs=require("fs");if(!WebAssembly.validate(fs.readFileSync(process.argv[1])))process.exit(1)' "$wasm" >/dev/null 2>&1 || iv=$((iv+1)); done < <(find "$d/_build/wasm-gc" -name '*.wasm' -type f 2>/dev/null)
    if find "$d" -name '*_test.mbt' -print -quit | grep -q .; then
      ta=$((ta+1)); (cd "$d" && timeout 60 moon test --target wasm-gc) >"$OUT/wto" 2>"$OUT/wte"; wtrc=$?; (cd "$d" && timeout 60 moon test --target js) >"$OUT/jto" 2>"$OUT/jte"; jtrc=$?
      if [ "$wtrc" != 0 ] && cat "$OUT/wto" "$OUT/wte"|grep -qE 'CompileError|WebAssembly.Module|Error: \[[0-9]+\]'; then tcf=$((tcf+1)); [ "$jtrc" = 0 ] && diff=$((diff+1)); fi
    fi
  fi
  inval=$((inval+iv)); rel=${d#"$SCRATCH/"}
  jq -nc --arg pkg "$rel" --argjson wrc "$wrc" --argjson jrc "$jrc" --arg wcode "$wc" --arg jcode "$jc" --argjson artifacts "$wa" --argjson invalid "$iv" --arg first "$(head -1 "$OUT/we")" '{pkg:$pkg,wasm_rc:$wrc,js_rc:$jrc,wasm_code:$wcode,js_code:$jcode,artifacts:$artifacts,invalids:$invalid,first:$first}' >> "$OUT/m.jsonl"
done < "$OUT/list"
jq -s --argjson N "$N" --argjson attempted "$attempt" --argjson both "$both" --argjson wonly "$wonly" --argjson jonly "$jonly" --argjson diffc "$diffc" --argjson inval "$inval" --argjson ta "$ta" --argjson tcf "$tcf" --argjson diff "$diff" '
{modules:$N,attempted:$attempted,buildable_both:$both,wasm_only:$wonly,js_only:$jonly,different_codes:$diffc,invalid_artifact:$inval,test_attempted:$ta,test_compile_fail:$tcf,differential:$diff,
 wasm_only_pkgs:[.[]|select(.wasm_rc!=0 and .js_rc==0)|{pkg,first}],
 js_only_pkgs:[.[]|select(.wasm_rc==0 and .js_rc!=0)|{pkg,first}],
 invalid_pkgs:[.[]|select(.invalids>0)|.pkg]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_g.json
cat /data/audit/mbtfuzz/findings/discovery_g.json; rm -rf "$OUT"
