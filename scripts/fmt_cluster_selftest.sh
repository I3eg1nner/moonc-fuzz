#!/usr/bin/env bash
# End-to-end formatter clustering control.
#
# Three different sources with the same F5-style prefix operator must land in
# one REPARSE directory (the signature comes from the reparse failure, not the
# source hash).  Distinctness of different errors is unit-tested in
# moonbit/cluster/cluster_wbtest.mbt.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/fmt_cluster_selftest}
SEEDS="$OUT/seeds"
rm -rf "$OUT"; mkdir -p "$SEEDS"
printf 'fn f() {\n  +1\n}\n' > "$SEEDS/a.mbt"
printf 'fn g() {\n  +2\n}\n' > "$SEEDS/b.mbt"
printf 'fn h() {\n  +3\n}\n' > "$SEEDS/c.mbt"
"$BIN" --root "$ROOT" --out "$OUT/run" --workers 2 --duration 60 \
  --mode mbt --body-only --seed-dir "$SEEDS" --fmt-check \
  --trace-t1 0 --trace-t2 0 --parent-cap 100 --stats-cap 1000 \
  > "$OUT/run.log" 2>&1 || true
dirs=$(find "$OUT/run" -type d -path '*findings/fmt/REPARSE/*' 2>/dev/null | wc -l | tr -d ' ')
echo "reparse_dirs=$dirs"
if [ "$dirs" != "1" ]; then
  echo "fmt cluster selftest failed: expected 1 directory, got $dirs" >&2
  exit 1
fi
echo "fmt cluster selftest: ok"
