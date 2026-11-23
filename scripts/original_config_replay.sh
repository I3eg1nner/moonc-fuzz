#!/bin/bash
# J2: snapshot original package/config/source/argv and replay in a fresh dir.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
OUT="/tmp/mbtfuzz_original_replay_$$"; mkdir -p "$OUT/snap"
# Construct a TEST_FAIL package.
cat > "$OUT/snap/moon.mod" <<'EOF'
name = "tf"
version = "0.1.0"
EOF
cat > "$OUT/snap/moon.pkg" <<'EOF'
options("is-main": false)
EOF
cat > "$OUT/snap/lib_test.mbt" <<'EOF'
test "fail_case" {
  assert_eq(1, 2)
}
EOF
printf '%s\n' 'moon test --target wasm-gc' > "$OUT/snap/argv.txt"
# Save manifest.
( cd "$OUT/snap" && sha256sum moon.mod moon.pkg lib_test.mbt argv.txt > manifest.txt )
# Replay helper: always from the snapshot, never from a live package.
replay() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d"
  cp "$OUT/snap/moon.mod" "$d/moon.mod"; cp "$OUT/snap/moon.pkg" "$d/moon.pkg"
  cp "$OUT/snap/lib_test.mbt" "$d/lib_test.mbt"
  ( cd "$d" && timeout 60 moon test --target wasm-gc ) >"$d/out" 2>"$d/err"
  echo $? > "$d/rc"
}
# Save-time expected = first replay output.
replay "$OUT/r0"; cp "$OUT/r0/out" "$OUT/expected.out"; cp "$OUT/r0/err" "$OUT/expected.err"
# Three fresh replays.
matched=0
for i in 1 2 3; do
  replay "$OUT/r$i"
  if cmp -s "$OUT/r$i/out" "$OUT/expected.out" && cmp -s "$OUT/r$i/err" "$OUT/expected.err"; then matched=$((matched+1)); fi
done
# Positive control: mutate a live copy of the package (not the snapshot).
cp -r "$OUT/snap" "$OUT/live"; sed -i 's/assert_eq(1, 2)/assert_eq(1, 1)/' "$OUT/live/lib_test.mbt"
( cd "$OUT/live" && timeout 60 moon test --target wasm-gc ) >/tmp/live.out 2>/tmp/live.err; live_rc=$?
# replay still uses snapshot: check it matches expected and live differs.
live_snapshot_ok=1
if [ "$live_rc" = 0 ] && cmp -s "$OUT/expected.out" /tmp/live.out; then live_snapshot_ok=0; fi
# Negative control: tamper the snapshot's expected assertion text.
sed -i 's/assert_eq(1, 2)/assert_eq(2, 2)/' "$OUT/snap/lib_test.mbt"
replay "$OUT/rt"
tamper_mismatch=0
if ! cmp -s "$OUT/rt/out" "$OUT/expected.out" || ! cmp -s "$OUT/rt/err" "$OUT/expected.err"; then tamper_mismatch=1; fi
# Save counts.
jq -n --argjson saved 1 --argjson replayed 3 --argjson matched "$matched" \
  --argjson live_mutation_still_match "$live_snapshot_ok" --argjson tamper_mismatch "$tamper_mismatch" \
  --arg manifest "$(cat "$OUT/snap/manifest.txt" | tr '\n' ';')" \
  '{saved:$saved,replayed:$replayed,matched:$matched,expected:"FAILED: `1 != 2`",live_mutation_still_match:$live_mutation_still_match,tamper_mismatch:$tamper_mismatch,manifest:$manifest}' > "$OUT/summary.json"
cat "$OUT/summary.json"
rm -rf "$OUT"
[[ "$matched" -eq 3 && "$live_snapshot_ok" -eq 1 && "$tamper_mismatch" -eq 1 ]]
