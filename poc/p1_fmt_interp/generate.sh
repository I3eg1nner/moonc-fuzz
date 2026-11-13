#!/bin/bash
# Generate the P1 interpolation input without Python.
set -euo pipefail
K="${1:-1024}"
OUT="${2:-p.mbt}"
{
  printf 'fn f() -> String { "'
  for ((i=0; i<K; i++)); do printf '\\{%d}' "$i"; done
  printf '" }\n'
} > "$OUT"
wc -c "$OUT"
