#!/usr/bin/env bash
# Positive/negative controls for cmd/triage.
#
#   pos-known   the F2 ICE witness must come out as `known` (3/3 reproducible)
#   neg-valid   a valid program must not be confirmed
#   neg-timeout a plain timeout must not be confirmed (timeout-only)
#
# Usage: scripts/triage_selftest.sh [OUT]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/triage/triage.exe"
OUT=${1:-/tmp/triage_selftest}
[ -x "$BIN" ] || { echo "build triage first" >&2; exit 2; }
rm -rf "$OUT"; mkdir -p "$OUT/pos-known" "$OUT/neg-valid" "$OUT/neg-timeout"

f2=$(find "$ROOT/poc/f2_lex_escape_ice" -name '*.mbt' | head -1)
cp "$f2" "$OUT/pos-known/in.mbt"
printf '{"stage":"build","kind":"ICE","signature":"crash|ICE|Invalid_argument(\\"Char.chr\\")|known=F2"}\n' > "$OUT/pos-known/meta.json"
printf 'fn main {\n  println("ok")\n}\n' > "$OUT/neg-valid/in.mbt"
printf 'fn main {\n  while true {\n    ()\n  }\n}\n' > "$OUT/neg-timeout/in.mbt"

echo "-- pos-known"
"$BIN" --case "$OUT/pos-known" --stage build --timeout-ms 10000 | tee "$OUT/pos.json"
echo "-- neg-valid"
"$BIN" --case "$OUT/neg-valid" --stage build --timeout-ms 10000 | tee "$OUT/neg.json"
echo "-- neg-timeout"
"$BIN" --case "$OUT/neg-timeout" --stage build --timeout-ms 1 | tee "$OUT/to.json"

python3 - "$OUT" <<'PY'
import json, sys, pathlib
out = pathlib.Path(sys.argv[1])
pos = json.loads((out / "pos.json").read_text())
neg = json.loads((out / "neg.json").read_text())
to = json.loads((out / "to.json").read_text())
bad = []
if pos["status"] != "known" or pos["reproduced"] != "3/3":
    bad.append(f"pos-known -> {pos['status']} {pos['reproduced']}")
if neg["status"] == "confirmed":
    bad.append("neg-valid was confirmed")
if to["status"] == "confirmed":
    bad.append("neg-timeout was confirmed")
if bad:
    raise SystemExit("triage selftest failed: " + "; ".join(bad))
print("triage selftest: ok")
PY
