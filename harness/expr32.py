#!/usr/bin/env python3
"""Int32 复合表达式一致性测试（codex 第 5 轮）。

可观测：`case|expr_id|a|b|c|result_i32`
* expr_id 对应一棵记录在 cases.json 里的、完全括号化的表达式树；
* 参考实现是 AST 解释器，**每个算术/左移节点后都回绕到有符号 32 位**；
* 移位量固定 0..31；
* 必须出现的 witness：`(MAX + 1) >> 1` 必须得到 `-1073741824`。

用法：
  python3 expr32.py gen --n 200 --out /tmp/e32
  python3 expr32.py run --dir /tmp/e32 --workers 24 --out out/expr32.json
"""
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
from collections import Counter
from multiprocessing import Pool

MOON = os.path.expanduser("~/.moon/bin/moon")
TARGETS = ["wasm", "wasm-gc", "js", "native"]
MIN, MAX = -2**31, 2**31 - 1
CFG = {}
MOD = """name = "e32/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "e32/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "e32/p{i:03d}/lib" @lib,\n  "e32/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub fn add(a : Int, b : Int) -> Int { a + b }
pub fn sub(a : Int, b : Int) -> Int { a - b }
pub fn mul(a : Int, b : Int) -> Int { a * b }
pub fn shl(a : Int, b : Int) -> Int { a << b }
pub fn shr(a : Int, b : Int) -> Int { a >> b }

pub fn vec3(a : Int, b : Int, c : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<3 {
    out.push(if i == 0 { a } else if i == 1 { b } else { c })
  }
  out
}
"""

ALG = """pub fn run(f : (Int, Int) -> Int, a : Int, b : Int) -> Int { f(a, b) }
"""

OPS = ["ADD", "SUB", "MUL", "SHL", "SHR"]


def i32(x):
    x &= 0xFFFFFFFF
    return x - 2**32 if x >= 2**31 else x


def ev(n, vs):
    if isinstance(n, str):
        return vs[n] if n in ("a", "b", "c") else int(n)
    op, x, y = n
    l, r = ev(x, vs), ev(y, vs)
    if op == "ADD":
        return i32(l + r)
    if op == "SUB":
        return i32(l - r)
    if op == "MUL":
        return i32(l * r)
    if op == "SHL":
        return i32(l << r)
    return l >> r


def emit(n):
    if isinstance(n, str):
        return ("v" + n) if n in ("a", "b", "c") else str(n)
    op, x, y = n
    fn = {"ADD": "add", "SUB": "sub", "MUL": "mul", "SHL": "shl", "SHR": "shr"}[op]
    return f"@lib.{fn}({emit(x)}, {emit(y)})"


def rand_tree(rng, depth, leaves):
    if depth <= 0 or rng.random() < 0.3:
        return rng.choice(leaves)
    op = rng.choice(OPS)
    if op in ("SHL", "SHR"):
        return (op, rand_tree(rng, depth - 1, leaves), str(rng.randrange(0, 32)))
    return (op, rand_tree(rng, depth - 1, leaves), rand_tree(rng, depth - 1, leaves))


def gen_one(i):
    rng = random.Random(0xE32 + i)
    a = rng.choice([MIN, MIN + 1, -2**20, -2, -1, 0, 1, 2, 2**20, MAX - 1, MAX])
    b = rng.choice([MIN, MIN + 1, -2**16, -1, 0, 1, 2**16, MAX])
    c = rng.choice([MIN, -1, 0, 1, 7, MAX])
    leaves = ["a", "b", "c", "0", "1", "-1", str(MAX), str(MIN)]
    exprs = [("W", ("SHR", ("ADD", str(MAX), "1"), "1"))]   # mandatory witness
    for k in range(10):
        exprs.append((f"E{k}", rand_tree(rng, 3, leaves)))
    L = ["fn main {", f"  let xs = @lib.vec3({a}, {b}, {c})",
         "  let va = xs[0]", "  let vb = xs[1]", "  let vc = xs[2]"]
    for eid, tree in exprs:
        L.append(f'  let r_{eid} = {emit(tree)}')
        L.append(f'  println("{eid}|{eid}|\\{{va}}|\\{{vb}}|\\{{vc}}|\\{{r_{eid}}}")')
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
    vs = {"a": a, "b": b, "c": c}
    json.dump({"i": i, "a": a, "b": b, "c": c,
               "exprs": [[eid, tree] for eid, tree in exprs],
               "expect": [ev(t, vs) for _, t in exprs]},
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
            outs[t] = dict(ok=False, rc=None, out="", timeout=True)
    return {"i": i, "meta": meta, "outs": outs}


def parse(out):
    rec = {}
    for line in out.splitlines():
        f = line.strip().split("|")
        if len(f) == 6:
            try:
                rec[f[0]] = int(f[5])
            except ValueError:
                pass
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
        print(f"[e32] generated {len(ps)} -> {a.out}")
        return
    CFG["timeout"] = a.timeout
    projs = sorted(os.path.join(a.dir, d) for d in os.listdir(a.dir)
                   if os.path.isdir(os.path.join(a.dir, d)))
    with Pool(a.workers) as p:
        res = p.map(run_one, list(enumerate(projs)), chunksize=1)
    full = [r for r in res if all(r["outs"][t]["ok"] for t in TARGETS)]
    mism, paircls, details = Counter(), Counter(), []
    witness_bad = []
    for r in res:
        exp = r["meta"]["expect"]
        eids = [e for e, _ in r["meta"]["exprs"]]
        recs = {t: parse(r["outs"][t]["out"]) for t in TARGETS if r["outs"][t]["ok"]}
        for t, rec in recs.items():
            for k, eid in enumerate(eids):
                got = rec.get(eid)
                if got != exp[k]:
                    mism[f"{t}:{eid[:1]}"] += 1
                    if len(details) < 20:
                        details.append({"prog": r["i"], "t": t, "eid": eid,
                                        "exp": exp[k], "got": got})
                if eid == "W" and got != -1073741824:
                    witness_bad.append({"prog": r["i"], "t": t, "got": got})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = all(recs[a_].get(e) == recs[b_].get(e) for e in eids
                           if e in recs[a_] and e in recs[b_])
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               cases=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), witness_failures=witness_bad[:10],
               pair_classes=dict(paircls), details=details)
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[e32] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"exprs={out['cases']} fails={out['fails']}")
    print(f"[e32] 参考不一致: {sum(mism.values())} 处 {dict(mism)}; "
          f"witness 失败 {len(witness_bad)}")
    for k, v in paircls.most_common(5):
        print(f"   {v:5d}  {k}")
    for d in details[:5]:
        print("   ", d)


if __name__ == "__main__":
    main()
