#!/bin/bash
# Portable process-group supervisor (safe subset: exit rc, deadline, max-procs,
# RSS; setsid escape is explicitly unsupported and reported).
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
[ $# -gt 0 ] || { echo '{"incomplete":1,"error":"no command","leader_rc":2,"orphans":0,"escaped":0}'; exit 2; }
setsid "$@" >/tmp/sup_out 2>/tmp/sup_err &
pid=$!; pgid=$pid
caller_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
caller_sid=$(ps -o sid= -p $$ 2>/dev/null | tr -d ' ')
guard_pgid() {
  case "$pgid" in ''|0|*[!0-9]*) return 1 ;; esac
  [ "$pgid" != "$caller_pgid" ] && [ "$pgid" != "$caller_sid" ]
}
safe_kill() {
  local sig="$1"
  guard_pgid || { echo REFUSE_KILL >&2; return 3; }
  kill -"$sig" -"$pgid" 2>/dev/null || true
}
start=$(date +%s%N); incomplete=0; reason=""; rss=0; procs=0; elapsed_ms=0; leader_rc=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 0.5
  now=$(date +%s%N); elapsed_ms=$(( (now-start)/1000000 ))
  rss=$(ps -eo pgid=,rss= | awk -v g="$pgid" '$1==g {s+=$2} END{print s+0}')
  procs=$(ps -eo pid=,pgid= | awk -v g="$pgid" '$2==g {n++} END{print n+0}')
  if [ "$agg" -gt 0 ] && [ "$rss" -gt $((agg*1024)) ]; then incomplete=1; reason="agg_rss"; break; fi
  if [ "$maxp" -gt 0 ] && [ "$procs" -gt "$maxp" ]; then incomplete=1; reason="max_procs"; break; fi
  if [ "$deadline" -gt 0 ] && [ "$elapsed_ms" -gt $((deadline*1000)) ]; then incomplete=1; reason="deadline"; break; fi
done
wait "$pid" 2>/dev/null; leader_rc=$?
alive=$(ps -eo pid=,pgid= | awk -v g="$pgid" '$2==g {print $1}' | while read p; do kill -0 "$p" 2>/dev/null && echo "$p"; done | wc -l)
if [ "$alive" -gt 0 ] || [ "$incomplete" = 1 ]; then
  [ "$incomplete" = 0 ] && { incomplete=1; reason="orphan_after_exit"; }
  safe_kill TERM || true
  sleep 2
  safe_kill KILL || true
  wait "$pid" 2>/dev/null || true
  sleep 0.5
fi
orphans=$(ps -eo pid=,pgid= | awk -v g="$pgid" '$2==g {print $1}' | while read p; do kill -0 "$p" 2>/dev/null && echo "$p"; done | wc -l)
jq -n --argjson incomplete "$incomplete" --arg reason "$reason" --argjson orphans "$orphans" --argjson escaped 0 --arg setsid_escape "unsupported" --argjson leader_rc "$leader_rc" --argjson rss_kb "$rss" --argjson procs "$procs" --argjson elapsed_ms "$elapsed_ms" \
  '{incomplete:$incomplete,reason:$reason,orphans:$orphans,escaped:$escaped,setsid_escape:$setsid_escape,leader_rc:$leader_rc,rss_kb:$rss_kb,procs:$procs,elapsed_ms:$elapsed_ms}'
if [ "$incomplete" = 1 ]; then [ "$leader_rc" -ne 0 ] && exit "$leader_rc"; exit 90; fi
[ "$leader_rc" -ne 0 ] && exit "$leader_rc"
exit 0
