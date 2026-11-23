#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; SUP="$ROOT/scripts/supervisor.sh"; OUT=/tmp/sup_tree_$$; mkdir -p "$OUT"
# a clean
"$SUP" --json-out "$OUT/a.json" -- /bin/sh -c 'sleep 0.2' >/dev/null 2>&1; arc=$?
ai=$(jq -r '.rc' "$OUT/a.json"); ainc=$(jq -r '.incomplete' "$OUT/a.json"); aor=$(jq -r '.orphans' "$OUT/a.json")
# b exit 7
"$SUP" --json-out "$OUT/b.json" -- /bin/sh -c 'exit 7' >/dev/null 2>&1; brc=$?
bi=$(jq -r '.incomplete' "$OUT/b.json")
# c leader exits with child
"$SUP" --json-out "$OUT/c.json" -- /bin/sh -c 'sleep 3 & exit 0' >/dev/null 2>&1; crc=$?
ci=$(jq -r '.incomplete' "$OUT/c.json"); cre=$(jq -r '.reason' "$OUT/c.json"); cor=$(jq -r '.orphans' "$OUT/c.json")
# d outer shell survives
bash -c "'$SUP' --json-out '$OUT/d.json' -- /bin/sh -c 'sleep 0.2' >/dev/null 2>&1; echo alive" >"$OUT/d.out" 2>&1; drc=$?
# f run.sh dryrun limits must scale with DUR/WORKERS.
OUT_LIM="$OUT/limits"; mkdir -p "$OUT_LIM"
OUT="$OUT_LIM" DUR=600 WORKERS=48 SUPERVISOR_DRYRUN=1 "$ROOT/run.sh" hybrid 48 600 mbt >"$OUT/run_limits.log" 2>&1; lrc=$?
LJ=$(cat "$OUT_LIM/supervisor.limits" 2>/dev/null || echo '{}')
LDL=$(jq -r '.deadline // 0' <<<"$LJ"); LMP=$(jq -r '.max_procs // 0' <<<"$LJ")
# e soak one 2s epoch
MAX_PROCS=0 AGG_RSS_MB=0 "$ROOT/scripts/soak_epochs.sh" "$OUT/soak" 1 2 >"$OUT/soak.log" 2>&1; erc=$?
esup="$OUT/soak/e1.sup.json"
ei=$(jq -r '.rc' "$esup" 2>/dev/null); einc=$(jq -r '.incomplete' "$esup" 2>/dev/null)
hdr=$(head -1 "$OUT/soak/epochs.csv" 2>/dev/null)
ok=0
if [ "$arc" = 0 ] && [ "$ai" = 0 ] && [ "$ainc" = 0 ] && [ "$aor" = 0 ] &&
   [ "$brc" = 7 ] && [ "$bi" = 0 ] &&
   [ "$crc" = 90 ] && [ "$ci" = 1 ] && [ "$cre" = orphan_after_exit ] && [ "$cor" = 0 ] &&
   [ "$drc" = 0 ] && grep -q alive "$OUT/d.out" &&
   [ "$erc" = 0 ] && [ "$ei" = 0 ] && [ "$einc" = 0 ] &&
   [ "$lrc" = 0 ] && [ "$LDL" -ge 600 ] && [ "$LMP" -ge 48 ] &&
   [[ "$hdr" == *sup_rc* && "$hdr" == *incomplete* && "$hdr" == *orphans* ]]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson a_rc "$ai" --argjson a_incomplete "$ainc" --argjson a_orphans "$aor" --argjson b_rc "$brc" --argjson b_incomplete "$bi" --argjson c_rc "$crc" --argjson c_incomplete "$ci" --arg c_reason "$cre" --argjson c_orphans "$cor" --argjson d_outer_rc "$drc" --argjson soak_rc "$ei" --argjson soak_incomplete "$einc" --arg header "$hdr" --argjson run_limits_rc "$lrc" --argjson limits_deadline "$LDL" --argjson limits_max_procs "$LMP" '{ok:$ok,a:{rc:$a_rc,incomplete:$a_incomplete,orphans:$a_orphans},b:{rc:$b_rc,incomplete:$b_incomplete},c:{rc:$c_rc,incomplete:$c_incomplete,reason:$c_reason,orphans:$c_orphans},d_outer_rc:$d_outer_rc,soak:{rc:$soak_rc,incomplete:$soak_incomplete,header:$header},run_limits:{rc:$run_limits_rc,deadline:$limits_deadline,max_procs:$limits_max_procs}}' > "$OUT/sum.json"
cat "$OUT/sum.json"; [ "$ok" = 1 ]
