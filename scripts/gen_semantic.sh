#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/semgen}"; COUNT="${2:-600}"; WORKERS="${3:-16}"
rm -rf "$OUT"; mkdir -p "$OUT/pkgs"; : > "$OUT/manifest.tsv"; : > "$OUT/metrics.jsonl"
emit() { local d="$OUT/pkgs/p$1"; mkdir -p "$d"; printf 'name="p%s"\nversion="0.1.0"\n' "$1" > "$d/moon.mod"; printf 'options("is-main": true)\n' > "$d/moon.pkg"; printf '%s\nfn main {}\n' "$4" > "$d/main.mbt"; printf '%s\t%s\t%s\n' "$1" "$2" "$d" >> "$OUT/manifest.tsv"; }
idx=0; identity=0
while [ "$idx" -lt "$COUNT" ]; do
  fam=$((idx % 12)); v=$((idx / 12)); n=$((v+1)); a=$((n%17+1)); b=$((n%7+1)); e=$((a+b))
  case $fam in
    0) src="test \"t\" { let a = $a; let b = $b; let c = a + b; inspect(c, content=\"$e\") }"; seed="int-add-$a-$b";;
    1) q=$(( (a*b+3) / b )); r=$(( (a*b+3) % b )); src="test \"t\" { let a = $((a*b+3)); let b = $b; let q = a / b; let r = a % b; inspect(q, content=\"$q\"); inspect(r, content=\"$r\") }"; seed="divmod-$a-$b";;
    2) s=$((n%8)); e=$((1<<s)); src="test \"t\" { let s = $s; let c = 1 << s; inspect(c, content=\"$e\") }"; seed="shift-$s";;
    3) src="test \"t\" { let a = $a; let b = $b; inspect(a & b, content=\"$((a&b))\"); inspect(a | b, content=\"$((a|b))\"); inspect(a ^ b, content=\"$((a^b))\") }"; seed="bit-$a-$b";;
    4) src="test \"t\" { let a = $a; inspect(a < $((a+1)), content=\"true\"); inspect(a * 2, content=\"$((a*2))\") }"; seed="int-mul-$a";;
    5) src="test \"t\" { let s = \"abc\"; inspect(s.length(), content=\"3\") }"; seed="string";;
    6) src="test \"t\" { let xs = [1, 2, 3]; inspect(xs.length(), content=\"3\"); inspect(xs[1], content=\"2\") }"; seed="array";;
    7) src="test \"t\" { let r = Ref(1); r.val = 2; inspect(r.val, content=\"2\") }"; seed="ref";;
    8) src="test \"t\" { let x = $a; let y = match x { 0 => 1; _ => x + 1 }; inspect(y, content=\"$((a+1))\") }"; seed="match-$a";;
    9) src="test \"t\" { let f = fn(x : Int) { x + 1 }; inspect(f($a), content=\"$((a+1))\") }"; seed="closure-$a";;
    10) src="test \"t\" { let xs = [1, 2, 3]; let mut sum = 0; for x in xs { sum = sum + x }; inspect(sum, content=\"6\") }"; seed="loop";;
    11) identity=$((identity+1)); if [ $((identity*10)) -le "$COUNT" ]; then src="pub fn[A, B] bad(_ : A) -> B = \"%identity\""$'\n'"test \"t\" { let f : () -> Int = fn() { 0 }; let g : () -> Double = bad(f); inspect(g(), content=\"0.0\") }"; seed="identity"; else src="test \"t\" { inspect($a, content=\"$a\") }"; seed="identity-skip"; fi;;
  esac
  emit $idx "$fam" "$seed" "$src"; idx=$((idx+1))
done
echo "generated=$idx identity=$identity out=$OUT" >&2
worker() {
  d="$1"; base=$(basename "$d")
  ( cd "$d" && timeout 30 moon build --target wasm-gc ) >"$d/wo" 2>"$d/we"; wrc=$?
  ( cd "$d" && timeout 30 moon build --target js ) >"$d/jo" 2>"$d/je"; jrc=$?
  ( cd "$d" && timeout 30 moon test --target wasm-gc ) >"$d/wto" 2>"$d/wte"; wtrc=$?
  ( cd "$d" && timeout 30 moon test --target js ) >"$d/jto" 2>"$d/jte"; jtrc=$?
  inv=0; while read -r f; do [ -n "$f" ] || continue; node -e 'const fs=require("fs");try{new WebAssembly.Module(fs.readFileSync(process.argv[1]));process.exit(0)}catch(e){process.exit(1)}' "$f" || inv=$((inv+1)); done < <(find "$d/_build/wasm-gc" -name '*.wasm' -type f 2>/dev/null)
  outw=$(grep -h '^Total tests' "$d/wto" "$d/wte" 2>/dev/null | head -1)
  outj=$(grep -h '^Total tests' "$d/jto" "$d/jte" 2>/dev/null | head -1)
  disc=0; [ "$wtrc" != "$jtrc" ] && disc=1
  [ "$outw" != "$outj" ] && disc=1
  jq -nc --arg pkg "$base" --arg seed "$(awk -v p="${base#p}" '$1==p{print $2}' "$OUT/manifest.tsv")" --argjson wrc "$wrc" --argjson jrc "$jrc" --argjson wtrc "$wtrc" --argjson jtrc "$jtrc" --argjson inv "$inv" --argjson disc "$disc" --arg wout "$outw" --arg jout "$outj" '{pkg:$pkg,seed:$seed,wasm_rc:$wrc,js_rc:$jrc,wasm_test_rc:$wtrc,js_test_rc:$jtrc,invalids:$inv,discordant:$disc,wasm_out:$wout,js_out:$jout}' >> "$OUT/metrics.jsonl"
}
export -f worker; export OUT
find "$OUT/pkgs" -mindepth 1 -maxdepth 1 -type d | xargs -P "$WORKERS" -n1 -I{} bash -c 'worker "$1"' _ {}
jq -s --argjson generated "$idx" --argjson identity "$identity" '
{generated:$generated,identity_samples:$identity,
 build_valid:([.[]|select(.wasm_rc==0 and .js_rc==0 and .invalids==0)]|length),
valid_legal:([.[]|select(.seed!="identity" and .wasm_rc==0 and .js_rc==0 and .invalids==0)]|length),
 invalid_artifact:([.[]|select(.invalids>0)]|length),
 discordant:([.[]|select(.discordant==1)]|length),
 discordant_details:[.[]|select(.discordant==1)|{pkg,seed,wasm_out,js_out,wasm_test_rc,js_test_rc}]}' "$OUT/metrics.jsonl" > "$OUT/summary.json"
cat "$OUT/summary.json"
