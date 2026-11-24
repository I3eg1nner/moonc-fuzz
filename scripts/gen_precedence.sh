#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/precgen}"; N="${2:-400}"; W="${3:-16}"; rm -rf "$OUT"; mkdir -p "$OUT/pkgs"; : > "$OUT/m.jsonl"
norm() { sed '/^\/\/\/|/d' "$1"|tr -d '[:space:]'|sed 's/#derive/derive/g; s/derive([^)]*)//g; s/Int32/Int/g; s/;/ /g'; }
for i in $(seq 1 "$N"); do
  d="$OUT/pkgs/p$i"; mkdir -p "$d"; printf 'name="p%s"\nversion="0.1.0"\n' "$i" > "$d/moon.mod"; printf 'options("is-main": true)\n' > "$d/moon.pkg"
  case $((i%10)) in
   0) e='1 + 2 * 3';;
   1) e='(1 + 2) * 3';;
   2) e='1 << 2 + 1';;
   3) e='(1 << 2) + 1';;
   4) e='1 & 2 | 3';;
   5) e='(1 & 2) | 3';;
   6) e='1 ^ 2 & 3';;
   7) e='((1 + 2) * (3 + 4))';;
   8) e='1 + (2 + (3 + 4))';;
   9) e='1 * 2 + 3 * 4';;
  esac
  printf 'fn main { println(%s) }\n' "$e" > "$d/main.mbt"
done
export -f norm; one() { d="$1"; norm "$d/main.mbt" > "$d/ta"; timeout 10 moonfmt "$d/main.mbt" -o "$d/fmt.mbt" >/dev/null 2>&1; fr=$?; [ $fr = 0 ] && norm "$d/fmt.mbt" > "$d/tb" || : > "$d/tb"; cmp -s "$d/ta" "$d/tb" && tok=0 || tok=1; timeout 10 moon check "$d/fmt.mbt" >/dev/null 2>&1 && chk=0 || chk=1; timeout 10 moonfmt "$d/fmt.mbt" -o "$d/fmt2.mbt" >/dev/null 2>&1; fr2=$?; cmp -s "$d/fmt.mbt" "$d/fmt2.mbt" && idem=0 || idem=1; timeout 10 moon run "$d/main.mbt" --target wasm-gc >"$d/o1" 2>/dev/null; r1=$?; timeout 10 moon run "$d/fmt.mbt" --target wasm-gc >"$d/o2" 2>/dev/null; r2=$?; cmp -s "$d/o1" "$d/o2" && out=0 || out=1; timeout 10 moon check "$d/main.mbt" >/dev/null 2>&1 && src=0 || src=1; bad=0; [ "$src" = 0 ] && { [ "$tok" = 1 ] || [ "$chk" = 1 ] || [ "$idem" = 1 ] || [ "$out" = 1 ] || [ "$r1" != "$r2" ]; } && bad=1; jq -nc --arg pkg "p$i" --argjson fmt_rc "$fr" --argjson check_rc "$chk" --argjson token "$tok" --argjson idem "$idem" --argjson out "$out" --argjson src "$src" --argjson bad "$bad" '{pkg:$pkg,fmt_rc:$fmt_rc,check_rc:$check_rc,token:$token,idem:$idem,stdout:$out,src_ok:$src,bad:$bad}' >> "$OUT/m.jsonl"; }
export -f one; find "$OUT/pkgs" -mindepth 1 -maxdepth 1 -type d | xargs -P "$W" -n1 -I{} bash -c 'one "$1"' _ {}
jq -s --argjson n "$N" '{generated:$n,source_bad:([.[]|select(.src_ok!=0)]|length),fmt_bad:([.[]|select(.fmt_rc!=0)]|length),check_bad:([.[]|select(.src_ok==0 and .check_rc!=0)]|length),token_bad:([.[]|select(.src_ok==0 and .token!=0)]|length),idem_bad:([.[]|select(.src_ok==0 and .idem!=0)]|length),stdout_bad:([.[]|select(.src_ok==0 and .stdout!=0)]|length),violations:[.[]|select(.bad==1)|{pkg,check_rc,token,idem,stdout}]}' "$OUT/m.jsonl" > "$ROOT/findings/discovery_o_prec.json" 2>/dev/null || true
jq -s --argjson n "$N" '{generated:$n,source_bad:([.[]|select(.src_ok!=0)]|length),fmt_bad:([.[]|select(.fmt_rc!=0)]|length),check_bad:([.[]|select(.src_ok==0 and .check_rc!=0)]|length),token_bad:([.[]|select(.src_ok==0 and .token!=0)]|length),idem_bad:([.[]|select(.src_ok==0 and .idem!=0)]|length),stdout_bad:([.[]|select(.src_ok==0 and .stdout!=0)]|length),violations:[.[]|select(.bad==1)|{pkg,check_rc,token,idem,stdout}]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_o_prec.json
cat /data/audit/mbtfuzz/findings/discovery_o_prec.json
