#!/usr/bin/env bash
# Multi-seed feedback A/B, including a deep-queue arm.
#
# arms:
#   behavior   no coverage traces, no deep queue (behaviour novelty only)
#   function   coverage traces, edge novelty not rewarded
#   func-edge  coverage traces with the edge bonus (driver default)
#   deep-edge  func-edge plus 30% of iterations seeded from type-valid IR
#
# All arms run the same duration, worker count, caps and seed list, in
# parallel; per-arm medians are computed over seeds.
#
# Usage: scripts/bench_multi_seed.sh [OUT] [SECONDS] [SEEDS]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/bench_ms}
SECS=${2:-300}
SEEDS=${3:-1,7,2026}
WORKERS=${WORKERS:-2}
QEMU=${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}
[ -x "$BIN" ] || { echo "build first" >&2; exit 2; }
mkdir -p "$OUT"
run_arm_seed() {
  local arm=$1 seed=$2
  local dir="$OUT/$arm/s$seed"
  mkdir -p "$OUT/$arm"
  rm -rf "$dir"
  local extra=()
  case "$arm" in
    behavior)  extra=(--trace-t1 0 --trace-t2 0 --trace-t3 0) ;;
    function)  extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0 --trace-cpu 25 --no-edge-reward) ;;
    func-edge) extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0 --trace-cpu 25) ;;
    deep-edge) extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0 --trace-cpu 25 --deep-p 30) ;;
  esac
  /usr/bin/time -q -o "$dir.time" -f "%M" \
    "$BIN" --root "$ROOT" --out "$dir" --workers "$WORKERS" --duration "$SECS" \
      --mode mbt --body-only --seed "$seed" \
      --trace-workers 2 --trace-queue 32 --trace-max-mb 64 \
      --baseline-trace-max-mb 256 \
      --coverage-cap 200 --persist-cap 400 --parent-cap 500 --edge-cap 50000 \
      --qemu "$QEMU" "${extra[@]}" > "$dir.log" 2>&1 || true
  echo "$arm seed=$seed done"
}
pids=()
for arm in behavior function func-edge deep-edge; do
  for seed in ${SEEDS//,/ }; do
    run_arm_seed "$arm" "$seed" &
    pids+=($!)
  done
done
for p in "${pids[@]}"; do wait "$p" || true; done

field() { grep -o "\"$2\":[0-9]*" "$1" | head -1 | cut -d: -f2; }
printf "%-10s %-6s %8s %8s %8s %8s %8s\n" arm seed it t2_ok adds edges maxrss_mb
for arm in behavior function func-edge deep-edge; do
  for seed in ${SEEDS//,/ }; do
    dir="$OUT/$arm/s$seed"
    sum=$(ls "$dir"/*/summary.json 2>/dev/null | head -1)
    rss=$(cat "$dir.time" 2>/dev/null || echo 0)
    if [ -n "$sum" ]; then
      printf "%-10s %-6s %8s %8s %8s %8s %8s\n" "$arm" "$seed" \
        "$(field "$sum" it)" "$(field "$sum" t2_ok)" \
        "$(field "$sum" coverage_adds)" "$(field "$sum" new_edges)" \
        "$((rss/1024))"
    fi
  done
done
echo "--- medians over seeds"
for arm in behavior function func-edge deep-edge; do
  for f in it t2_ok coverage_adds new_edges; do
    vals=()
    for seed in ${SEEDS//,/ }; do
      sum=$(ls "$OUT/$arm/s$seed"/*/summary.json 2>/dev/null | head -1)
      [ -n "$sum" ] && vals+=("$(field "$sum" "$f")")
    done
    if [ ${#vals[@]} -gt 0 ]; then
      med=$(printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
      printf "%s.%s=%s " "$arm" "$f" "$med"
    fi
  done
  echo
done
