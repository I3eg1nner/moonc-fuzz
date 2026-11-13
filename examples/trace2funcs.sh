#!/usr/bin/env bash
# Minimal runnable example: turn `nm -n` output plus a QEMU `-d exec` log
# into the sorted function set, then compare with the committed expectation.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo/moonbit"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

moon run cmd/trace2funcs -- \
  accept_fixtures/nm.txt accept_fixtures/trace.log "$tmp/out.json"

# The CLI writes no trailing newline; strip it on both sides before comparing.
if [ "$(cat accept_fixtures/expected_trace.json)" != "$(cat "$tmp/out.json")" ]; then
  echo "trace2funcs: output differs from accept_fixtures/expected_trace.json" >&2
  diff -u accept_fixtures/expected_trace.json "$tmp/out.json" >&2 || true
  exit 1
fi

echo "trace2funcs: OK"
