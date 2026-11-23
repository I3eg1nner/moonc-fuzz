#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
p=$(TAMPER_PIN=1 bash "$ROOT/scripts/original_config_e2e.sh" "$ROOT" 2>/dev/null | jq -r '.pin_refused // 0')
n=$(bash "$ROOT/scripts/original_config_e2e.sh" "$ROOT" 2>/dev/null)
es=$(jq -r '.expected_tamper' <<<"$n"); ns=$(jq -r '.name_tamper' <<<"$n"); bs=$(jq -r '.baseline' <<<"$n")
ok=0; [ "$p" = 1 ] && [ "$es" != confirmed ] && [ "$ns" != confirmed ] && [ "$bs" != confirmed ] && ok=1
jq -n --argjson ok "$ok" --argjson pin_refused "$p" --arg expected_tamper "$es" --arg name_tamper "$ns" --arg baseline "$bs" '{ok:$ok,pin_refused:$pin_refused,expected_tamper:$expected_tamper,name_tamper:$name_tamper,baseline:$baseline}' > /tmp/ocr_neg.json
cat /tmp/ocr_neg.json; [ "$ok" = 1 ]
