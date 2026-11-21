#!/usr/bin/env bash
# Replay one sem3 witness: same source, same targets, compare expected.
set -euo pipefail
W=${1:?usage: replay_sem3.sh WITNESS_DIR}
TMP=${2:-/tmp/sem3_replay}
rm -rf "$TMP"; mkdir -p "$TMP"
cp "$W/main.mbt" "$TMP/main.mbt"
printf 'name = "sem3replay"\nversion = "0.1.0"\n' > "$TMP/moon.mod"
printf 'pkgtype(kind: "executable")\n' > "$TMP/moon.pkg"
cat "$W/expected.txt"; echo "--- expected above"
for t in js wasm-gc native; do
  ( cd "$TMP" && timeout 60 moon run main.mbt --target "$t" > "$TMP/$t.out" 2>"$TMP/$t.err" ); echo "--- $t rc=$?"; head -5 "$TMP/$t.out"
done
