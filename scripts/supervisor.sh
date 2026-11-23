#!/bin/bash
# Portable process-group resource supervisor.
set -uo pipefail
agg=0; maxp=0; deadline=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agg-rss-mb) agg="$2"; shift 2 ;;
    --max-procs) maxp="$2"; shift 2 ;;
    --deadline) deadline="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo '{"incomplete":0,"error":"no command"}'; exit 2; }
setsid "$@" >/tmp/sup_out 2>/tmp/sup_err &
pid=$!
pgid=$pid
start=$(date +%s%N)
incomplete=0; reason=""
while kill -0 "$pid" 2>/dev/null; do
  sleep 0.5
  now=$(date +%s%N); elapsed_ms=$(( (now-start)/1000000 ))
  rss=$(ps -o rss= -g "$pgid" 2>/dev/null | awk '{s+=$1} END{print s+0}')
  procs=$(ps -o pid= -g "$pgid" 2>/dev/null | wc -l)
  if [ "$agg" -gt 0 ] && [ "$rss" -gt $((agg*1024)) ]; then incomplete=1; reason="agg_rss"; break; fi
  if [ "$maxp" -gt 0 ] && [ "$procs" -gt "$maxp" ]; then incomplete=1; reason="max_procs"; break; fi
  if [ "$deadline" -gt 0 ] && [ "$elapsed_ms" -gt $((deadline*1000)) ]; then incomplete=1; reason="deadline"; break; fi
done
if [ "$incomplete" = 1 ]; then
  kill -TERM -"$pgid" 2>/dev/null || true
  sleep 2
  kill -KILL -"$pgid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  sleep 0.5
fi
orphans=$(ps -o pid= -g "$pgid" 2>/dev/null | wc -l)
if [ "$incomplete" = 1 ]; then
  jq -n --argjson incomplete 1 --arg reason "$reason" --argjson orphans "$orphans" --argjson rss_kb "$rss" --argjson procs "$procs" --argjson elapsed_ms "$elapsed_ms" \
    '{incomplete:$incomplete,reason:$reason,orphans:$orphans,rss_kb:$rss_kb,procs:$procs,elapsed_ms:$elapsed_ms}'
  exit 42
else
  jq -n --argjson incomplete 0 --argjson orphans "$orphans" --argjson rss_kb "$rss" --argjson procs "$procs" --argjson elapsed_ms "$elapsed_ms" \
    '{incomplete:$incomplete,orphans:$orphans,rss_kb:$rss_kb,procs:$procs,elapsed_ms:$elapsed_ms}'
fi
