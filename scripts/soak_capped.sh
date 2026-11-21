#!/usr/bin/env bash
# Long bounded soak with an explicit memory top, in two layers:
#
#   prlimit --as=AS_MB   hard per-process address-space cap (kernel enforced)
#   --rss-limit-mb RSS   in-harness soft stop: monitor crosses it, workers stop
#                        accepting work, the campaign drains and writes summary
#
# Usage: scripts/soak_capped.sh [OUT] [SECONDS]
# Env: RSS_MB (default 3000), AS_MB (default 6144), WORKERS (default 4),
#      TRACE_T1 (2), TRACE_T2 (5) -- these are integer percent (0..100), not
#      fractions; a fractional value is rejected by the driver with exit 2,
#      QEMU, SEED
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/soak2h}
DUR=${2:-7200}
RSS_MB=${RSS_MB:-3000}
AS_MB=${AS_MB:-6144}
WORKERS=${WORKERS:-4}
SEED=${SEED:-7}
QEMU=${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}
TRACE_T1=${TRACE_T1:-2}
TRACE_T2=${TRACE_T2:-5}

[ -x "$BIN" ] || { echo "build first: cd moonbit && moon build --target native" >&2; exit 2; }
mkdir -p "$OUT"
rm -rf "$OUT"/*
CSV="$OUT/monitor.csv"
echo "ts,elapsed_s,rss_kb,cpu_ticks,files,bytes,stats_lines,trace_dropped" > "$CSV"

prlimit --as=$((AS_MB * 1024 * 1024)) -- "$BIN" \
  --root "$ROOT" --out "$OUT" --workers "$WORKERS" --duration "$DUR" \
  --mode mbt --body-only --seed "$SEED" --trace-max-mb 64 \
  --baseline-trace-max-mb "${BASELINE_MB:-256}" \
  --trace-t1 "$TRACE_T1" --trace-t2 "$TRACE_T2" --trace-t3 0 --trace-cpu 25 \
  --trace-workers 1 --trace-queue 8 \
  --coverage-cap 200 --persist-cap 400 --parent-cap 2000 --edge-cap 50000 \
  --rss-limit-mb "$RSS_MB" --qemu "$QEMU" > "$OUT/run.log" 2>&1 &
pid=$!
start=$(date +%s)
# Monitoring must never kill the soak: a missing stats file on the first tick
# used to abort the whole script through `set -e` + pipefail.
set +e
while kill -0 "$pid" 2>/dev/null; do
  ts=$(date +%s)
  rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)
  cpu=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null)
  files=$(find "$OUT" -type f 2>/dev/null | wc -l)
  bytes=$(du -sb "$OUT" 2>/dev/null | cut -f1)
  sl=$(cat "$OUT"/*/stats.jsonl 2>/dev/null | wc -l)
  drop=$(tail -1 "$OUT"/*/stats.jsonl 2>/dev/null | sed 's/.*"trace_dropped":\([0-9]*\).*/\1/')
  echo "$ts,$((ts-start)),${rss:-0},${cpu:-0},${files:-0},${bytes:-0},${sl:-0},${drop:-0}" >> "$CSV"
  sleep 60
done
rc=0
wait "$pid" || rc=$?
set -e
echo "soak rc=$rc"
python3 - "$OUT" <<'PY'
import glob, json, sys
out = sys.argv[1]
runs = sorted(glob.glob(out + "/*/summary.json"))
if not runs:
    print("no summary written")
    raise SystemExit(1)
d = json.load(open(runs[-1]))
keys = ["it","t1","t2","t2_ok","trace_completed","trace_failed","trace_dropped",
        "coverage_adds","new_edges","coverage_written","coverage_skipped",
        "persist_written","persist_skipped","parents_evicted",
        "parents_protected_forced","candidate_witnesses","confirmed_witnesses",
        "stop_reason","rss_mb","baseline_state"]
print("summary:", {k: d.get(k) for k in keys})
PY
