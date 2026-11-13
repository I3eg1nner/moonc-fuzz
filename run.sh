#!/bin/bash
# MoonBit is the default fuzzing path.
#   ./run.sh [mode] [workers] [seconds]      # mode: mbt|pkg|mod|mbtmd|mbti|mbtx
#   ./run.sh py [mode] [workers] [seconds]   # legacy Python reference
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "usage: ./run.sh [mbt|pkg|mod|mbtmd|mbti|mbtx|py] [workers] [seconds]"
  exit 0
fi
if [ "${1:-}" = "py" ]; then
  shift
  MODE="${1:-mbt}"; WORKERS="${2:-96}"; DUR="${3:-3600}"
  exec python3 "$ROOT/harness/mbtfuzz.py" --mode "$MODE" --workers "$WORKERS" \
    --duration "$DUR" --p-deep 0.5 --p-run 0.5 --diff
fi
MODE="${1:-mbt}"; WORKERS="${2:-48}"; DUR="${3:-600}"
BIN="$ROOT/moonbit/_build/native/release/build/cmd/fuzz/fuzz.exe"
if [ ! -x "$BIN" ]; then
  moon -C "$ROOT/moonbit" build cmd/fuzz --target native --release
fi
exec "$BIN" --root "$ROOT" --out "$ROOT/out/mb_run" --mode "$MODE" \
  --workers "$WORKERS" --duration "$DUR" --p-deep 50 --body-only
