#!/usr/bin/env bash
# Formal A/B after backpressure: 3 seeds x 15 min x function/func-edge,
# trace 50% + trace-cpu 25 (budget corrected, baseline excluded).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/bp_ab}
SECS=${2:-900}
for seed in 1 7 2026; do
  echo "[batch] seed=$seed"
  pids=()
  for arm in function func-edge; do
    dir="$OUT/$arm/s$seed"; mkdir -p "$OUT/$arm"; rm -rf "$dir"
    extra=(); [ "$arm" = function ] && extra=(--no-edge-reward)
    /usr/bin/time -q -o "$dir.time" -f "%U %S %M" \
      "$BIN" --root "$ROOT" --out "$dir" --workers 2 --duration "$SECS" \
        --mode mbt --body-only --seed "$seed" \
        --trace-t1 50 --trace-t2 50 --trace-t3 0 --trace-workers 4 \
        --trace-queue 128 --trace-max-mb 256 --baseline-trace-max-mb 256 \
        --baseline-seeds 8 --coverage-cap 200 --persist-cap 400 \
        --parent-cap 500 --edge-cap 200000 --trace-cpu 25 "${extra[@]}" \
        > "$dir.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
done
python3 - "$OUT" <<'PY'
import json, glob, os, statistics, sys
out=sys.argv[1]; rows=[]
for arm in ("function","func-edge"):
    for seed in ("1","7","2026"):
        run=os.path.join(out,arm,"s"+seed)
        sums=glob.glob(os.path.join(run,"*","summary.json"))
        if not sums: continue
        d=json.load(open(sums[0]))
        tf=os.path.join(out,arm,"s"+seed+".time")
        cpu=0.0
        if os.path.exists(tf):
            p=open(tf).read().split(); cpu=float(p[0])+float(p[1])
        comp=(d.get("trace_completed") or 0)
        failed=(d.get("trace_failed") or 0)
        deferred=(d.get("trace_deferred") or 0)+(d.get("trace_deferred_close") or 0)
        total=comp+failed+deferred
        rows.append(dict(arm=arm,seed=seed,it=d.get("it"),adds=d.get("coverage_adds"),
            edges=d.get("new_edges"),cpu=round(cpu,2),
            adds_cpu=round((d.get("coverage_adds") or 0)/cpu,3) if cpu else 0,
            edges_cpu=round((d.get("new_edges") or 0)/cpu,3) if cpu else 0,
            t2=(d.get("unique_t2_ok_inputs") or 0),
            completion=round(100*comp/total,1) if total else 0,
            baseline=d.get("baseline_state")))
print("arm,seed,it,adds,edges,cpu_s,adds_per_cpu_s,edges_per_cpu_s,distinct_t2,completion,baseline")
for r in rows: print(",".join(str(r[k]) for k in ("arm","seed","it","adds","edges","cpu","adds_cpu","edges_cpu","t2","completion","baseline")))
print("--- medians (valid = baseline complete and completion>=80)")
for arm in ("function","func-edge"):
    v=[r for r in rows if r["arm"]==arm and r["baseline"]=="complete" and r["completion"]>=80]
    print(f"{arm}: valid={len(v)}/3", end=" ")
    for k in ("adds","edges","adds_cpu","edges_cpu","t2"):
        vals=[r[k] for r in v]
        if vals: print(f"{k}={statistics.median(vals)}", end=" ")
    print()
PY
