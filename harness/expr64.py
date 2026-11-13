#!/usr/bin/env python3
"""Double 复合表达式一致性测试（codex 第 6 轮）。

可观测：`id|expr_id|a_bits|b_bits|c_bits|result_bits|tag`
* 每棵树完全记录；oracle 为 binary64 就近偶数舍入，**每个节点后都舍入**；
* NaN 只比分类，不比 payload；
* 7 个 mandatory witness（含 2^53、FMA 敏感、上溢、下溢、-0）。

用法：
  python3 expr64.py gen --n 200 --out /tmp/e64
  python3 expr64.py run --dir /tmp/e64 --workers 24 --out out/expr64.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import struct
import subprocess
import sys
from collections import Counter
from multiprocessing import Pool

MOON = os.path.expanduser("~/.moon/bin/moon")
TARGETS = ["wasm", "wasm-gc", "js", "native"]
CFG = {}
MOD = """name = "e64/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "e64/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "e64/p{i:03d}/lib" @lib,\n  "e64/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub fn add(a : Double, b : Double) -> Double { a + b }
pub fn sub(a : Double, b : Double) -> Double { a - b }
pub fn mul(a : Double, b : Double) -> Double { a * b }
pub fn div(a : Double, b : Double) -> Double { a / b }

pub fn vec3(a : Double, b : Double, c : Double) -> Array[Double] {
  let out : Array[Double] = []
  for i in 0..<3 {
    out.push(if i == 0 { a } else if i == 1 { b } else { c })
  }
  out
}

pub fn tag(x : Double) -> String {
  if x != x { "nan" }
  else if x == 1.0 / 0.0 { "+inf" }
  else if x == -1.0 / 0.0 { "-inf" }
  else if x == 0.0 { if (1.0 / x) < 0.0 { "-zero" } else { "+zero" } }
  else { "finite" }
}
"""

ALG = """pub fn run(f : (Double, Double) -> Double, a : Double, b : Double) -> Double {
  f(a, b)
}
"""

BITS = {
    "P0": 0x0000000000000000, "-0": 0x8000000000000000,
    "MINSUB": 0x0000000000000001, "MINNORM": 0x0010000000000000,
    "MAXFIN": 0x7FEFFFFFFFFFFFFF, "PINF": 0x7FF0000000000000,
    "NINF": 0xFFF0000000000000, "QNAN": 0x7FF8000000000000,
    "P1": 0x3FF0000000000000, "M1": 0xBFF0000000000000,
    "P2": 0x4000000000000000, "2P53": 0x4340000000000000,
    "2P53P1": 0x4340000000000001, "HALF": 0x3FE0000000000000,
    "TINY": 0x3E40000000000000,
}
CONSTS = list(BITS)


def f64(b):
    return struct.unpack("<d", struct.pack("<Q", b & 0xFFFFFFFFFFFFFFFF))[0]


def bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def fd(a, b):
    x, y = f64(a), f64(b)
    if y == 0.0:
        if x == 0.0 or x != x:
            return float("nan")
        s = -1.0 if ((a >> 63) ^ (b >> 63)) else 1.0
        return s * float("inf")
    return x / y


def ev(n, vs):
    if isinstance(n, str):
        if n in vs:
            return vs[n]
        if n in BITS:
            return f64(BITS[n])
        raise KeyError(n)
    op, x, y = n
    l, r = ev(x, vs), ev(y, vs)
    if op == "ADD":
        return l + r
    if op == "SUB":
        return l - r
    if op == "MUL":
        return l * r
    return fd(bits(l), bits(r))


def emit(n):
    if isinstance(n, str):
        return n if n in ("va", "vb", "vc") else f"{BITS[n]}UL.reinterpret_as_double()"
    op, x, y = n
    fn = {"ADD": "add", "SUB": "sub", "MUL": "mul", "DIV": "div"}[op]
    return f"@lib.{fn}({emit(x)}, {emit(y)})"


def rand_tree(rng, depth):
    if depth <= 0 or rng.random() < 0.28:
        return rng.choice(["va", "vb", "vc"] + CONSTS)
    op = rng.choice(["ADD", "SUB", "MUL", "DIV"])
    return (op, rand_tree(rng, depth - 1), rand_tree(rng, depth - 1))


WITNESSES = [
    ("W0", ("SUB", ("ADD", "2P53", "P1"), "2P53")),
    ("W1", ("ADD", "2P53", ("SUB", "P1", "2P53"))),
    ("W2", ("SUB", ("MUL", ("ADD", "P1", "TINY"), ("SUB", "P1", "TINY")), "P1")),
    ("W3", ("DIV", ("MUL", "MAXFIN", "P2"), "P2")),
    ("W4", ("MUL", ("DIV", "MINSUB", "P2"), "P2")),
    ("W5", ("ADD", ("MUL", "-0", "P1"), "-0")),
    ("W6", ("DIV", "P1", ("MUL", "-0", "P1"))),
]


def gen_one(i):
    rng = random.Random(0xE64 + i)
    ab = rng.choice(list(BITS.values()))
    bb = rng.choice(list(BITS.values()))
    cb = rng.choice(list(BITS.values()))
    trees = list(WITNESSES) + [(f"E{k}", rand_tree(rng, 3)) for k in range(9)]
    L = ["fn main {",
         f"  let xs = @lib.vec3({ab}UL.reinterpret_as_double(), "
         f"{bb}UL.reinterpret_as_double(), {cb}UL.reinterpret_as_double())",
         "  let va = xs[0]", "  let vb = xs[1]", "  let vc = xs[2]"]
    for eid, t in trees:
        L.append(f"  let r_{eid} = {emit(t)}")
        L.append(f'  println("{eid}|{eid}|{ab}|{bb}|{cb}|'
                 f'\\{{r_{eid}.reinterpret_as_uint64()}}|\\{{@lib.tag(r_{eid})}}")')
    L.append("}")
    p = os.path.join(CFG["out"], f"p{i:03d}")
    for sub in ("lib", "alg", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "alg", "moon.pkg"), "w").write(ALG_PKG.format(i=i))
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(LIB)
    open(os.path.join(p, "alg", "alg.mbt"), "w").write(ALG)
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write("\n".join(L) + "\n")
    vs = {"va": f64(ab), "vb": f64(bb), "vc": f64(cb)}
    exp = []
    for eid, t in trees:
        v = ev(t, vs)
        exp.append([eid, bits(v), "nan" if v != v else ("+inf" if v == float("inf") else
                    ("-inf" if v == float("-inf") else ("+zero" if v == 0.0 and bits(v) == 0 else
                     ("-zero" if v == 0.0 else "finite"))))])
    json.dump({"i": i, "a": ab, "b": bb, "c": cb,
               "exprs": [[e, t] for e, t in trees], "expect": exp},
              open(os.path.join(p, "cases.json"), "w"))
    return p


def run_one(arg):
    i, p = arg
    meta = json.load(open(os.path.join(p, "cases.json")))
    outs = {}
    for t in TARGETS:
        try:
            r = subprocess.run([MOON, "run", "cmd/main", "--target", t], cwd=p,
                               capture_output=True, timeout=CFG["timeout"])
            outs[t] = dict(ok=(r.returncode == 0), rc=r.returncode,
                           out=r.stdout.decode("utf-8", "replace"),
                           err=r.stderr.decode("utf-8", "replace")[:300])
        except subprocess.TimeoutExpired:
            outs[t] = dict(ok=False, rc=None, out="")
    return {"i": i, "meta": meta, "outs": outs}


def parse(out):
    rec = {}
    for line in out.splitlines():
        f = line.strip().split("|")
        if len(f) == 7:
            rec[f[0]] = (f[5], f[6])
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["gen", "run"])
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--workers", type=int, default=24)
    ap.add_argument("--timeout", type=int, default=180)
    a = ap.parse_args()
    if a.mode == "gen":
        CFG["out"] = a.out
        if os.path.exists(a.out):
            shutil.rmtree(a.out)
        os.makedirs(a.out, exist_ok=True)
        with Pool(32) as p:
            ps = p.map(gen_one, range(a.n), chunksize=4)
        print(f"[e64] generated {len(ps)} -> {a.out}")
        return
    CFG["timeout"] = a.timeout
    projs = sorted(os.path.join(a.dir, d) for d in os.listdir(a.dir)
                   if os.path.isdir(os.path.join(a.dir, d)))
    with Pool(a.workers) as p:
        res = p.map(run_one, list(enumerate(projs)), chunksize=1)
    full = [r for r in res if all(r["outs"][t]["ok"] for t in TARGETS)]
    mism, paircls, details = Counter(), Counter(), []
    for r in res:
        exp = r["meta"]["expect"]
        recs = {t: parse(r["outs"][t]["out"]) for t in TARGETS if r["outs"][t]["ok"]}
        for t, rec in recs.items():
            for eid, ebits, etag in exp:
                got = rec.get(eid)
                if got is None:
                    mism[f"{t}:MISSING"] += 1
                    continue
                gb, gt = got
                if etag == "nan":
                    ok = (gt == "nan")
                else:
                    ok = (gt == etag and int(gb) == ebits)
                if not ok:
                    mism[f"{t}:{eid[:1]}"] += 1
                    if len(details) < 20:
                        details.append({"prog": r["i"], "t": t, "eid": eid,
                                        "exp": [hex(ebits), etag], "got": [hex(int(gb)) if gb.isdigit() else gb, gt]})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = True
                for eid, ebits, etag in exp:
                    fa, fb = recs[a_].get(eid), recs[b_].get(eid)
                    if not fa or not fb:
                        continue
                    if etag == "nan":
                        same &= (fa[1] == fb[1])
                    else:
                        same &= (fa[0] == fb[0] and fa[1] == fb[1])
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               cases=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details)
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[e64] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"exprs={out['cases']} fails={out['fails']}")
    print(f"[e64] 参考不一致: {sum(mism.values())} 处 {dict(mism)}")
    for k, v in paircls.most_common(5):
        print(f"   {v:5d}  {k}")
    for d in details[:5]:
        print("   ", d)


if __name__ == "__main__":
    main()
