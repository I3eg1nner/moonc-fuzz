#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
SUP="$ROOT/scripts/supervisor.sh"
OUT=/tmp/agg_cancel_$$; mkdir -p "$OUT"
# Positive: 4 workers allocate 120 MiB each; aggregate cap 100 MiB must kill.
"$SUP" --agg-rss-mb 100 --max-procs 20 --deadline 10 -- \
  /bin/sh -c 'for i in 1 2 3 4; do python3 -c "import time; a=bytearray(120*1024*1024); time.sleep(20)" & done; wait' >"$OUT/pos.json" 2>"$OUT/pos.err"
prc=$?
pos=$(cat "$OUT/pos.json")
inc=$(jq -r '.incomplete' <<<"$pos"); orph=$(jq -r '.orphans' <<<"$pos"); ms=$(jq -r '.elapsed_ms' <<<"$pos")
# Negative: one small worker must finish normally.
"$SUP" --agg-rss-mb 1000 --max-procs 5 --deadline 10 -- /bin/sh -c 'sleep 1' >"$OUT/neg.json" 2>"$OUT/neg.err"
nrc=$?
neg=$(cat "$OUT/neg.json"); ninc=$(jq -r '.incomplete' <<<"$neg")
# cgroup evidence: report mount and writability, never claim if read-only.
CG=$(findmnt -n -o FSTYPE,TARGET /sys/fs/cgroup 2>/dev/null | head -1)
writable=0; [ -w /sys/fs/cgroup ] && writable=1
ok=0
if [ "$prc" = 42 ] && [ "$inc" = 1 ] && [ "$orph" = 0 ] && [ "$ms" -lt 10000 ] && [ "$nrc" = 0 ] && [ "$ninc" = 0 ]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson positive_incomplete "$inc" --argjson orphans "$orph" --argjson killed_ms "$ms" --argjson negative_incomplete "$ninc" --arg cgroup "$CG" --argjson cgroup_writable "$writable" \
  '{ok:$ok,positive_incomplete:$positive_incomplete,positive_orphans:$orphans,positive_killed_ms:$killed_ms,negative_incomplete:$negative_incomplete,cgroup_mount:$cgroup,cgroup_writable:$cgroup_writable}' > "$OUT/summary.json"
cat "$OUT/summary.json"
rm -rf "$OUT"
[ "$ok" = 1 ]
