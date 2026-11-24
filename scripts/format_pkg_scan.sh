#!/bin/bash
set -uo pipefail
ROOT="${1:-/data/audit/mbtfuzz}"; N="${2:-400}"; OUT=/tmp/fpkg_$$; mkdir -p "$OUT"; : > "$OUT/files"
for d in "$ROOT/templates" "$ROOT/poc" "$ROOT/oracle_cases" "$ROOT/regressions" "$HOME/.mooncakes"; do [ -d "$d" ] && find "$d" -name '*.mbt' -type f -size -200k | head -n "$N" >> "$OUT/files"; done
head -n "$N" "$OUT/files" > "$OUT/list"; : > "$OUT/m.jsonl"
norm() { sed '/^\/\/\/|/d' "$1" | tr -d '[:space:]' | sed 's/#derive/derive/g; s/derive([^)]*)//g; s/Int32/Int/g'; }
one() { f="$1"; h="$OUT/$(echo "$f"|md5sum|cut -c1-8)"; timeout 8 moonfmt "$f" -o "$h.a" >/dev/null 2>&1; r1=$?; timeout 8 moonfmt "$h.a" -o "$h.b" >/dev/null 2>&1; r2=$?; tok=-1; idem=-1; if [ "$r1" = 0 ]; then norm "$f" > "$h.ta"; norm "$h.a" > "$h.tb"; cmp -s "$h.ta" "$h.tb" && tok=0 || tok=1; fi; if [ "$r1" = 0 ] && [ "$r2" = 0 ]; then cmp -s "$h.a" "$h.b" && idem=0 || idem=1; fi; jq -nc --arg f "$f" --argjson r1 "$r1" --argjson r2 "$r2" --argjson tok "$tok" --argjson idem "$idem" '{file:$f,fmt_rc:$r1,fmt2_rc:$r2,token:$tok,idem:$idem}' >> "$OUT/m.jsonl"; }
export -f one norm; export OUT
cat "$OUT/list" | xargs -P 16 -n1 -I{} bash -c 'one "$1"' _ {} 2>/dev/null
jq -s --argjson files "$(wc -l < "$OUT/list")" '{files_attempted:$files,fmt_rc_nonzero:([.[]|select(.fmt_rc!=0)]|length),idempotence_violations:([.[]|select(.idem==1)]|length),token_violations:([.[]|select(.token==1)]|length),samples:[.[]|select(.token==1 or .idem==1)|{file,token,idem}]|.[0:10]}' "$OUT/m.jsonl" > "$ROOT/findings/discovery_n_pkg.json"
cat "$ROOT/findings/discovery_n_pkg.json"; rm -rf "$OUT"
