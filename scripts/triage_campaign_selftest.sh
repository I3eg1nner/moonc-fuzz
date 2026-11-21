#!/usr/bin/env bash
# End-to-end triage controls for the campaign's --triage-only path.
#
# Builds a findings tree with one known witness, one benign candidate and one
# timeout-only candidate, runs the real driver over it, and checks the counts.
# This exercises the same code path the campaign uses at exit (--triage), not
# just the pure classifier.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/triage_campaign_selftest}
[ -x "$BIN" ] || { echo "build fuzz first" >&2; exit 2; }
rm -rf "$OUT"
mkdir -p "$OUT/build/ICE/known" "$OUT/build/ICE/benign" "$OUT/build/HANG/to"
f2=$(find "$ROOT/poc/f2_lex_escape_ice" -name '*.mbt' | head -1)
cp "$f2" "$OUT/build/ICE/known/in.mbt"
printf '{"stage":"build","kind":"ICE","status":"candidate","signature":"crash|ICE|Invalid_argument(\\"Char.chr\\")"}\n' > "$OUT/build/ICE/known/meta.json"
printf 'fn main {\n  println("ok")\n}\n' > "$OUT/build/ICE/benign/in.mbt"
printf '{"stage":"build","kind":"ICE","status":"candidate"}\n' > "$OUT/build/ICE/benign/meta.json"
printf 'fn main {\n  while true {\n    ()\n  }\n}\n' > "$OUT/build/HANG/to/in.mbt"
printf '{"stage":"build","kind":"HANG","status":"candidate"}\n' > "$OUT/build/HANG/to/meta.json"

"$BIN" --root "$ROOT" --triage-only "$OUT" | tee "$OUT/summary.json"

python3 - "$OUT/summary.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
if d.get("triaged") != 3:
    bad.append(f"triaged={d.get('triaged')}")
if d.get("known") != 1:
    bad.append(f"known={d.get('known')}")
if d.get("confirmed") != 0:
    bad.append(f"confirmed={d.get('confirmed')}")
if d.get("inconclusive") != 2:
    bad.append(f"inconclusive={d.get('inconclusive')}")
if bad:
    raise SystemExit("triage campaign selftest failed: " + ", ".join(bad))
print("triage campaign selftest: ok")
PY
