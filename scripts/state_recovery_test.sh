#!/bin/bash
# J1: checkpoint kill/resume + corruption quarantine.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"
OUT="/tmp/mbtfuzz_state_recovery_$$"
EP1="$OUT/e1"; EP2="$OUT/e2"; mkdir -p "$EP1"
STATE1="$EP1/ep1/coverage_state.jsonl"
# Start epoch1 and stop only after a checkpoint exists.
"$BIN" --out "$EP1" --run-id ep1 --duration 30 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 2 --coverage-state "$STATE1" >"$OUT/e1.out" 2>"$OUT/e1.err" &
PID=$!
for i in $(seq 1 120); do
  [ -f "$STATE1" ] && [ -f "$STATE1.sha256" ] && break
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.5
done
HAS_STATE=0; [ -f "$STATE1" ] && [ -f "$STATE1.sha256" ] && HAS_STATE=1
kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
if [ "$HAS_STATE" = 0 ]; then
  echo '{"ok":false,"error":"no checkpoint before kill"}'; exit 1
fi
# Resume epoch2 in a fresh run dir using the checkpoint.
"$BIN" --out "$EP1" --run-id ep2 --duration 6 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 2 --coverage-state "$STATE1" >"$OUT/e2.out" 2>"$OUT/e2.err"
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
adds2=$(jq -r 'select(has("schema"))|.adds' "$STATE2")
dup=$(jq -r 'select(has("key"))|.key' "$STATE2" | sort | uniq -d | wc -l)
lost=$(comm -23 <(jq -r 'select(has("key"))|.key' "$STATE1" | sort -u) <(jq -r 'select(has("key"))|.key' "$STATE2" | sort -u) | wc -l)
# Budget: epoch2 adds must be <= 10% of epoch1 adds, with a 1 unit floor.
limit=$(( adds1 / 10 )); [ "$limit" -lt 1 ] && limit=1
budget_ok=0; [ "$adds2" -le "$limit" ] && budget_ok=1
# Corruption controls: truncate and checksum flip must quarantine.
COR="$OUT/corrupt"; mkdir -p "$COR"
cp "$STATE1" "$COR/coverage_state.jsonl"
# remove last non-empty line (truncation)
head -n -1 "$COR/coverage_state.jsonl" > "$COR/t"; mv "$COR/t" "$COR/coverage_state.jsonl"
"$BIN" --out "$COR" --run-id c1 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c1.out" 2>"$COR/c1.err"
q1=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
cp "$STATE1" "$COR/coverage_state.jsonl"; cp "$STATE1.sha256" "$COR/coverage_state.jsonl.sha256" 2>/dev/null || true
# flip one hex digit in checksum
sha=$(cat "$COR/coverage_state.jsonl.sha256" 2>/dev/null || echo 0000)
first=${sha:0:1}; [ "$first" = "0" ] && repl=1 || repl=0
printf '%s\n' "$repl${sha:1}" > "$COR/coverage_state.jsonl.sha256"
"$BIN" --out "$COR" --run-id c2 --duration 2 --seed-dir "$ROOT/templates" \
  --mode mbt --workers 1 --coverage-state "$COR/coverage_state.jsonl" >"$COR/c2.out" 2>"$COR/c2.err"
q2=$(ls "$COR"/coverage_state.jsonl.corrupt.* 2>/dev/null | wc -l)
quarantine_ok=0; [ "$q1" -gt 0 ] && [ "$q2" -gt 0 ] && quarantine_ok=1
ok=0
if [ "$RC2" -eq 0 ] && [ "$dup" -eq 0 ] && [ "$lost" -eq 0 ] && [ "$budget_ok" = 1 ] && [ "$quarantine_ok" = 1 ]; then ok=1; fi
jq -n --argjson ok "$ok" --argjson epoch1_keys "$keys1" --argjson epoch1_edges "$edges1" \
  --argjson epoch1_adds "$adds1" --argjson epoch2_keys "$keys2" --argjson epoch2_edges "$edges2" \
  --argjson epoch2_adds "$adds2" --argjson duplicates "$dup" --argjson lost "$lost" \
  --argjson budget_ok "$budget_ok" --argjson quarantine_ok "$quarantine_ok" \
  --arg h1 "$h1" --arg h2 "$h2" \
  '{ok:$ok,epoch1:{by_key:$epoch1_keys,edges:$epoch1_edges,coverage_adds:$epoch1_adds,header:$h1},epoch2:{by_key:$epoch2_keys,edges:$epoch2_edges,coverage_adds:$epoch2_adds,header:$h2},duplicates:$duplicates,lost:$lost,budget_ok:$budget_ok,quarantine_ok:$quarantine_ok}' > "$OUT/summary.json"
cat "$OUT/summary.json"
# keep for debug
[ "$ok" = 1 ]
