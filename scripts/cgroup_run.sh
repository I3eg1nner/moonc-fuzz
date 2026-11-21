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

cleanup() {
  if [ -n "${peak:-}" ]; then
    printf '%s\n' "$peak" > "$OUT/memory.peak" 2>/dev/null || true
  fi
  if [ -n "${disk_peak:-}" ]; then
    printf '%s\n' "$disk_peak" > "$OUT/disk_peak_bytes" 2>/dev/null || true
  fi
  rmdir "$CGROUP_ROOT/$NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "$MEM" > "$CGROUP_ROOT/$NAME/memory.max"
echo "$PIDS" > "$CGROUP_ROOT/$NAME/pids.max"
echo $$ > "$CGROUP_ROOT/$NAME/cgroup.procs"

[ -n "$OUT" ] && mkdir -p "$OUT"
"$@" &
child=$!
peak=0
disk_peak=0
while kill -0 "$child" 2>/dev/null; do
  p=$(cat "$CGROUP_ROOT/$NAME/memory.peak" 2>/dev/null || echo 0)
  [ "$p" -gt "$peak" ] 2>/dev/null && peak=$p
  if [ -n "$OUT" ] && [ -d "$OUT" ]; then
    d=$(du -sb "$OUT" 2>/dev/null | awk '{print $1}')
    [ -n "$d" ] && [ "$d" -gt "$disk_peak" ] 2>/dev/null && disk_peak=$d
  fi
  sleep 2
done
wait "$child"
rc=$?
echo "cgroup: memory.peak=$peak bytes, disk_peak=$disk_peak bytes, rc=$rc"
exit "$rc"
