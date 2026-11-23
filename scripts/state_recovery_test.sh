#!/bin/bash
# J1: checkpoint kill/resume + corruption quarantine.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT="/tmp/mbtfuzz_state_recovery_$$"
EP1="$OUT/e1"; EP2="$OUT/e2"; mkdir -p "$EP1"
STATE1="$EP1/ep1/coverage_state.jsonl"
# Start epoch1 and stop only after a checkpoint exists.
"$BIN" --out "$EP1" --run-id ep1 --duration 20 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 2 --baseline-seeds 0 --trace-t1 20 --trace-t2 0 --trace-t3 0 \
  --trace-workers 2 --trace-wait-ms 100 --coverage-state "$STATE1" >"$OUT/e1.out" 2>"$OUT/e1.err" &
PID=$!
for i in $(seq 1 120); do
  if [ -f "$STATE1" ]; then
    c=$(jq -r 'select(has("schema"))|.cases' "$STATE1" 2>/dev/null || echo 0)
    o=$(jq -r 'select(has("schema"))|.owners' "$STATE1" 2>/dev/null || echo 0)
    ch=$(jq -r 'select(has("schema"))|.checksum' "$STATE1" 2>/dev/null || echo "")
    [ "${c:-0}" -ge 20 ] && [ "${o:-0}" -gt 0 ] && [ -n "${ch:-}" ] && break
  fi
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.5
done
HAS_STATE=0; [ -f "$STATE1" ] && HAS_STATE=1
kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
if [ "$HAS_STATE" = 0 ]; then
  echo '{"ok":false,"error":"no checkpoint before kill"}'; exit 1
fi
# Resume epoch2 in a fresh run dir using the checkpoint.
"$BIN" --out "$EP1" --run-id ep2 --duration 4 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 2 --baseline-seeds 0 --trace-t1 0 --trace-t2 0 --trace-t3 0 \
  --trace-workers 0 --trace-wait-ms 100 --coverage-state "$STATE1" \
  --coverage-state-out "$EP1/ep2/coverage_state.jsonl" >"$OUT/e2.out" 2>"$OUT/e2.err"
RC2=$?
STATE2="$EP1/ep2/coverage_state.jsonl"
[ -f "$STATE2" ] || { echo '{"ok":false,"error":"no epoch2 state"}'; exit 1; }
# Counts from state files.
keys1=$(jq -r 'select(has("key"))|.key' "$STATE1" | sort -u | wc -l)
keys2=$(jq -r 'select(has("key"))|.key' "$STATE2" | sort -u | wc -l)
edges1=$(jq -r 'select(has("edges"))|.edges|length' "$STATE1")
edges2=$(jq -r 'select(has("edges"))|.edges|length' "$STATE2")
h1=$(jq -c 'select(has("schema"))' "$STATE1")
h2=$(jq -c 'select(has("schema"))' "$STATE2")
adds1=$(jq -r 'select(has("schema"))|.adds' "$STATE1")
cases1=$(jq -r 'select(has("schema"))|.cases' "$STATE1")
owners1=$(jq -r 'select(has("schema"))|.owners' "$STATE1")
adds2=$(jq -r 'select(has("schema"))|.adds' "$STATE2")
cases2=$(jq -r 'select(has("schema"))|.cases' "$STATE2")
owners2=$(jq -r 'select(has("schema"))|.owners' "$STATE2")
last2=$(jq -r 'select(has("schema"))|.last' "$STATE2")
last1=$(jq -r 'select(has("schema"))|.last' "$STATE1")
dup=$(jq -r 'select(has("key"))|.key' "$STATE2" | sort | uniq -d | wc -l)
lost=$(comm -23 <(jq -r 'select(has("key"))|.key' "$STATE1" | sort -u) <(jq -r 'select(has("key"))|.key' "$STATE2" | sort -u) | wc -l)
# Budget: epoch2 adds must be <= 10% of epoch1 adds, with a 1 unit floor.
limit=$(( adds1 / 10 )); [ "$limit" -lt 1 ] && limit=1
delta=$(( adds2 - adds1 )); [ "$delta" -lt 0 ] && delta=0
cases_ok=0; [ "$cases2" -ge "$cases1" ] && cases_ok=1
owners_ok=0; [ "$owners2" -gt 0 ] && owners_ok=1
hash_ok=0
if [[ "$last1" =~ ^[0-9a-f]{40}$ ]] && [[ "$last2" =~ ^[0-9a-f]{40}$ ]] && [ "$last1" != "$last2" ]; then hash_ok=1; fi
budget_ok=0; [ "$delta" -le "$limit" ] && budget_ok=1
resign() {
  local f="$1" payload canon vals
  payload=$(tail -n +2 "$f")
  vals=$(head -1 "$f" | jq -r '[.epoch,.cases,.owners,.adds,.config_hash,.pin_hash,.corpus_hash,.last]|@tsv')
  eval "$(printf '%s' "$vals" | awk -F '\t' '{printf "e=%s c=%s o=%s a=%s ch=%s ph=%s coh=%s last=%s\n",$1,$2,$3,$4,$5,$6,$7,$8}')"
  canon="{\"schema\":\"coverage_state/v3\",\"version\":2,\"epoch\":"$e",\"cases\":"$c",\"owners\":"$o",\"adds\":"$a",\"config_hash\":\""$ch"\",\"pin_hash\":\""$ph"\",\"corpus_hash\":\""$coh"\",\"last\":\""$last"\"}"
  sum=$(printf '%s\n%s\n' "$canon" "$payload" | sha1sum | awk '{print $1}')
  sed -i "s/\"checksum\":\"[0-9a-f]*\"/\"checksum\":\"$sum\"/" "$f"
}

# Independent R1-R5 controls with skip-injection.
corrupt_count() { ls "$1"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l; }
run_control() {
  local name="$1" reason="$2" skip="$3" tamper="$4" seed="$5" strict="$6" expect_cases="$7"
  local dd="$OUT/R_${name}_def" sd="$OUT/R_${name}_skip"
  mkdir -p "$dd" "$sd"
  cp "$STATE1" "$dd/coverage_state.jsonl"; cp "$STATE1" "$sd/coverage_state.jsonl"
  D="$dd/coverage_state.jsonl" eval "$tamper"
  D="$sd/coverage_state.jsonl" eval "$tamper"
  local defout skipout
  if [ "$strict" = 1 ]; then
    "$BIN" --out "$dd" --run-id "${name}d" --duration 2 --seed-dir "$seed" --require-same-corpus \
      --mode mbt --workers 1 --coverage-state "$dd/coverage_state.jsonl" --recover-only >"$dd/out" 2>"$dd/err"
  else
    "$BIN" --out "$dd" --run-id "${name}d" --duration 2 --seed-dir "$seed" \
      --mode mbt --workers 1 --coverage-state "$dd/coverage_state.jsonl" --recover-only >"$dd/out" 2>"$dd/err"
  fi
  if [ "$strict" = 1 ]; then
    FUZZ_STATE_TEST_INJECT=1 FUZZ_STATE_SKIP="$skip" "$BIN" --out "$sd" --run-id "${name}s" --duration 2 --seed-dir "$seed" --require-same-corpus \
      --mode mbt --workers 1 --coverage-state "$sd/coverage_state.jsonl" --recover-only >"$sd/out" 2>"$sd/err"
  else
    FUZZ_STATE_TEST_INJECT=1 FUZZ_STATE_SKIP="$skip" "$BIN" --out "$sd" --run-id "${name}s" --duration 2 --seed-dir "$seed" \
      --mode mbt --workers 1 --coverage-state "$sd/coverage_state.jsonl" --recover-only >"$sd/out" 2>"$sd/err"
  fi
  local dnc dhit drec snc srec
  dnc=$(corrupt_count "$dd"); dhit=$(ls "$dd"/coverage_state.jsonl.corrupt.* 2>/dev/null | grep -c ".corrupt.$reason.")
  drec=$(tail -1 "$dd/out" | jq -r '.recovered_cases // 0')
  snc=$(corrupt_count "$sd"); srec=$(tail -1 "$sd/out" | jq -r '.recovered_cases // 0')
  if [ "$dnc" -eq 1 ] && [ "$dhit" -eq 1 ] && [ "$drec" -eq 0 ] && [ "$snc" -eq 0 ] && [ "$srec" -eq "$expect_cases" ]; then
    echo true
  else
    echo "def_n=$dnc def_hit=$dhit def_rec=$drec skip_n=$snc skip_rec=$srec expect=$expect_cases" >&2
    echo false
  fi
}
# R1 cases change, payload untouched.
r1=$(run_control r1 header header "sed -i 's/\"cases\":[0-9]*/\"cases\":999999/' \"\$D\"" "$ROOT/templates" 0 999999)
# R2 missing pin.
r2=$(run_control r2 identity identity "sed -i 's/,\"pin_hash\":\"[^\"]*\"//' \"\$D\"" "$ROOT/templates" 0 "$cases1")
# R3 pin change + canonical checksum recompute.
r3=$(run_control r3 pin pin "sed -i 's/\"pin_hash\":\"[^\"]*\"/\"pin_hash\":\"deadbeef\"/' \"\$D\"; resign \"\$D\"" "$ROOT/templates" 0 "$cases1")
# R4 missing corpus.
r4=$(run_control r4 identity identity "sed -i 's/,\"corpus_hash\":\"[^\"]*\"//' \"\$D\"" "$ROOT/templates" 0 "$cases1")
# R5 seed content change, strict.
mkdir -p "$OUT/seeds2"; cp "$ROOT/templates/01_int_ops.mbt" "$OUT/seeds2/01_int_ops.mbt"; printf '\n' >> "$OUT/seeds2/01_int_ops.mbt"
r5=$(run_control r5 corpus corpus "true" "$OUT/seeds2" 1 "$cases1")
# R5 default drift must load counts.
mkdir -p "$OUT/R_r5d"; cp "$STATE1" "$OUT/R_r5d/coverage_state.jsonl"
"$BIN" --out "$OUT/R_r5d" --run-id r5d --duration 2 --seed-dir "$OUT/seeds2" \
  --mode mbt --workers 1 --coverage-state "$OUT/R_r5d/coverage_state.jsonl" >"$OUT/R_r5d/out" 2>"$OUT/R_r5d/err"
drift=$(jq -r '.corpus_drift' "$OUT/R_r5d"/*/summary.json 2>/dev/null | tail -1)
drcase=$(jq -r 'select(has("schema"))|.cases' "$OUT/R_r5d/coverage_state.jsonl" 2>/dev/null || echo 0)
drown=$(jq -r 'select(has("schema"))|.owners' "$OUT/R_r5d/coverage_state.jsonl" 2>/dev/null || echo 0)
drift_ok=0; [ "${drift:-0}" = 1 ] && [ "$drcase" -eq "$cases1" ] && [ "$drown" -eq "$owners1" ] && grep -q 'corpus-drift' "$OUT/R_r5d/out" && drift_ok=1
# Only skip without TEST_INJECT must not bypass.
mkdir -p "$OUT/R_noinject"; cp "$STATE1" "$OUT/R_noinject/coverage_state.jsonl"
sed -i 's/"cases":[0-9]*/"cases":999999/' "$OUT/R_noinject/coverage_state.jsonl"
FUZZ_STATE_SKIP=header "$BIN" --out "$OUT/R_noinject" --run-id ni --duration 2 --seed-dir "$ROOT/templates" --mode mbt --workers 1 --coverage-state "$OUT/R_noinject/coverage_state.jsonl" --recover-only >"$OUT/R_noinject/out" 2>"$OUT/R_noinject/err"
ni_n=$(corrupt_count "$OUT/R_noinject"); ni_rec=$(tail -1 "$OUT/R_noinject/out" | jq -r '.recovered_cases // 0')
no_inject_ok=0; [ "$ni_n" -eq 1 ] && [ "$ni_rec" -eq 0 ] && no_inject_ok=1
quarantine_ok=0; [ "$r1" = true ] && [ "$r2" = true ] && [ "$r3" = true ] && [ "$r4" = true ] && [ "$r5" = true ] && [ "$drift_ok" = 1 ] && [ "$no_inject_ok" = 1 ] && quarantine_ok=1

# Per-control detail counts (default and skip).
r1_def=$(tail -1 "$OUT/R_r1_def/out" | jq -r '.recovered_cases // 0'); r1_skip=$(tail -1 "$OUT/R_r1_skip/out" | jq -r '.recovered_cases // 0')
r2_def=$(tail -1 "$OUT/R_r2_def/out" | jq -r '.recovered_cases // 0'); r2_skip=$(tail -1 "$OUT/R_r2_skip/out" | jq -r '.recovered_cases // 0')
r3_def=$(tail -1 "$OUT/R_r3_def/out" | jq -r '.recovered_cases // 0'); r3_skip=$(tail -1 "$OUT/R_r3_skip/out" | jq -r '.recovered_cases // 0')
r4_def=$(tail -1 "$OUT/R_r4_def/out" | jq -r '.recovered_cases // 0'); r4_skip=$(tail -1 "$OUT/R_r4_skip/out" | jq -r '.recovered_cases // 0')
r5_def=$(tail -1 "$OUT/R_r5_def/out" | jq -r '.recovered_cases // 0'); r5_skip=$(tail -1 "$OUT/R_r5_skip/out" | jq -r '.recovered_cases // 0')

# --recover: remove active, keep a valid .corrupt, expect counts restored.
REC="$OUT/recover"; mkdir -p "$REC"
cp "$STATE1" "$REC/coverage_state.jsonl.corrupt.1"
cp "$STATE1" "$REC/ref"
ref_cases=$(jq -r 'select(has("schema"))|.cases' "$REC/ref")
ref_owners=$(jq -r 'select(has("schema"))|.owners' "$REC/ref")
ref_epoch=$(jq -r 'select(has("schema"))|.epoch' "$REC/ref")
"$BIN" --out "$REC" --run-id r1 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --baseline-seeds 0 --trace-t1 0 --trace-t2 0 --trace-t3 0 --trace-workers 0 \
  --coverage-state "$REC/coverage_state.jsonl" --recover --recover-only >"$REC/out" 2>"$REC/err"
recover_json=$(tail -1 "$REC/out")
recover_cases=$(jq -r '.recovered_cases // 0' <<<"$recover_json")
recover_owners=$(jq -r '.recovered_owners // 0' <<<"$recover_json")
recover_epoch=$(jq -r '.recovered_epoch // 0' <<<"$recover_json")
recover_ok=0
[ "$recover_cases" = "$ref_cases" ] && [ "$recover_owners" = "$ref_owners" ] && [ "$recover_epoch" = "$((ref_epoch+1))" ] && recover_ok=1
# Three kill points: old or new must be valid, never empty.
kill_ok=1
for mode in mid_payload after_tmp after_rename; do
  RK="$OUT/kill_$mode"; mkdir -p "$RK"
  cp "$STATE1" "$RK/coverage_state.jsonl"
  FUZZ_STATE_KILL="$mode" "$BIN" --out "$RK" --run-id k1 --duration 8 --seed-dir "$ROOT/templates" \
    --mode mbt --workers 1 --baseline-seeds 0 --trace-t1 0 --trace-t2 0 --trace-t3 0 --trace-workers 0 \
    --coverage-state "$RK/coverage_state.jsonl" >"$RK/out" 2>"$RK/err"
  kc=$(jq -r 'select(has("schema"))|.cases' "$RK/coverage_state.jsonl" 2>/dev/null || echo "")
  kh=$(jq -r 'select(has("schema"))|.checksum' "$RK/coverage_state.jsonl" 2>/dev/null || echo "")
  [ -n "$kc" ] && [ -n "$kh" ] || kill_ok=0
done
ok=0
if [ "$RC2" -eq 0 ] && [ "$dup" -eq 0 ] && [ "$lost" -eq 0 ] && [ "$budget_ok" = 1 ] && [ "$cases_ok" = 1 ] && [ "$owners_ok" = 1 ] && [ "$hash_ok" = 1 ] && [ "$quarantine_ok" = 1 ] && [ "$recover_ok" = 1 ] && [ "$kill_ok" = 1 ]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson epoch1_keys "$keys1" --argjson epoch1_edges "$edges1" \
  --argjson epoch1_adds "$adds1" --argjson epoch1_cases "$cases1" --argjson epoch1_owners "$owners1" --argjson epoch2_keys "$keys2" --argjson epoch2_edges "$edges2" \
  --argjson epoch2_adds "$adds2" --argjson epoch2_cases "$cases2" --argjson epoch2_owners "$owners2" --argjson add_delta "$delta" --argjson cases_ok "$cases_ok" --argjson owners_ok "$owners_ok" --argjson hash_ok "$hash_ok" --argjson duplicates "$dup" --argjson lost "$lost" \
  --argjson budget_ok "$budget_ok" --argjson quarantine_ok "$quarantine_ok" --arg r1 "$r1" --arg r2 "$r2" --arg r3 "$r3" --arg r4 "$r4" --arg r5 "$r5" --argjson r1_def "$r1_def" --argjson r1_skip "$r1_skip" --argjson r2_def "$r2_def" --argjson r2_skip "$r2_skip" --argjson r3_def "$r3_def" --argjson r3_skip "$r3_skip" --argjson r4_def "$r4_def" --argjson r4_skip "$r4_skip" --argjson r5_def "$r5_def" --argjson r5_skip "$r5_skip" --argjson drift_ok "$drift_ok" --argjson no_inject_ok "$no_inject_ok" --argjson ni_n "$ni_n" --argjson ni_rec "$ni_rec" --argjson recover_ok "$recover_ok" --argjson recover_cases "$recover_cases" --argjson kill_ok "$kill_ok" \
  --arg h1 "$h1" --arg h2 "$h2" \
  '{ok:$ok,epoch1:{by_key:$epoch1_keys,edges:$epoch1_edges,coverage_adds:$epoch1_adds,cases:$epoch1_cases,owners:$epoch1_owners,header:$h1},epoch2:{by_key:$epoch2_keys,edges:$epoch2_edges,coverage_adds:$epoch2_adds,cases:$epoch2_cases,owners:$epoch2_owners,add_delta:$add_delta,header:$h2},duplicates:$duplicates,lost:$lost,budget_ok:$budget_ok,cases_ok:$cases_ok,owners_ok:$owners_ok,hash_ok:$hash_ok,quarantine_ok:$quarantine_ok,r1:$r1,r1_def:$r1_def,r1_skip:$r1_skip,r2_def:$r2_def,r2_skip:$r2_skip,r3_def:$r3_def,r3_skip:$r3_skip,r4_def:$r4_def,r4_skip:$r4_skip,r5_def:$r5_def,r5_skip:$r5_skip,r2:$r2,r3:$r3,r4:$r4,r5:$r5,drift_ok:$drift_ok,no_inject_ok:$no_inject_ok,ni_n:$ni_n,ni_rec:$ni_rec,recover_ok:$recover_ok,recover_cases:$recover_cases,kill_ok:$kill_ok}' > "$OUT/summary.json"
cat "$OUT/summary.json"
# keep for debug
[ "$ok" = 1 ]
