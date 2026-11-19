#!/usr/bin/env bash
# Third-party MoonBit corpus: azhzx/qbe.mbt (a QBE reimplementation in MoonBit).
#
# WHY THIS EXISTS
#   Every corpus this project has run so far is either generated code or a small
#   library package.  qbe.mbt is a 1.5 MB, 188-file compiler with native C
#   stubs, `moonbitlang/async` imports and its own 549-test suite, so it is a
#   much harder conformance input for `moonc`.  It is used as a *corpus*, not as
#   a backend: MoonBit's native target does not go through QBE.
#
# WHAT IT MEASURES
#   `moon test --target native` on a pinned commit must reach 549/549.  A drop
#   is either a compiler regression in the host toolchain or an upstream change
#   in the corpus; both are worth stopping for.
#
# COST
#   ~7 MB clone and roughly 3 minutes cold (build + 549 tests), seconds warm.
#
# NOTE
#   The clone is patched locally: `native/native_stub.c` uses RTLD_DEFAULT
#   without `_GNU_SOURCE`, which glibc rejects.  That is a portability bug in
#   the corpus, not in moonc, so the patch is applied to the clone only and is
#   idempotent.
#
# Usage:
#   scripts/probe/qbe_corpus.sh [--json OUT]
# Env:
#   QBE_SRC        reuse an existing checkout instead of cloning to /tmp
#   QBE_COMMIT     override the pinned commit
#   MOON           path to `moon` (default ~/.moon/bin/moon)
set -uo pipefail

PIN="2e1f3e5"
SRC="${QBE_SRC:-/tmp/mbtfuzz_qbe_corpus}"
COMMIT="${QBE_COMMIT:-$PIN}"
MOON="${MOON:-$HOME/.moon/bin/moon}"
JSON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone --depth 1 -q https://github.com/azhzx/qbe.mbt.git "$SRC" || {
    echo '{"ok":false,"error":"clone failed"}' >&2; exit 1; }
fi

have=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo none)
if [ "$have" != "$COMMIT" ]; then
  if git -C "$SRC" fetch -q --depth 1 origin "$COMMIT" 2>/dev/null; then
    git -C "$SRC" checkout -q FETCH_HEAD 2>/dev/null || true
  fi
fi
have=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo none)

# glibc requires _GNU_SOURCE for RTLD_DEFAULT.  Idempotent.
if ! grep -q '^#define _GNU_SOURCE' "$SRC/native/native_stub.c" 2>/dev/null; then
  python3 - "$SRC/native/native_stub.c" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write("#ifndef _GNU_SOURCE\n#define _GNU_SOURCE\n#endif\n" + s)
PY
fi

start=$(date +%s)
out=$(cd "$SRC" && timeout 900 "$MOON" test --target native 2>&1)
rc=$?
ms=$(( ($(date +%s) - start) * 1000 ))

total=$(printf '%s' "$out" | sed -n 's/^Total tests: \([0-9]*\).*/\1/p' | tail -1)
passed=$(printf '%s' "$out" | sed -n 's/^Total tests: [0-9]*, passed: \([0-9]*\).*/\1/p' | tail -1)
failed=$(printf '%s' "$out" | sed -n 's/^Total tests: [0-9]*, passed: [0-9]*, failed: \([0-9]*\).*/\1/p' | tail -1)
total=${total:-0}; passed=${passed:-0}; failed=${failed:-0}

ok=false
if [ "$rc" -eq 0 ] && [ "$failed" = "0" ] && [ "$total" != "0" ]; then ok=true; fi

line=$(printf '{"ok":%s,"corpus":"azhzx/qbe.mbt","commit":"%s","total":%s,"passed":%s,"failed":%s,"rc":%s,"ms":%s}' \
  "$ok" "$have" "$total" "$passed" "$failed" "$rc" "$ms")
echo "$line"
if [ -n "$JSON" ]; then printf '%s\n' "$line" > "$JSON"; fi
[ "$ok" = "true" ] || exit 1
