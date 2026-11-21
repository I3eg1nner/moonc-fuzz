#!/usr/bin/env bash
# Post-fix A/B: function vs function+edge vs deep, 30 minutes per run,
# 3 seeds, all runs in parallel (each 2 workers).
#
# Usage: scripts/bench_ab_30m.sh [OUT] [SECONDS] [SEEDS]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/ab30}
SECS=${2:-1800}
SEEDS=${3:-1,7,2026}
QEMU=${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}
[ -x "$BIN" ] || { echo "build first" >&2; exit 2; }
mkdir -p "$OUT"
run_one() {
  local arm=$1 seed=$2
  local dir="$OUT/$arm/s$seed"
  mkdir -p "$OUT/$arm"; rm -rf "$dir"
  local extra=()
  case "$arm" in
    function)  extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0 --no-edge-reward) ;;
    func-edge) extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0) ;;
    deep)      extra=(--trace-t1 5 --trace-t2 5 --trace-t3 0 --deep-p 30) ;;
  esac
  /usr/bin/time -q -o "$dir.time" -f "%M" \
    "$BIN" --root "$ROOT" --out "$dir" --workers 2 --duration "$SECS" \
      --mode mbt --body-only --seed "$seed" \
      --trace-workers 2 --trace-queue 32 --trace-max-mb 64 \
      --baseline-trace-max-mb 256 --baseline-seeds 8 \
      --coverage-cap 200 --persist-cap 400 --parent-cap 500 --edge-cap 50000 \
      --qemu "$QEMU" "${extra[@]}" > "$dir.log" 2>&1 || true
  echo "$arm seed=$seed done"
}
pids=()
for arm in function func-edge deep; do
  for seed in ${SEEDS//,/ }; do
    run_one "$arm" "$seed" & pids+=($!)
  done
done
for p in "${pids[@]}"; do wait "$p" || true; done
python3 - "$OUT" <<'PY'
import json, glob, os, statistics, sys
out = sys.argv[1]
rows = []
for arm in ("function", "func-edge", "deep"):
    for seed in ("1", "7", "2026"):
        run = os.path.join(out, arm, "s" + seed)
        sums = glob.glob(os.path.join(run, "*", "summary.json"))
        if not sums:
            continue
        d = json.load(open(sums[0]))
        rss = 0
        tf = os.path.join(out, arm, "s" + seed + ".time")
        if os.path.exists(tf):
            rss = int(open(tf).read().strip() or 0) // 1024
        t2 = d.get("t2", 0)
        rows.append(dict(arm=arm, seed=seed, it=d.get("it"),
                         t2=t2, t2_ok=d.get("t2_ok"),
                         rate=round(100 * (d.get("t2_ok") or 0) / t2, 1) if t2 else 0,
                         adds=d.get("coverage_adds"), edges=d.get("new_edges"),
                         baseline=d.get("baseline_state"), rss=rss))
print("arm,seed,it,t2_ok,rate,adds,edges,baseline,rss_mb")
for r in rows:
    print(f"{r['arm']},{r['seed']},{r['it']},{r['t2_ok']},{r['rate']},{r['adds']},{r['edges']},{r['baseline']},{r['rss']}")
print("--- medians")
for arm in ("function", "func-edge", "deep"):
    for key in ("it", "t2_ok", "adds", "edges"):
        vals = [r[key] for r in rows if r["arm"] == arm and r[key] is not None]
        if vals:
            print(f"{arm}.{key}={int(statistics.median(vals))}", end=" ")
    print()
PY
