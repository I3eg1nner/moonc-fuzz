#!/usr/bin/env bash
# End-to-end unknown-witness control with a stub compiler.
#
# The stub moonc emits a table-outside ICE for inputs containing
# STUB_UNKNOWN_ICE and forwards everything else to the real moonc.  A real
# campaign save_crash writes the candidate, then --triage replays it through
# the same stub and must reach `confirmed` (the signature is unknown).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT=${1:-/tmp/stub_ice_triage}
REAL_MOON_HOME=${REAL_MOON_HOME:-$HOME/.moon}
[ -x "$BIN" ] || { echo "build fuzz first" >&2; exit 2; }
rm -rf "$OUT"; mkdir -p "$OUT/home/bin" "$OUT/seeds"
for t in moon moonfmt; do
  [ -e "$REAL_MOON_HOME/bin/$t" ] && ln -sf "$REAL_MOON_HOME/bin/$t" "$OUT/home/bin/$t"
done
cat > "$OUT/home/bin/moonc" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [ -f "\$a" ] && grep -q STUB_UNKNOWN_ICE "\$a" 2>/dev/null; then
    echo 'Oops, the compiler has encountered an exception' >&2
    echo 'Error: Machine_error(kind=unsupported; who="Stub_machine.unknown_op"; message="stub")' >&2
    exit 199
  fi
done
exec "$REAL_MOON_HOME/bin/moonc" "\$@"
STUB
chmod +x "$OUT/home/bin/moonc"
printf 'fn main {\n  // STUB_UNKNOWN_ICE\n  println("x")\n}\n' > "$OUT/seeds/m.mbt"
MOON_HOME="$OUT/home" "$BIN" --root "$ROOT" --out "$OUT/run" --workers 1 \
  --duration 90 --mode mbt --body-only --seed-dir "$OUT/seeds" \
  --trace-t1 0 --trace-t2 0 --parent-cap 20 --stats-cap 100 \
  --triage > "$OUT/run.log" 2>&1 || true
python3 - "$OUT" <<'PY'
import glob, json, os, sys
out = sys.argv[1]
sums = glob.glob(os.path.join(out, "run", "*", "summary.json"))
if not sums:
    raise SystemExit("stub triage failed: no summary")
d = json.load(open(sums[0]))
tri = [json.loads(l) for l in open(os.path.join(out, "run", "*", "triage.jsonl").replace("*", os.path.basename(os.path.dirname(sums[0])))) if l.strip()] if False else []
print("summary:", {k: d.get(k) for k in ("it", "triage_checked", "triage_confirmed", "triage_known", "triage_flaky", "triage_inconclusive")})
confirmed = d.get("triage_confirmed") or 0
known = d.get("triage_known") or 0
wits = glob.glob(os.path.join(out, "run", "*", "findings", "t1", "*", "*", "confirmed", "in.mbt"))
if confirmed < 1:
    raise SystemExit(f"stub triage failed: confirmed={confirmed} known={known}")
if not wits:
    raise SystemExit("stub triage failed: confirmed witness not preserved")
print("witness:", wits[0])
print("stub triage: ok")
PY
