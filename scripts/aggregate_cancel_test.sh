#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; SUP="$ROOT/scripts/supervisor.sh"; OUT=/tmp/agg_cancel_$$; mkdir -p "$OUT"
t0=$(date +%s%N); "$SUP" --agg-rss-mb 100 --max-procs 20 --deadline 10 -- /bin/sh -c 'for i in 1 2 3 4; do python3 -c "import time; a=bytearray(120*1024*1024); time.sleep(20)" & done; wait' >"$OUT/agg" 2>/dev/null; arc=$?; t1=$(date +%s%N); agg_wall=$(( (t1-t0)/1000000 ))
"$SUP" --agg-rss-mb 1000 --max-procs 3 --deadline 10 -- /bin/sh -c 'for i in 1 2 3 4 5 6; do sleep 10 & done; wait' >"$OUT/max" 2>/dev/null; mrc=$?
t0=$(date +%s%N); "$SUP" --agg-rss-mb 1000 --max-procs 10 --deadline 2 -- sleep 10 >"$OUT/dl" 2>/dev/null; drc=$?; t1=$(date +%s%N); dl_wall=$(( (t1-t0)/1000000 ))
"$SUP" --agg-rss-mb 1000 --max-procs 5 --deadline 10 -- sleep 1 >"$OUT/neg" 2>/dev/null; nrc=$?
a=$(cat "$OUT/agg"); m=$(cat "$OUT/max"); d=$(cat "$OUT/dl"); n=$(cat "$OUT/neg")
ai=$(jq -r .incomplete <<<"$a"); ao=$(jq -r .orphans <<<"$a"); am=$(jq -r .elapsed_ms <<<"$a")
mi=$(jq -r .incomplete <<<"$m"); mo=$(jq -r .orphans <<<"$m")
di=$(jq -r .incomplete <<<"$d"); do_=$(jq -r .orphans <<<"$d"); dm=$(jq -r .elapsed_ms <<<"$d")
ni=$(jq -r .incomplete <<<"$n")
ok=0
if [ "$arc" = 90 ] && [ "$ai" = 1 ] && [ "$ao" = 0 ] && [ "$agg_wall" -lt 10000 ] && [ "$am" -le $((agg_wall+1000)) ] && [ "$agg_wall" -le $((am+1000)) ] &&
   [ "$mrc" = 90 ] && [ "$mi" = 1 ] && [ "$mo" = 0 ] &&
   [ "$drc" = 90 ] && [ "$di" = 1 ] && [ "$do_" = 0 ] && [ "$dl_wall" -ge 2000 ] && [ "$dl_wall" -le 4000 ] && [ "$dm" -le $((dl_wall+1000)) ] && [ "$dl_wall" -le $((dm+1000)) ] &&
   [ "$nrc" = 0 ] && [ "$ni" = 0 ]; then ok=1; fi
CG=$(findmnt -n -o FSTYPE,TARGET /sys/fs/cgroup 2>/dev/null | head -1); w=0; [ -w /sys/fs/cgroup ] && w=1
jq -n --argjson ok "$ok" --argjson agg_incomplete "$ai" --argjson agg_orphans "$ao" --argjson agg_ms "$am" --argjson agg_wall "$agg_wall" --argjson max_incomplete "$mi" --argjson max_orphans "$mo" --argjson deadline_ms "$dm" --argjson dl_wall "$dl_wall" --argjson negative_incomplete "$ni" --arg cgroup "$CG" --argjson cgroup_writable "$w" '{ok:$ok,agg_incomplete:$agg_incomplete,agg_orphans:$agg_orphans,agg_ms:$agg_ms,agg_wall:$agg_wall,max_incomplete:$max_incomplete,max_orphans:$max_orphans,deadline_ms:$deadline_ms,dl_wall:$dl_wall,negative_incomplete:$negative_incomplete,setsid_escape:"unsupported",cgroup_mount:$cgroup,cgroup_writable:$cgroup_writable}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
