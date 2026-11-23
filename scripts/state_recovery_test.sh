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
dup=$(jq -r 'select(has("key"))|.key' "$STATE2" | sort | uniq -d | wc -l)
lost=$(comm -23 <(jq -r 'select(has("key"))|.key' "$STATE1" | sort -u) <(jq -r 'select(has("key"))|.key' "$STATE2" | sort -u) | wc -l)
# Budget: epoch2 adds must be <= 10% of epoch1 adds, with a 1 unit floor.
limit=$(( adds1 / 10 )); [ "$limit" -lt 1 ] && limit=1
delta=$(( adds2 - adds1 )); [ "$delta" -lt 0 ] && delta=0
cases_ok=0; [ "$cases2" -ge "$cases1" ] && cases_ok=1
owners_ok=0; [ "$owners2" -gt 0 ] && owners_ok=1
hash_ok=0; [ -n "$last2" ] && [ "$last2" != "" ] && hash_ok=1
budget_ok=0; [ "$delta" -le "$limit" ] && budget_ok=1
# Corruption controls: truncate and checksum flip must quarantine.
COR="$OUT/corrupt"; mkdir -p "$COR"
cp "$STATE1" "$COR/coverage_state.jsonl"
# remove last non-empty line (truncation)
head -n -1 "$COR/coverage_state.jsonl" > "$COR/t"; mv "$COR/t" "$COR/coverage_state.jsonl"
"$BIN" --out "$COR" --run-id c1 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c1.out" 2>"$COR/c1.err"
q1=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
cp "$STATE1" "$COR/coverage_state.jsonl"
# flip one hex digit in the header checksum (the authoritative copy)
sha=$(jq -r 'select(has("schema"))|.checksum' "$COR/coverage_state.jsonl" 2>/dev/null || echo 0000)
first=${sha:0:1}; [ "$first" = "0" ] && repl=1 || repl=0
sed -i "0,/\"checksum\":\"$sha\"/s//\"checksum\":\"$sha\"/\"checksum\":\"$repl${sha:1}\"/" "$COR/coverage_state.jsonl"
# header is the only checksum
"$BIN" --out "$COR" --run-id c2 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c2.out" 2>"$COR/c2.err"
q2=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
# Schema mismatch must quarantine, not reinterpret as v2.
cp "$STATE1" "$COR/coverage_state.jsonl"
sed -i 's/"schema":"coverage_state\/v2"/"schema":"coverage_state\/v99"/' "$COR/coverage_state.jsonl"
"$BIN" --out "$COR" --run-id c3 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c3.out" 2>"$COR/c3.err"
q3=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
# Missing checksum must quarantine, not silently clear/merge.
cp "$STATE1" "$COR/coverage_state.jsonl"
sed -i 's/"checksum":"[0-9a-f]*"/"checksum":""/' "$COR/coverage_state.jsonl"
"$BIN" --out "$COR" --run-id c4 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c4.out" 2>"$COR/c4.err"
q4=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
quarantine_ok=0; [ "$q1" -gt 0 ] && [ "$q2" -gt 0 ] && [ "$q3" -gt 0 ] && [ "$q4" -gt 0 ] && quarantine_ok=1
ok=0
if [ "$RC2" -eq 0 ] && [ "$dup" -eq 0 ] && [ "$lost" -eq 0 ] && [ "$budget_ok" = 1 ] && [ "$cases_ok" = 1 ] && [ "$owners_ok" = 1 ] && [ "$hash_ok" = 1 ] && [ "$quarantine_ok" = 1 ]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson epoch1_keys "$keys1" --argjson epoch1_edges "$edges1" \
  --argjson epoch1_adds "$adds1" --argjson epoch1_cases "$cases1" --argjson epoch1_owners "$owners1" --argjson epoch2_keys "$keys2" --argjson epoch2_edges "$edges2" \
  --argjson epoch2_adds "$adds2" --argjson epoch2_cases "$cases2" --argjson epoch2_owners "$owners2" --argjson add_delta "$delta" --argjson cases_ok "$cases_ok" --argjson owners_ok "$owners_ok" --argjson hash_ok "$hash_ok" --argjson duplicates "$dup" --argjson lost "$lost" \
  --argjson budget_ok "$budget_ok" --argjson quarantine_ok "$quarantine_ok" \
  --arg h1 "$h1" --arg h2 "$h2" \
  '{ok:$ok,epoch1:{by_key:$epoch1_keys,edges:$epoch1_edges,coverage_adds:$epoch1_adds,cases:$epoch1_cases,owners:$epoch1_owners,header:$h1},epoch2:{by_key:$epoch2_keys,edges:$epoch2_edges,coverage_adds:$epoch2_adds,cases:$epoch2_cases,owners:$epoch2_owners,add_delta:$add_delta,header:$h2},duplicates:$duplicates,lost:$lost,budget_ok:$budget_ok,cases_ok:$cases_ok,owners_ok:$owners_ok,hash_ok:$hash_ok,quarantine_ok:$quarantine_ok}' > "$OUT/summary.json"
cat "$OUT/summary.json"
# keep for debug
[ "$ok" = 1 ]
