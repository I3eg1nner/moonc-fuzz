#!/usr/bin/env python3
"""可变引用别名一致性测试（codex review #4 指定）。

可观测：`case|step|read_a|read_b|slot_a|slot_b`，每次 mutation 后都打印。
参考实现：显式 store + 引用 id 的独立解释器（不依赖跨后端互比）。

覆盖：共享 vs 独立引用、`f(r, r)` 重复实参、嵌套调用、读-写-读序列、
跨包传递（cmd -> alg -> lib）。

用法：
  python3 alias.py gen --n 200 --out /tmp/alias200
  python3 alias.py run --dir /tmp/alias200 --workers 24 --out out/alias200.json
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
CFG = {}
MOD = """name = "als/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "als/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "als/p{i:03d}/lib" @lib,\n  "als/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub fn read(x : Array[Int]) -> Int { x[0] }
pub fn setv(x : Array[Int], v : Int) -> Unit { x[0] = v }
pub fn bump(x : Array[Int], y : Array[Int]) -> Int {
  x[0] = x[0] + 1
  y[0]
}
pub fn addto(x : Array[Int], y : Array[Int], k : Int) -> Int {
  x[0] = x[0] + y[0] + k
  x[0]
}
pub fn nested(x : Array[Int], y : Array[Int]) -> Int {
  setv(x, read(y) + 1)
  read(x)
}
"""

ALG = """pub fn twice(f : (Array[Int], Array[Int]) -> Int, x : Array[Int], y : Array[Int]) -> Int {
  f(x, y) + f(y, x)
}
"""


def gen_steps(rng, n_steps=12):
    steps = []
    for _ in range(n_steps):
        kind = rng.choice(["W", "W", "BUMP", "BUMP", "ADD", "NEST", "TWICE"])
        if kind == "W":
            steps.append(("W", rng.choice("ab"), rng.randrange(-5, 9)))
        elif kind == "BUMP":
            steps.append(("BUMP", rng.choice("ab"), rng.choice("ab")))
        elif kind == "ADD":
            steps.append(("ADD", rng.choice("ab"), rng.choice("ab"), rng.randrange(-3, 4)))
        elif kind == "NEST":
            steps.append(("NEST", rng.choice("ab"), rng.choice("ab")))
        else:
            steps.append(("TWICE", rng.choice("ab"), rng.choice("ab")))
    return steps


def interpret(steps):
    """显式 store：slot id -> 值。返回每步后的 (a, b)。"""
    st = {"a": 0, "b": 0}
    trace = []
    for s in steps:
        k = s[0]
        if k == "W":
            st[s[1]] = s[2]
        elif k == "BUMP":
            st[s[1]] = st[s[1]] + 1          # 先写 x，再返回 y 的值
        elif k == "ADD":
            st[s[1]] = st[s[1]] + st[s[2]] + s[3]
        elif k == "NEST":
            st[s[1]] = st[s[2]] + 1          # setv(x, read(y)+1)
        elif k == "TWICE":
            # f(x,y)+f(y,x), f = bump：两次各自 +1
            st[s[1]] = st[s[1]] + 1
            st[s[2]] = st[s[2]] + 1
        trace.append([st["a"], st["b"], st["a"], st["b"]])
    return trace


def emit(steps):
    L = ["fn main {", "  let a : Array[Int] = [0]", "  let b : Array[Int] = [0]"]
    for i, s in enumerate(steps):
        k = s[0]
        if k == "W":
            call = f"@lib.setv({s[1]}, {s[2]})"
        elif k == "BUMP":
            call = f"let _ = @lib.bump({s[1]}, {s[2]})"
        elif k == "ADD":
            call = f"let _ = @lib.addto({s[1]}, {s[2]}, {s[3]})"
        elif k == "NEST":
            call = f"let _ = @lib.nested({s[1]}, {s[2]})"
        else:
            call = (f"let _ = @alg.twice(fn(x, y) {{ @lib.bump(x, y) }}, "
                    f"{s[1]}, {s[2]})")
        L.append(f"  {call}")
        L.append(f'  println("{i}|{k}|\\{{@lib.read(a)}}|\\{{@lib.read(b)}}|'
                 f'\\{{a[0]}}|\\{{b[0]}}")')
    L.append("}")
    return "\n".join(L) + "\n"


def gen_one(i):
    rng = random.Random(0xA11A5 + i)
    steps = gen_steps(rng)
    p = os.path.join(CFG["out"], f"p{i:03d}")
    for sub in ("lib", "alg", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "alg", "moon.pkg"), "w").write(ALG_PKG.format(i=i))
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(LIB)
    open(os.path.join(p, "alg", "alg.mbt"), "w").write(ALG)
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write(emit(steps))
    json.dump({"i": i, "steps": steps, "expect": interpret(steps)},
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
            outs[t] = dict(ok=False, rc=None, out="", err="timeout")
    return {"i": i, "meta": meta, "outs": outs}


def parse(out):
    rec = {}
    for line in out.splitlines():
        f = line.strip().split("|")
        if len(f) == 6 and f[0].isdigit():
            rec[int(f[0])] = [int(x) for x in f[2:]]
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
        print(f"[als] generated {len(ps)} -> {a.out}")
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
            for sid, e in enumerate(exp):
                got = rec.get(sid)
                if got != list(e):
                    mism[f"{t}:{r['meta']['steps'][sid][0]}"] += 1
                    if len(details) < 20:
                        details.append({"prog": r["i"], "t": t, "step": sid,
                                        "op": r["meta"]["steps"][sid], "exp": e, "got": got})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = all(recs[a_].get(s) == recs[b_].get(s) for s in range(len(exp)))
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               steps=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details)
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[als] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"steps={out['steps']} fails={out['fails']}")
    print(f"[als] 参考实现不一致: {sum(mism.values())} 处 {dict(mism)}")
    for k, v in paircls.most_common(6):
        print(f"   {v:5d}  {k}")
    for d in details[:5]:
        print("   ", d)


if __name__ == "__main__":
    main()
