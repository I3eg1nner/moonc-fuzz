#!/bin/bash
# P0-4 e2e: delegate TEST_FAIL replay to triage, never reimplement its compare.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
W="$ROOT/regressions/pkg_test_fail/witness"
OUT=/tmp/original_e2e_$$; mkdir -p "$OUT"
PIN=$(cat "$W/original/pin.json")
if [ "${TAMPER_PIN:-0}" = 1 ]; then
  printf '%s' "$PIN" | sed 's/"pin_hash": *"[^"]*"/"pin_hash":"deadbeef"/' > "$OUT/pin.tamper"
  PIN=$(cat "$OUT/pin.tamper")
fi
PIN_HASH=$(jq -r '.pin_hash' <<<"$PIN")
CUR_HASH=$(printf '%s|%s' "$(moon --version 2>/dev/null)" "$(moonc -v 2>/dev/null)" | sha1sum | awk '{print $1}')
if [ "$PIN_HASH" != "$CUR_HASH" ]; then
  jq -n '{e2e:0,pin_refused:1,reason:"pin hash mismatch"}'; exit 1
fi
TR=$(bash "$ROOT/scripts/test_fail_triage_test.sh" "$ROOT")
ok=$(jq -r '.ok' <<<"$TR"); st=$(jq -r '.normal_status' <<<"$TR"); rp=$(jq -r '.normal_reproduced' <<<"$TR")
sg=$(jq -r '.normal_signature' <<<"$TR"); es=$(jq -r '.expected_tamper_status' <<<"$TR"); ns=$(jq -r '.name_tamper_status' <<<"$TR"); bs=$(jq -r '.baseline_status' <<<"$TR")
e2e=0; [ "$ok" = 1 ] && [ "$st" = confirmed ] && [ "$rp" = "3/3" ] && e2e=1
jq -n --argjson e2e "$e2e" --arg stage "test" --arg status "$st" --arg reproduced "$rp" --arg signature "$sg" --arg expected_tamper "$es" --arg name_tamper "$ns" --arg baseline "$bs" '{e2e:$e2e,stage:$stage,status:$status,reproduced:$reproduced,signature:$signature,expected_tamper:$expected_tamper,name_tamper:$name_tamper,baseline:$baseline}' > "$OUT/summary.json"
cat "$OUT/summary.json"; rm -rf "$OUT"; [ "$e2e" = 1 ]
