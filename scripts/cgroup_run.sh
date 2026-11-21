#!/usr/bin/env bash
# Run a command under a cgroup v2 with explicit memory/pids/disk accounting.
#
#   scripts/cgroup_run.sh --out DIR --memory-max 8G [--pids-max 512] -- CMD...
#   scripts/cgroup_run.sh --dry-run
#
# If the host does not expose a writable cgroup delegation, --dry-run prints
# what would be configured and exits 2; it never pretends the limits were
# enforced.
set -euo pipefail
CGROUP_ROOT=${CGROUP_ROOT:-/sys/fs/cgroup}
NAME=${NAME:-mbtfuzz-$$}
MEM=${MEMORY_MAX:-8G}
PIDS=${PIDS_MAX:-512}
OUT=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift 2 ;;
    --memory-max) MEM=$2; shift 2 ;;
    --pids-max) PIDS=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

writable=0
if [ -w "$CGROUP_ROOT" ] && mkdir -p "$CGROUP_ROOT/$NAME" 2>/dev/null; then
  writable=1
fi

if [ "$DRY" = 1 ] || [ "$writable" = 0 ]; then
  cat <<PLAN
cgroup v2 plan (not executed):
  root:        $CGROUP_ROOT
  group:       $NAME
  memory.max:  $MEM
  memory.peak: $CGROUP_ROOT/$NAME/memory.peak  (read after run)
  pids.max:    $PIDS
  disk peak:   sampled with du -sb on --out while the command runs
  run:         \$CGROUP_ROOT/$NAME/cgroup.procs += \$\$ ; exec -- "$@"
status: $([ "$writable" = 1 ] && echo "writable (dry-run requested)" || echo "NOT WRITABLE on this host; limits not enforced")
PLAN
  if [ "$writable" = 0 ] && [ "$DRY" = 0 ]; then
    echo "refusing to claim enforcement: no writable cgroup delegation" >&2
    exit 2
  fi
  exit 0
fi

supervisor_outside=1
peak=0
disk_peak=0
child=""
cleanup() {
  # Final peak read happens even on signal, before the group is removed.
  if [ -n "${cg:-}" ] && [ -d "$cg" ]; then
    p=$(cat "$cg/memory.peak" 2>/dev/null || echo 0)
    [ "$p" -gt "$peak" ] 2>/dev/null && peak=$p
    echo 1 > "$cg/cgroup.kill" 2>/dev/null || true
  fi
  if [ -n "${OUT:-}" ] && [ -d "$OUT" ]; then
    printf '%s\n' "$peak" > "$OUT/memory.peak" 2>/dev/null || true
    printf '%s\n' "$disk_peak" > "$OUT/disk_peak_bytes" 2>/dev/null || true
  fi
  [ -n "${cg:-}" ] && rmdir "$cg" 2>/dev/null || true
}
on_signal() {
  # Forward to the child, then kill anything it spawned inside the group.
  if [ -n "$child" ]; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  echo 1 > "$cg/cgroup.kill" 2>/dev/null || true
  cleanup
  exit 130
}
trap on_signal INT TERM
trap cleanup EXIT

cg="$CGROUP_ROOT/$NAME"
echo "$MEM" > "$cg/memory.max"
echo "$PIDS" > "$cg/pids.max"

[ -n "$OUT" ] && mkdir -p "$OUT"
# The supervisor never joins the cgroup: the child shell writes its own pid
# into cgroup.procs and then execs the command, so the whole command tree is
# accounted for without counting the wrapper.
sh -c 'echo $$ > "$1"; shift; exec "$@"' sh "$cg/cgroup.procs" "$@" &
child=$!
while kill -0 "$child" 2>/dev/null; do
  p=$(cat "$cg/memory.peak" 2>/dev/null || echo 0)
  [ "$p" -gt "$peak" ] 2>/dev/null && peak=$p
  if [ -n "$OUT" ] && [ -d "$OUT" ]; then
    d=$(du -sb "$OUT" 2>/dev/null | awk '{print $1}')
    [ -n "$d" ] && [ "$d" -gt "$disk_peak" ] 2>/dev/null && disk_peak=$d
  fi
  sleep 2
done
wait "$child"
rc=$?
p=$(cat "$cg/memory.peak" 2>/dev/null || echo 0)
[ "$p" -gt "$peak" ] 2>/dev/null && peak=$p
echo "cgroup: memory.peak=$peak bytes, disk_peak=$disk_peak bytes, rc=$rc"
[ "$supervisor_outside" = 1 ] && true
exit "$rc"
