#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
OUT="${2:-/tmp/must_reject.jsonl}"
CASE="$ROOT/regressions/must_reject"
: > "$OUT"
acc=0; rej=0; neg_bad=0; pos=0; neg=0
for f in "$CASE"/positive/*.mbt; do
  pos=$((pos+1))
  ( cd "$(dirname "$f")" && timeout 60 moon check "$(basename "$f")" ) >/tmp/mr_o 2>/tmp/mr_e
  rc=$?
  if [ "$rc" = 0 ]; then
    acc=$((acc+1)); verdict=accepted
  else
    rej=$((rej+1)); verdict=rejected
  fi
  printf '{"file":"%s","class":"positive","rc":%d,"verdict":"%s"}\n' "$(basename "$f")" "$rc" "$verdict" >> "$OUT"
done
for f in "$CASE"/negative/*.mbt; do
  neg=$((neg+1))
  ( cd "$(dirname "$f")" && timeout 60 moon check "$(basename "$f")" ) >/tmp/mr_o 2>/tmp/mr_e
  rc=$?
  if [ "$rc" = 0 ]; then
    verdict=expected
  else
    neg_bad=$((neg_bad+1)); verdict=wrong_diagnostic
  fi
  printf '{"file":"%s","class":"negative","rc":%d,"verdict":"%s"}\n' "$(basename "$f")" "$rc" "$verdict" >> "$OUT"
done
# Positive control: missing trait import must be rejected (from 551 package)
( cd "$ROOT/oracle_cases/typecheck/551" && moon check ) >/tmp/mr_o 2>/tmp/mr_e
ctl=$?
printf '{"file":"control_missing_trait_import","class":"control","rc":%d,"verdict":"%s"}\n' "$ctl" "$([ "$ctl" != 0 ] && echo rejected || echo accepted)" >> "$OUT"
jq -n --argjson pos "$pos" --argjson rejected "$rej" --argjson accepted "$acc" --argjson neg "$neg" --argjson neg_bad "$neg_bad" --argjson control_rc "$ctl" \
 '{positives:$pos,rejected:$rejected,accepted:$accepted,negative_controls:$neg,negative_bad:$neg_bad,control_rc:$control_rc}' > "${OUT%.jsonl}.summary.json"
cat "${OUT%.jsonl}.summary.json"
[[ "$acc" -eq 0 && "$neg_bad" -eq 0 && "$ctl" -ne 0 && "$pos" -ge 100 ]]
