#!/bin/bash
# H must-reject/diagnostic-precision gate.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
OUT="${2:-/tmp/must_reject_h.jsonl}"
BASE="$ROOT/regressions/must_reject_v2"
: > "$OUT"
pos=0; acc=0; wrong=0; neg=0; negbad=0; fams=0; ctl=0
families=""
for d in "$BASE"/positive/*; do
  [ -d "$d" ] || continue
  fam=$(jq -r '.family' "$d/expected.json" 2>/dev/null || echo "")
  exp=$(jq -r '.expected_codes[0]' "$d/expected.json" 2>/dev/null || echo "")
  if [ -z "$families" ]; then families="$fam"; else families="$families,$fam"; fi
  if [ -f "$d/main.mbt" ]; then
    ( cd "$d" && timeout 60 moon check main.mbt ) >/tmp/mr_o 2>/tmp/mr_e; rc=$?
  else
    ( cd "$d" && timeout 60 moon check ) >/tmp/mr_o 2>/tmp/mr_e; rc=$?
  fi
  pos=$((pos+1))
  code=$(cat /tmp/mr_e /tmp/mr_o 2>/dev/null | grep -oE 'Error: \[[0-9]{3,5}\]' | head -1 | grep -oE '[0-9]{3,5}')
  if [ "$rc" = 0 ]; then verdict=accepted; acc=$((acc+1))
  elif [ "$code" = "$exp" ]; then verdict=expected
  else verdict=wrong_diagnostic; wrong=$((wrong+1)); fi
  printf '{"case":"%s","family":"%s","expected":"%s","rc":%d,"code":"%s","verdict":"%s"}\n' "$(basename "$d")" "$fam" "$exp" "$rc" "$code" "$verdict" >> "$OUT"
done
for f in "$BASE"/negative/*.mbt; do
  neg=$((neg+1))
  ( cd "$(dirname "$f")" && timeout 60 moon check "$(basename "$f")" ) >/tmp/mr_o 2>/tmp/mr_e; rc=$?
  if [ "$rc" = 0 ]; then verdict=expected; else verdict=wrong_diagnostic; negbad=$((negbad+1)); fi
  printf '{"case":"%s","family":"negative","expected":"0","rc":%d,"code":"","verdict":"%s"}\n' "$(basename "$f")" "$rc" "$verdict" >> "$OUT"
done
( cd "$ROOT/oracle_cases/typecheck/551" && moon check ) >/tmp/mr_o 2>/tmp/mr_e; ctl=$?
# distinct families
fams=$(printf '%s' "$families" | tr ',' '\n' | sort -u | wc -l)
jq -n --argjson pos "$pos" --argjson acc "$acc" --argjson wrong "$wrong" --argjson neg "$neg" --argjson negbad "$negbad" --argjson fams "$fams" --argjson ctl "$ctl" \
 '{positives:$pos,transforms:$fams,accepted:$acc,wrong_diagnostic:$wrong,negative_controls:$neg,negative_bad:$negbad,control_rc:$ctl}' > "${OUT%.jsonl}.summary.json"
cat "${OUT%.jsonl}.summary.json"
[[ "$pos" -ge 350 && "$fams" -ge 12 && "$acc" -eq 0 && "$negbad" -eq 0 && "$ctl" -ne 0 ]]
