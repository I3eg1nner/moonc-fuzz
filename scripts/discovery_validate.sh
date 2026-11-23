#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; OUT=/tmp/discovery_validate_$$; mkdir -p "$OUT"
LIST="$OUT/pkgs.txt"; : > "$LIST"
for r in "$HOME/.moon/lib" "$HOME/.mooncakes" "$ROOT/poc" "$ROOT/oracle_cases" "$ROOT/regressions"; do
  [ -d "$r" ] || continue
  find "$r" -name moon.mod -type f 2>/dev/null | while read f; do dirname "$f"; done >> "$LIST"
done
sort -u "$LIST" -o "$LIST"; N=$(wc -l < "$LIST")
: > "$OUT/metrics.jsonl"; : > "$OUT/wasm_only.txt"; : > "$OUT/codes.txt"
while read d; do
  case "$d" in */_build/*|*/.mooncakes/*|*/witness/*) continue;; esac
  rm -rf "$OUT/pkg"; cp -r "$d" "$OUT/pkg" 2>/dev/null || continue
  rm -rf "$OUT/pkg/_build" "$OUT/pkg/target" "$OUT/pkg/witness"
  rel=${d#"$ROOT"/}
  ( cd "$OUT/pkg" && timeout 30 moon build --target wasm-gc ) >"$OUT/wo" 2>"$OUT/we"; wrc=$?
  ( cd "$OUT/pkg" && timeout 30 moon build --target js ) >"$OUT/jo" 2>"$OUT/je"; jrc=$?
  warts=0; ivals=0; first=""
  if [ "$wrc" = 0 ]; then
    while read -r f; do
      [ -n "$f" ] || continue; warts=$((warts+1))
      if node -e 'const fs=require("fs"); const b=fs.readFileSync(process.argv[1]); if(!WebAssembly.validate(b)){console.error("INVALID"); process.exit(1)}' "$f" >/dev/null 2>&1; then :; else ivals=$((ivals+1)); [ -z "$first" ] && first=$(node -e 'const fs=require("fs"); const b=fs.readFileSync(process.argv[1]); WebAssembly.validate(b)' "$f" 2>&1 | head -1); fi
    done < <(find "$OUT/pkg/_build/wasm-gc" -name '*.wasm' -type f 2>/dev/null)
  fi
  ta=0; tcf=0; tjs=0; diff=0; tfer=""
  if [ "$wrc" = 0 ]; then
    ta=1
    ( cd "$OUT/pkg" && timeout 60 moon test --target wasm-gc ) >"$OUT/wto" 2>"$OUT/wte"; wtrc=$?
    ( cd "$OUT/pkg" && timeout 60 moon test --target js ) >"$OUT/jto" 2>"$OUT/jte"; jtrc=$?
    if [ "$wtrc" != 0 ] && cat "$OUT/wto" "$OUT/wte" | grep -qE 'CompileError|WebAssembly.Module|Error: \[[0-9]+\]'; then
      tcf=1; tfer=$(grep -m1 -E 'CompileError|WebAssembly.Module|Error: \[[0-9]+\]' "$OUT/wte" "$OUT/wto" | head -1)
      [ "$jtrc" = 0 ] && diff=1
    fi
  fi
  wline=$(head -1 "$OUT/we")
  bucket=""
  if [ "$wrc" != 0 ]; then
    if grep -qE 'module not found|registry|Failed to resolve|dependency' "$OUT/we"; then bucket=missing_dep
    elif grep -qE 'E3002|Parse error|unexpected token' "$OUT/we"; then bucket=old_syntax
    elif [ "$jrc" = 0 ]; then bucket=wasm_only
    else bucket=other_backend; fi
    code=$(grep -oE 'Error: \[[0-9]+\]' "$OUT/we" | head -1 | tr -d '[]' | sed 's/Error: //')
    [ -n "$code" ] && echo "$code" >> "$OUT/codes.txt"
    [ "$bucket" = wasm_only ] && echo "$rel | $(head -1 "$OUT/we")" >> "$OUT/wasm_only.txt"
  fi
  jq -nc --arg pkg "$rel" --argjson wrc "$wrc" --argjson jrc "$jrc" --arg bucket "$bucket" --argjson warts "$warts" --argjson ivals "$ivals" --arg first "$first" --argjson test_attempted "$ta" --argjson test_compile_fail "$tcf" --argjson differential "$diff" --arg wasm_first "$wline" '{pkg:$pkg,wasm_rc:$wrc,js_rc:$jrc,bucket:$bucket,wasm_artifacts:$warts,invalid_artifacts:$ivals,first_invalid:$first,test_attempted:$test_attempted,test_compile_fail:$test_compile_fail,differential:$differential}' >> "$OUT/metrics.jsonl"
done < "$LIST"
jq -s --argjson N "$N" '
 def s(f): map(select(f))|length;
 {N:$N,
  pkgs_wasm_ok:s(.wasm_rc==0),
  wasm_artifacts:(map(.wasm_artifacts)|add//0),
  invalid_artifacts:(map(.invalid_artifacts)|add//0),
  invalid_packages:[.[]|select(.invalid_artifacts>0)|{pkg,first_invalid}],
  test_attempted:s(.test_attempted==1),
  test_compile_fail:s(.test_compile_fail==1),
  differential:s(.differential==1),
  differential_packages:[.[]|select(.differential==1)|.pkg],
  buckets:(map(select(.bucket!=""))|group_by(.bucket)|map({key:.[0].bucket,value:length})|from_entries),
  wasm_only:[.[]|select(.bucket=="wasm_only")|{pkg,first:(.wasm_first//"")}],
  error_codes:($codes|from_entries)}' "$OUT/metrics.jsonl" --argjson codes "$(awk '{print "{\"key\":\""$0"\",\"value\":1}"}' "$OUT/codes.txt" 2>/dev/null | jq -s 'group_by(.key)|map({key:.[0].key,value:length})' 2>/dev/null || echo '[]')" > "$ROOT/findings/discovery_validate.json"
# bucket by reading jq? already; list wasm-only from file
cp "$OUT/wasm_only.txt" "$ROOT/findings/discovery_wasm_only.txt"
cat "$ROOT/findings/discovery_validate.json"; rm -rf "$OUT"
