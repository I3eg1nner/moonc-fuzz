#!/usr/bin/env python3
"""Interface-emission consistency pilot (codex fallback after option 3).

Oracle:
  1. build package P from source          -> p.mi      (source-built interface)
  2. mooninfo -format text p.mi           -> p.mbti    (textual public interface)
  3. moonc build-interface p.mbti         -> p2.mi     (rebuilt interface)
  4. check identical clients against p.mi and p2.mi; require equal
     accept/reject for clients using the represented public API.
  5. fault control: alter a signature in p.mbti (arity/type/label); the client
     outcome must change, otherwise the oracle is blind.

Clients cover correct calls and expected rejections (arity, wrong type,
missing/unknown label, unknown name).  Packages are function-only with
builtin types so the emitted .mbti is in the dialect build-interface accepts.

Success: one minimized reproducible mismatch attributable to interface
emission/reconstruction/import, or a new crash/ICE.
Abandon: setup gate 30 min; otherwise 2 h without a credible candidate.

Usage:
  python3 harness/iface.py calib
  python3 harness/iface.py run --n 120 --out out/iface.jsonl
  python3 harness/iface.py report
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
import syntax_boundary as sb

MOONC = os.path.expanduser("~/.moon/bin/moonc")
MOONINFO = os.path.expanduser("~/.moon/bin/mooninfo")
PRELUDE = os.path.expanduser(
    "~/.moon/lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi")
TMP = os.path.join(ROOT, "out", "iface_tmp")
PKG = "iface/p"
ALIAS = "p"


def sh(which, args, timeout=30):
    d = os.path.join(TMP, which)
    os.makedirs(d, exist_ok=True)
    r = sb.run_measured(args, d, timeout, os.path.join(d, "o"), os.path.join(d, "e"))
    st, sig = sb.classify(r)
    r["status"], r["sig"] = st, sig
    return r


def build_pkg(src):
    d = os.path.join(TMP, "pkg")
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, "lib.mbt")
    with open(f, "w") as fh:
        fh.write(src)
    mi = os.path.join(d, "p.mi")
    r = sh("pkg", [MOONC, "build-package", "-pkg", PKG, "-i", PRELUDE,
                   "-o", os.path.join(d, "p.core"), f])
    return r, mi


def emit_iface(mi_path):
    d = os.path.dirname(mi_path)
    out = os.path.join(d, "p.mbti")
    r = sh("info", [MOONINFO, "-format", "text", "-no-alias", mi_path, "-o", out])
    return r, out


def build_iface(mbti_path):
    d = os.path.dirname(mbti_path)
    out = os.path.join(d, "p2.mi")
    r = sh("bif", [MOONC, "build-interface", "-pkg", PKG, "-i", PRELUDE,
                   "-o", out, mbti_path])
    return r, out


def check_client(mi_path, src, tag):
    d = os.path.join(TMP, "client")
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, "c.mbt")
    with open(f, "w") as fh:
        fh.write(src)
    r = sh("client", [MOONC, "check", "-no-mi", "-pkg", "iface/client",
                      "-i", mi_path, "-i", PRELUDE, f])
    return r


def abstract_pkg(rng):
    src = ("pub struct S { priv v : Int }\n"
           "pub fn s_make(v : Int) -> S { { v: v } }\n"
           "pub fn s_get(s : S) -> Int { s.v }\n")
    clients = [("abs:ok", "fn c() -> Int { @p.s_get(@p.s_make(1)) }", "accept"),
               ("abs:bad", "fn c() -> Int { @p.s_get(1) }", "reject"),
               ("abs:bad2", "fn c() -> Int { @p.s_make() }", "reject")]
    return src, clients


def normalize_abstract(text):
    """moon info emits `pub struct S { // private fields }` for an opaque
    public type; build-interface wants `type S`.  Move declarations to the top."""
    lines = text.splitlines()
    out, types = [], []
    i = 0
    while i < len(lines):
        l = lines[i]
        m = re.match(r"\s*pub struct (\w+) \{", l)
        if m:
            types.append("type " + m.group(1))
            depth = l.count("{") - l.count("}")
            i += 1
            while i < len(lines) and depth > 0:
                depth += lines[i].count("{") - lines[i].count("}")
                i += 1
            continue
        out.append(l)
        i += 1
    res = []
    for l in out:
        res.append(l)
        if l.startswith("package "):
            res.extend(types)
    return "\n".join(res) + "\n"


def norm_iface(text):
    """Declaration lines only, order-insensitive, whitespace-normalised."""
    lines = []
    for l in text.splitlines():
        l = l.strip()
        if not l or l.startswith("//"):
            continue
        if l.startswith("package "):
            continue
        l = re.sub(r"\s+", " ", l)
        lines.append(l)
    return sorted(lines)


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

def package_src(rng):
    """Function-only package with builtin types."""
    fns, clients = [], []
    specs = [
        ("f_int2", "pub fn f_int2(x : Int, y : Int) -> Int { x + y }",
         ("fn c() -> Int { @p.f_int2(1, 2) }",
          ["fn c() -> Int { @p.f_int2(1) }",
           'fn c() -> Int { @p.f_int2("a", 2) }'])),
        ("f_bool", "pub fn f_bool(b : Bool) -> Int { if b { 1 } else { 0 } }",
         ("fn c() -> Int { @p.f_bool(true) }",
          ["fn c() -> Int { @p.f_bool(1) }"])),
        ("f_str", 'pub fn f_str(s : String) -> String { s + "!" }',
         ('fn c() -> String { @p.f_str("a") }',
          ["fn c() -> String { @p.f_str(1) }"])),
        ("f_pair", "pub fn f_pair(a : Int, b : Int) -> (Int, Int) { (a, b) }",
         ("fn c() -> (Int, Int) { @p.f_pair(1, 2) }",
          ["fn c() -> (Int, Int) { @p.f_pair(1) }"])),
        ("f_label", "pub fn f_label(x~ : Int) -> Int { x }",
         ("fn c() -> Int { @p.f_label(x=1) }",
          ["fn c() -> Int { @p.f_label(1) }",
           "fn c() -> Int { @p.f_label(y=1) }"])),
        ("f_zero", "pub fn f_zero() -> Int { 0 }",
         ("fn c() -> Int { @p.f_zero() }",
          ["fn c() -> Int { @p.f_zero(1) }"])),
        ("f_gen", "pub fn[T] f_gen(x : T) -> T { x }",
         ("fn c() -> Int { @p.f_gen(1) }",
          ["fn c() -> Int { @p.f_gen() }",
           "fn c() -> Int { @p.f_gen(1, 2) }"])),
        ("f_opt", "pub fn f_opt(x~ : Int, y? : Int = 1) -> Int { x + y }",
         ("fn c() -> Int { @p.f_opt(x=1) }",
          ["fn c() -> Int { @p.f_opt(1) }",
           'fn c() -> Int { @p.f_opt(x=1, y="a") }'])),
        ("f_three", "pub fn f_three(a : Int, b : Int, c : Int) -> Int { a + b + c }",
         ("fn c() -> Int { @p.f_three(1, 2, 3) }",
          ["fn c() -> Int { @p.f_three(1, 2) }"])),
    ]
    rng.shuffle(specs)
    for name, decl, (ok, bad) in specs:
        if rng.random() < 0.8:
            fns.append(decl)
            clients.append((name + ":ok", ok, "accept"))
            for j, b in enumerate(bad):
                clients.append((name + ":bad%d" % j, b, "reject"))
    clients.append(("unknown", "fn c() -> Int { @p.nope(1) }", "reject"))
    return "\n".join(fns) + "\n", clients


def calib():
    """Hand fixture + fault controls; proves oracle sensitivity."""
    src = ("pub fn add(x : Int, y : Int) -> Int { x + y }\n"
           "pub fn label(x~ : Int) -> Int { x }\n")
    r, mi = build_pkg(src)
    assert r["rc"] == 0, r["stderr"]
    ri, mbti = emit_iface(mi)
    assert ri["rc"] == 0, ri["stderr"]
    rb, mi2 = build_iface(mbti)
    assert rb["rc"] == 0, rb["stderr"]
    text = open(mbti).read()
    print("--- emitted mbti ---")
    print(text)
    ok = "fn c() -> Int { @p.add(1, 2) + @p.label(x=1) }"
    bad = ["fn c() -> Int { @p.add(1) }", "fn c() -> Int { @p.label(1) }"]
    rows = []
    for name, src_c, exp in [("ok", ok, "accept")] + [("bad%d" % i, b, "reject")
                                                     for i, b in enumerate(bad)]:
        a = check_client(mi, src_c, name)
        b2 = check_client(mi2, src_c, name)
        rows.append({"case": name, "expect": exp, "src_rc": a["rc"], "iface_rc": b2["rc"]})
        print("%-6s expect=%-6s src_rc=%s iface_rc=%s" % (name, exp, a["rc"], b2["rc"]))
    # fault control: arity change must flip the accepting client
    ftxt = text.replace("pub fn add(Int32, Int32)", "pub fn add(Int32)")
    fd = os.path.dirname(mbti)
    with open(os.path.join(fd, "pf.mbti"), "w") as f:
        f.write(ftxt)
    rf, mif = build_iface(os.path.join(fd, "pf.mbti"))
    fc = check_client(mif, ok, "fault")
    print("fault arity 2->1: bif_rc=%s client_rc=%s (must be non-zero)" % (rf["rc"], fc["rc"]))
    ok = (fc["rc"] not in (0, None)) and all(
        (row["src_rc"] == 0) == (row["iface_rc"] == 0) for row in rows)
    print("CALIB", "PASS" if ok else "FAIL")
    return 0 if ok else 1


# --------------------------------------------------------------------------
# differential run
# --------------------------------------------------------------------------

def run_diff(n, seed=0x1FACE, timeout=30):
    rng = random.Random(seed)
    out = open(os.path.join(ROOT, "out", "iface.jsonl"), "w")
    counts = {}
    n_ok = 0
    for i in range(n):
        if i % 5 == 4:
            src, clients = abstract_pkg(rng)
        else:
            src, clients = package_src(rng)
        r, mi = build_pkg(src)
        if r["rc"] != 0:
            counts["PKG_BUILD_FAIL"] = counts.get("PKG_BUILD_FAIL", 0) + 1
            continue
        ri, mbti = emit_iface(mi)
        if ri["rc"] != 0:
            counts["INFO_FAIL"] = counts.get("INFO_FAIL", 0) + 1
            continue
        rb, mi2 = build_iface(mbti)
        normalized = False
        mtext = open(mbti).read()
        if rb["rc"] != 0 and "pub struct" in mtext:
            counts["RAW_TEXT_UNSUPPORTED"] = counts.get("RAW_TEXT_UNSUPPORTED", 0) + 1
            with open(mbti, "w") as f:
                f.write(normalize_abstract(mtext))
            rb, mi2 = build_iface(mbti)
            normalized = True
        if rb["rc"] != 0:
            counts["BIF_FAIL"] = counts.get("BIF_FAIL", 0) + 1
            print("BIF_FAIL pkg=%d norm=%s: %s" % (i, normalized, rb["stderr"][:300]))
            continue
        # interface text equality (emit rebuilt mi again)
        r3 = sh("info", [MOONINFO, "-format", "text", "-no-alias",
                         mi2, "-o", os.path.join(os.path.dirname(mi2), "p2.mbti")])
        text1 = open(mbti).read()
        text2 = open(os.path.join(os.path.dirname(mi2), "p2.mbti")).read() if r3["rc"] == 0 else ""
        if norm_iface(text1) != norm_iface(text2):
            counts["TEXT_DIFF"] = counts.get("TEXT_DIFF", 0) + 1
            rec = {"i": i, "class": "TEXT_DIFF", "src": src, "normalized": normalized,
                   "t1": norm_iface(text1), "t2": norm_iface(text2)}
            out.write(json.dumps(rec) + "\n")
        for cname, csrc, expect in clients:
            a = check_client(mi, csrc, "src")
            b = check_client(mi2, csrc, "iface")
            sa, sb = a["rc"] == 0, b["rc"] == 0
            if a["status"] in ("crash", "ice", "timeout", "silent") or \
               b["status"] in ("crash", "ice", "timeout", "silent"):
                cls = "IFACE_CRASH"
            elif sa and sb:
                cls = "SAME_ACCEPT"
            elif (not sa) and (not sb):
                cls = "SAME_REJECT"
            elif sb and not sa:
                cls = "IFACE_ACCEPT_ONLY"
            else:
                cls = "IFACE_REJECT_ONLY"
            counts[cls] = counts.get(cls, 0) + 1
            if cls not in ("SAME_ACCEPT", "SAME_REJECT"):
                print("%-16s expect=%-6s pkg=%d client=%s norm=%s"
                      % (cls, expect, i, cname, normalized))
                out.write(json.dumps({"i": i, "class": cls, "client": cname,
                                      "expect": expect, "csrc": csrc, "src": src,
                                      "src_rc": a["rc"], "iface_rc": b["rc"],
                                      "src_sig": a["sig"], "iface_sig": b["sig"]}) + "\n")
        n_ok += 1
        if (i + 1) % 20 == 0:
            out.flush()
            print("  %d/%d %s" % (i + 1, n, counts), flush=True)
    out.close()
    with open(os.path.join(ROOT, "out", "iface_summary.json"), "w") as f:
        json.dump({"packages": n_ok, "counts": counts}, f, indent=1)
    print("\npackages built=%d counts=%s" % (n_ok, counts))
    return 0


def report():
    p = os.path.join(ROOT, "out", "iface.jsonl")
    if not os.path.exists(p):
        print("no results")
        return 1
    sp = os.path.join(ROOT, "out", "iface_summary.json")
    if os.path.exists(sp):
        print("summary:", json.load(open(sp)))
    rows = [json.loads(l) for l in open(p)]
    import collections
    c = collections.Counter(r["class"] for r in rows)
    print("mismatch records", len(rows), dict(c))
    for r in rows[:10]:
        print(r["class"], r.get("client"), "src_rc=%s iface_rc=%s" % (r.get("src_rc"), r.get("iface_rc")))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("calib")
    r = sub.add_parser("run")
    r.add_argument("--n", type=int, default=120)
    sub.add_parser("report")
    a = ap.parse_args()
    {"calib": lambda _: calib(), "run": lambda x: run_diff(x.n),
     "report": lambda _: report()}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
