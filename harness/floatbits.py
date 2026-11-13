#!/usr/bin/env python3
"""Double 位级一致性测试（codex review #2 第 2 项）。

按 codex 的格式：`id|op|a_bits|b_bits|tag|result_bits_or_bool`
（bits 用十进制打印，等价于 hex；NaN 不比 payload，只比 tag）

覆盖：±0、最小/最大 subnormal、最小 normal 及邻居、最大有限、±inf、qNaN、
±1 与 2^53 的邻居；运算 + - * /、取负、比较、抵消、halfway rounding、
上溢、渐进下溢。参考实现独立用 Python 的 IEEE double 语义。

用法：
  python3 floatbits.py gen --n 200 --out /tmp/flt200
  python3 floatbits.py run --dir /tmp/flt200 --workers 24 --out out/float200.json
"""
from __future__ import annotations

import argparse
import json
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

# 位模式（UInt64 十进制）
BITS = {
    "+0": 0x0000000000000000,
    "-0": 0x8000000000000000,
    "minsub": 0x0000000000000001,
    "maxsub": 0x000FFFFFFFFFFFFF,
    "minnorm": 0x0010000000000000,
    "minnorm+1": 0x0010000000000001,
    "maxfinite": 0x7FEFFFFFFFFFFFFF,
    "+inf": 0x7FF0000000000000,
    "-inf": 0xFFF0000000000000,
    "qnan": 0x7FF8000000000000,
    "1.0": 0x3FF0000000000000,
    "1.0+ulp": 0x3FF0000000000001,
    "1.0-ulp": 0x3FEFFFFFFFFFFFFF,
    "2^53": 0x4340000000000000,
    "2^53+1": 0x4340000000000001,
    "2^53-1": 0x433FFFFFFFFFFFFF,
    "halfway": 0x3FE0000000000000,
}
NAMES = list(BITS)
OPS = ["ADD", "SUB", "MUL", "DIV", "NEG", "EQ", "LT", "LE"]

MOD = """name = "flt/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "flt/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "flt/p{i:03d}/lib" @lib,\n  "flt/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub fn add(a : Double, b : Double) -> Double { a + b }
pub fn sub(a : Double, b : Double) -> Double { a - b }
pub fn mul(a : Double, b : Double) -> Double { a * b }
pub fn div(a : Double, b : Double) -> Double { a / b }
pub fn neg(a : Double) -> Double { -a }
pub fn eq(a : Double, b : Double) -> Bool { a == b }
pub fn lt(a : Double, b : Double) -> Bool { a < b }
pub fn le(a : Double, b : Double) -> Bool { a <= b }

pub fn tag(x : Double) -> String {
  if x != x { "nan" }
  else if x == 1.0 / 0.0 { "+inf" }
  else if x == -1.0 / 0.0 { "-inf" }
  else if x == 0.0 {
    if (1.0 / x) < 0.0 { "-zero" } else { "+zero" }
  } else { "finite" }
}
"""

ALG = """pub fn via_closure(f : (Double, Double) -> Double, a : Double, b : Double) -> Double {
  f(a, b)
}
"""


def f64(bits: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", bits & 0xFFFFFFFFFFFFFFFF))[0]


def bits_of(x: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def ref(op: str, a: int, b: int):
    x, y = f64(a), f64(b)
    nan = float("nan")
    try:
        if op == "ADD":
            return "v", bits_of(x + y)
        if op == "SUB":
            return "v", bits_of(x - y)
        if op == "MUL":
            return "v", bits_of(x * y)
        if op == "DIV":
            if y == 0.0:
                if x == 0.0 or x != x:
                    return "v", bits_of(nan)
                s = -1.0 if (bits_of(x) >> 63) ^ (bits_of(y) >> 63) else 1.0
                return "v", bits_of(s * float("inf"))
            return "v", bits_of(x / y)
        if op == "NEG":
            return "v", bits_of(-x)
        if op == "EQ":
            return "b", int(x == y)
        if op == "LT":
            return "b", int(x < y)
        if op == "LE":
            return "b", int(x <= y)
    except OverflowError:
        return "v", bits_of(float("inf") if x > 0 else float("-inf"))
    return "?", 0


def main_src(cases):
    L = ["fn main {"]
    for cid, (op, an, bn) in enumerate(cases):
        a = BITS[an]
        b = 0 if bn == '-' else BITS[bn]
        if op == "NEG":
            call = f"@lib.neg({a}UL.reinterpret_as_double())"
            L.append(f'  let r{cid} = {call}')
            L.append(f'  println("{cid}|{op}|{a}|-|\\{{@lib.tag(r{cid})}}|\\{{r{cid}.reinterpret_as_uint64()}}")')
        elif op in ("EQ", "LT", "LE"):
            fn = {"EQ": "eq", "LT": "lt", "LE": "le"}[op]
            call = f"@lib.{fn}({a}UL.reinterpret_as_double(), {b}UL.reinterpret_as_double())"
            L.append(f'  println("{cid}|{op}|{a}|{b}|bool|\\{{{call}}}")')
        else:
            fn = {"ADD": "add", "SUB": "sub", "MUL": "mul", "DIV": "div"}[op]
            call = (f"@lib.{fn}({a}UL.reinterpret_as_double(), {b}UL.reinterpret_as_double())")
            L.append(f'  let r{cid} = {call}')
            L.append(f'  println("{cid}|{op}|{a}|{b}|\\{{@lib.tag(r{cid})}}|\\{{r{cid}.reinterpret_as_uint64()}}")')
    L.append("}")
    return "\n".join(L) + "\n"


def gen_one(i):
    rng = random.Random(0xF10A7 + i)
    cases = []
    for _ in range(20):
        op = rng.choice(OPS)
        an = rng.choice(NAMES)
        bn = "-" if op == "NEG" else rng.choice(NAMES)
        cases.append((op, an, bn))
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
    exp = []
    for op, an, bn in cases:
        a = BITS[an]
        b = 0 if bn == "-" else BITS[bn]
        exp.append(list(ref(op, a, b)))
    json.dump({"i": i, "cases": cases, "expect": exp},
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


def parse(out: str):
    rec = {}
    for line in out.splitlines():
        f = line.strip().split("|")
        if len(f) == 6 and f[0].isdigit():
            rec[int(f[0])] = f
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
        print(f"[flt] generated {len(ps)} -> {a.out}")
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
            for cid, (kind, val) in enumerate(exp):
                f = rec.get(cid)
                if not f:
                    mism[f"{t}:MISSING"] += 1
                    continue
                tag, got = f[4], f[5]
                if kind == "b":
                    gv = 1 if got == "true" else (0 if got == "false" else None)
                    if gv != val:
                        mism[f"{t}:CMP"] += 1
                        details.append({"prog": r["i"], "t": t, "case": cid, "exp": val, "got": got})
                else:
                    if tag == "nan":
                        if f[4] != "nan":
                            mism[f"{t}:NAN_TAG"] += 1
                            details.append({"prog": r["i"], "t": t, "case": cid,
                                            "exp": "nan", "got": tag})
                    elif int(got) != val:
                        mism[f"{t}:BITS"] += 1
                        details.append({"prog": r["i"], "t": t, "case": cid,
                                        "exp": hex(val), "got": hex(int(got)) if got.isdigit() else got})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = True
                for cid, (kind, val) in enumerate(exp):
                    fa, fb = recs[a_].get(cid), recs[b_].get(cid)
                    if not fa or not fb:
                        continue
                    if fa[4] == "nan" or fb[4] == "nan":
                        same &= (fa[4] == fb[4])
                    else:
                        same &= (fa[5] == fb[5])
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               cases=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details[:40])
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[flt] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"cases={out['cases']} fails={out['fails']}")
    print(f"[flt] 与参考实现不一致: {sum(mism.values())} 处 {dict(mism)}")
    for k, v in paircls.most_common(6):
        print(f"   {v:5d}  {k}")
    for d in details[:6]:
        print("   ", d)


if __name__ == "__main__":
    main()
