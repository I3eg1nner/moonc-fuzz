#!/bin/bash
# MoonBit fuzzing entry point.
#
#   ./run.sh [campaign] [workers] [seconds] [mode]
#   ./run.sh [mode] [workers] [seconds]        # legacy positional form
#
# Campaigns:
#   parser         T1 only (lexer/parser)
#   typer          T1 + T2 for every parseable input
#   semantic-diff  T1 + T2 + wasm/js differential for every buildable input
#   hybrid         T1 + sampled T2 + sampled T3 (default)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
usage: ./run.sh [parser|typer|semantic-diff|hybrid] [workers] [seconds] [mode]
       ./run.sh [mbt|pkg|mod|mbtmd|mbti|mbtx] [workers] [seconds]

environment:
  P_DEEP=50       percent of parseable inputs sent to T2
  P_RUN=10        percent of buildable inputs sent to T3
  TRACE_T1=20     percent of eligible T1 inputs sampled for trace
  TRACE_T2=70     percent of eligible T2 inputs sampled for trace
  TRACE_T3=10     percent of buildable inputs sampled for link trace
  TRACE_WORKERS=3 background trace workers
  TRACE_QUEUE=32  bounded queue length
  TRACE_MAX_MB=256 maximum accepted QEMU log per task
  TRACE_CPU=25    adaptive trace CPU budget, percent of campaign
  BASELINE_SEEDS=8 seed traces used for U0
  SEED_DIR=       explicit seed root (for example $ROOT/templates)
  QEMU=/tmp/AFLplusplus/afl-qemu-trace
  OUT=$ROOT/out/mb_runs
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

MODE="mbt"
CAMPAIGN="hybrid"
WORKERS="48"
DUR="600"
if [ $# -gt 0 ]; then
  case "$1" in
    mbt|pkg|mod|mbtmd|mbti|mbtx)
      MODE="$1"; WORKERS="${2:-48}"; DUR="${3:-600}"
      ;;
    parser|typer|semantic-diff|hybrid)
      CAMPAIGN="$1"; WORKERS="${2:-48}"; DUR="${3:-600}"; MODE="${4:-mbt}"
      ;;
    *)
      echo "unknown campaign or mode: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

case "$CAMPAIGN" in
  parser)        P_DEEP="${P_DEEP:-0}";   P_RUN="${P_RUN:-0}" ;;
  typer)         P_DEEP="${P_DEEP:-100}"; P_RUN="${P_RUN:-0}" ;;
  semantic-diff) P_DEEP="${P_DEEP:-100}"; P_RUN="${P_RUN:-100}" ;;
  hybrid)        P_DEEP="${P_DEEP:-50}";  P_RUN="${P_RUN:-10}" ;;
esac

# Always invoke the incremental build.  Reusing a release binary just because
# it exists silently runs stale code after a source edit.
moon -C "$ROOT/moonbit" build cmd/fuzz --target native --release

OUT_DIR="${OUT:-$ROOT/out/mb_runs}"
mkdir -p "$OUT_DIR"
exec "$ROOT/scripts/supervisor.sh" \
  --json-out "$OUT_DIR/supervisor.json" \
  --agg-rss-mb "${AGG_RSS_MB:-0}" --max-procs "${MAX_PROCS:-8}" --deadline "${SUPERVISOR_DEADLINE:-120}" \
  -- "$ROOT/moonbit/_build/native/release/build/cmd/fuzz/fuzz.exe" \
  --root "$ROOT" \
  --out "$OUT_DIR" \
  --campaign "$CAMPAIGN" \
  --run-id "${RUN_ID:-$(date -u +%Y%m%dT%H%M%S)-$$}" \
  --mode "$MODE" \
  --workers "$WORKERS" \
  --duration "$DUR" \
  --p-deep "$P_DEEP" \
  --p-run "$P_RUN" \
  --trace-t1 "${TRACE_T1:-20}" \
  --trace-t2 "${TRACE_T2:-70}" \
  --trace-t3 "${TRACE_T3:-10}" \
  --trace-workers "${TRACE_WORKERS:-3}" \
  --trace-queue "${TRACE_QUEUE:-32}" \
  --trace-max-mb "${TRACE_MAX_MB:-256}" \
  --trace-cpu "${TRACE_CPU:-25}" \
  --baseline-seeds "${BASELINE_SEEDS:-8}" \
  --seed-dir "${SEED_DIR:-}" \
  --qemu "${QEMU:-/tmp/AFLplusplus/afl-qemu-trace}" \
  --body-only
