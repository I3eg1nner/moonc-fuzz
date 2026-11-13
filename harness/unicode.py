#!/usr/bin/env python3
"""Unicode/字符串一致性测试（codex 第 7 轮：exceptions 之后做 Unicode）。

可观测：`id|op|sid|arg|r1|r2`
* CLEN: `char_length()`（码点数）；ULEN: `length()`（code units）；
  CU(i): `code_unit_at(i)`（UTF-16 码元）+ 下一位；
* 参考：Python 的码点语义 + UTF-16 编码。

用法：
  python3 unicode.py gen --n 200 --out /tmp/uni
  python3 unicode.py run --dir /tmp/uni --workers 24 --out out/unicode.json
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
MOD = """name = "uni/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""
LIB_PKG = "import {\n}\n"
ALG_PKG = 'import {{\n  "uni/p{i:03d}/lib" @lib,\n}}\n'
CMD_PKG = 'import {{\n  "uni/p{i:03d}/lib" @lib,\n  "uni/p{i:03d}/alg" @alg,\n}}\n\npkgtype(kind: "executable")\n'

STRINGS = [
    "abc", "aé中😀", "é", "中文字", "😀😀", "e\u0301", "🇨🇳", "a\u0000b",
    "\u007f\u0080", "\u00ff\u0100", "𝕬𝕭", "👨‍👩‍👧", "مرحبا", "a😀b中c",
]

LIB = """pub fn chlen(s : String) -> Int { s.char_length() }
pub fn ulen(s : String) -> Int { s.length() }
pub fn cu(s : String, i : Int) -> Int { s.code_unit_at(i).to_int() }
"""

ALG = """pub fn call1(f : (String) -> Int, s : String) -> Int { f(s) }
pub fn call2(f : (String, Int) -> Int, s : String, i : Int) -> Int { f(s, i) }
"""


def esc(s: str) -> str:
    out = []
    for ch in s:
        o = ord(ch)
        if 32 <= o < 127 and ch not in '"\\':
            out.append(ch)
        else:
            out.append("\\u{%X}" % o)
    return '"' + "".join(out) + '"'


def u16_units(s: str):
    b = s.encode("utf-16-le")
    return [int.from_bytes(b[i:i + 2], "little") for i in range(0, len(b), 2)]


def gen_one(i):
    rng = random.Random(0x0A11 + i)
    cases = []
    for _ in range(10):
        sid = rng.randrange(len(STRINGS))
        s = STRINGS[sid]
        units = u16_units(s)
        op = rng.choice(["CLEN", "ULEN", "CU"])
        if op == "CU":
            idx = rng.randrange(0, max(1, len(units) - 1))
            a, b = units[idx], units[idx + 1] if idx + 1 < len(units) else -1
            cases.append((op, sid, idx, a, b))
        elif op == "CLEN":
            cases.append((op, sid, -1, len(s), -1))
        else:
            cases.append((op, sid, -1, len(units), -1))
    L = ["fn main {"]
    for cid, (op, sid, idx, r1, r2) in enumerate(cases):
        lit = esc(STRINGS[sid])
        if op == "CLEN":
            call = f"@lib.chlen({lit})"
            L.append(f'  println("{cid}|{op}|{sid}|-|\\{{{call}}}|-")')
        elif op == "ULEN":
            call = f"@lib.ulen({lit})"
            L.append(f'  println("{cid}|{op}|{sid}|-|\\{{{call}}}|-")')
        else:
            u = u16_units(STRINGS[sid])
            call = f"@lib.cu({lit}, {idx})"
            if idx + 1 < len(u):
                call2 = f"@lib.cu({lit}, {idx + 1})"
                L.append(f'  println("{cid}|{op}|{sid}|{idx}|\\{{{call}}}|\\{{{call2}}}")')
            else:
                L.append(f'  println("{cid}|{op}|{sid}|{idx}|\\{{{call}}}|-")')
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
    json.dump({"i": i, "cases": cases, "expect": [[c[0], c[1], c[2], c[3], c[4]]
                                                  for c in cases]},
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
        if len(f) == 6 and f[0].isdigit():
            def iv(x):
                return -1 if x == "-" else int(x)
            rec[int(f[0])] = [f[1], int(f[2]), iv(f[3]), iv(f[4]), iv(f[5])]
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
        print(f"[uni] generated {len(ps)} -> {a.out}")
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
            for cid, e in enumerate(exp):
                got = rec.get(cid)
                if got != e:
                    mism[f"{t}:{e[0]}"] += 1
                    if len(details) < 20:
                        details.append({"prog": r["i"], "t": t, "case": cid,
                                        "exp": e, "got": got,
                                        "str": STRINGS[e[1]]})
        names = list(recs)
        for x in range(len(names)):
            for y in range(x + 1, len(names)):
                a_, b_ = names[x], names[y]
                same = all(recs[a_].get(k) == recs[b_].get(k) for k in range(len(exp)))
                paircls["SAME" if same else f"DIFF:{a_}|{b_}"] += 1
    out = dict(n=len(res), full4=len(full), full_rate=round(len(full) / max(len(res), 1), 4),
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS},
               cases=sum(len(r["meta"]["expect"]) for r in res),
               ref_mismatch=dict(mism), pair_classes=dict(paircls), details=details)
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[uni] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"cases={out['cases']} fails={out['fails']}")
    print(f"[uni] 参考不一致: {sum(mism.values())} 处 {dict(mism)}")
    for k, v in paircls.most_common(5):
        print(f"   {v:5d}  {k}")
    for d in details[:6]:
        print("   ", d)


if __name__ == "__main__":
    main()
