#!/usr/bin/env python3
"""Int 32 位溢出 / 移位的跨后端一致性测试（codex review #2 的第 2 项）。

要点（按 codex 的要求）：
* 操作数取 MIN/MAX/-1/0/1/2^15/2^16/2^30/MIN+1/MAX-1，移位量取 0/1/15/16/30/31；
* 每个操作**逐条打印** `id|op|a|b|result`，不打印 checksum；
* 同时和**独立的 32 位参考实现**比对（跨后端一致也可能一起错）；
* 本轮排除除法与越界移位量（负移位、>=32）。

用法：
  python3 overflow.py gen --n 200 --out /tmp/ovf200
  python3 overflow.py run --dir /tmp/ovf200 --workers 28 --out out/overflow200.json
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
OPERANDS = [MIN, MIN + 1, -2**30, -2**16, -2**15, -1, 0, 1, 2**15, 2**16, 2**30, MAX - 1, MAX]
SHIFTS = [0, 1, 15, 16, 30, 31]
OPS = ["ADD", "SUB", "MUL", "SHL", "SHR"]
CFG = {}

MOD = """name = "ovf/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "ovf/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "ovf/p{i:03d}/lib" @lib,\n  "ovf/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub fn add(a : Int, b : Int) -> Int { a + b }
pub fn sub(a : Int, b : Int) -> Int { a - b }
pub fn mul(a : Int, b : Int) -> Int { a * b }
pub fn shl(a : Int, b : Int) -> Int { a << b }
pub fn shr(a : Int, b : Int) -> Int { a >> b }

pub fn dispatch(op : Int, a : Int, b : Int) -> Int {
  if op == 0 { add(a, b) }
  else if op == 1 { sub(a, b) }
  else if op == 2 { mul(a, b) }
  else if op == 3 { shl(a, b) }
  else { shr(a, b) }
}
"""

ALG = """pub fn via_closure(op : Int, a : Int, b : Int) -> Int {
  let f = fn(x, y) { @lib.dispatch(op, x, y) }
  f(a, b)
}
"""


def i32(x: int) -> int:
    x &= 0xFFFFFFFF
    return x - 2**32 if x >= 2**31 else x


def ref(op: str, a: int, b: int) -> int:
    if op == "ADD":
        return i32(a + b)
    if op == "SUB":
        return i32(a - b)
    if op == "MUL":
        return i32(a * b)
    if op == "SHL":
        return i32(a << b) if 0 <= b < 32 else 0
    return a >> b                       # 算术右移（符号保持）


def lit(v: int, neg_paren=True) -> str:
    if v == MIN:
        return "(-2147483647 - 1)"
    return str(v)


def main_src(cases):
    lines = ["fn main {"]
    for cid, (op, a, b) in enumerate(cases):
        call = f"@alg.via_closure({OPS.index(op)}, {lit(a)}, {lit(b)})"
        lines.append(f'  println("{cid}|{op}|{a}|{b}|\\{{{call}}}")')
    lines.append("}")
    return "\n".join(lines) + "\n"


def gen_one(i):
    rng = random.Random(0x0FFE + i)
    cases = []
    for _ in range(18):
        op = rng.choice(OPS)
        a = rng.choice(OPERANDS)
        b = rng.choice(SHIFTS) if op in ("SHL", "SHR") else rng.choice(OPERANDS)
        cases.append((op, a, b))
    p = os.path.join(CFG["out"], f"p{i:03d}")
    for sub in ("lib", "alg", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "alg", "moon.pkg"), "w").write(ALG_PKG.format(i=i))
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(LIB)
    open(os.path.join(p, "alg", "alg.mbt"), "w").write(ALG)
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write(main_src(cases))
    meta = {"i": i, "cases": [[op, a, b] for op, a, b in cases],
            "expect": [ref(op, a, b) for op, a, b in cases]}
    open(os.path.join(p, "cases.json"), "w").write(json.dumps(meta))
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
    return {"i": i, "path": p, "meta": meta, "outs": outs}


def parse(out: str):
    rec = {}
    for line in out.splitlines():
        parts = line.strip().split("|")
        if len(parts) == 5 and parts[0].isdigit():
            try:
                rec[int(parts[0])] = int(parts[4])
            except ValueError:
                rec[int(parts[0])] = parts[4]
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
        print(f"[ovf] generated {len(ps)} -> {a.out}")
        return
    CFG["timeout"] = a.timeout
    projs = sorted(os.path.join(a.dir, d) for d in os.listdir(a.dir)
                   if os.path.isdir(os.path.join(a.dir, d)))
    with Pool(a.workers) as p:
        res = p.map(run_one, list(enumerate(projs)), chunksize=1)
    full = [r for r in res if all(r["outs"][t]["ok"] for t in TARGETS)]
    mism = Counter()
    details = []
    paircls = Counter()
    for r in res:
        exp = r["meta"]["expect"]
        recs = {t: parse(r["outs"][t]["out"]) for t in TARGETS if r["outs"][t]["ok"]}
        for t, rec in recs.items():
            for cid, e in enumerate(exp):
                got = rec.get(cid)
                if got != e:
                    mism[f"{t}:{r['meta']['cases'][cid][0]}"] += 1
                    if len(details) < 30:
                        details.append({"prog": r["i"], "target": t, "case": cid,
                                        "op": r["meta"]["cases"][cid], "expect": e, "got": got})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = all(recs[a_].get(c) == recs[b_].get(c) for c in range(len(exp)))
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details,
               cases=sum(len(r["meta"]["expect"]) for r in res))
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[ovf] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"cases={out['cases']} fails={out['fails']}")
    print(f"[ovf] 参考实现不一致: {sum(mism.values())} 处 {dict(mism)}")
    for k, v in paircls.most_common(5):
        print(f"   {v:5d}  {k}")
    for d in details[:5]:
        print("   ", d)


if __name__ == "__main__":
    main()
