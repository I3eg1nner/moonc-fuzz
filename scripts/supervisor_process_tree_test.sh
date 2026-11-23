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
# f run.sh dryrun limits: two exact groups.
mkdir -p "$OUT/lim_small" "$OUT/lim_big"
OUT="$OUT/lim_small" DUR=10 WORKERS=2 SUPERVISOR_DRYRUN=1 "$ROOT/run.sh" hybrid 2 10 mbt >"$OUT/run_limits_s.log" 2>&1; lsrc=$?
LSLD=$(jq -r '.deadline // 0' "$OUT/lim_small/supervisor.limits" 2>/dev/null); LSMP=$(jq -r '.max_procs // 0' "$OUT/lim_small/supervisor.limits" 2>/dev/null); LSAG=$(jq -r '.agg_rss_mb // 0' "$OUT/lim_small/supervisor.limits" 2>/dev/null)
OUT="$OUT/lim_big" DUR=600 WORKERS=48 SUPERVISOR_DRYRUN=1 "$ROOT/run.sh" hybrid 48 600 mbt >"$OUT/run_limits_b.log" 2>&1; lbrc=$?
LBLD=$(jq -r '.deadline // 0' "$OUT/lim_big/supervisor.limits" 2>/dev/null); LBMP=$(jq -r '.max_procs // 0' "$OUT/lim_big/supervisor.limits" 2>/dev/null); LBAG=$(jq -r '.agg_rss_mb // 0' "$OUT/lim_big/supervisor.limits" 2>/dev/null)
# nonzero soak: max_procs=1 must be killed, CSV sup_rc=90/incomplete=1.
MAX_PROCS=1 WORKERS=1 AGG_RSS_MB=0 "$ROOT/scripts/soak_epochs.sh" "$OUT/soak_bad" 1 2 >"$OUT/soak_bad.log" 2>&1; bsrc=$?
BSLINE=$(sed -n '2p' "$OUT/soak_bad/epochs.csv" 2>/dev/null)
BSRC=$(echo "$BSLINE" | cut -d, -f9); BSINC=$(echo "$BSLINE" | cut -d, -f10); BSSTOP=$(echo "$BSLINE" | cut -d, -f8)
# e soak one 2s epoch
MAX_PROCS=0 "$ROOT/scripts/soak_epochs.sh" "$OUT/soak" 1 2 >"$OUT/soak.log" 2>&1; erc=$?
esup="$OUT/soak/e1.sup.json"
ei=$(jq -r '.rc' "$esup" 2>/dev/null); einc=$(jq -r '.incomplete' "$esup" 2>/dev/null); eagg=$(jq -r '.agg_rss_mb // 0' "$esup" 2>/dev/null)
hdr=$(head -1 "$OUT/soak/epochs.csv" 2>/dev/null)
ok=0
if [ "$arc" = 0 ] && [ "$ai" = 0 ] && [ "$ainc" = 0 ] && [ "$aor" = 0 ] &&
   [ "$brc" = 7 ] && [ "$bi" = 0 ] &&
   [ "$crc" = 90 ] && [ "$ci" = 1 ] && [ "$cre" = orphan_after_exit ] && [ "$cor" = 0 ] &&
   [ "$drc" = 0 ] && grep -q alive "$OUT/d.out" &&
   [ "$erc" = 0 ] && [ "$ei" = 0 ] && [ "$einc" = 0 ] && [ "$eagg" -gt 0 ] &&
   [ "$lsrc" = 0 ] && [ "$LSLD" = 340 ] && [ "$LSMP" = 16 ] && [ "$LSAG" -gt 0 ] &&
   [ "$lbrc" = 0 ] && [ "$LBLD" = 930 ] && [ "$LBMP" = 200 ] && [ "$LBAG" -gt 0 ] &&
   [ "$bsrc" = 0 ] && [ "$BSRC" = 90 ] && [ "$BSINC" = 1 ] && [[ "$BSSTOP" == supervisor_* ]] &&
   [[ "$hdr" == *sup_rc* && "$hdr" == *incomplete* && "$hdr" == *orphans* ]]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson a_rc "$ai" --argjson a_incomplete "$ainc" --argjson a_orphans "$aor" --argjson b_rc "$brc" --argjson b_incomplete "$bi" --argjson c_rc "$crc" --argjson c_incomplete "$ci" --arg c_reason "$cre" --argjson c_orphans "$cor" --argjson d_outer_rc "$drc" --argjson soak_rc "$ei" --argjson soak_incomplete "$einc" --argjson soak_agg "$eagg" --arg header "$hdr" --argjson run_limits_small_rc "$lsrc" --argjson limits_small_deadline "$LSLD" --argjson limits_small_max "$LSMP" --argjson limits_small_agg "$LSAG" --argjson run_limits_big_rc "$lbrc" --argjson limits_big_deadline "$LBLD" --argjson limits_big_max "$LBMP" --argjson limits_big_agg "$LBAG" --argjson soak_bad_rc "$bsrc" --arg soak_bad_sup_rc "$BSRC" --arg soak_bad_incomplete "$BSINC" --arg soak_bad_stop "$BSSTOP" '{ok:$ok,a:{rc:$a_rc,incomplete:$a_incomplete,orphans:$a_orphans},b:{rc:$b_rc,incomplete:$b_incomplete},c:{rc:$c_rc,incomplete:$c_incomplete,reason:$c_reason,orphans:$c_orphans},d_outer_rc:$d_outer_rc,soak:{rc:$soak_rc,incomplete:$soak_incomplete,agg:$soak_agg,header:$header},run_limits_small:{rc:$run_limits_small_rc,deadline:$limits_small_deadline,max_procs:$limits_small_max,agg:$limits_small_agg},run_limits_big:{rc:$run_limits_big_rc,deadline:$limits_big_deadline,max_procs:$limits_big_max,agg:$limits_big_agg},soak_bad:{rc:$soak_bad_rc,sup_rc:$soak_bad_sup_rc,incomplete:$soak_bad_incomplete,stop:$soak_bad_stop}}' > "$OUT/sum.json"
cat "$OUT/sum.json"; [ "$ok" = 1 ]
