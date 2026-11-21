#!/usr/bin/env bash
# Three feedback arms, same budget, serial, real CPU accounting.
#
#   behavior   no coverage traces at all: parents come from behaviour novelty
#   function   coverage traces on, edge novelty updates the universe but gives
#              no parent reward (--no-edge-reward)
#   func-edge  coverage traces on with the +8 edge bonus (the default driver)
#
# Usage: scripts/bench_campaigns.sh [OUT] [SECONDS] [SEED]
#
# CPU is measured by GNU time around the whole campaign (user+sys includes
# waited-for children), and max RSS is recorded next to it.  Each arm writes
# its own run directory with stats.jsonl and summary.json.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/bench_ab}
SECS=${2:-600}
SEED=${3:-1}
QEMU=${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}

[ -x "$BIN" ] || { echo "build the harness first: cd moonbit && moon build --target native" >&2; exit 2; }
mkdir -p "$OUT"

run_arm() {
  local name=$1
  shift
  local arm_out="$OUT/$name"
  rm -rf "$arm_out"
  echo "[bench] arm=$name seconds=$SECS seed=$SEED" >&2
  /usr/bin/time -q -o "$OUT/$name.time" -f "%U %S %M" \
    "$BIN" --root "$ROOT" --out "$arm_out" --workers 4 --duration "$SECS" \
      --mode mbt --body-only --seed "$SEED" --trace-max-mb 64 \
      --trace-workers 1 --trace-queue 8 \
      --coverage-cap 200 --persist-cap 400 --parent-cap 2000 --edge-cap 50000 \
      --qemu "$QEMU" "$@" > "$OUT/$name.log" 2>&1
}

run_arm behavior --trace-t1 0 --trace-t2 0 --trace-t3 0
run_arm function --trace-t1 2 --trace-t2 5 --trace-cpu 25 --no-edge-reward
run_arm func-edge --trace-t1 2 --trace-t2 5 --trace-cpu 25

BENCHSTAT="$ROOT/moonbit/_build/native/debug/build/cmd/benchstat/benchstat.exe"
[ -x "$BENCHSTAT" ] || { echo "build benchstat first" >&2; exit 2; }
"$BENCHSTAT" "$OUT"
