#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/unarygen}"; N="${2:-300}"; rm -rf "$OUT"; mkdir -p "$OUT"; : > "$OUT/m.jsonl"
norm() { sed '/^\/\/\/|/d' "$1" | tr -d '[:space:]' | sed 's/#derive/derive/g; s/derive([^)]*)//g; s/Int32/Int/g'; }
for i in $(seq 1 "$N"); do
  d="$OUT/p$i"; mkdir -p "$d"; cp /dev/null "$d/x"
  case $((i%12)) in
    0) e='-(-1)';;
    1) e='-(-2147483648)';;
    2) e='-(-(-1))';;
    3) e='!(!true)';;
    4) e='~(~1)';;
    5) e='-(~1)';;
    6) e='-(-(1+2))';;
    7) e='-(fn() { 3 })()';;
    8) e='!(!(1 == 1))';;
    9) e='~(~(-1))';;
    10) e='-(-(2*3))';;
    11) e='!(-(-1) == 1)';;
  esac
  printf 'fn main { println(%s) }\n' "$e" > "$d/main.mbt"
  timeout 10 moon check "$d/main.mbt" >/dev/null 2>"$d/srce"; src_ok=$?
  timeout 10 moonfmt "$d/main.mbt" -o "$d/fmt.mbt" >/dev/null 2>"$d/fmte"; frc=$?
  timeout 10 moon check "$d/fmt.mbt" >/dev/null 2>"$d/chke"; crc=$?
  norm "$d/main.mbt" > "$d/ta"; norm "$d/fmt.mbt" > "$d/tb"; cmp -s "$d/ta" "$d/tb"; tok=$?
  timeout 10 moon run "$d/main.mbt" --target wasm-gc >"$d/oo" 2>"$d/oe"; orc=$?
  timeout 10 moon run "$d/fmt.mbt" --target wasm-gc >"$d/fo" 2>"$d/fe"; frc2=$?
  cmp -s "$d/oo" "$d/fo"; outdiff=$?
  bad=0; [ "$src_ok" = 0 ] && [ "$frc" != 0 ] && bad=1; [ "$src_ok" = 0 ] && [ "$crc" != 0 ] && bad=1; [ "$src_ok" = 0 ] && [ "$tok" != 0 ] && bad=1; [ "$src_ok" = 0 ] && [ "$orc" != "$frc2" ] && bad=1; [ "$src_ok" = 0 ] && [ "$outdiff" != 0 ] && bad=1
  jq -nc --arg pkg "p$i" --arg expr "$e" --argjson fmt_rc "$frc" --argjson check_rc "$crc" --argjson token_diff "$tok" --argjson run_rc "$orc" --argjson run_fmt_rc "$frc2" --argjson stdout_diff "$outdiff" --argjson bad "$bad" --argjson source_ok "$src_ok" '{pkg:$pkg,expr:$expr,source_ok:$source_ok,expr_src:("fn main { println("+$expr+") }"),fmt_rc:$fmt_rc,check_rc:$check_rc,token_diff:$token_diff,run_rc:$run_rc,run_fmt_rc:$run_fmt_rc,stdout_diff:$stdout_diff,bad:$bad}' >> "$OUT/m.jsonl"
done
# ROOT not exported; use absolute
jq -s --argjson n "$N" '{generated:$n,source_bad:([.[]|select(.source_ok!=0)]|length),fmt_rc_bad:([.[]|select(.fmt_rc!=0)]|length),check_bad:([.[]|select(.check_rc!=0)]|length),token_bad:([.[]|select(.token_diff!=0)]|length),stdout_bad:([.[]|select(.stdout_diff!=0)]|length),run_bad:([.[]|select(.run_rc!=.run_fmt_rc)]|length),violations:[.[]|select(.bad==1)|{pkg,expr,check_rc,token_diff,stdout_diff,run_rc,run_fmt_rc}]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_n_unary.json
cat /data/audit/mbtfuzz/findings/discovery_n_unary.json
