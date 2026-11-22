#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; OUT="${2:-/tmp/attribute.jsonl}"
BASE="$ROOT/regressions/attributes"; : > "$OUT"
cases=0; expected=0; missing=0; extra=0; fams=""
for d in "$BASE"/*; do
 [ -d "$d" ] || continue; cases=$((cases+1))
 ( cd "$d" && timeout 60 moon check main.mbt ) >/tmp/at_o 2>/tmp/at_e; rc=$?
 codes=$(cat /tmp/at_e /tmp/at_o 2>/dev/null | grep -oE '(Warning|Error): \[[0-9]{3,5}\]' | grep -oE '[0-9]{3,5}' | sort -u | tr '\n' ',' | sed 's/,$//')
 exp=$(jq -r '.expected_codes|join(",")' "$d/expected.json")
 fam=$(jq -r '.family // ""' "$d/expected.json"); if [ -z "$fams" ]; then fams="$fam"; else fams="$fams,$fam"; fi
 verdict=expected
 if [ -n "$exp" ]; then
   for c in ${exp//,/ }; do if ! grep -q "$c" <<<"$codes"; then verdict=missing_warning; fi; done
 fi
 if [ -z "$exp" ] && [ -n "$codes" ]; then verdict=extra_warning; fi
 case "$verdict" in expected) expected=$((expected+1));; missing_warning) missing=$((missing+1));; extra_warning) extra=$((extra+1));; esac
 printf '{"case":"%s","rc":%d,"codes":"%s","expected":"%s","verdict":"%s"}\n' "$(basename "$d")" "$rc" "$codes" "$exp" "$verdict" >> "$OUT"
done
nf=$(printf '%s' "$fams" | tr ',' '\n' | sort -u | wc -l)
jq -n --argjson cases "$cases" --argjson families "$nf" --argjson expected "$expected" --argjson missing "$missing" --argjson extra "$extra" '{cases:$cases,families:$families,expected:$expected,missing_warning:$missing,extra_warning:$extra}' > "${OUT%.jsonl}.summary.json"
cat "${OUT%.jsonl}.summary.json"
nf=$(printf '%s' "$fams" | tr ',' '\n' | sort -u | wc -l)
[[ "$cases" -ge 160 && "$nf" -ge 8 ]]
