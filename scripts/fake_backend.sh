#!/bin/bash
# Deterministic sem3 test backend: args = TARGET PROGRAM. MODE_<TARGET>.
set -uo pipefail
target="$1"; shift || true
prog="${1:-}"
v="MODE_$(printf '%s' "$target" | tr 'a-z-' 'A-Z_')"
mode="${!v:-ok}"
outv="OUT_$(printf '%s' "$target" | tr 'a-z-' 'A-Z_')"
case "$mode" in
  ok) printf '%s\n' "${!outv:-123}"; exit 0 ;;
  trap) printf 'trap\n' >&2; exit 134 ;;
  compile_error) printf 'Error: [E9999] synthetic\n' >&2; exit 1 ;;
  timeout) sleep 10; exit 0 ;;
  truncated) head -c 1100000 /dev/zero | tr '\0' 'x'; exit 0 ;;
  ice) printf 'Oops, the compiler\n' >&2; exit 2 ;;
  *) printf 'unknown mode %s\n' "$mode" >&2; exit 90 ;;
esac
