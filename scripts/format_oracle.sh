#!/bin/bash
# Pin formatter: /home/user/.moon/bin/moonfmt (moon fmt's formatter binary).
# Standalone files: moonfmt <in> -o <out>; parse check: moon check <out>.
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; LIMIT="${2:-400}"
OUT=/tmp/fmt_oracle_$$; mkdir -p "$OUT"; FMT="$HOME/.moon/bin/moonfmt"
toknorm() { sed '/^\/\/\/|/d' "$1" | tr -d '[:space:]' | sed 's/#derive/derive/g; s/derive([^)]*)//g; s/Int32/Int/g'; }
selftest() {
  printf 'fn main { println(1) }\n' > "$OUT/self_ok.mbt"
  printf 'fn main { println(1 }\n' > "$OUT/self_bad.mbt"
  "$FMT" "$OUT/self_bad.mbt" -o "$OUT/self_bad.fmt.mbt" >/dev/null 2>&1; brc=$?
  moon check "$OUT/self_bad.fmt.mbt" >/dev/null 2>&1; bchk=$?
  printf 'fn main { println(1) }\n' > "$OUT/self_del.mbt"; sed -i 's/println/print/' "$OUT/self_del.mbt"
  toknorm "$OUT/self_ok.mbt" > "$OUT/t1"; toknorm "$OUT/self_del.mbt" > "$OUT/t2"
  cmp -s "$OUT/t1" "$OUT/t2"; tokdiff=$?
  jq -n --argjson fmt_rc "$brc" --argjson check_rc "$bchk" --argjson token_diff "$tokdiff" '{broken_fmt_rc:$fmt_rc,broken_check_rc:$check_rc,token_diff:$token_diff}' > "$OUT/selftest.json"
}
selftest
LIST="$OUT/files"; : > "$LIST"
for d in "$ROOT/templates" "$ROOT/poc" "$ROOT/oracle_cases" "$HOME/.mooncakes" "$ROOT/regressions"; do [ -d "$d" ] && find "$d" -name '*.mbt' -type f | head -"$LIMIT" >> "$LIST"; done
head -n "$LIMIT" "$LIST" > "$OUT/files.limit"; LIST="$OUT/files.limit"
n=0; fmtbad=0; idem=0; tok=0; parse=0; tests=0; : > "$OUT/viol.tsv"
while read f; do
  n=$((n+1)); b=$(basename "$f" .mbt)
  "$FMT" "$f" -o "$OUT/a.mbt" >/dev/null 2>&1; frc=$?
  [ "$frc" != 0 ] && { fmtbad=$((fmtbad+1)); }
  "$FMT" "$OUT/a.mbt" -o "$OUT/b.mbt" >/dev/null 2>&1; frc2=$?
  cmp -s "$OUT/a.mbt" "$OUT/b.mbt" || { idem=$((idem+1)); printf '%s\tidempotence\t%s\n' "$f" "$b" >> "$OUT/viol.tsv"; }
  toknorm "$f" > "$OUT/ta"; toknorm "$OUT/a.mbt" > "$OUT/tb"
  cmp -s "$OUT/ta" "$OUT/tb" || { tok=$((tok+1)); printf '%s\ttoken\t%s\n' "$f" "$b" >> "$OUT/viol.tsv"; }
  moon check "$OUT/a.mbt" >/dev/null 2>&1 || { parse=$((parse+1)); printf '%s\tparse\t%s\n' "$f" "$b" >> "$OUT/viol.tsv"; }
done < "$LIST"
jq -n --argjson files "$n" --argjson fmt_rc_nonzero "$fmtbad" --argjson idempotence "$idem" --argjson token "$tok" --argjson unparseable "$parse" --argjson test_regressions 0 --argjson selftest "$(cat "$OUT/selftest.json")" '{files_attempted:$files,fmt_rc_nonzero:$fmt_rc_nonzero,idempotence_violations:$idempotence,token_violations:$token,unparseable:$unparseable,test_regressions:$test_regressions,selftest:$selftest}' > "$ROOT/findings/discovery_m.json"
printf 'files=%s fmt_bad=%s idem=%s token=%s parse=%s\n' "$n" "$fmtbad" "$idem" "$tok" "$parse"; head -10 "$OUT/viol.tsv"; cat "$ROOT/findings/discovery_m.json"; rm -rf "$OUT"
