#!/usr/bin/env python3
"""Generate + run a focused native/FFI/async compiler-probe matrix."""
import os, re, json, shutil, subprocess, sys, time
import concurrent.futures as cf

ROOT = "/tmp/mbtfuzz_probe_scratch"
CASES = os.path.join(ROOT, "cases")
RESULTS = os.path.join(ROOT, "results")
os.makedirs(CASES, exist_ok=True)
os.makedirs(RESULTS, exist_ok=True)

# ---------------- case writers ----------------
def emit(cid, family, meta, files):
    d = os.path.join(CASES, cid)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for name, text in files.items():
        p = os.path.join(d, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)
    with open(os.path.join(d, ".meta.json"), "w") as f:
        json.dump({"id": cid, "family": family, **meta}, f)
    return cid

PKG = ""
def mod(name, deps=()):
    s = f'name = "{name}"\nversion = "0.1.0"\n'
    if deps:
        s += "\nimport {\n" + "".join(f'  "{d}",\n' for d in deps) + "}\n"
    return s

def base_files(cid, lib, test, pkg=PKG, deps=(), extra=None):
    files = {"moon.mod": mod(cid, deps), "moon.pkg": pkg,
             "lib.mbt": lib, "case_wbtest.mbt": test}
    if extra:
        files.update(extra)
    return files

# ---------------- MoonBit type helpers ----------------
# (name, default-expr, score-expr given var `v`, type-decl snippet optional)
def t_int():    return ("Int", "1", "v")
def t_i64():    return ("Int64", "1L", "v.to_int()")
def t_bool():   return ("Bool", "true", "if v { 1 } else { 0 }")
def t_str():    return ("String", '"s"', "v.length()")
def t_arr():    return ("Array[Int]", "[1, 2, 3]", "v.length()")
def t_farr():   return ("FixedArray[Int]", "FixedArray::make(2, 1)", "v.length()")
def t_bytes():  return ("Bytes", 'b"abc"', "v.length()")
def t_opt():    return ("Option[Int]", "Some(2)", "match v { Some(x) => x; None => 0 }")
def t_res():    return ("Result[Int, String]", "Ok(3)", "match v { Ok(x) => x; Err(_) => 0 }")

FTYPES = [t_int, t_i64, t_bool, t_str, t_arr, t_farr, t_bytes, t_opt, t_res]

def struct_fields(k, combo):
    # deterministic distinct-ish selection, allow repeats for small lists
    picked = []
    for i in range(k):
        picked.append(FTYPES[(combo * 3 + i * 2) % len(FTYPES)]())
    return picked

def struct_decl(name, kind, fields, attrs=""):
    head = ("#valtype\n" if kind == "valtype" else "") + attrs
    if not fields:
        return f"{head}pub struct {name} {{}}\n"
    body = "\n".join(f"  f{i} : {t}" for i, (t, _, _) in enumerate(fields))
    return f"{head}pub struct {name} {{\n{body}\n}}\n"

def struct_ctor(name, fields):
    if not fields:
        return f"{name}::{{}}"
    return f"{name}::{{ " + ", ".join(f"f{i}: {d}" for i, (_, d, _) in enumerate(fields)) + " }"

def score_expr(fields):
    parts = [f"({sc.replace('v', f'v.f{i}')})" for i, (_, _, sc) in enumerate(fields)]
    return " + ".join(parts) if parts else "0"

# ---------------- A1: struct field matrix ----------------
def gen_a_structs():
    ids = []
    combos = 5
    for kind in ("valtype", "plain"):
        for k in range(0, 6):
            for combo in range(combos):
                cid = f"a_struct_{kind}_k{k}_c{combo}"
                fields = struct_fields(k, combo)
                fields = [(t, d, sc) for (t, d, sc) in fields]
                decl = struct_decl("S", kind, fields)
                lib = decl + f"""
pub fn mk() -> S {{ {struct_ctor("S", fields)} }}

pub fn score(v : S) -> Int {{ {score_expr(fields)} }}

pub fn run() -> Int {{
  let s = mk()
  let arr : Array[S] = []
  arr.push(s)
  arr.push(mk())
  let t = arr[1]
  let u = arr[0]
  arr[0] = t
  let fa = FixedArray::make(2, s)
  fa[1] = u
  let r = score(arr[0]) + score(fa[0])
  r + arr.length()
}}
"""
                test = 'test "case" { assert_true(run() >= 0) }\n'
                ids.append(emit(cid, "A1_struct", {"kind": kind, "k": k, "combo": combo},
                                base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- A2: enums ----------------
def gen_a_enums():
    ids = []
    shapes = [
        ("single", "pub enum E { A }\n", "E::A",
         "match v { A => 0 }\n", "A"),
        ("pay_str", "pub enum E { A; B(String) }\n", "E::B(\"x\")",
         "match v { A => 0; B(_) => 1 }\n", "B"),
        ("pay_arr", "pub enum E { A; B(Array[Int]) }\n", "E::B([1, 2])",
         "match v { A => 0; B(_) => 1 }\n", "B"),
        ("pay_int", "pub enum E { A; B(Int) }\n", "E::B(7)",
         "match v { A => 0; B(x) => x }\n", "B"),
        ("pay_valtype", "#valtype\npub struct P { x : Int; y : String }\npub enum E { A; B(P) }\n",
         "E::B(P::{ x: 1, y: \"p\" })",
         "match v { A => 0; B(p) => p.x }\n", "B"),
        ("both_pay", "pub enum E { A(Int); B(String) }\n", "E::A(4)",
         "match v { A(x) => x; B(_) => 1 }\n", "A"),
    ]
    for kind in ("valtype", "plain"):
        for sname, decl, ctor, match_expr, _ in shapes:
            for wrap in ("bare", "ins", "arr"):
                cid = f"a_enum_{kind}_{sname}_{wrap}"
                attr = "#valtype\n" if kind == "valtype" else ""
                if wrap == "ins":
                    # struct containing the enum
                    pre = attr + "pub struct S {\n  id : Int\n  e : E\n}\n" + decl
                    run = f"""
pub fn run() -> Int {{
  let v = {ctor}
  let s = S::{{ id: 3, e: v }}
  let arr : Array[S] = []
  arr.push(s)
  let e2 = arr[0].e
  let n = {match_expr.replace('v', 'e2')}
  n + arr[0].id
}}
"""
                elif wrap == "arr":
                    pre = decl
                    run = f"""
pub fn run() -> Int {{
  let v = {ctor}
  let arr : Array[E] = []
  arr.push(v)
  arr.push(v)
  let e2 = arr[1]
  let n = {match_expr.replace('v', 'e2')}
  n + arr.length()
}}
"""
                else:
                    pre = decl
                    run = f"""
pub fn run() -> Int {{
  let v = {ctor}
  let n = {match_expr.replace('v', 'v')}
  n
}}
"""
                lib = pre + run
                test = 'test "case" { assert_true(run() >= 0) }\n'
                ids.append(emit(cid, "A2_enum", {"kind": kind, "shape": sname, "wrap": wrap},
                                base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- A3: array / fixedarray ops ----------------
def gen_a_ops():
    ids = []
    elems = {
        "int": ("Int", "[1, 2, 3]", "1", "v"),
        "str": ("String", '["a", "b"]', '"z"', "v.length()"),
        "rec": ("S", "[]", "S::{ x: 1 }", "v.x"),
        "enum": ("E", "[]", "E::B(1)", "match v { A => 0; B(x) => x }"),
    }
    defs = {
        "int": "",
        "str": "",
        "rec": "#valtype\npub struct S { x : Int }\n",
        "enum": "pub enum E { A; B(Int) }\n",
    }
    op_sets = {
        "push_slice": """
  let arr : Array[T] = init
  arr.push(elem)
  let sl = arr[0:arr.length()]
  sl.length()
""",
        "makei_map_filter": """
  let arr : Array[T] = Array::makei(3, fn(i) { if i == 0 { elem } else { init[0] } })
  let m = arr.map(fn(x) { x })
  let f = m.filter(fn(_x) { true })
  f.length()
""",
        "fixed": """
  let fa = FixedArray::make(3, elem)
  fa[0] = elem
  let x = fa[1]
  let fb : FixedArray[T] = FixedArray::makei(2, fn(i) { if i == 0 { elem } else { fa[0] } })
  fb.length()
""",
    }
    for ekey, (et, init, elem, sc) in elems.items():
        for okey, ops in op_sets.items():
            for kind in ("valtype", "plain"):
                if ekey in ("int", "str") and kind == "plain":
                    continue  # no user type, avoid duplicate
                cid = f"a_ops_{ekey}_{okey}_{kind}"
                code = ops.replace("T", et).replace("init", init).replace("elem", elem)
                lib = defs[ekey] + f"\npub fn run() -> Int {{{code}}}\n"
                test = 'test "case" { assert_true(run() >= 0) }\n'
                ids.append(emit(cid, "A3_ops", {"elem": ekey, "op": okey, "kind": kind},
                                base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- A4: arity matrix ----------------
def gen_a_arities():
    ids = []
    arities = [0, 1, 4, 8, 12, 16, 20]
    modes = ["int", "struct", "mixed", "ret_struct"]

    def arglist(n, mode):
        if n == 0:
            return ""
        args = []
        for i in range(n):
            if mode == "int":
                args.append("Int")
            elif mode == "struct":
                args.append("S")
            elif mode == "ret_struct":
                args.append("S" if i % 2 == 0 else "Int")
            else:
                args.append(["S", "E", "Int"][i % 3])
        return ", ".join(f"a{i} : {t}" for i, t in enumerate(args))

    def consumes(n, mode):
        out = []
        for i in range(n):
            if mode in ("struct", "ret_struct"):
                out.append(f"if i % 2 == 0 {{ 0 }} else {{ 0 }}") if False else None
        # simpler: return first Int arg or 0; still forces materialization of args
        return "0"

    for n in arities:
        for mode in modes:
            cid = f"a_arity_{n}_{mode}"
            ret = "S" if mode == "ret_struct" else "Int"
            args = arglist(n, mode)
            body_ret = "S::{ f0: 0 }" if ret == "S" else "0"
            # construct S with one field for ret mode
            sdecl = "#valtype\npub struct S { f0 : Int }\n" + "pub enum E { A; B(Int) }\n"
            defs = "" if mode in ("int", "struct") else sdecl
            if mode == "struct" and n > 0:
                defs = "#valtype\npub struct S { f0 : Int }\n"
            elif mode == "struct":
                defs = "#valtype\npub struct S { f0 : Int }\n"
            callargs = ", ".join(("S::{ f0: 1 }" if (mode == "struct" or (mode == "mixed" and i % 3 == 0)) else
                                  ("E::B(1)" if (mode == "mixed" and i % 3 == 1) else
                                   ("S::{ f0: 1 }" if (mode == "ret_struct" and i % 2 == 0) else "1")))
                                 for i in range(n))
            ret_use = "let r = f(" + callargs + ")\n  r.f0" if ret == "S" else "let r = f(" + callargs + ")\n  r"
            lib = defs + f"""
pub fn f({args}) -> {ret} {{ {body_ret} }}

pub fn run() -> Int {{
  {ret_use}
}}
"""
            test = 'test "case" { assert_true(run() >= 0) }\n'
            ids.append(emit(cid, "A4_arity", {"n": n, "mode": mode},
                            base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- A5: nested aggregates ----------------
def gen_a_nested():
    ids = []
    nshapes = [
        ("opt_s", "Option[S]", "Some(S::{ x: 1 })", "match v { Some(s) => s.x; None => 0 }"),
        ("res_s", "Result[S, String]", "Ok(S::{ x: 1 })", "match v { Ok(s) => s.x; Err(_) => 0 }"),
        ("arr_s", "Array[S]", "[S::{ x: 1 }]", "v[0].x"),
        ("farr_s", "FixedArray[S]", "FixedArray::make(2, S::{ x: 1 })", "v[0].x"),
        ("arr_e", "Array[E]", "[E::B(2)]", "match v[0] { A => 0; B(x) => x }"),
    ]
    for kind in ("valtype", "plain"):
        for sh, ty, ctor, sc in nshapes:
            cid = f"a_nest_{kind}_{sh}"
            attr = "#valtype\n" if kind == "valtype" else ""
            lib = f"""{attr}pub struct S {{ x : Int }}

pub enum E {{ A; B(Int) }}

{attr}pub struct Outer {{
  id : Int
  n : {ty}
}}

pub fn run() -> Int {{
  let o = Outer::{{ id: 1, n: {ctor} }}
  let arr : Array[Outer] = []
  arr.push(o)
  let v = arr[0].n
  let n = {sc}
  n + arr[0].id
}}
"""
            test = 'test "case" { assert_true(run() >= 0) }\n'
            ids.append(emit(cid, "A5_nested", {"kind": kind, "shape": sh},
                            base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- B: FFI / native stub ----------------
def gen_b_ffi():
    ids = []
    stub = """#include "moonbit.h"
#include <stdint.h>
#include <string.h>
static unsigned char sink[64];
"""
    shapes = [
        ("v128_arg", "pub fn run() -> Unit { take_v128(@v128.f32x4_const(1.0, 2.0, 3.0, 4.0)) }",
         'extern "C" fn take_v128(a : V128) -> Unit = "probe_v128_arg"', "void probe_v128_arg(moonbit_v128_t a) { memcpy(sink, &a, 16); }", True),
        ("v128_ret", "pub fn run() -> Unit { let v = ret_v128(); ignore(v) }",
         'extern "C" fn ret_v128() -> V128 = "probe_v128_ret"', "moonbit_v128_t probe_v128_ret(void) { moonbit_v128_t v; memset(&v, 0, 16); return v; }", True),
        ("v128_two", "pub fn run() -> Unit { take_v128_2(@v128.f32x4_const(1.0,1.0,1.0,1.0), @v128.f32x4_const(2.0,2.0,2.0,2.0)) }",
         'extern "C" fn take_v128_2(a : V128, b : V128) -> Unit = "probe_v128_two"', "void probe_v128_two(moonbit_v128_t a, moonbit_v128_t b) { memcpy(sink, &a, 16); memcpy(sink+16, &b, 16); }", True),
        ("v128_mixed", "pub fn run(x : Int) -> Unit { take_mixed(x, @v128.f32x4_const(1.0,1.0,1.0,1.0), 3) }",
         'extern "C" fn take_mixed(a : Int, b : V128, c : Int) -> Unit = "probe_mixed"', "void probe_mixed(int32_t a, moonbit_v128_t b, int32_t c) { (void)a; (void)c; memcpy(sink, &b, 16); }", True),
        ("struct_arg", "pub fn run() -> Unit { take_s(S::{ x: 1, y: 2 }) }",
         '#borrow(a)\nextern "C" fn take_s(a : S) -> Unit = "probe_struct_arg"', "void probe_struct_arg(void* a) { (void)a; }", False),
        ("struct_ret", "pub fn run() -> Unit { let s = ret_s(); ignore(s.x) }",
         'extern "C" fn ret_s() -> S = "probe_struct_ret"', "void* probe_struct_ret(void) { return 0; }", False),
        ("struct_pair", "pub fn run() -> Unit { let s = ret_s(); take_s(s) }",
         '#borrow(a)\nextern "C" fn take_s(a : S) -> Unit = "probe_struct_arg"\nextern "C" fn ret_s() -> S = "probe_struct_ret"', "void probe_struct_arg(void* a) { (void)a; }\nvoid* probe_struct_ret(void) { return 0; }", False),
        ("enum_arg", "pub fn run() -> Unit { take_e(E::B(4)) }",
         '#borrow(a)\nextern "C" fn take_e(a : E) -> Unit = "probe_enum_arg"', "void probe_enum_arg(void* a) { (void)a; }", False),
        ("big_struct", "pub fn run() -> Unit { take_big(B::{ a: 1, b: 2L, c: true, d: \"q\" }) }",
         '#borrow(a)\nextern "C" fn take_big(a : B) -> Unit = "probe_big_arg"', "void probe_big_arg(void* a) { (void)a; }", False),
    ]
    for kind in ("valtype", "plain"):
        for name, run, decls, cdef, needs_v128 in shapes:
            cid = f"b_ffi_{kind}_{name}"
            attr = "#valtype\n" if kind == "valtype" else ""
            defs = attr + """pub struct S {
  x : Int
  y : Int
}

pub enum E { A; B(Int) }
"""
            if name == "big_struct":
                defs = attr + """pub struct B {
  a : Int
  b : Int64
  c : Bool
  d : String
}
"""
            imports = 'import {\n  "moonbitlang/core/v128",\n}\n' if needs_v128 else ""
            pkg = imports + 'options(\n  "native-stub": [ "stub.c" ],\n)\n'
            lib = defs + "\n" + decls + "\n\n" + run + "\n"
            test = ('test "case" { run(1) }\n' if name == "v128_mixed" else 'test "case" { run() }\n')
            extra = {"stub.c": stub + cdef + "\n"}
            ids.append(emit(cid, "B_ffi", {"kind": kind, "shape": name},
                            base_files(f"probe/{cid}", lib, test, pkg=pkg, extra=extra)))
    return ids

# ---------------- C: async ----------------
ASYNC_DEPS = ("moonbitlang/async@0.22.9",)
ASYNC_PKG = 'import {\n  "moonbitlang/async" @aio,\n}\n'

def async_case(cid, meta, lib, test):
    return emit(cid, "C_async", meta,
                base_files(f"probe/{cid}", lib, test, pkg=ASYNC_PKG, deps=ASYNC_DEPS))

def gen_c_async():
    ids = []
    shapes = [
        # name, lib, test
        ("f8_pause_then_raiseq",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}
""",
         """async test "c" {
  let _ = pick(fn(x) { if x == 1 { Some(x) } else { None } })
}
"""),
        ("raiseq_then_pause",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  let r = select(1)
  @aio.pause()
  r
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
}
"""),
        ("no_pause_raiseq",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  select(1)
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
}
"""),
        ("raise_control",
         """pub async fn[T] pick(select : (Int) -> T raise?) -> T {
  @aio.pause()
  select(1)
}
""",
         """async test "c" {
  let _ = pick(fn(x) { x })
}
"""),
        ("two_pause_raiseq",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  @aio.pause()
  select(2)
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
}
"""),
        ("loop_pause_raiseq",
         """pub async fn[T] pick(n : Int, select : (Int) -> T? raise?) -> T? {
  let mut r : T? = None
  for i in 0..<n {
    @aio.pause()
    if i == 2 { break }
    r = select(i)
  }
  r
}
""",
         """async test "c" {
  let _ = pick(4, fn(x) { Some(x) })
}
"""),
        ("loop_continue_raiseq",
         """pub async fn[T] pick(n : Int, select : (Int) -> T? raise?) -> T? {
  let mut r : T? = None
  for i in 0..<n {
    @aio.pause()
    if i % 2 == 0 { continue }
    r = select(i)
  }
  r
}
""",
         """async test "c" {
  let _ = pick(4, fn(x) { Some(x) })
}
"""),
        ("try_catch_raiseq",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  try {
    @aio.pause()
    select(1)
  } catch {
    _ => None
  }
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
}
"""),
        ("nested_async_raiseq",
         """pub async fn[T] inner(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}

pub async fn[T] outer(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  inner(select)
}
""",
         """async test "c" {
  let _ = outer(fn(x) { Some(x) })
}
"""),
        ("struct_ret_raiseq",
         """pub struct R { x : Int; y : String }

pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}

pub async fn make() -> R {
  @aio.pause()
  R::{ x: 1, y: "a" }
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
  let r = make()
  assert_true(r.x >= 0)
}
"""),
        ("raiseq_inside_loop_try",
         """pub async fn[T] pick(n : Int, select : (Int) -> T? raise?) -> T? {
  let mut r : T? = None
  for i in 0..<n {
    try {
      @aio.pause()
      r = select(i)
    } catch {
      _ => ()
    }
    if i == 1 { break }
  }
  r
}
""",
         """async test "c" {
  let _ = pick(3, fn(x) { Some(x) })
}
"""),
        ("with_timeout_raiseq",
         """pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.with_timeout(50, fn() {
    @aio.pause()
    select(1)
  })
}
""",
         """async test "c" {
  let _ = pick(fn(x) { Some(x) })
}
"""),
    ]
    for name, lib, test in shapes:
        ids.append(async_case(f"c_async_{name}", {"shape": name}, lib, test))
    agg_shapes = [
        ("keep_struct_nopause",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> Int {
  let s = S::{ x: 1, y: "a" }
  s.x
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_struct_pause",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> Int {
  let s = S::{ x: 1, y: "a" }
  @aio.pause()
  s.x + s.y.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_struct_gc_pause",
         """#valtype
pub struct S { id : Int; a : Array[Int]; s : String }
pub async fn f() -> Int {
  let s = S::{ id: 1, a: [1, 2, 3], s: "abc" }
  @aio.pause()
  s.id + s.a.length() + s.s.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_array_struct_pause",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> Int {
  let a : Array[S] = []
  a.push(S::{ x: 1, y: "b" })
  @aio.pause()
  a[0].x + a.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_enum_gc_pause",
         """pub enum E { A; B(String); C(Array[Int]) }
pub async fn f(n : Int) -> Int {
  let e : E = if n == 0 { A } else if n == 1 { B("x") } else { C([1, 2]) }
  @aio.pause()
  match e {
    A => 0
    B(_) => 1
    C(_) => 2
  }
}
""",
         """async test "c" { assert_true(f(2) >= 0) }
"""),
        ("keep_fixedarray_pause",
         """pub async fn f() -> Int {
  let fa = FixedArray::make(3, 0)
  fa[0] = 7
  @aio.pause()
  fa[0] + fa.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_bytes_pause",
         """pub async fn f() -> Int {
  let b : Bytes = b"abcd"
  @aio.pause()
  b.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_option_struct_pause",
         """#valtype
pub struct S { x : Int }
pub async fn f() -> Int {
  let o : Option[S] = Some(S::{ x: 3 })
  @aio.pause()
  match o { Some(s) => s.x; None => 0 }
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("keep_result_struct_pause",
         """#valtype
pub struct S { x : Int }
pub async fn f() -> Int {
  let r : Result[S, String] = Ok(S::{ x: 3 })
  @aio.pause()
  match r { Ok(s) => s.x; Err(_) => 0 }
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("raising_across_pause",
         """pub async fn f(n : Int) -> Int raise {
  if n < 0 { raise Failure("neg") }
  @aio.pause()
  n
}
""",
         """async test "c" { assert_true(f(1) >= 0) }
"""),
        ("try_catch_pause_raise",
         """pub async fn f() -> Int {
  try {
    @aio.pause()
    raise Failure("x")
  } catch {
    _ => 1
  }
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("nested_async_nonraise",
         """pub async fn inner() -> Int {
  @aio.pause()
  1
}
pub async fn outer() -> Int {
  @aio.pause()
  inner()
}
""",
         """async test "c" { assert_true(outer() >= 0) }
"""),
        ("async_returns_valtype_struct",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> S {
  let s = S::{ x: 1, y: "a" }
  @aio.pause()
  s
}
""",
         """async test "c" { let s = f(); assert_true(s.x >= 0) }
"""),
        ("multiple_aggregates_pause",
         """#valtype
pub struct S { x : Int; y : String }
pub enum E { A; B(Int) }
pub async fn f() -> Int {
  let s = S::{ x: 1, y: "q" }
  let e = E::B(2)
  let a = [1, 2, 3]
  @aio.pause()
  s.x + a.length() + (match e {
    A => 0
    B(x) => x
  })
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
    ]
    for name, lib, test in agg_shapes:
        ids.append(async_case(f"c_async_{name}", {"shape": name}, lib, test))
    # extra: pause position / mixed variants
    for pos in range(3):
        cid = f"c_async_pause_pos{pos}"
        pre = "  @aio.pause()\n" * pos
        mid = "  @aio.pause()\n"
        post = "  @aio.pause()\n" * (2 - pos)
        lib = f"""pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {{
{pre}  let r = select({pos})
{mid}{post}  r
}}
"""
        test = 'async test "c" { let _ = pick(fn(x) { Some(x) }) }\n'
        ids.append(async_case(cid, {"shape": f"pause_pos{pos}"}, lib, test))
    return ids

# ---------------- A6: cross-package aggregate ABI ----------------
def gen_a_crosspkg():
    ids = []
    shapes = [
        ("s_plain", "", "#valtype\n" if False else "", "S", "plain", "struct"),
        ("s_valtype", "#valtype\n", "", "S", "valtype", "struct"),
        ("e_plain", "", "", "E", "plain", "enum"),
        ("e_valtype", "#valtype\n", "", "E", "valtype", "enum"),
    ]
    for name, _, _, ty, kind, what in shapes:
        for arity in (1, 4, 8, 12):
            cid = f"a_cross_{name}_n{arity}"
            if what == "struct":
                decl = ("#valtype\n" if kind == "valtype" else "") + """pub struct S {
  x : Int
  y : String
  a : Array[Int]
}

pub fn mk(n : Int) -> S { S::{ x: n, y: "s", a: [n] } }
pub fn score(s : S) -> Int { s.x + s.y.length() + s.a.length() }
"""
                args = ", ".join(f"a{i} : S" for i in range(arity))
                cons = ", ".join(f"@lib.mk({i})" for i in range(arity))
                callee = f"pub fn combine({args}) -> S {{\n  let mut acc = 0\n  " + "\n  ".join(
                    f"acc = acc + score(a{i})" for i in range(arity)) + "\n  mk(acc)\n}\n"
                caller = f"  let r = @lib.combine({cons})\n  let _ = @lib.score(r)\n"
            else:
                decl = "pub enum E { A; B(Int); C(String) }\n\npub fn mk_e(i : Int) -> E { if i % 2 == 0 { E::B(i) } else { E::C(\"q\") } }\n"
                args = ", ".join(f"a{i} : E" for i in range(arity))
                cons = ", ".join(f"@lib.mk_e({i})" for i in range(arity))
                callee = f"pub fn combine({args}) -> Int {{\n  " + " ".join(
                    f"let v{i} = match a{i} {{ A => 0; B(x) => x; C(_) => 1 }}\n  " for i in range(arity)) + \
                    "\n  " + " + ".join(f"v{i}" for i in range(arity)) + "\n}\n"
                caller = f"  let r = @lib.combine({cons})\n  ignore(r)\n"
            files = {
                "moon.mod": mod(f"probe/{cid}"),
                "lib/moon.pkg": "",
                "lib/lib.mbt": decl + callee,
                "lib/lib_wbtest.mbt": ('test "lib" { assert_true(score(mk(1)) >= 0) }\n' if what == "struct" else f'test "lib" {{ assert_true(combine({", ".join(f"mk_e({i})" for i in range(arity))}) >= 0) }}\n'),
                "app/moon.pkg": f'import {{\n  "probe/{cid}/lib" @lib,\n}}\n\npkgtype(kind: "executable")\n',
                "app/main.mbt": "fn main {\n" + caller + "}\n",
            }
            ids.append(emit(cid, "A6_crosspkg", {"shape": name, "n": arity}, files))
    return ids

# ---------------- A7: extra native layout lowerings ----------------
def gen_a_layout2():
    ids = []
    tmpl = {
        "arr_literal": """pub fn run() -> Int {
  let a : Array[S] = [S::{ x: 1, y: "a" }, S::{ x: 2, y: "b" }]
  a[0].x + a.length()
}
""",
        "arr_make_init": """pub fn run() -> Int {
  let a : Array[S] = Array::make(2, S::{ x: 1, y: "a" })
  a[1].x + a.length()
}
""",
        "arr_makei": """pub fn run() -> Int {
  let a : Array[S] = Array::makei(3, fn(i) { S::{ x: i, y: "a" } })
  a[2].x + a.length()
}
""",
        "arr_reserve": """pub fn run() -> Int {
  let a : Array[S] = []
  a.reserve_capacity(8)
  a.push(S::{ x: 1, y: "a" })
  a[0].x
}
""",
        "farr_make_init": """pub fn run() -> Int {
  let a : FixedArray[S] = FixedArray::make(2, S::{ x: 1, y: "a" })
  a[1].x + a.length()
}
""",
        "farr_makei": """pub fn run() -> Int {
  let a : FixedArray[S] = FixedArray::makei(3, fn(i) { S::{ x: i, y: "a" } })
  a[2].x + a.length()
}
""",
        "arr_enum_make": """pub fn run() -> Int {
  let a : Array[E] = Array::make(2, E::B("q"))
  match a[0] { A => 0; B(_) => 1; C(_) => 2 }
}
""",
        "arrview": """pub fn run() -> Int {
  let a : Array[S] = [S::{ x: 1, y: "a" }, S::{ x: 2, y: "b" }]
  let v = a[0:2]
  v[1].x + v.length()
}
""",
        "from_fixed": """pub fn run() -> Int {
  let fa : FixedArray[S] = FixedArray::make(2, S::{ x: 1, y: "a" })
  let a = Array::from_fixed_array(fa)
  a[0].x + a.length()
}
""",
        "big_arity": """pub fn run() -> Int {
  let a0 = mk(1)
  let a1 = mk(2)
  let a2 = mk(3)
  let a3 = mk(4)
  let a4 = mk(5)
  let a5 = mk(6)
  let r = combine(a0, a1, a2, a3, a4, a5)
  r.x
}
""",
    }
    for kind in ("valtype", "plain"):
        for name, body in tmpl.items():
            cid = f"a_layout2_{kind}_{name}"
            attr = "#valtype\n" if kind == "valtype" else ""
            decl = attr + """pub struct S {
  x : Int
  y : String
}

pub enum E { A; B(String); C(Array[Int]) }

pub fn mk(n : Int) -> S { S::{ x: n, y: "s" } }
pub fn combine(a : S, b : S, c : S, d : S, e : S, f : S) -> S {
  S::{ x: a.x + b.x + c.x + d.x + e.x + f.x, y: "r" }
}
"""
            lib = decl + "\n" + body
            test = 'test "case" { assert_true(run() >= 0) }\n'
            ids.append(emit(cid, "A7_layout2", {"kind": kind, "shape": name},
                            base_files(f"probe/{cid}", lib, test)))
    # wide structs
    for n in (6, 8, 12, 16):
        cid = f"a_layout2_wide_{n}"
        fields = "\n".join(f"  f{i} : {'String' if i % 3 == 2 else 'Int'}" for i in range(n))
        vals = ", ".join((f'f{i}: "s"' if i % 3 == 2 else f"f{i}: {i}") for i in range(n))
        get = " + ".join((f"s.f{i}.length()" if i % 3 == 2 else f"s.f{i}") for i in range(n))
        lib = f"""#valtype
pub struct W {{
{fields}
}}

pub fn mk() -> W {{ W::{{ {vals} }} }}

pub fn get(s : W) -> Int {{ {get} }}

pub fn run() -> Int {{
  let w = mk()
  let a : Array[W] = [w, mk()]
  get(a[1]) + a.length()
}}
"""
        test = 'test "case" { assert_true(run() >= 0) }\n'
        ids.append(emit(cid, "A7_layout2", {"kind": "wide", "n": n},
                        base_files(f"probe/{cid}", lib, test)))
    return ids

# ---------------- B2: extra FFI ----------------
def gen_b_ffi2():
    ids = []
    shapes = [
        ("owned_bytes", "#owned(b)", 'extern "C" fn take_bytes(b : Bytes) -> Unit = "probe_bytes"',
         "void probe_bytes(void* b) { (void)b; }",
         "pub fn run() -> Unit { take_bytes(b\"abc\") }", False),
        ("borrow_farr", "#borrow(a)", 'extern "C" fn take_farr(a : FixedArray[Int]) -> Unit = "probe_farr"',
         "void probe_farr(void* a) { (void)a; }",
         "pub fn run() -> Unit { take_farr(FixedArray::make(2, 1)) }", False),
        ("three_structs", "#borrow(a)\n#borrow(b)\n#borrow(c)",
         'extern "C" fn take3(a : S, b : S, c : S) -> Unit = "probe_three"',
         "void probe_three(void* a, void* b, void* c) { (void)a; (void)b; (void)c; }",
         "pub fn run() -> Unit { take3(S::{ x: 1, y: 2 }, S::{ x: 3, y: 4 }, S::{ x: 5, y: 6 }) }", False),
        ("struct_v128_field", "#borrow(a)", 'extern "C" fn take_sv(a : SV) -> Unit = "probe_sv"',
         "void probe_sv(void* a) { (void)a; }",
         "pub fn run() -> Unit { take_sv(SV::{ v: @v128.f32x4_const(1.0,1.0,1.0,1.0), n: 2 }) }", True),
        ("v128_ret_use", "", 'extern "C" fn ret_v128() -> V128 = "probe_v128_ret2"',
         "void probe_v128_ret2(void) {}",
         "pub fn run() -> Unit { let v = ret_v128(); ignore(v) }", True),
        ("enum_ret", "", 'extern "C" fn ret_e() -> E = "probe_enum_ret"',
         "void probe_enum_ret(void) {}",
         "pub fn run() -> Unit { let e = ret_e(); ignore(e) }", False),
        ("mixed_s_e", "#borrow(a)\n#borrow(b)",
         'extern "C" fn take_se(a : S, b : E) -> Unit = "probe_se"',
         "void probe_se(void* a, void* b) { (void)a; (void)b; }",
         "pub fn run() -> Unit { take_se(S::{ x: 1, y: 2 }, E::B(3)) }", False),
        ("v128_and_struct", "#borrow(a)",
         'extern "C" fn take_vs(v : V128, a : S) -> Unit = "probe_vs"',
         "void probe_vs(moonbit_v128_t v, void* a) { (void)v; (void)a; }",
         "pub fn run() -> Unit { take_vs(@v128.f32x4_const(1.0,1.0,1.0,1.0), S::{ x: 1, y: 2 }) }", True),
        ("big_ret", "", 'extern "C" fn ret_big() -> B = "probe_big_ret"',
         "void probe_big_ret(void) {}",
         "pub fn run() -> Unit { let b = ret_big(); ignore(b.a) }", False),
    ]
    for kind in ("valtype", "plain"):
        for name, attrs, decls, cdef, run, needs_v128 in shapes:
            cid = f"b_ffi2_{kind}_{name}"
            attr = "#valtype\n" if kind == "valtype" else ""
            defs = attr + """pub struct S {
  x : Int
  y : Int
}

pub enum E { A; B(Int) }

type SV

pub struct B {
  a : Int
  b : Int64
  c : Bool
  d : String
}
"""
            if name == "struct_v128_field":
                defs = "#valtype\npub struct SV {\n  v : V128\n  n : Int\n}\n"
            if name == "big_ret" or name == "mixed_s_e":
                pass
            ann = ""
            if attrs:
                ann = "\n".join(attrs.split("\\n")) + "\n"
            imports = 'import {\n  "moonbitlang/core/v128",\n}\n' if needs_v128 else ""
            pkg = imports + 'options(\n  "native-stub": [ "stub.c" ],\n)\n'
            lib = defs + "\n" + ann + decls + "\n\n" + run + "\n"
            test = 'test "case" { run() }\n'
            extra = {"stub.c": "#include \"moonbit.h\"\n#include <stdint.h>\n#include <string.h>\nstatic unsigned char sink[64];\n" + cdef + "\n"}
            ids.append(emit(cid, "B2_ffi2", {"kind": kind, "shape": name},
                            base_files(f"probe/{cid}", lib, test, pkg=pkg, extra=extra)))
    return ids

# ---------------- C2: extra async ----------------
def gen_c_async2():
    ids = []
    shapes = [
        ("param_struct_pause",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f(s : S) -> Int {
  @aio.pause()
  s.x + s.y.length()
}
""",
         """async test "c" { assert_true(f(S::{ x: 1, y: "a" }) >= 0) }
"""),
        ("param_enum_pause",
         """pub enum E { A; B(String); C(Array[Int]) }
pub async fn f(e : E) -> Int {
  @aio.pause()
  match e { A => 0; B(_) => 1; C(_) => 2 }
}
""",
         """async test "c" { assert_true(f(E::C([1])) >= 0) }
"""),
        ("defer_pause",
         """pub async fn f() -> Int {
  let mut n = 0
  defer { n = n + 1 }
  @aio.pause()
  n
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("match_enum_pause",
         """pub enum E { A; B(Int) }
pub async fn f(e : E) -> Int {
  let mut r = 0
  match e {
    A => { @aio.pause(); r = 1 }
    B(x) => { @aio.pause(); r = x }
  }
  r
}
""",
         """async test "c" { assert_true(f(E::B(3)) >= 0) }
"""),
        ("generic_value_pause",
         """pub async fn[T] f(v : T) -> T {
  @aio.pause()
  v
}
""",
         """async test "c" { assert_true(f(3) >= 0) }
"""),
        ("arr_push_struct_pause",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> Int {
  let a : Array[S] = []
  a.push(S::{ x: 1, y: "a" })
  @aio.pause()
  a[0].x + a.length()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("nested_raise_try_pause",
         """pub async fn inner(n : Int) -> Int raise {
  if n < 0 { raise Failure("neg") }
  n
}
pub async fn outer(n : Int) -> Int {
  try {
    @aio.pause()
    inner(n)
  } catch {
    _ => 0
  }
}
""",
         """async test "c" { assert_true(outer(1) >= 0) }
"""),
        ("returns_array_struct",
         """#valtype
pub struct S { x : Int; y : String }
pub async fn f() -> Array[S] {
  @aio.pause()
  [S::{ x: 1, y: "a" }]
}
""",
         """async test "c" { let a = f(); assert_true(a.length() >= 0) }
"""),
        ("closure_capture_pause",
         """#valtype
pub struct S { x : Int }
pub async fn f() -> Int {
  let s = S::{ x: 4 }
  let g = fn() { s.x }
  @aio.pause()
  g()
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("handle_cancellation_pause",
         """pub async fn f() -> Int {
  let r = @aio.handle_cancellation(fn() {
    @aio.pause()
    1
  })
  match r { Some(x) => x; None => 0 }
}
""",
         """async test "c" { assert_true(f() >= 0) }
"""),
        ("loop_break_pause",
         """pub async fn f(n : Int) -> Int {
  let mut r = 0
  for i in 0..<n {
    @aio.pause()
    if i == 2 { break }
    r = r + i
  }
  r
}
""",
         """async test "c" { assert_true(f(4) >= 0) }
"""),
        ("while_loop_pause",
         """pub async fn f(n : Int) -> Int {
  let mut i = 0
  let mut r = 0
  while i < n {
    @aio.pause()
    r = r + i
    i = i + 1
  }
  r
}
""",
         """async test "c" { assert_true(f(3) >= 0) }
"""),
    ]
    for name, lib, test in shapes:
        ids.append(async_case(f"c_async2_{name}", {"shape": name}, lib, test))
    return ids

# ---------------- runner ----------------
ICE_PAT = re.compile(
    r'Assertion failed|Machine_error|unexpected situation|Fatal error|internal error|'
    r'Stack overflow|moonc\.ml["\']?,? line|Invalid_argument|Not_found|Match_failure')
DIAG_PAT = re.compile(r'^Error: \[\d+\]|^Error: \[[0-9A-Z]+\]')

def normalize(out):
    """Extract normalized ICE signature or diagnostic marker."""
    lines = out.splitlines()
    sig = []
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith("Compiler args:"):
            continue
        if "Assertion failed" in s:
            m = re.search(r'File "([^"]+)", line (\d+)', s)
            sig.append(f"assert:{m.group(1)}:{m.group(2)}" if m else "assert:unknown")
        elif "Machine_error" in s:
            m = re.search(r'Machine_error\(kind=([^;]+);\s*who="([^"]+)";\s*message="([^"]*)"', s)
            if m:
                sig.append(f"machine:{m.group(1)}:{m.group(2)}:{m.group(3)}")
            else:
                sig.append(s[:300])
        elif "unexpected situation" in s:
            sig.append("ice-banner")
        elif re.search(r'(Fatal error|internal error|Invalid_argument|Not_found|Match_failure|Stack overflow)', s):
            sig.append(s[:300])
        elif re.search(r'^Error: \[[0-9A-Z]+\]', s):
            sig.append("diag:" + s[:120])
        elif s.startswith("Error:") and len(sig) < 8:
            sig.append("err:" + s[:300])
    # dedupe preserve order
    out2 = []
    for x in sig:
        if x not in out2:
            out2.append(x)
    return out2

def run_cmd(cmd, cwd, timeout=180):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or ""), time.time() - t0
    except subprocess.TimeoutExpired as e:
        out = ""
        for stream in (e.stdout, e.stderr):
            if stream:
                out += stream.decode() if isinstance(stream, bytes) else stream
        return "TIMEOUT", out, time.time() - t0

STAGES = [
    ("check", ["moon", "check", "--target", "native"]),
    ("build", ["moon", "build", "--target", "native"]),
    ("testbuild", ["moon", "test", "--target", "native", "--build-only"]),
]

def run_case(cid):
    d = os.path.join(CASES, cid)
    meta = json.load(open(os.path.join(d, ".meta.json")))
    rec = {"id": cid, "family": meta["family"], "meta": meta, "stages": {}}
    for stage, cmd in STAGES:
        rc, out, dur = run_cmd(cmd, d)
        sig = normalize(out)
        rec["stages"][stage] = {"rc": rc, "sig": sig, "dur": round(dur, 2),
                                "tail": out[-1500:]}
    return rec

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    gens = {
        "A": [gen_a_structs, gen_a_enums, gen_a_ops, gen_a_arities, gen_a_nested, gen_a_crosspkg, gen_a_layout2],
        "B": [gen_b_ffi, gen_b_ffi2],
        "C": [gen_c_async, gen_c_async2],
    }
    ids = []
    for key in (["A", "B", "C"] if which == "all" else list(which)):
        for g in gens[key]:
            got = g()
            print(f"{g.__name__}: {len(got)} cases", flush=True)
            ids += got
    print(f"total {len(ids)} cases", flush=True)
    t0 = time.time()
    recs = []
    with cf.ThreadPoolExecutor(max_workers=12) as ex:
        futs = {ex.submit(run_case, cid): cid for cid in ids}
        done = 0
        for fut in cf.as_completed(futs):
            recs.append(fut.result())
            done += 1
            if done % 20 == 0:
                print(f"  ran {done}/{len(ids)}", flush=True)
    recs.sort(key=lambda r: r["id"])
    outpath = os.path.join(RESULTS, f"results_{which}.jsonl")
    with open(outpath, "w") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")
    # summary
    def is_ice(rec):
        return any(any(s.startswith(("assert:", "machine:", "ice-banner", "Fatal error", "internal error", "Invalid_argument")) or
                       "Fatal error" in s or "internal error" in s or "Invalid_argument" in s
                       for s in st["sig"]) for st in rec["stages"].values())
    ice = [r for r in recs if is_ice(r)]
    diag = [r for r in recs if not is_ice(r) and
            any(st["rc"] not in (0, "TIMEOUT") for st in r["stages"].values())]
    print(f"\n{len(ids)} cases, {len(ice)} ICE-ish, {len(diag)} non-ICE failures, {time.time()-t0:.1f}s")
    groups = {}
    for r in ice:
        keys = []
        for st in r["stages"].values():
            keys += [s for s in st["sig"] if s.startswith(("assert:", "machine:", "ice-banner")) or
                     "Fatal error" in s or "internal error" in s or "Invalid_argument" in s]
        prio = [k for k in keys if k.startswith(("assert:", "machine:"))]
        key = (prio or keys or ["?"])[0]
        groups.setdefault(key, []).append(r["id"])
    for k, v in sorted(groups.items()):
        print(f"\nSIG {k}\n  n={len(v)}: {', '.join(v[:8])}{' ...' if len(v) > 8 else ''}")
    if diag:
        print("\nnon-ICE failing cases (likely generator bugs / compile errors):")
        for r in diag[:40]:
            st = next((s for s in r["stages"].values() if s["rc"] not in (0, "TIMEOUT")), None)
            print(f"  {r['id']}: {st['sig'][:2]}")
    print(f"\nresults: {outpath}")

if __name__ == "__main__":
    main()
