#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
p=$(TAMPER_PIN=1 bash "$ROOT/scripts/original_config_e2e.sh" "$ROOT" 2>/dev/null | jq -r '.pin_refused // 0')
e=$(TAMPER_EXPECTED=1 bash "$ROOT/scripts/original_config_e2e.sh" "$ROOT" 2>/dev/null | jq -r '.e2e // 0')
ok=0; [ "$p" = 1 ] && [ "$e" = 0 ] && ok=1
jq -n --argjson ok "$ok" --argjson pin_refused "$p" --argjson expected_mismatch "$e" '{ok:$ok,pin_refused:$pin_refused,expected_e2e:$expected_mismatch}' > /tmp/ocr_neg.json
cat /tmp/ocr_neg.json; [ "$ok" = 1 ]
