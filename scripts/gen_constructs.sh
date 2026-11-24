#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/constrgen}"; N="${2:-300}"; rm -rf "$OUT"; mkdir -p "$OUT/pkgs"; : > "$OUT/m.jsonl"
norm() { sed '/^\/\/\/|/d' "$1"|tr -d '[:space:]'|sed 's/#derive/derive/g;s/derive([^)]*)//g;s/Int32/Int/g;s/;//g'; }
for i in $(seq 1 "$N"); do
 d="$OUT/pkgs/p$i"; mkdir -p "$d"; printf 'name="p%s"\nversion="0.1.0"\n' "$i" > "$d/moon.mod"; printf 'options("is-main": true)\n' > "$d/moon.pkg"
 case $((i%10)) in
 0) src=$'struct S { a : Int; b : String }\nfn main { let s : S = { a: 1, b: "x" }; println(s.a) }';;
 1) src=$'enum E { A(Int); B }\nfn main { let e : E = E::A(1); match e { A(n) => println(n); B => println(0) } }';;
 2) src=$'fn id[T](x : T) -> T { x }\nfn main { println(id(1)) }';;
 3) src=$'fn main { println(1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10) }';;
 4) src=$'fn main { for i in 0..3 { if i % 2 == 0 { println(i) } } }';;
 5) src=$'trait T { fn get() -> Int }\nstruct S { x : Int }\nimpl T for S with fn get(self) -> Int { self.x }\nfn main { let s : S = { x: 1 }; println(s.get()) }';;
 6) src=$'fn main { let f = fn(x : Int) { x + 1 }; println(f(1)) }';;
 7) src=$'fn main { match 1 { 1 | 2 => println("a"); _ => println("b") } }';;
 8) src=$'fn main { let t : (Int, String) = (1, "x"); println(t.0) }';;
 9) src=$'fn main { let xs : Array[Int] = [1, 2, 3]; println(xs.length()) }';;
 esac
 printf '%s\n' "$src" > "$d/main.mbt"
done
export OUT; export -f norm; one() { d="$1"; norm "$d/main.mbt" > "$d/ta"; timeout 10 moon check "$d/main.mbt" >/dev/null 2>&1; s=$?; timeout 10 moonfmt "$d/main.mbt" -o "$d/fmt.mbt" >/dev/null 2>&1; f=$?; [ $f = 0 ] && norm "$d/fmt.mbt" > "$d/tb" || : > "$d/tb"; cmp -s "$d/ta" "$d/tb" && t=0 || t=1; timeout 10 moon check "$d/fmt.mbt" >/dev/null 2>&1 && c=0 || c=1; timeout 10 moonfmt "$d/fmt.mbt" -o "$d/fmt2.mbt" >/dev/null 2>&1; cmp -s "$d/fmt.mbt" "$d/fmt2.mbt" && id=0 || id=1; timeout 10 moon run "$d/main.mbt" --target wasm-gc >"$d/o1" 2>/dev/null; r1=$?; timeout 10 moon run "$d/fmt.mbt" --target wasm-gc >"$d/o2" 2>/dev/null; r2=$?; cmp -s "$d/o1" "$d/o2" && out=0 || out=1; bad=0; [ "$s" = 0 ] && { [ "$t" = 1 ] || [ "$c" = 1 ] || [ "$id" = 1 ] || [ "$out" = 1 ] || [ "$r1" != "$r2" ]; } && bad=1; jq -nc --arg pkg "p$i" --argjson src "$s" --argjson fmt "$f" --argjson check "$c" --argjson token "$t" --argjson idem "$id" --argjson stdout "$out" --argjson bad "$bad" '{pkg:$pkg,src_ok:$src,fmt_rc:$fmt,check_rc:$check,token:$token,idem:$idem,stdout:$stdout,bad:$bad}' >> "$OUT/m.jsonl"; }
export -f one; find "$OUT/pkgs" -mindepth 1 -maxdepth 1 -type d | xargs -P 16 -n1 -I{} bash -c 'one "$1"' _ {}
jq -s --argjson n "$N" '{generated:$n,source_bad:([.[]|select(.src_ok!=0)]|length),fmt_bad:([.[]|select(.fmt_rc!=0)]|length),check_bad:([.[]|select(.src_ok==0 and .check_rc!=0)]|length),token_bad:([.[]|select(.src_ok==0 and .token!=0)]|length),idem_bad:([.[]|select(.src_ok==0 and .idem!=0)]|length),stdout_bad:([.[]|select(.src_ok==0 and .stdout!=0)]|length),violations:[.[]|select(.bad==1)|{pkg,check_rc,token,idem,stdout}]}' "$OUT/m.jsonl" > /data/audit/mbtfuzz/findings/discovery_s_constructs.json
cat /data/audit/mbtfuzz/findings/discovery_s_constructs.json
