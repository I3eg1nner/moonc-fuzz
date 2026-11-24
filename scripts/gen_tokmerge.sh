#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/tokmerge}"; N="${2:-200}"; rm -rf "$OUT"; mkdir -p "$OUT/pkgs"; : > "$OUT/m.jsonl"
norm() { sed '/^\/\/\/|/d' "$1"|tr -d '[:space:]'|sed 's/#derive/derive/g;s/derive([^)]*)//g;s/Int32/Int/g;s/;/ /g'; }
for i in $(seq 1 "$N"); do
 d="$OUT/pkgs/p$i"; mkdir -p "$d"; printf 'name="p%s"\nversion="0.1.0"\n' "$i" > "$d/moon.mod"; printf 'options("is-main": true)\n' > "$d/moon.pkg"
 case $((i%5)) in
  0) src="fn main { println(1 - -2) }"; seed="minus-minus";;
  1) src="fn main { println(1 + +2) }"; seed="plus-plus";;
  2) src="fn main { let b = true; println(! !b) }"; seed="bang-bang";;
  3) src="fn main { println(1 - (-2)) }"; seed="minus-paren";;
  4) src="fn main { let x = 1; let y = 2; x = - -y; println(x) }"; seed="assign-minus";;
 esac
 printf '%s\n' "$src" > "$d/main.mbt"
done
export -f norm; one() { d="$1"; norm "$d/main.mbt" > "$d/ta"; timeout 10 moon check "$d/main.mbt" >/dev/null 2>&1; s=$?; timeout 10 moonfmt "$d/main.mbt" -o "$d/fmt.mbt" >/dev/null 2>&1; f=$?; [ "$f" = 0 ] && norm "$d/fmt.mbt" > "$d/tb" || : > "$d/tb"; cmp -s "$d/ta" "$d/tb" && t=0 || t=1; timeout 10 moon check "$d/fmt.mbt" >/dev/null 2>&1 && c=0 || c=1; timeout 10 moonfmt "$d/fmt.mbt" -o "$d/fmt2.mbt" >/dev/null 2>&1; cmp -s "$d/fmt.mbt" "$d/fmt2.mbt" && id=0 || id=1; timeout 10 moon run "$d/main.mbt" --target wasm-gc >"$d/o1" 2>/dev/null; r1=$?; timeout 10 moon run "$d/fmt.mbt" --target wasm-gc >"$d/o2" 2>/dev/null; r2=$?; cmp -s "$d/o1" "$d/o2" && out=0 || out=1; bad=0; [ "$s" = 0 ] && { [ "$t" = 1 ] || [ "$c" = 1 ] || [ "$id" = 1 ] || [ "$out" = 1 ] || [ "$r1" != "$r2" ]; } && bad=1; jq -nc --arg pkg "p$i" --argjson src "$s" --argjson fmt "$f" --argjson check "$c" --argjson token "$t" --argjson idem "$id" --argjson stdout "$out" --argjson bad "$bad" '{pkg:$pkg,src_ok:$src,fmt_rc:$fmt,check_rc:$check,token:$token,idem:$idem,stdout:$stdout,bad:$bad}' >> "$OUT/m.jsonl"; }
export -f one; find "$OUT/pkgs" -mindepth 1 -maxdepth 1 -type d | xargs -P 16 -n1 -I{} bash -c 'one "$1"' _ {}
jq -s --argjson n "$N" '{generated:$n,source_bad:([.[]|select(.src_ok!=0)]|length),fmt_bad:([.[]|select(.fmt_rc!=0)]|length),check_bad:([.[]|select(.src_ok==0 and .check_rc!=0)]|length),token_bad:([.[]|select(.src_ok==0 and .token!=0)]|length),idem_bad:([.[]|select(.src_ok==0 and .idem!=0)]|length),stdout_bad:([.[]|select(.src_ok==0 and .stdout!=0)]|length),violations:[.[]|select(.bad==1)|{pkg,check_rc,token,idem,stdout}]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_p_tokmerge.json
cat /data/audit/mbtfuzz/findings/discovery_p_tokmerge.json
