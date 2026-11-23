#!/usr/bin/env bash
# Long bounded soak built from process epochs.
#
# The 2 h single-process soak showed RSS growing ~1.4 MB/s with no plateau.
# Component checks (spawnprobe: 3000 /bin/true and 2000 moonc spawns leave RSS
# flat; parent bytes ~12 MB; stats/persist caps at 1k/0) point at harness heap
# growth under allocation churn, not at retained campaign state.  Until that is
# fixed, bound the process: run fixed-length epochs and carry the corpus over
# through --seed-dir.  Each epoch is a fresh process, so max RSS is per epoch.
#
# Usage: scripts/soak_epochs.sh [OUT] [EPOCHS] [EPOCH_SECONDS]
# Env: WORKERS, TRACE_T1, TRACE_T2, RSS_MB (per-epoch self-limit)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/soak_epochs}
EPOCHS=${2:-6}
SECS=${3:-600}
WORKERS=${WORKERS:-4}
TRACE_T1=${TRACE_T1:-5}
TRACE_T2=${TRACE_T2:-5}
RSS_MB=${RSS_MB:-1800}
SUP_MAX=${MAX_PROCS:-$((WORKERS*4+8))}

[ -x "$BIN" ] || { echo "build first" >&2; exit 2; }
mkdir -p "$OUT"
POOL="$OUT/pool"
if [ ! -d "$POOL" ]; then
  mkdir -p "$POOL"
  # Initial seeds: copy the .mbt files that the default campaign would load.
  find "$ROOT/seeds" "$ROOT/seeds_real" "$ROOT/seeds_real2" -name '*.mbt' -size -12000c \
    -print0 2>/dev/null | xargs -0 -r cp -t "$POOL" 2>/dev/null || true
fi
echo "epoch,seconds,maxrss_kb,it,t2_ok,coverage_adds,new_edges,stop_reason,sup_rc,incomplete,orphans" > "$OUT/epochs.csv"
for i in $(seq 1 "$EPOCHS"); do
  run="$OUT/e$i"
  rm -rf "$run"
  state_args=()
  if [ -f "$POOL/coverage_state.jsonl" ]; then
    state_args=(--coverage-state "$POOL/coverage_state.jsonl")
  fi
  if "$ROOT/scripts/supervisor.sh" --json-out "$OUT/e$i.sup.json" \
    --agg-rss-mb "${AGG_RSS_MB:-0}" --max-procs "$SUP_MAX" --deadline "${SUPERVISOR_DEADLINE:-1200}" -- \
    /usr/bin/time -q -o "$OUT/e$i.time" -f "%M" \
    "$BIN" --root "$ROOT" --out "$run" --workers "$WORKERS" --duration "$SECS" \
      "${state_args[@]}" \
      --mode mbt --body-only --seed-dir "$POOL" \
      --trace-t1 "$TRACE_T1" --trace-t2 "$TRACE_T2" --trace-t3 0 --trace-cpu 25 \
      --trace-workers 3 --trace-queue 32 --trace-max-mb 64 \
      --baseline-trace-max-mb 256 \
      --coverage-cap 200 --persist-cap 400 --parent-cap 2000 --edge-cap 50000 \
      --rss-limit-mb "$RSS_MB" --qemu "${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}" \
      > "$OUT/e$i.log" 2>&1; then sup_rc=0; else sup_rc=$?; fi
  sup=$(cat "$OUT/e$i.sup.json" 2>/dev/null || echo '{}')
  sup_inc=$(jq -r '.incomplete // 1' <<<"$sup" 2>/dev/null || echo 1)
  sup_orph=$(jq -r '.orphans // 0' <<<"$sup" 2>/dev/null || echo 0)
  sup_reason=$(jq -r '.reason // ""' <<<"$sup" 2>/dev/null || echo "")
  rss=$(cat "$OUT/e$i.time" 2>/dev/null || echo 0)
  sum=$(ls "$run"/*/summary.json 2>/dev/null | head -1)
  if [ -n "$sum" ]; then
    it=$(grep -o '"it":[0-9]*' "$sum" | head -1 | cut -d: -f2)
    t2=$(grep -o '"t2_ok":[0-9]*' "$sum" | head -1 | cut -d: -f2)
    adds=$(grep -o '"coverage_adds":[0-9]*' "$sum" | head -1 | cut -d: -f2)
    edges=$(grep -o '"new_edges":[0-9]*' "$sum" | head -1 | cut -d: -f2)
    stop=$(grep -o '"stop_reason":"[^"]*"' "$sum" | head -1 | cut -d'"' -f4)
    if [ "$sup_inc" = 1 ] || [ "$sup_rc" != 0 ]; then stop="supervisor_${sup_reason:-rc${sup_rc}}"; fi
    # carry the epoch's persisted corpus and coverage state to the next epoch
    cp -n "$run"/*/corpus/*.mbt "$POOL" 2>/dev/null || true
    cp -f "$run"/*/coverage_state.jsonl "$POOL/coverage_state.jsonl" 2>/dev/null || true
    cp -f "$run"/*/coverage_state.jsonl.sha256 "$POOL/coverage_state.jsonl.sha256" 2>/dev/null || true
    echo "$i,$SECS,$rss,${it:-0},${t2:-0},${adds:-0},${edges:-0},${stop:-},$sup_rc,$sup_inc,$sup_orph" >> "$OUT/epochs.csv"
  else
    echo "$i,$SECS,$rss,0,0,0,0,no-summary,$sup_rc,$sup_inc,$sup_orph" >> "$OUT/epochs.csv"
  fi
  if [ "$sup_inc" = 1 ] || [ "$sup_rc" != 0 ]; then break; fi
done
column -t -s, "$OUT/epochs.csv" 2>/dev/null || cat "$OUT/epochs.csv"
awk -F, 'NR>1 && $3+0>m {m=$3} END {printf "max_rss_kb=%d\n", m}' "$OUT/epochs.csv"
