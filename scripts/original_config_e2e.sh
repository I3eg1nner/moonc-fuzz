#!/bin/bash
# Behavior-only e2e: real TEST_FAIL campaign; triage decides; 3 behavior controls.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
TRI="$ROOT/moonbit/_build/native/debug/build/cmd/triage/triage.exe"
OUT=/tmp/original_e2e_$$; mkdir -p "$OUT"
timeout 35 "$BIN" --out "$OUT" --duration 20 --workers 1 \
  --pkg-seed "$ROOT/regressions/pkg_test_fail" --pkg-file lib_test.mbt \
  --pkg-argv "build --target js" --pkg-run-argv "test --target js" \
  >"$OUT/fuzz.out" 2>"$OUT/fuzz.err"
W=$(find "$OUT" -type d -path '*/findings/build/TEST_FAIL/*/original' | head -1 | xargs -r dirname)
if [ -z "$W" ] || [ ! -f "$W/meta.json" ]; then
  echo '{"ok":0,"reason":"no TEST_FAIL witness"}'
  tail -20 "$OUT/fuzz.out" >&2; tail -20 "$OUT/fuzz.err" >&2
  find "$OUT/findings" -maxdepth 3 -type d >&2; rm -rf "$OUT"; exit 1
fi
STAGE=$(jq -r '.stage' "$W/meta.json")
tr() { timeout 120 "$TRI" --case "$1" --stage test --timeout-ms 30000 2>/dev/null; }
N=$(tr "$W"); NST=$(jq -r '.status' <<<"$N"); NRP=$(jq -r '.reproduced' <<<"$N"); NSIG=$(jq -r '.signature' <<<"$N")
tamper() { local name="$1" cmd="$2"; cp -r "$W" "$OUT/$name"; eval "$cmd"; tr "$OUT/$name" | jq -r '.status'; }
E=$(tamper expected "sed -i 's/3 != 5/3 != 9/' '$OUT/expected/original/expected.json'")
P=$(tamper pkg "sed -i 's/a + b/a - b/' '$OUT/pkg/original/pkg/lib.mbt'")
B=$(tamper baseline "cp '$W/in.mbt' '$OUT/baseline/baseline.mbt'")
A=$(tamper argv "sed -i 's/\"test\"/\"build\"/' '$OUT/argv/original/argv.json'")
PIN=$(tamper pin "sed -i 's/\"pin_hash\": *\"[^\"]*\"/\"pin_hash\": \"deadbeef\"/' '$OUT/pin/original/pin.json'")
V=$(tamper env "sed -i 's/\"HOME\":\"/\"HOME\":\"\/tmp\/x/' '$OUT/env/original/env.json'")
controls=0; for s in "$E" "$P" "$B"; do [ "$s" != confirmed ] && controls=$((controls+1)); done
ok=0
if [ "$STAGE" = test ] && [ "$NST" = confirmed ] && [ "$NRP" = "3/3" ] && [ "$controls" = 3 ]; then ok=1; fi
jq -n --argjson ok "$ok" --arg stage "$STAGE" --arg status "$NST" --arg reproduced "$NRP" --arg signature "$NSIG" --argjson controls "$controls" --arg expected "$E" --arg pkg "$P" --arg baseline "$B" --arg argv_not_sensitive "$A" --arg env_not_sensitive "$V" --arg pin_control "$PIN" '{ok:$ok,stage:$stage,status:$status,reproduced:$reproduced,signature:$signature,controls:$controls,expected_control:$expected,pkg_control:$pkg,baseline_control:$baseline,argv_not_sensitive:$argv_not_sensitive,env_not_sensitive:$env_not_sensitive,pin_control:$pin_control}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
