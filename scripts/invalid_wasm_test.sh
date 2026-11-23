#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; BIN="$ROOT/moonbit/_build/native/debug/build/cmd/fuzz/fuzz.exe"; TRI="$ROOT/moonbit/_build/native/debug/build/cmd/triage/triage.exe"; OUT=/tmp/inv_wasm_$$; mkdir -p "$OUT"
# positive 415 real campaign
cp -r "$ROOT/oracle_cases/miscompile/415" "$OUT/seed415"
timeout 25 "$BIN" --out "$OUT/p415" --duration 8 --workers 1 --pkg-seed "$OUT/seed415" --pkg-file main.mbt --pkg-argv "build --target wasm-gc" --pkg-run-argv "test --target wasm-gc" >/dev/null 2>&1
W=$(find "$OUT/p415" -type d -path '*/INVALID_WASM/*/original'|head -1|xargs -r dirname)
PK=0; PST=missing
if [ -n "$W" ]; then PK=$(jq -r .kind "$W/meta.json"); PST=$(timeout 120 "$TRI" --case "$W" --stage build --timeout-ms 30000 2>/dev/null | jq -r .status); fi
# negative a: syntax/type error package, must not create INVALID_WASM/confirmed
mkdir -p "$OUT/syntax"; printf 'name = "bad"\nversion = "0.1.0"\n' > "$OUT/syntax/moon.mod"; printf 'fn main { let x : Int = "s" }\n' > "$OUT/syntax/main.mbt"; printf 'options("is-main": true)\n' > "$OUT/syntax/moon.pkg"
timeout 20 "$BIN" --out "$OUT/psyn" --duration 6 --workers 1 --pkg-seed "$OUT/syntax" --pkg-file main.mbt --pkg-argv "build --target wasm-gc" >/dev/null 2>&1
SW=$(find "$OUT/psyn" -type d -path '*/INVALID_WASM/*/original'|head -1); SN=0; [ -n "$SW" ] && SN=1
# negative b: clean package no witness
cp -r "$ROOT/regressions/package_seeds/single" "$OUT/clean"
timeout 20 "$BIN" --out "$OUT/pclean" --duration 6 --workers 1 --pkg-seed "$OUT/clean" --pkg-file lib.mbt --pkg-argv "build --target wasm-gc" >/dev/null 2>&1
CW=$(find "$OUT/pclean" -type d -path '*/INVALID_WASM/*/original'|head -1); CN=0; [ -n "$CW" ] && CN=1
ok=0; [ "$PK" = INVALID_WASM ] && [ "$PST" = confirmed ] && [ "$SN" = 0 ] && [ "$CN" = 0 ] && ok=1
jq -n --argjson ok "$ok" --arg kind "$PK" --arg status "$PST" --argjson syntax_invalid "$SN" --argjson clean_invalid "$CN" '{ok:$ok,positive_kind:$kind,positive_status:$status,syntax_invalid_witness:$syntax_invalid,clean_invalid_witness:$clean_invalid}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
