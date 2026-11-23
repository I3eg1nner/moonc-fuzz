#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; TRI="$ROOT/moonbit/_build/native/debug/build/cmd/triage/triage.exe"
BASE="$ROOT/regressions/pkg_test_fail/witness"; OUT=/tmp/tf_triage_$$; mkdir -p "$OUT"
run() { "$TRI" --case "$1" --stage test --timeout-ms 30000 2>/dev/null; }
status() { run "$1" | jq -r '.status'; }
repro() { run "$1" | jq -r '.reproduced'; }
# normal
n=$(run "$BASE"); nst=$(jq -r '.status' <<<"$n"); nrep=$(jq -r '.reproduced' <<<"$n"); nsig=$(jq -r '.signature' <<<"$n")
csig=$(jq -r '.signature' "$BASE/capsule.json"); msig=$(jq -r '.signature' "$BASE/meta.json")
# expected text tamper
cp -r "$BASE" "$OUT/exp"; sed -i 's/1 != 2/1 != 9/' "$OUT/exp/meta.json"; est=$(status "$OUT/exp"); erep=$(repro "$OUT/exp")
# test name tamper
cp -r "$BASE" "$OUT/name"; sed -i 's/fail_case/other_case/' "$OUT/name/meta.json"; tst=$(status "$OUT/name"); trep=$(repro "$OUT/name")
# baseline becomes failing
cp -r "$BASE" "$OUT/base"; cp "$OUT/base/in.mbt" "$OUT/base/baseline.mbt"; bst=$(status "$OUT/base"); brep=$(repro "$OUT/base")
ok=0
[ "$nst" = confirmed ] && [ "$nrep" = "3/3" ] && [ "$nsig" = "$csig" ] && [ "$csig" = "$msig" ] && \
[ "$est" != confirmed ] && [ "$erep" != "3/3" ] && \
[ "$tst" != confirmed ] && [ "$trep" != "3/3" ] && \
[ "$bst" != confirmed ] && ok=1
jq -n --argjson ok "$ok" --arg normal_reproduced "$nrep" --arg normal_status "$nst" --arg normal_signature "$nsig" --arg expected_status "$est" --arg expected_reproduced "$erep" --arg name_status "$tst" --arg name_reproduced "$trep" --arg baseline_status "$bst" --arg baseline_reproduced "$brep" '{ok:$ok,normal_status:$normal_status,normal_reproduced:$normal_reproduced,normal_signature:$normal_signature,expected_tamper_status:$expected_status,expected_tamper_reproduced:$expected_reproduced,name_tamper_status:$name_status,name_tamper_reproduced:$name_reproduced,baseline_status:$baseline_status,baseline_reproduced:$baseline_reproduced}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
