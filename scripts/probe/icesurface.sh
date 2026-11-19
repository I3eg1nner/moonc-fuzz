#!/usr/bin/env bash
# Trigger-surface sweep for F8 (async `raise?` callback after suspension) and
# F9 (`extern "C"` stub taking V128 on native debug link).
#
# Both defects were reported as single witnesses.  A witness says "this fails";
# a surface says which factor makes it fail, which is what lets a maintainer
# recognise the same bug in a different shape.  This script builds a small
# module per case, records the verdict, and prints one TSV row per run.
#
# Usage: scripts/probe/icesurface.sh [OUT_DIR]
#
# Verdicts:
#   ICE-assert       "Assertion failed" in the link-core output
#   ICE-unsupported  Machine_error(kind=unsupported; ...)
#   error            any other non-zero exit
#   ok               everything linked
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-/tmp/icesurface}
MOON=${MOON:-$HOME/.moon/bin/moon}
rm -rf "$OUT"
mkdir -p "$OUT"

verdict() { # log -> verdict
  local log=$1
  if grep -q "Assertion failed" "$log"; then
    echo "ICE-assert"
  elif grep -q "Machine_error(kind=unsupported" "$log"; then
    echo "ICE-unsupported"
  elif grep -qE "^(Error|error)" "$log"; then
    echo "error"
  else
    echo "ok"
  fi
}

run() { # label dir args...
  local label=$1 dir=$2
  shift 2
  local log="$OUT/$label.log"
  ( cd "$dir" && timeout 180 "$MOON" "$@" ) >"$log" 2>&1
  local rc=$?
  printf '%s\t%s\trc=%d\n' "$label" "$(verdict "$log")" "$rc"
}

# ---------------------------------------------------------------------------
# F8: async function, suspension point, callback parameter with `raise?`.
# ---------------------------------------------------------------------------
f8_case() { # name source-body test-body
  local name=$1 body=$2 test=$3
  local dir="$OUT/f8/$name"
  mkdir -p "$dir/p"
  cat >"$dir/moon.mod" <<'EOF'
name = "repro/f8surface"
version = "0.0.1"

import {
  "moonbitlang/async@0.22.9",
}
EOF
  cat >"$dir/p/moon.pkg" <<'EOF'
import {
  "moonbitlang/async" @aio,
}

supported_targets = "wasm+js+native"
EOF
  printf '%s\n' "$body" >"$dir/p/p.mbt"
  printf '%s\n' "$test" >"$dir/p/p_test.mbt"
  run "f8/$name" "$dir" test --target js --build-only
}

echo "== F8 =="
BASELINE='pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}'
TEST_BASE='async test "t" {
  assert_eq(@p.pick(x => if x == 1 { Some(x) } else { None }), Some(1))
}'
f8_case "a-baseline" "$BASELINE" "$TEST_BASE"
f8_case "b-no-raise-question" 'pub async fn[T] pick(select : (Int) -> T?) -> T? {
  @aio.pause()
  select(1)
}' 'async test "t" {
  assert_eq(@p.pick(x => Some(x)), Some(1))
}'
f8_case "c-nullable-raise-question" 'pub async fn[T] pick(select : (Int) -> T raise?) -> T {
  @aio.pause()
  select(1)
}' 'async test "t" {
  assert_eq(@p.pick(x => x), 1)
}'
f8_case "d-plain-callback" 'pub async fn[T] pick(select : (Int) -> T) -> T {
  @aio.pause()
  select(1)
}' 'async test "t" {
  assert_eq(@p.pick(x => x), 1)
}'
f8_case "e-no-suspend" 'pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  select(1)
}' "$TEST_BASE"
f8_case "f-call-before-suspend" 'pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  let r = select(1)
  @aio.pause()
  r
}' "$TEST_BASE"
# Non-async control.  The first version of this case returned `T?` while calling
# a `raise?` callback, which is a source error ([4122]), not a link result; the
# signature has to carry the error for the case to mean anything.
f8_case "g-not-async" 'pub fn[T] pick(select : (Int) -> T? raise?) -> T? raise? {
  select(1)
}' 'test "t" {
  let r = @p.pick(x => if x == 1 { Some(x) } else { None }) catch { _ => None }
  assert_eq(r, Some(1))
}'
f8_case "h-async-no-callback-pause" 'pub async fn spin() -> Unit {
  @aio.pause()
}' 'async test "t" {
  @p.spin()
}'

# ---------------------------------------------------------------------------
# F9: native stub whose `extern "C"` signature mentions V128, linked in debug.
# ---------------------------------------------------------------------------
F9_STUB='#include "moonbit.h"
#include <stdint.h>
#include <string.h>

static unsigned char sink[16];
static unsigned char src[16];

void repro_store_v128(uint64_t address, moonbit_v128_t value) {
  (void)address;
  memcpy(sink, &value, 16);
}

moonbit_v128_t repro_load_v128(uint64_t address) {
  (void)address;
  moonbit_v128_t v;
  memcpy(&v, src, 16);
  return v;
}

void repro_store_int(uint64_t address, int32_t value) {
  (void)address;
  sink[0] = (unsigned char)value;
}

void repro_store_float(uint64_t address, double value) {
  (void)address;
  memcpy(sink, &value, 8);
}'

f9_case() { # name source-body
  local name=$1 body=$2
  local dir="$OUT/f9/$name"
  mkdir -p "$dir"
  cat >"$dir/moon.mod" <<'EOF'
name = "repro/v128surface"
version = "0.1.0"
EOF
  cat >"$dir/moon.pkg" <<'EOF'
import {
  "moonbitlang/core/v128",
}

options(
  "native-stub": [ "stub.c" ],
  targets: { "lib.mbt": [ "native" ] },
)
EOF
  printf '%s\n' "$F9_STUB" >"$dir/stub.c"
  printf '%s\n' "$body" >"$dir/lib.mbt"
  run "f9/$name/debug-test" "$dir" test --target native --build-only
  run "f9/$name/release-test" "$dir" test --target native --build-only --release
  run "f9/$name/debug-build" "$dir" build --target native
}

echo "== F9 =="
F9_PARAM='extern "C" fn store_v128(address : UInt64, value : V128) -> Unit = "repro_store_v128"

pub fn store(x : Float) -> Unit {
  store_v128(0UL, @v128.f32x4_const(x, x, x, x))
}

test "store" {
  store(1.0)
}'
f9_case "a-param-v128" "$F9_PARAM"
f9_case "b-return-v128" 'extern "C" fn load_v128(address : UInt64) -> V128 = "repro_load_v128"

pub fn load() -> V128 {
  load_v128(0UL)
}

test "load" {
  let _ = load()
}'
f9_case "c-param-int" 'extern "C" fn store_int(address : UInt64, value : Int) -> Unit = "repro_store_int"

pub fn store_i(x : Int) -> Unit {
  store_int(0UL, x)
}

test "store" {
  store_i(1)
}'
f9_case "d-param-double" 'extern "C" fn store_float(address : UInt64, value : Double) -> Unit = "repro_store_float"

pub fn store_f(x : Double) -> Unit {
  store_float(0UL, x)
}

test "store" {
  store_f(1.0)
}'
f9_case "e-v128-no-call" 'extern "C" fn store_v128(address : UInt64, value : V128) -> Unit = "repro_store_v128"

test "no-call" {
  assert_eq(1, 1)
}'
