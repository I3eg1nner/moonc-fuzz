#!/usr/bin/env bash
# Deterministic formatter-clustering control.
#
# `clusterprobe reparse` runs the real moonfmt, then the real moonc on its
# output, and prints cluster.formatter_signature for the reparse failure --
# the same computation the campaign's REPARSE path uses.
#
# Three sources with F5's prefix-plus shape must share one signature; a valid
# source (no reparse failure) must differ.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/clusterprobe/clusterprobe.exe"
OUT=${1:-/tmp/fmt_cluster_selftest}
rm -rf "$OUT"; mkdir -p "$OUT"
printf 'fn f(y : Int) -> Int { +y }\n' > "$OUT/a.mbt"
printf 'fn g(z : Int) -> Int { +z }\n' > "$OUT/b.mbt"
printf 'fn h(w : Int) -> Int { +w }\n' > "$OUT/c.mbt"
printf 'fn ok() -> Int { 1 }\nfn main { println(ok().to_string()) }\n' > "$OUT/ok.mbt"
[ -x "$BIN" ] || { echo "build clusterprobe first" >&2; exit 2; }
"$BIN" reparse "$OUT/a.mbt" "$OUT/b.mbt" "$OUT/c.mbt" "$OUT/ok.mbt" | tee "$OUT/sigs.txt"
python3 - "$OUT/sigs.txt" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
sigs = [d["sig"] for d in lines]
bad = []
if len(sigs) != 4:
    bad.append(f"expected 4 signatures, got {len(sigs)}")
else:
    if not (sigs[0] == sigs[1] == sigs[2]):
        bad.append(f"same error did not merge: {sigs[:3]}")
    if sigs[3] == sigs[0]:
        bad.append("valid source shared the defect signature")
if bad:
    raise SystemExit("fmt cluster selftest failed: " + "; ".join(bad))
print("fmt cluster selftest: ok")
PY
