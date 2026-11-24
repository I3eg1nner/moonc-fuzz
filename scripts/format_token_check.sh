#!/bin/bash
set -uo pipefail
norm() { sed '/^\/\/\/|/d' "$1" | tr -d '[:space:]' | sed 's/#derive/derive/g; s/derive([^)]*)//g; s/Int32/Int/g'; }
OUT=/tmp/ftok_$$; mkdir -p "$OUT"
printf 'struct P { x : Int } derive(Show)\nfn main { println(1) }\n' > "$OUT/w.mbt"
moonfmt "$OUT/w.mbt" -o "$OUT/w.fmt.mbt" >/dev/null 2>&1
norm "$OUT/w.mbt" > "$OUT/wa"; norm "$OUT/w.fmt.mbt" > "$OUT/wb"; cmp -s "$OUT/wa" "$OUT/wb"; wdiff=$?
printf 'struct P { x : Int } derive(Show)\nfn main { println(1) }\n' > "$OUT/d.mbt"; sed -i 's/println/print/' "$OUT/d.mbt"
norm "$OUT/d.mbt" > "$OUT/da"; norm "$OUT/d.fmt.mbt" > "$OUT/db" 2>/dev/null; cmp -s "$OUT/da" "$OUT/w.fmt.mbt" >/dev/null 2>&1; ddiff=$?
# explicit deleted-token compare against w.fmt
cmp -s "$OUT/da" "$OUT/wb"; ddiff=$?
jq -n --argjson whitelist_diff "$wdiff" --argjson deleted_token_diff "$ddiff" '{whitelist_diff:$whitelist_diff,deleted_token_diff:$deleted_token_diff}' > "$OUT/sum.json"
cat "$OUT/sum.json"; rm -rf "$OUT"
