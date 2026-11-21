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
rm -rf "$OUT"; mkdir -p "$OUT"
# Positive control through the real save path: --emit-selftest-finding calls
# @corpus.save_finding with the cluster signature, so the fixture is produced
# by the same writer the campaign uses.
"$BIN" --root "$ROOT" --emit-selftest-finding "$OUT" > "$OUT/emit.json"

mkdir -p "$OUT/findings/build/ICE/benign" "$OUT/findings/build/HANG/to"
printf 'fn main {\n  println("ok")\n}\n' > "$OUT/findings/build/ICE/benign/in.mbt"
printf '{"stage":"build","kind":"ICE","status":"candidate"}\n' > "$OUT/findings/build/ICE/benign/meta.json"
printf 'fn main {\n  while true {\n    ()\n  }\n}\n' > "$OUT/findings/build/HANG/to/in.mbt"
printf '{"stage":"build","kind":"HANG","status":"candidate"}\n' > "$OUT/findings/build/HANG/to/meta.json"

"$BIN" --root "$ROOT" --triage-only "$OUT/findings" | tee "$OUT/summary.json"

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
