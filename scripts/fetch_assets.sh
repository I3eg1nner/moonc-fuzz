#!/bin/bash
# Download the large assets that are intentionally not committed.
#   - WeiR-h/moonldif@0.7.6 for the external F6 reproduction (12 MB)
#   - moonbitlang/core source tree for the seed corpus (optional, ~16 MB)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="${ASSETS_DIR:-$ROOT/assets}"
mkdir -p "$ASSETS"

# 1. F6 external package.  Prefer the registry cache, then `moon add`.
F6="$ASSETS/f6_external"
mkdir -p "$F6"
ZIP="$HOME/.moon/registry/cache/WeiR-h/moonldif/0.7.6.zip"
if [ -f "$ZIP" ]; then
  rm -rf "$F6/moonldif"
  unzip -q "$ZIP" -d "$F6/moonldif"
else
  cat > "$F6/moon.mod" <<'MOD'
name = "f6external"
version = "0.1.0"
MOD
  ( cd "$F6" && moon add WeiR-h/moonldif@0.7.6 )
  rm -rf "$F6/moonldif"
  cp -a "$F6/.mooncakes/WeiR-h/moonldif" "$F6/moonldif"
  rm -rf "$F6/moonldif/_build"
fi
echo "F6 asset: $F6/moonldif"

# 2. Seed corpus.  This is optional for the PoCs, required for a fuzz campaign.
CORE="$ASSETS/core"
if [ "${FETCH_SEEDS:-1}" = "1" ]; then
  if [ ! -d "$CORE" ]; then
    git clone --depth 1 https://github.com/moonbitlang/core "$CORE"
  fi
  mkdir -p "$ROOT/seeds"
  find "$CORE" -type f \( -name '*.mbt' -o -name '*.mbt.md' -o -name '*.mbti' \
    -o -name 'moon.pkg' -o -name 'moon.mod' \) -print0 |
    xargs -0 -r cp --parents -t "$ROOT/seeds"
  echo "seed files: $(find "$ROOT/seeds" -type f | wc -l) under $ROOT/seeds"
fi
