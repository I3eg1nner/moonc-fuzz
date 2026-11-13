#!/bin/bash
# Reproduce every local PoC against the pinned toolchain.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOONC="${MOONC:-$HOME/.moon/bin/moonc}"
MOON="${MOON:-$HOME/.moon/bin/moon}"
FMT="${MOONFMT:-$HOME/.moon/bin/moonfmt}"
cd "$ROOT"

run() { echo "== $*"; "$@"; echo "rc=$?"; }

echo "toolchain:"; "$MOONC" -v; "$MOON" version --all | head -3

run "$MOONC" syncheck poc/f1_moon_pkg_segv/moon.pkg
(cd poc/f1b_pkg_map_segv && run "$MOONC" syncheck moon.pkg)
(cd poc/f2_lex_escape_ice && rm -rf _build && run "$MOON" check)
(cd poc/f2b_zwsp_escape_t2_ice && run "$MOONC" build-package main.mbt \
  -o /tmp/f2b.core -pkg f2b/p -pkg-type executable \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/builtin/builtin.mi:moonbitlang/core/builtin" \
  -i "$HOME/.moon/lib/core/_build/wasm/release/bundle/prelude/prelude.mi:prelude" \
  -pkg-sources f2b/p:. -target wasm -g -O0 -workspace-path . \
  -all-pkgs "$ROOT/harness/all_pkgs.json")
(cd poc/f3_parser_oom && run prlimit --as=6442450944 -- "$MOONC" syncheck cmd/main.mbt)
run "$MOONC" syncheck poc/f4_invalid_utf8/doc.mbt.md
run "$MOONC" syncheck poc/f4b_invalid_utf8_2/doc.mbt.md
(cd poc/f5_prefix_plus && {
  run "$MOONC" syncheck u.mbt
  run "$FMT" u.mbt -o /tmp/f5_u1.mbt
  run "$MOONC" syncheck /tmp/f5_u1.mbt
})
(cd poc/f6_native_export_closure_min && rm -rf _build && run "$MOON" build --target native)

if [ -d "$ROOT/assets/f6_external/moonldif" ]; then
  (cd "$ROOT/assets/f6_external/moonldif" && rm -rf _build && run "$MOON" test --target native)
else
  echo "== F6 external skipped (run scripts/fetch_assets.sh)"
fi
