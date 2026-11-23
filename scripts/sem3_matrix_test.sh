#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
SEM="$ROOT/moonbit/_build/native/debug/build/cmd/sem3/sem3.exe"
FB="$ROOT/scripts/fake_backend.sh"
OUT=/tmp/sem3_matrix_$$; mkdir -p "$OUT"
run() {
  local name="$1" family="$2" expected="$3" js="$4" wg="$5" nat="$6"
  local od="$OUT/$name"; rm -rf "$od"; mkdir -p "$od"
  OUT_JS="${7:-123}" OUT_WASM_GC="${8:-123}" OUT_NATIVE="${9:-123}" \
  MODE_JS="$js" MODE_WASM_GC="$wg" MODE_NATIVE="$nat" \
  SEM3_BACKEND_TIMEOUT_MS=1000 \
  "$SEM" --out "$od" --limit 1 --duration 3 --family "$family" --no-node \
    --expected "$expected" --backend-timeout-ms 1000 \
    --backend-cmd "js=$FB" --backend-cmd "wasm-gc=$FB" --backend-cmd "native=$FB" \
    >"$od/out" 2>"$od/err"
  jq -c . "$od/summary.json"
}
a=$(run A i32 123 ok ok timeout)
b=$(run B i32 123 ok trap compile_error)
c=$(run C array_oob "" trap trap trap)
d=$(run D i32 123 ok ok ok)
e=$(run E i32 123 ok ok ok 456 789)
get() { jq -r ".families[] | select(.witness==1) | .witness" <<<"$1" 2>/dev/null; }
# easier: top-level fields; family object has witness/inconclusive
wa=$(jq -r '.families.i32.witness' <<<"$a"); ia=$(jq -r '.families.i32.inconclusive' <<<"$a")
wb=$(jq -r '.families.i32.witness' <<<"$b"); ib=$(jq -r '.families.i32.inconclusive' <<<"$b")
wc=$(jq -r '.families.array_oob.witness' <<<"$c")
wd=$(jq -r '.families.i32.witness' <<<"$d"); id=$(jq -r '.families.i32.inconclusive' <<<"$d")
we=$(jq -r '.families.i32.witness' <<<"$e")
ok=0
if [ "$wa" = 0 ] && [ "$ia" = 1 ] && [ "$wb" = 0 ] && [ "$ib" = 1 ] && \
   [ "$wc" = 1 ] && [ "$wd" = 0 ] && [ "$id" = 0 ] && [ "$we" = 1 ]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson A_witness "$wa" --argjson A_inconclusive "$ia" --argjson B_witness "$wb" --argjson B_inconclusive "$ib" --argjson C_witness "$wc" --argjson D_witness "$wd" --argjson D_inconclusive "$id" --argjson E_witness "$we" '{ok:$ok,A:{witness:$A_witness,inconclusive:$A_inconclusive},B:{witness:$B_witness,inconclusive:$B_inconclusive},C:{witness:$C_witness},D:{witness:$D_witness,inconclusive:$D_inconclusive},E:{witness:$E_witness}}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
