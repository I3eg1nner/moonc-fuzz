#!/usr/bin/env bash
# function vs function+edge, 30 min/arm, 3 seeds, new identity edge space.
# Seed-major batches (2 arms in parallel) to keep trace I/O sane.  CPU is
# recorded with GNU time: format "%U %S %M" (user, sys, maxRSS).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/edge30}
SECS=${2:-1800}
SEEDS=${3:-1,7,2026}
QEMU=${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}
mkdir -p "$OUT"
for seed in ${SEEDS//,/ }; do
  echo "[batch] seed=$seed"
  pids=()
  for arm in function func-edge; do
    dir="$OUT/$arm/s$seed"; mkdir -p "$OUT/$arm"; rm -rf "$dir"
    extra=()
    [ "$arm" = function ] && extra=(--no-edge-reward)
    /usr/bin/time -q -o "$dir.time" -f "%U %S %M" \
      "$BIN" --root "$ROOT" --out "$dir" --workers 2 --duration "$SECS" \
        --mode mbt --body-only --seed "$seed" \
        --trace-t1 20 --trace-t2 20 --trace-t3 0 --trace-workers 2 \
        --trace-queue 32 --trace-max-mb 64 --baseline-trace-max-mb 256 \
        --baseline-seeds 8 --coverage-cap 200 --persist-cap 400 \
        --parent-cap 500 --edge-cap 200000 --qemu "$QEMU" "${extra[@]}" \
        > "$dir.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
done
python3 - "$OUT" <<'PY'
import json, glob, os, statistics, sys
out = sys.argv[1]
rows = []
for arm in ("function", "func-edge"):
    for seed in ("1", "7", "2026"):
        run = os.path.join(out, arm, "s" + seed)
        sums = glob.glob(os.path.join(run, "*", "summary.json"))
        if not sums:
            continue
        d = json.load(open(sums[0]))
        u = s = rss = 0
        tf = os.path.join(out, arm, "s" + seed + ".time")
        if os.path.exists(tf):
            parts = open(tf).read().split()
            u, s, rss = float(parts[0]), float(parts[1]), int(parts[2])
        t2 = d.get("t2", 0)
        rows.append(dict(arm=arm, seed=seed, it=d.get("it"), t2=t2,
                         t2_ok=d.get("t2_ok"),
                         rate=round(100 * (d.get("t2_ok") or 0) / t2, 1) if t2 else 0,
                         adds=d.get("coverage_adds"), edges=d.get("new_edges"),
                         baseline=d.get("baseline_state"),
                         est=d.get("edge_status"), collisions=d.get("edge_collisions"),
                         cpu=round(u + s, 2), rss=rss // 1024))
print("arm,seed,it,t2_ok,rate,adds,edges,baseline,edge_status,collisions,cpu_s,rss_mb")
for r in rows:
    print(",".join(str(r[k]) for k in ("arm","seed","it","t2_ok","rate","adds","edges","baseline","est","collisions","cpu","rss")))
print("--- medians (valid = baseline complete AND edge_status ok)")
for arm in ("function", "func-edge"):
    valid = [r for r in rows if r["arm"] == arm and r["baseline"] == "complete" and r["est"] == "ok"]
    print(f"{arm}: valid={len(valid)}/3", end=" ")
    for key in ("it","t2_ok","adds","edges","cpu"):
        vals = [r[key] for r in valid]
        if vals:
            print(f"{key}={statistics.median(vals)}", end=" ")
    adds = [r["adds"] for r in valid]
    if len(adds) > 1:
        print(f"adds_range={min(adds)}-{max(adds)}", end=" ")
    print()
PY
