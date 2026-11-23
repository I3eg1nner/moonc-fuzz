#!/bin/bash
# A1: passed seed -> /tmp campaign -> TEST_FAIL; 4 behavior controls.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
TRI="$ROOT/moonbit/_build/native/debug/build/cmd/triage/triage.exe"
OUT=/tmp/original_e2e_$$; mkdir -p "$OUT"
cp -r "$ROOT/regressions/pkg_test_fail" "$OUT/seed"
( cd "$OUT/seed" && moon test --target js ) >"$OUT/base.out" 2>"$OUT/base.err"; BRC=$?
baseline_clean=0; [ "$BRC" = 0 ] && baseline_clean=1
timeout 35 "$BIN" --out "$OUT" --duration 20 --workers 1 \
  --pkg-seed "$OUT/seed" --pkg-file lib_test.mbt \
  --pkg-argv "build --target js" --pkg-run-argv "test --target js" \
  >"$OUT/fuzz.out" 2>"$OUT/fuzz.err"
W=$(find "$OUT" -type d -path '*/findings/test/TEST_FAIL/*/original' | head -1 | xargs -r dirname)
if [ -z "$W" ] || [ ! -f "$W/meta.json" ]; then
  echo '{"ok":0,"reason":"no TEST_FAIL witness"}'
  tail -20 "$OUT/fuzz.out" >&2; tail -20 "$OUT/fuzz.err" >&2
  find "$OUT/findings" -maxdepth 3 -type d >&2; rm -rf "$OUT"; exit 1
fi
STAGE=$(jq -r '.stage' "$W/meta.json")
WKB=$(du -sk "$W" | awk '{print $1}')
NO_BUILD=1; [ -d "$W/pkg/_build" ] || [ -d "$W/target" ] && NO_BUILD=0
SRC_NE_BASE=0; cmp -s "$W/in.mbt" "$W/baseline.mbt" || SRC_NE_BASE=1
tr() { timeout 120 "$TRI" --case "$1" --stage test --timeout-ms 30000 2>/dev/null; }
N=$(tr "$W"); NST=$(jq -r '.status' <<<"$N"); NRP=$(jq -r '.reproduced' <<<"$N"); NSIG=$(jq -r '.signature' <<<"$N")
tamper() { local name="$1" cmd="$2"; cp -r "$W" "$OUT/$name"; eval "$cmd"; tr "$OUT/$name" | jq -r '.status'; }
E=$(tamper expected "jq '.stdout=\"BOGUS\" | .stderr=\"BOGUS\"' '$OUT/expected/original/expected.json' > '$OUT/expected/original/e2' && mv '$OUT/expected/original/e2' '$OUT/expected/original/expected.json'")
NM=$(tamper name "jq '.signature |= sub(\"fail_case\"; \"other_case\")' '$OUT/name/meta.json' > '$OUT/name/m2' && mv '$OUT/name/m2' '$OUT/name/meta.json'")
P=$(tamper pkg "sed -i 's/a + b/a - b/' '$OUT/pkg/original/pkg/lib.mbt'")
B=$(tamper baseline "cp '$W/in.mbt' '$OUT/baseline/baseline.mbt'")
A=$(tamper argv "sed -i 's/\"test\"/\"build\"/' '$OUT/argv/original/argv.json'")
V=$(tamper env "sed -i 's/\"HOME\":\"/\"HOME\":\"\/tmp\/x/' '$OUT/env/original/env.json'")
PIN=$(tamper pin "jq '.pin_hash=\"deadbeef\"' '$OUT/pin/original/pin.json' > '$OUT/pin/p2' && mv '$OUT/pin/p2' '$OUT/pin/original/pin.json'")
K=$(tamper kind "jq 'del(.kind)' '$OUT/kind/meta.json' > '$OUT/kind/m2' && mv '$OUT/kind/m2' '$OUT/kind/meta.json'")
S=$(tamper stage "jq 'del(.stage)' '$OUT/stage/meta.json' > '$OUT/stage/m2' && mv '$OUT/stage/m2' '$OUT/stage/meta.json'")
controls=0; for s in "$E" "$NM" "$P" "$B"; do [ "$s" != confirmed ] && controls=$((controls+1)); done
ok=0
if [ "$STAGE" = test ] && [ "$baseline_clean" = 1 ] && [ "$NST" = confirmed ] && [ "$NRP" = "3/3" ] && [ "$controls" = 4 ] && [ "$SRC_NE_BASE" = 1 ] && [ "$K" = schema_invalid ] && [ "$S" = schema_invalid ]; then ok=1; fi
jq -n --argjson ok "$ok" --arg stage "$STAGE" --arg status "$NST" --arg reproduced "$NRP" --arg signature "$NSIG" --argjson controls "$controls" --argjson baseline_clean "$baseline_clean" --argjson source_ne_baseline "$SRC_NE_BASE" --arg expected_control "$E" --arg name_control "$NM" --arg pkg_control "$P" --arg baseline_control "$B" --arg argv_not_sensitive "$A" --arg env_not_sensitive "$V" --arg pin_control "$PIN" --arg kind_control "$K" --arg stage_control "$S" --argjson witness_kb "$WKB" --argjson no_build "$NO_BUILD" '{ok:$ok,stage:$stage,status:$status,reproduced:$reproduced,signature:$signature,controls:$controls,baseline_clean:$baseline_clean,source_ne_baseline:$source_ne_baseline,expected_control:$expected_control,name_control:$name_control,pkg_control:$pkg_control,baseline_control:$baseline_control,argv_not_sensitive:$argv_not_sensitive,env_not_sensitive:$env_not_sensitive,pin_control:$pin_control,kind_control:$kind_control,stage_control:$stage_control,witness_kb:$witness_kb,no_build:$no_build}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
