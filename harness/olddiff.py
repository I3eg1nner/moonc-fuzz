#!/usr/bin/env python3
"""Differential front-end testing: 2025-03-12 open-source moonc vs current moonc.

Old binary (built from /data/audit/moonbit-compiler, v0.1.20250312+a7a1e9804):
    _build/default/src/moon0_main.exe check -no-mi -pkg cal/p c.mbt
New binary:
    ~/.moon/bin/moonc check -no-mi -pkg cal/p -i <core>/bundle/prelude/prelude.mi c.mbt

Both are invoked in a temp dir on a single dependency-free file.  The old
compiler has builtin Int/String/operators hard-coded and needs no prelude; the
new one requires the current prelude import, so the shared subset avoids
prelude-provided methods (`.to_string()`, `println`, `Array::push`, ...).

Modes:
  calib  -- 60 shared-language controls with expected accept/reject; gate:
            >= 50 controls where *both* compilers match the expectation.
  diff   -- generated well-typed and ill-typed programs; classify
            SAME_ACCEPT / SAME_REJECT / NEW_REJECT / NEW_ACCEPT / NEW_CRASH.
  min    -- token-deletion reducer preserving a chosen disagreement class.

Usage:
  python3 harness/olddiff.py calib
  python3 harness/olddiff.py diff --n 600 --out out/olddiff.jsonl
  python3 harness/olddiff.py min --src '<program>' --class NEW_ACCEPT
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import syntax_boundary as sb  # run_measured / classify

OLD = os.path.join(ROOT, "..", "moonbit-compiler", "_build", "default", "src", "moon0_main.exe")
OLD = os.path.abspath(OLD)
NEW = os.path.expanduser("~/.moon/bin/moonc")
PRELUDE = os.path.expanduser(
    "~/.moon/lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi")
TMP = os.path.join(ROOT, "out", "olddiff_tmp")

OLD_ARGS = [OLD, "check", "-no-mi", "-pkg", "cal/p"]
NEW_ARGS = [NEW, "check", "-no-mi", "-pkg", "cal/p", "-i", PRELUDE]


def run_one(which, src, timeout=10):
    os.makedirs(TMP, exist_ok=True)
    d = os.path.join(TMP, which)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "c.mbt"), "w") as f:
        f.write(src)
    argv = (OLD_ARGS if which == "old" else NEW_ARGS) + ["c.mbt"]
    r = sb.run_measured(argv, d, timeout, os.path.join(d, "o"), os.path.join(d, "e"))
    st, sig = sb.classify(r)
    return {"rc": r["rc"], "status": st, "sig": sig, "ms": r["ms"],
            "stderr": r["stderr"][:600]}


def compare(src, timeout=10):
    old = run_one("old", src, timeout)
    new = run_one("new", src, timeout)
    oa, na = old["rc"] == 0, new["rc"] == 0
    if new["status"] in ("crash", "ice", "timeout", "silent"):
        cls = "NEW_CRASH"
    elif oa and na:
        cls = "SAME_ACCEPT"
    elif (not oa) and (not na):
        cls = "SAME_REJECT"
    elif oa and not na:
        cls = "NEW_REJECT"
    elif na and not oa:
        cls = "NEW_ACCEPT"
    else:
        cls = "OTHER"
    return {"class": cls, "old": old, "new": new}


# --------------------------------------------------------------------------
# calibration controls
# --------------------------------------------------------------------------

def controls():
    """Only constructs accepted/rejected identically by both snapshots with
    no prelude import (verified in the calibration run itself)."""
    C = []

    def add(name, src, expect):
        C.append({"name": name, "src": src, "expect": expect})

    # ---- shared accepts: builtin arithmetic / control flow ----------------
    add("intlit", "fn f() -> Int { 42 }", "accept")
    add("add", "fn f() -> Int { 1 + 2 }", "accept")
    add("sub", "fn f(x : Int) -> Int { x - 1 }", "accept")
    add("prec", "fn f() -> Int { 1 + 2 * 3 }", "accept")
    add("prec2", "fn f() -> Int { 1 - 2 - 3 }", "accept")
    add("paren", "fn f() -> Int { (1 + 2) * 3 }", "accept")
    add("shift", "fn f() -> Int { (1 << 3) >> 1 }", "accept")
    add("bitwise", "fn f() -> Int { (6 & 3) | (4 ^ 1) }", "accept")
    add("divmod", "fn f() -> Int { 7 / 2 + 7 % 2 }", "accept")
    add("muldiv", "fn f(x : Int) -> Int { x * 2 / 3 % 2 }", "accept")
    add("cmp", "fn f(x : Int) -> Bool { x < 3 }", "accept")
    add("eq", "fn f(x : Int) -> Bool { x == 3 }", "accept")
    add("bool_and", "fn f(a : Bool, b : Bool) -> Bool { a && b }", "accept")
    add("bool_or", "fn f(a : Bool, b : Bool) -> Bool { a || b }", "accept")
    add("bool_lit", "fn f() -> Bool { true }", "accept")
    add("unit", "fn f() -> Unit { () }", "accept")
    add("if", "fn f(x : Int) -> Int { if x > 0 { 1 } else { 0 } }", "accept")
    add("ifelseif", "fn f(x : Int) -> Int { if x > 0 { 1 } else if x < 0 { -1 } else { 0 } }", "accept")
    add("ifnested", "fn f(x : Int) -> Int { if x > 0 { if x > 1 { 2 } else { 1 } } else { 0 } }", "accept")
    add("let", "fn f() -> Int { let a = 1; let b = 2; a + b }", "accept")
    add("letshadow", "fn f() -> Int { let a = 1; let a = 2; a }", "accept")
    add("letmut", "fn f() -> Int { let mut a = 1; a = a + 1; a }", "accept")
    add("assign", "fn f() -> Int { let mut a = 1; a = 2; a }", "accept")
    add("while", "fn f() -> Int { let mut i = 0; while i < 3 { i = i + 1 }; i }", "accept")
    add("forloop", "fn f() -> Int { let mut s = 0; for i in 0..<10 { s = s + i }; s }", "accept")
    add("fact", "fn fact(n : Int) -> Int { if n <= 1 { 1 } else { n * fact(n - 1) } }", "accept")
    add("unusedarg", "fn f(x : Int) -> Int { 0 }", "accept")
    add("label", "fn f(x~ : Int) -> Int { x }\nfn g() -> Int { f(x=1) }", "accept")
    add("stringlit", 'fn f() -> String { "hello" }', "accept")
    add("string_cat", 'fn f() -> String { "a" + "b" }', "accept")
    add("string_cmp", 'fn f() -> Bool { "a" == "b" }', "accept")

    # ---- shared accepts: patterns / enum / struct / tuple -----------------
    add("match_int", "fn f(x : Int) -> Int { match x { 0 => 1; _ => 2 } }", "accept")
    add("match_or", "fn f(x : Int) -> Int { match x { 0 | 1 => 1; _ => 2 } }", "accept")
    add("match_bool", "fn f(b : Bool) -> Int { match b { true => 1; false => 0 } }", "accept")
    add("match_str", 'fn f(s : String) -> Int { match s { "a" => 1; _ => 0 } }', "accept")
    add("guard", "fn f(x : Int) -> Int { match x { n if n > 0 => 1; _ => 0 } }", "accept")
    add("enum", "enum E { A; B(Int) }\nfn f(e : E) -> Int { match e { A => 0; B(n) => n } }", "accept")
    add("enum_payload", "enum E { A(Int) }\nfn f(e : E) -> Int { match e { A(n) => n } }", "accept")
    add("enum_two", "enum E { A(Int); B(Int, Int) }\nfn f(e : E) -> Int { match e { A(n) => n; B(x, y) => x + y } }", "accept")
    add("struct", "struct S { x : Int; y : Int }\nfn f(s : S) -> Int { s.x + s.y }", "accept")
    add("struct_new", "struct S { x : Int }\nfn f() -> S { { x: 1 } }", "accept")
    add("struct_two", "struct S { x : Int; y : Int }\nfn f() -> S { { x: 1, y: 2 } }", "accept")
    add("tuple", "fn f() -> Int { let t = (1, 2); t.0 + t.1 }", "accept")
    add("tuple3", "fn f() -> Int { let t = (1, 2, 3); t.0 + t.1 + t.2 }", "accept")
    add("tuplepat", "fn f(t : (Int, Int)) -> Int { match t { (a, b) => a + b } }", "accept")
    add("nested_match", "fn f(x : Int, y : Int) -> Int { match (x, y) { (0, _) => 0; (a, b) => a + b } }", "accept")

    # ---- shared rejects ---------------------------------------------------
    add("rej_addstr", 'fn f() -> Int { 1 + "a" }', "reject")
    add("rej_unbound", "fn f() -> Int { nope }", "reject")
    add("rej_arity", "fn g(x : Int) -> Int { x }\nfn f() -> Int { g() }", "reject")
    add("rej_arity2", "fn g(x : Int) -> Int { x }\nfn f() -> Int { g(1, 2) }", "reject")
    add("rej_ret", "fn f() -> Int { true }", "reject")
    add("rej_field", "struct S { x : Int }\nfn f(s : S) -> Int { s.y }", "reject")
    add("rej_missing_field", "struct S { x : Int; y : Int }\nfn f() -> S { { x: 1 } }", "reject")
    add("rej_dup_field", "struct S { x : Int; x : Int }\nfn f() -> Int { 0 }", "reject")
    add("rej_enum_payload", "enum E { A }\nfn f(e : E) -> Int { match e { A(n) => n } }", "reject")
    add("rej_match_extra", "enum E { A }\nfn f(e : E) -> Int { match e { A => 0; B => 1 } }", "reject")
    add("rej_let_type", 'fn f() -> Int { let x : Int = "s"; x }', "reject")
    add("rej_unbound_type", "fn f(x : Nope) -> Int { 0 }", "reject")
    add("rej_call_nonfn", "fn f() -> Int { 1(2) }", "reject")
    add("rej_wrong_unop", 'fn f() -> Int { -"a" }', "reject")
    add("rej_if_branch", "fn f() -> Int { if true { 1 } else { false } }", "reject")
    add("rej_mut", "fn f() -> Int { let a = 1; a = 2; a }", "reject")
    add("rej_syntax1", "fn f( -> Int { 1 }", "reject")
    add("rej_syntax2", "fn f() -> Int { let = 1; 2 }", "reject")
    add("rej_syntax3", "fn f() -> Int { 1 + }", "reject")
    add("rej_syntax4", "fn f() -> Int { match 1 { 0 => } }", "reject")
    add("rej_arg_type", "fn g(x : Int) -> Int { x }\nfn f() -> Int { g(true) }", "reject")
    add("dup_arm_warn", "fn f(x : Int) -> Int { match x { 0 => 1; 0 => 2; _ => 3 } }", "accept")

    return C


def cmd_calib(args):
    C = controls()
    rows = []
    ok = 0
    for c in C:
        r = compare(c["src"])
        old_ok = r["old"]["rc"] == 0
        new_ok = r["new"]["rc"] == 0
        exp = c["expect"] == "accept"
        good_old = old_ok == exp
        good_new = new_ok == exp
        if good_old and good_new:
            ok += 1
        rows.append({"name": c["name"], "expect": c["expect"], "class": r["class"],
                     "old": r["old"]["rc"], "new": r["new"]["rc"],
                     "old_sig": r["old"]["sig"], "new_sig": r["new"]["sig"],
                     "good": good_old and good_new})
        if not (good_old and good_new):
            print("MISMATCH %-16s expect=%s old_rc=%s new_rc=%s class=%s"
                  % (c["name"], c["expect"], r["old"]["rc"], r["new"]["rc"], r["class"]))
            if not good_old:
                print("   old:", r["old"]["sig"][:110])
            if not good_new:
                print("   new:", r["new"]["sig"][:110])
    print("\ncontrols=%d  both-match=%d  gate(>=50)=%s"
          % (len(C), ok, "PASS" if ok >= 50 else "FAIL"))
    with open(os.path.join(ROOT, "out", "olddiff_calib.json"), "w") as f:
        json.dump(rows, f, indent=1)
    return 0 if ok >= 50 else 1


# --------------------------------------------------------------------------
# generators
# --------------------------------------------------------------------------

INT_OPS = ["+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>"]


def gen_expr(rng, depth=0):
    if depth > 3 or rng.random() < 0.3:
        return str(rng.randint(0, 100))
    op = rng.choice(INT_OPS)
    return "(%s %s %s)" % (gen_expr(rng, depth + 1), op, gen_expr(rng, depth + 1))


def gen_programs(n, seed=0x0D1F):
    rng = random.Random(seed)
    out = []
    for i in range(n):
        fam = i % 12
        if fam == 0:
            out.append(("expr_ok", "fn f() -> Int { %s }" % gen_expr(rng), "accept"))
        elif fam == 1:
            out.append(("expr_bad_str", 'fn f() -> Int { %s + "s" }' % gen_expr(rng), "reject"))
        elif fam == 2:
            out.append(("expr_bad_bool", "fn f() -> Int { %s + true }" % gen_expr(rng), "reject"))
        elif fam == 3:
            k = rng.randint(2, 4)
            names = ["A%d" % j for j in range(k)]
            body = "; ".join("%s => %d" % (nm, j) for j, nm in enumerate(names))
            out.append(("enum_ok", "enum E { %s }\nfn f(e : E) -> Int { match e { %s } }"
                        % ("; ".join(names), body), "accept"))
        elif fam == 4:
            k = rng.randint(3, 5)
            names = ["A%d" % j for j in range(k)]
            body = "; ".join("%s => %d" % (nm, j) for j, nm in enumerate(names[:-1]))
            out.append(("enum_missing_arm", "enum E { %s }\nfn f(e : E) -> Int { match e { %s } }"
                        % ("; ".join(names), body), "reject"))
        elif fam == 5:
            d = rng.randint(1, 4)
            ty = "Int"
            for _ in range(d):
                ty = "(%s, Int)" % ty
            pat = "a"
            for _ in range(d):
                pat = "(%s, c)" % pat
            expr = "a"
            for _ in range(d):
                expr = "%s + c" % expr
            out.append(("deep_tuple_pat", "fn f(t : %s) -> Int { match t { %s => %s } }"
                        % (ty, pat, expr), "accept"))
        elif fam == 6:
            k = rng.randint(1, 3)
            decls = ""
            for j in range(k):
                decls += "enum E%d { A; B(E%d) }\n" % (j, j)
            out.append(("rec_enum", decls + "fn f(e : E0) -> Int { match e { A => 0; B(x) => f(x) + 1 } }",
                        "accept"))
        elif fam == 7:
            out.append(("rec_enum_missing", "enum E { A; B(E) }\n"
                        "fn f(e : E) -> Int { match e { A => 0 } }", "reject"))
        elif fam == 8:
            out.append(("mut_field", "struct S { mut x : Int }\n"
                        "fn f(s : S) -> Int { s.x = %d; s.x }" % rng.randint(0, 9), "accept"))
        elif fam == 9:
            out.append(("label_order", "fn f(a~ : Int, b~ : Int) -> Int { a - b }\n"
                        "fn g() -> Int { f(b=%d, a=%d) }" % (rng.randint(0, 9), rng.randint(0, 9)),
                        "accept"))
        elif fam == 10:
            out.append(("field_shadow", "struct S { x : Int }\n"
                        "fn f() -> Int { let x = %d; let s = { x: %d }; s.x + x }"
                        % (rng.randint(0, 9), rng.randint(0, 9)), "accept"))
        else:
            out.append(("enum_arity", "enum E { B(Int) }\nfn f() -> E { B(%d, %d) }"
                        % (rng.randint(0, 9), rng.randint(0, 9)), "reject"))
    return out


def cmd_diff(args):
    items = gen_programs(args.n)
    res = []
    counts = {}
    with open(args.out, "w") as f:
        for i, (fam, src, expect) in enumerate(items):
            r = compare(src, timeout=args.timeout)
            rec = {"i": i, "family": fam, "expect": expect, "src": src,
                   "class": r["class"], "old_rc": r["old"]["rc"],
                   "new_rc": r["new"]["rc"], "old_sig": r["old"]["sig"],
                   "new_sig": r["new"]["sig"]}
            counts[r["class"]] = counts.get(r["class"], 0) + 1
            f.write(json.dumps(rec) + "\n")
            if r["class"] not in ("SAME_ACCEPT", "SAME_REJECT"):
                print("%-14s old=%s new=%s | %s" % (r["class"], r["old"]["rc"],
                                                    r["new"]["rc"], src.replace("\n", " ")[:90]))
            if (i + 1) % 100 == 0:
                f.flush()
                print("  %d/%d %s" % (i + 1, len(items), counts), flush=True)
    print("\ncounts:", counts)
    return 0


# --------------------------------------------------------------------------
# minimal reducer
# --------------------------------------------------------------------------

TOK = re.compile(r"\s+|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|.")


def interesting(src, cls, timeout=10):
    return compare(src, timeout)["class"] == cls


def cmd_min(args):
    src = args.src
    if not interesting(src, args.cls):
        print("input is not interesting (%s)" % args.cls)
        return 1
    toks = TOK.findall(src)
    changed = True
    while changed:
        changed = False
        n = len(toks)
        i = 0
        while i < n:
            cand = toks[:i] + toks[i + 1:]
            s = "".join(cand)
            if s.strip() and interesting(s, args.cls):
                toks = cand
                n = len(toks)
                changed = True
            else:
                i += 1
    print("".join(toks))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("calib")
    d = sub.add_parser("diff")
    d.add_argument("--n", type=int, default=600)
    d.add_argument("--timeout", type=float, default=10.0)
    d.add_argument("--out", default=os.path.join(ROOT, "out", "olddiff.jsonl"))
    m = sub.add_parser("min")
    m.add_argument("--src", required=True)
    m.add_argument("--class", dest="cls", required=True)
    args = ap.parse_args()
    {"calib": cmd_calib, "diff": cmd_diff, "min": cmd_min}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
