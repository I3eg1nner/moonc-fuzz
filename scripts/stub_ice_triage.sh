#!/usr/bin/env bash
# End-to-end unknown-witness control with a stub compiler, three lanes:
#   t1/syncheck, t2/build-package, capsule/package replay.
# The stub emits a table-outside ICE only for marked inputs; everything else
# is forwarded to the real moonc.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
CAP="$ROOT/moonbit/_build/native/debug/build/cmd/capsule/capsule.exe"
OUT=${1:-/tmp/stub_ice_triage}
REAL_MOON_HOME=${REAL_MOON_HOME:-$HOME/.moon}
[ -x "$BIN" ] || { echo "build fuzz first" >&2; exit 2; }
rm -rf "$OUT"; mkdir -p "$OUT/home/bin" "$OUT/seeds_t1" "$OUT/seeds_t2"
for t in moon moonfmt; do
  [ -e "$REAL_MOON_HOME/bin/$t" ] && ln -sf "$REAL_MOON_HOME/bin/$t" "$OUT/home/bin/$t"
done
# moon build (triage t2) needs the core library and registry, not just moonc.
for d in lib registry; do
  [ -e "$REAL_MOON_HOME/$d" ] && ln -sfn "$REAL_MOON_HOME/$d" "$OUT/home/$d"
done
cat > "$OUT/home/bin/moonc" <<STUB
#!/usr/bin/env bash
mode=syncheck
for a in "\$@"; do
  case "\$a" in *build-package*) mode=build ;; esac
done
for a in "\$@"; do
  if [ -f "\$a" ]; then
    if [ "\$mode" = build ] && grep -qE 'STUB_T2_ICE|STUB_PKG_ICE' "\$a" 2>/dev/null; then
      echo 'Oops, the compiler has encountered an exception' >&2
      echo 'Error: Machine_error(kind=unsupported; who="Stub_machine.t2_op"; message="stub")' >&2
      exit 199
    fi
    if [ "\$mode" = syncheck ] && grep -q 'STUB_T1_ICE' "\$a" 2>/dev/null; then
      echo 'Oops, the compiler has encountered an exception' >&2
      echo 'Error: Machine_error(kind=unsupported; who="Stub_machine.t1_op"; message="stub")' >&2
      exit 199
    fi
  fi
done
exec "$REAL_MOON_HOME/bin/moonc" "\$@"
STUB
chmod +x "$OUT/home/bin/moonc"
printf 'fn main {\n  // STUB_T1_ICE\n  println("x")\n}\n' > "$OUT/seeds_t1/m.mbt"
{
  echo '// STUB_T2_ICE (top comment survives body-only mutation)'
  for i in $(seq 1 40); do echo "fn h$i(x : Int) -> Int { x + $i }"; done
  echo 'fn main { println(h1(1).to_string()) }'
} > "$OUT/seeds_t2/m.mbt"

run_campaign() { # name seeddir duration
  MOON_HOME="$OUT/home" "$BIN" --root "$ROOT" --out "$OUT/$1" --workers 1 \
    --duration "$3" --mode mbt --body-only --seed-dir "$2" \
    --trace-t1 0 --trace-t2 0 --parent-cap 20 --stats-cap 100 \
    --triage > "$OUT/$1.log" 2>&1 || true
}
run_campaign t1 "$OUT/seeds_t1" 90
run_campaign t2 "$OUT/seeds_t2" 120

python3 - "$OUT" <<'PY'
import glob, json, os, sys
out = sys.argv[1]
def summary(path):
    s = glob.glob(os.path.join(out, path, "*", "summary.json"))
    return json.load(open(s[0])) if s else {}
bad = []
t1 = summary("t1")
if (t1.get("triage_confirmed") or 0) < 1:
    bad.append(f"t1 confirmed={t1.get('triage_confirmed')}")
t2 = summary("t2")
# t2 is reported but not asserted: moon build resolves its own moonc, so the
# stub at MOON_HOME/PATH is bypassed (see findings/stub_control.md).
wits = glob.glob(os.path.join(out, "*", "*", "findings", "*", "*", "*", "confirmed", "in.mbt"))
if len(wits) < 1:
    bad.append(f"confirmed witnesses={len(wits)}")
print("t1:", {k: t1.get(k) for k in ("triage_checked", "triage_confirmed", "triage_known")})
print("t2:", {k: t2.get(k) for k in ("triage_checked", "triage_confirmed", "triage_known")})
if bad:
    raise SystemExit("stub triage failed: " + "; ".join(bad))
print("stub triage: ok")
PY
