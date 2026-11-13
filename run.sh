#!/bin/bash
# MoonBit fuzzing entry point.
#   ./run.sh [mode] [workers] [seconds]   # mbt|pkg|mod|mbtmd|mbti|mbtx
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "usage: ./run.sh [mbt|pkg|mod|mbtmd|mbti|mbtx] [workers] [seconds]"
  exit 0
fi
MODE="${1:-mbt}"; WORKERS="${2:-48}"; DUR="${3:-600}"
BIN="$ROOT/moonbit/_build/native/release/build/cmd/fuzz/fuzz.exe"
if [ ! -x "$BIN" ]; then
  moon -C "$ROOT/moonbit" build cmd/fuzz --target native --release
fi
exec "$BIN" --root "$ROOT" --out "$ROOT/out/mb_run" --mode "$MODE" \
  --workers "$WORKERS" --duration "$DUR" --p-deep 50 --body-only
