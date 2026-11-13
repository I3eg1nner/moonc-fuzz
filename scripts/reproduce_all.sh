#!/bin/bash
# Reproduce every local PoC and assert the expected exit status/signature.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOONC="${MOONC:-$HOME/.moon/bin/moonc}"
MOON="${MOON:-$HOME/.moon/bin/moon}"
FMT="${MOONFMT:-$HOME/.moon/bin/moonfmt}"
TMP="${TMPDIR:-/tmp}/mbtfuzz_repro_$$"
mkdir -p "$TMP"
PASS=0
FAIL=0

check() {
  local label="$1" expected="$2" cwd="$3" needle="$4"
  shift 4
  ( cd "$cwd" && "$@" ) >"$TMP/out" 2>"$TMP/err"
  local rc=$?
  local ok=1
  [ "$rc" = "$expected" ] || ok=0
  if [ -n "$needle" ] && ! grep -qF -- "$needle" "$TMP/err" "$TMP/out"; then
    ok=0
  fi
  if [ "$ok" = "1" ]; then
    echo "[PASS] $label rc=$rc expected=$expected"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $label rc=$rc expected=$expected needle='$needle'"
    sed -n '1,8p' "$TMP/err"
    FAIL=$((FAIL + 1))
  fi
}

echo "toolchain:"
"$MOONC" -v
"$MOON" version --all | head -3

check F1 139 poc/f1_moon_pkg_segv "" "$MOONC" syncheck moon.pkg
check F1b 139 poc/f1b_pkg_map_segv "" "$MOONC" syncheck moon.pkg

(cd poc/f2_lex_escape_ice && rm -rf _build)
check F2 1 poc/f2_lex_escape_ice 'Invalid_argument("Char.chr")' "$MOON" check

check F2b 199 poc/f2b_zwsp_escape_t2_ice 'Char.chr' \
  "$MOONC" build-package main.mbt -o "$TMP/f2b.core" -pkg f2b/p \
  -pkg-type executable \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/builtin/builtin.mi:moonbitlang/core/builtin" \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/prelude/prelude.mi:prelude" \
  -pkg-sources f2b/p:. -target wasm -g -O0 -workspace-path . \
  -all-pkgs "$ROOT/harness/all_pkgs.json"

check F3 134 poc/f3_parser_oom "out of memory" \
  prlimit --as=6442450944 -- "$MOONC" syncheck cmd/main.mbt

check F4 199 poc/f4_invalid_utf8 'utf8_decode' "$MOONC" syncheck doc.mbt.md
check F4b 199 poc/f4b_invalid_utf8_2 'utf8_decode' "$MOONC" syncheck doc.mbt.md

check F5-parse 0 poc/f5_prefix_plus "" "$MOONC" syncheck u.mbt
check F5-fmt 0 poc/f5_prefix_plus "" "$FMT" u.mbt -o "$TMP/u1.mbt"
check F5-reparse 2 poc/f5_prefix_plus 'E3001' "$MOONC" syncheck "$TMP/u1.mbt"
if grep -qF '~+' "$TMP/u1.mbt"; then
  echo "[PASS] F5-formatter-emits-tilde-plus"
  PASS=$((PASS + 1))
else
  echo "[FAIL] F5-formatter-emits-tilde-plus"
  FAIL=$((FAIL + 1))
fi

(cd poc/f6_native_export_closure_min && rm -rf _build)
check F6-min 255 poc/f6_native_export_closure_min \
  'reject_export_type_containing_unsupported_callback' \
  "$MOON" build --target native

if [ -d "$ROOT/assets/f6_external/moonldif" ]; then
  (cd "$ROOT/assets/f6_external/moonldif" && rm -rf _build)
  check F6-external 1 assets/f6_external/moonldif \
    'reject_export_type_containing_unsupported_callback' \
    "$MOON" test --target native
else
  echo "[SKIP] F6-external (run scripts/fetch_assets.sh)"
fi

rm -rf "$TMP"
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = "0" ]
