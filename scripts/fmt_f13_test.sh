#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"
FMT="${MOONFMT:-$HOME/.moon/bin/moonfmt}"
OUT=/tmp/fmt_f13_$$; mkdir -p "$OUT"
pass=0; fail=0; neg_ok=1
run_case() {
  local name="$1" src="$2"
  printf '%s\n' "$src" > "$OUT/$name.mbt"
  "$FMT" "$OUT/$name.mbt" -o "$OUT/$name.fmt.mbt" >/tmp/f13_fmt_o 2>/tmp/f13_fmt_e; frc=$?
  moon check "$OUT/$name.fmt.mbt" >/tmp/f13_chk_o 2>/tmp/f13_chk_e; crc=$?
  code=$(grep -o '4095' /tmp/f13_chk_e | head -1)
  printf '%s fmt_rc=%s check_rc=%s code=%s\n' "$name" "$frc" "$crc" "$code" >&2
  [ "$frc" = 0 ] && [ "$crc" != 0 ] && [ "$code" = "4095" ] && return 0 || return 1
}
if run_case i32_min 'fn main { println(-(-2147483648)) }'; then pass=$((pass+1)); else fail=$((fail+1)); fi
if run_case i64_min 'fn main { println(-(-9223372036854775808L)) }'; then pass=$((pass+1)); else fail=$((fail+1)); fi
if run_case triple 'fn main { println(-(-(-2147483648))) }'; then pass=$((pass+1)); else fail=$((fail+1)); fi
# Negative: a healthy nested negation must still reparse and check.
printf '%s\n' 'fn main { println(-(-1)) }' > "$OUT/healthy.mbt"
"$FMT" "$OUT/healthy.mbt" -o "$OUT/healthy.fmt.mbt" >/dev/null 2>&1; hf=$?
moon check "$OUT/healthy.fmt.mbt" >/tmp/f13_h_o 2>/tmp/f13_h_e; hc=$?
[ "$hf" = 0 ] && [ "$hc" = 0 ] && neg_ok=1 || neg_ok=0
ok=0; [ "$pass" = 3 ] && [ "$fail" = 0 ] && [ "$neg_ok" = 1 ] && ok=1
jq -n --argjson ok "$ok" --argjson positives "$pass" --argjson failed "$fail" --argjson negative_ok "$neg_ok" --arg classification "compiler_inconsistency_candidate" '{ok:$ok,positives:$positives,failed:$failed,negative_ok:$negative_ok,classification:$classification}' > "$OUT/summary.json"
cat "$OUT/summary.json"; rm -rf "$OUT"; [ "$ok" = 1 ]
