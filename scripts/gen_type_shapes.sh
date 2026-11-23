#!/bin/bash
set -uo pipefail
OUT="${1:-/tmp/typegen}"; COUNT="${2:-600}"; WORKERS="${3:-16}"
rm -rf "$OUT"; mkdir -p "$OUT/pkgs"; : > "$OUT/manifest.tsv"; : > "$OUT/metrics.jsonl"
emit() { # idx family seed source
  local d="$OUT/pkgs/p$1"; mkdir -p "$d"
  printf 'name = "p%s"\nversion = "0.1.0"\n' "$1" > "$d/moon.mod"
  printf 'options("is-main": true)\n' > "$d/moon.pkg"
  printf '%s\nfn main {}\n' "$4" > "$d/main.mbt"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$d" >> "$OUT/manifest.tsv"
}
idx=0
# family 0: 415 function identity
emit $idx fn415 "fnA" 'pub fn[A, B] unsafe_coerce(_ : A) -> B = "%identity"
test { let f : () -> Int = fn() { 0 }; let g : () -> Double = unsafe_coerce(f); let h : () -> Int = unsafe_coerce(g); inspect(h(), content="0") }'; idx=$((idx+1))
# family 1: aitne Ref identity
emit $idx refany "aitne" 'type Object
fn[T] Object::of(value : T) -> Object = "%identity"
fn[T] Object::to(self : Object) -> T = "%identity"
fn[T] try_cast(a : Object) -> T? { let r : Ref[T] = Object::of(Ref(a)).to(); Some(r.val) }
test { let x : Int? = try_cast(Object::of(1)); inspect(x, content="Some(1)") }'; idx=$((idx+1))
# variants
while [ "$idx" -lt "$COUNT" ]; do
  fam=$((idx % 8)); v=$((idx / 8))
  case $fam in
    2) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
test { let a : Array[Int] = [1, 2]; let b : Array[String] = bad(a); inspect(b.length(), content="2") }' ; seed="array-$v";;
    3) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
struct A { x : Int }
struct B { y : Double }
test { let a : A = { x: 1 }; let b : B = bad(a); inspect(b.y, content="1.0") }' ; seed="struct-$v";;
    4) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
test { let a : (Int, String) = (1, "x"); let b : (Double, Int) = bad(a); inspect(b.1, content="1") }' ; seed="tuple-$v";;
    5) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
enum E { A(Int); B(String) }
test { let e : E = E::A(1); let f : E = bad(e); inspect(f, content="A(1)") }' ; seed="enum-$v";;
    6) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
struct Box[T] { v : T }
test { let a : Box[Int] = { v: 1 }; let b : Box[String] = bad(a); inspect(b.v, content="1") }' ; seed="generic-$v";;
    7) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
test { let f : () -> Int = fn() { 0 }; let g : () -> Double = bad(f); inspect(g(), content="0.0") }' ; seed="closure-$v";;
    8) src='trait T { fn get() -> Int }
struct S { x : Int }
impl T for S with fn get(self) -> Int { self.x }
pub fn[A, B] bad(_ : A) -> B = "%identity"
test { let s : S = { x: 1 }; let t : &T = bad(s); inspect(t.get(), content="1") }' ; seed="trait-$v";;
    9) src='pub fn[A, B] bad(_ : A) -> B = "%identity"
struct Node[T] { next : Node[T]?; v : T }
test { let a : Node[Int] = { next: None, v: 1 }; let b : Node[String] = bad(a); inspect(b.v, content="1") }' ; seed="recursive-$v";;
  esac
  emit $idx "$fam" "$seed" "$src"; idx=$((idx+1))
done
echo "generated=$idx out=$OUT" >&2
# build workers
worker() {
  d="$1"; base=$(basename "$d"); rel=${d#*/pkgs/}
  ( cd "$d" && timeout 30 moon build --target wasm-gc ) >"$d/wo" 2>"$d/we"; wrc=$?
  ( cd "$d" && timeout 30 moon build --target js ) >"$d/jo" 2>"$d/je"; jrc=$?
  ( cd "$d" && timeout 40 moon test --target wasm-gc ) >"$d/wto" 2>"$d/wte"; wtrc=$?
  ( cd "$d" && timeout 40 moon test --target js ) >"$d/jto" 2>"$d/jte"; jtrc=$?
  inv=0; sig=""; first=""
  while read -r f; do [ -n "$f" ] || continue; node -e 'const fs=require("fs");try{new WebAssembly.Module(fs.readFileSync(process.argv[1]));process.exit(0)}catch(e){console.log(e.message);process.exit(1)}' "$f" >/tmp/ge.$$ 2>&1 || { inv=$((inv+1)); [ -z "$sig" ] && sig=$(cat /tmp/ge.$$); }; done < <(find "$d/_build/wasm-gc" -name '*.wasm' -type f 2>/dev/null)
  if [ -n "$sig" ]; then
    case "$sig" in
      *"local.set"*"expected type (ref"*"found "*"type (ref"*) sig='local.set|ref<-ref|identity';;
      *"expected type anyref"*) sig='local.set|ref<-ref|identity' ;;
      *"call["*"expected type (ref"*) sig='local.set|ref<-ref|identity' ;;
      *"elements on the stack"*) sig='fallthru|stack2' ;;
      *) sig=$(printf '%s' "$sig" | sed -E 's/#[0-9]+//g; s/@\+[0-9]+//g; s/\(ref [0-9]+\)/(ref)/g' | head -c 120);;
    esac
  fi
  jq -nc --arg pkg "$rel" --arg seed "$(awk -v p="$base" '$1==p{print $3}' "$OUT/manifest.tsv")" --argjson wrc "$wrc" --argjson jrc "$jrc" --argjson inv "$inv" --arg sig "$sig" --arg first "$(grep -m1 'Error' "$d/we" "$d/wte" 2>/dev/null | head -1)" '{pkg:$pkg,seed:$seed,wasm_rc:$wrc,js_rc:$jrc,invalids:$inv,signature:$sig,first:$first}' >> "$OUT/metrics.jsonl"
  rm -f /tmp/ge.$$
}
export -f worker; export OUT
find "$OUT/pkgs" -mindepth 1 -maxdepth 1 -type d | xargs -P "$WORKERS" -n1 -I{} bash -c 'worker "$1"' _ {}
jq -s --argjson generated "$idx" '
{generated:$generated,
 build_ok:([.[]|select(.wasm_rc==0 and .js_rc==0)]|length),
 invalid_artifact:([.[]|select(.invalids>0)]|length),
 invalid_details:[.[]|select(.invalids>0)|{pkg,seed,signature,first}],
 buckets:([.[]|select(.invalids>0)]|group_by(.signature)|map({key:.[0].signature,value:length})|from_entries)}' "$OUT/metrics.jsonl" > "$OUT/summary.json"
cat "$OUT/summary.json"
