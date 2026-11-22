#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; OUT="${2:-/tmp/attribute.jsonl}"
BASE="$ROOT/regressions/attributes"; : > "$OUT"
cases=0; expected=0; missing=0; extra=0
for d in "$BASE"/*; do
 [ -d "$d" ] || continue; cases=$((cases+1))
 ( cd "$d" && timeout 60 moon check main.mbt ) >/tmp/at_o 2>/tmp/at_e; rc=$?
 codes=$(grep -oE 'Warning: \[[0-9]{3,5}\]' /tmp/at_e /tmp/at_o 2>/dev/null | grep -oE '[0-9]{3,5}' | sort -u | tr '\n' ',' | sed 's/,$//')
 exp=$(jq -r '.expected_codes|join(",")' "$d/expected.json")
 verdict=expected
 if [ -n "$exp" ]; then
   for c in ${exp//,/ }; do if ! grep -q "$c" <<<"$codes"; then verdict=missing_warning; fi; done
 fi
 if [ -z "$exp" ] && [ -n "$codes" ]; then verdict=extra_warning; fi
 case "$verdict" in expected) expected=$((expected+1));; missing_warning) missing=$((missing+1));; extra_warning) extra=$((extra+1));; esac
 printf '{"case":"%s","rc":%d,"codes":"%s","expected":"%s","verdict":"%s"}\n' "$(basename "$d")" "$rc" "$codes" "$exp" "$verdict" >> "$OUT"
done
jq -n --argjson cases "$cases" --argjson expected "$expected" --argjson missing "$missing" --argjson extra "$extra" '{cases:$cases,expected:$expected,missing_warning:$missing,extra_warning:$extra}' > "${OUT%.jsonl}.summary.json"
cat "${OUT%.jsonl}.summary.json"
[[ "$cases" -ge 100 ]]
