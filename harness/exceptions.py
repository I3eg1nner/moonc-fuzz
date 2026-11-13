#!/usr/bin/env python3
"""异常语义一致性测试（codex 第 7 轮）。

可观测：每行 `case|seq|site|event|tag|payload|s0|s1`
事件：WRITE / RAISE / HANDLE / RETHROW / DONE / ESCAPE。
参考实现：Python 解释器（返回 Normal/ Raised，显式 store 与事件表，不用 Python 异常）。
覆盖：嵌套处理器选择、rethrow 保留 tag/payload、handler 内抛错外泄、
raise 之后的副作用被跳过、跨包抛出与捕获。

用法：
  python3 exceptions.py gen --n 200 --out /tmp/exc
  python3 exceptions.py run --dir /tmp/exc --workers 24 --out out/exceptions.json
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
MOD = """name = "exc/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "exc/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "exc/p{i:03d}/lib" @lib,\n  "exc/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

LIB = """pub suberror Boom {
  Boom(Int)
}

pub fn raise_if(x : Int) -> Unit raise Boom {
  if x > 0 {
    raise Boom(x)
  }
}

pub fn rethrow(v : Int) -> Unit raise Boom {
  raise Boom(v)
}

pub fn note(st : Array[Int], slot : Int) -> Unit {
  st[slot] = st[slot] + 1
}
"""

ALG = """pub fn wrap(x : Int) -> Unit raise @lib.Boom {
  @lib.raise_if(x)
}
"""

EV = """fn ev(cid : Int, st : Array[Int], site : String, event : String, tag : String, payload : Int) -> Unit {
  println("\\{cid}|\\{st[2]}|\\{site}|\\{event}|\\{tag}|\\{payload}|\\{st[0]}|\\{st[1]}")
  st[2] = st[2] + 1
}
"""


def case_ops(rng):
    ops = []
    for _ in range(rng.randrange(0, 4)):
        ops.append(("W", rng.randrange(2), rng.randrange(0, 3)))
    if rng.random() < 0.7:
        ops.append(("R", rng.randrange(1, 9)))
    else:
        ops.append(("R", 0))          # 不抛，等价于普通调用
    for _ in range(rng.randrange(0, 2)):
        ops.append(("W", rng.randrange(2), 1))
    return ops


def gen_prog(rng):
    cases = []
    for _ in range(10):
        ops = case_ops(rng)
        if rng.random() < 0.5:
            # 在 raise 之前再插一个写，验证"raise 之后的写被跳过"
            ops.insert(rng.randrange(0, len(ops) + 1), ("W", rng.randrange(2), 2))
        thr = rng.choice([2, 4, 6, 8])
        hwrite = rng.choice([0, 1])
        cases.append({"ops": ops, "thr": thr, "hw": hwrite})
    return cases


def emit_case(k, c):
    L = [f"  // case {k}", "  try {", "    try {"]
    for op in c["ops"]:
        if op[0] == "W":
            L.append(f"      st[{op[1]}] = st[{op[1]}] + {op[2]}")
            L.append(f'      ev({k}, st, "main", "WRITE", "-", {op[2]})')
        else:
            L.append(f'      ev({k}, st, "main", "RAISE", "Boom", {op[1]})')
            L.append(f"      @alg.wrap({op[1]})")
    L.append(f'      ev({k}, st, "main", "DONE", "-", 0)')
    L += ["    } catch {", "      @lib.Boom(v) => {"]
    L.append(f'        ev({k}, st, "handler", "HANDLE", "Boom", v)')
    if c["hw"]:
        L.append("        st[1] = st[1] + v")
        L.append(f'        ev({k}, st, "handler", "WRITE", "-", v)')
    L.append(f"        if v > {c['thr']} {{")
    L.append(f'          ev({k}, st, "handler", "RETHROW", "Boom", v)')
    L.append("          @lib.rethrow(v)")
    L.append("        }")
    L += ["      }", "      _ => {", f'        ev({k}, st, "handler", "HANDLE", "OTHER", -1)',
          "      }", "    }", "  } catch {"]
    L.append(f'    @lib.Boom(v) => ev({k}, st, "outer", "ESCAPE", "Boom", v)')
    L.append(f'    _ => ev({k}, st, "outer", "ESCAPE", "OTHER", -1)')
    L.append("  }")
    return "\n".join(L)


def interpret(cases):
    """显式 store + 事件；控制流不用 Python 异常。"""
    st = [0, 0, 0]              # s0, s1, seq
    events = []

    def ev(k, site, event, tag, payload):
        events.append([k, st[2], site, event, tag, payload, st[0], st[1]])
        st[2] += 1

    for k, c in enumerate(cases):
        raised = None
        for op in c["ops"]:
            if op[0] == "W":
                st[op[1]] += op[2]
                ev(k, "main", "WRITE", "-", op[2])
            else:
                ev(k, "main", "RAISE", "Boom", op[1])
                if op[1] > 0:
                    raised = op[1]
                    break
        if raised is None:
            ev(k, "main", "DONE", "-", 0)
            continue
        v = raised
        ev(k, "handler", "HANDLE", "Boom", v)
        if c["hw"]:
            st[1] += v
            ev(k, "handler", "WRITE", "-", v)
        if v > c["thr"]:
            ev(k, "handler", "RETHROW", "Boom", v)
            ev(k, "outer", "ESCAPE", "Boom", v)
    return events


def gen_one(i):
    rng = random.Random(0xECC + i)
    cases = gen_prog(rng)
    p = os.path.join(CFG["out"], f"p{i:03d}")
    for sub in ("lib", "alg", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "alg", "moon.pkg"), "w").write(ALG_PKG.format(i=i))
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(LIB)
    open(os.path.join(p, "alg", "alg.mbt"), "w").write(ALG)
    body = "\n".join(emit_case(k, c) for k, c in enumerate(cases))
    src = "fn main {\n  let st : Array[Int] = [0, 0, 0]\n" + body + "\n}\n"
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write(EV + "\n" + src)
    json.dump({"i": i, "cases": cases, "expect": interpret(cases)},
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
    rec = []
    for line in out.splitlines():
        f = line.strip().split("|")
        if len(f) == 8 and f[0].isdigit():
            rec.append([int(x) if i != 2 and i != 3 and i != 4 else x
                        for i, x in enumerate(f)])
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
        print(f"[exc] generated {len(ps)} -> {a.out}")
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
            if rec != exp:
                n = min(len(rec), len(exp))
                bad = next((k for k in range(n) if rec[k] != exp[k]), n)
                mism[f"{t}:TRACE"] += 1
                if len(details) < 15:
                    details.append({"prog": r["i"], "t": t, "at": bad,
                                    "exp": exp[bad] if bad < len(exp) else None,
                                    "got": rec[bad] if bad < len(rec) else None,
                                    "len": [len(exp), len(rec)]})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                paircls["SAME" if recs[names[x]] == recs[names[y]]
                        else f"DIFF:{names[x]}|{names[y]}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               events=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details)
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[exc] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"events={out['events']} fails={out['fails']}")
    print(f"[exc] 参考不一致: {sum(mism.values())} 个程序 {dict(mism)}")
    for k, v in paircls.most_common(5):
        print(f"   {v:5d}  {k}")
    for d in details[:5]:
        print("   ", d)


if __name__ == "__main__":
    main()
