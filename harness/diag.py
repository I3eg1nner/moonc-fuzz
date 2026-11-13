#!/usr/bin/env python3
"""诊断消息聚类（D 层）：把 stderr 归一化成"诊断类"，当深度 fitness 用。

为什么不用边覆盖：边计数饱和后不再敏感；一条类型错误能告诉你"哪个类型对不上
哪个类型"，信息量比"又走到这条边"大得多。文献里没有直接对应工作，属自创
指标，报告时标注清楚。

用法：
  python3 diag.py <corpus_dir> [--real] [--limit 300] [--workers 48] [--out x.json]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cov  # noqa: E402
import realcorpus as RC  # noqa: E402

MOONC = os.path.expanduser("~/.moon/bin/moonc")
MI = [t for s in cov.core_mi_args() for t in s.split()]
LOC = re.compile(r"(?:[^\s:]*\.(?:mbt|mbti|mbt\.md|mbtx))?:\d+:\d+(?:-\d+:\d+)?")
E = re.compile(r"\[E(\d{4})\]")
QUOTED = re.compile(r"[`'\"]([^`'\"]{0,60})[`'\"]")
NUM = re.compile(r"\b\d+\b")
WS = re.compile(r"\s+")
CFG = {}


def w_init():
    CFG["wd"] = tempfile.mkdtemp(prefix="diag_", dir="/tmp")


def normalize(err: bytes, rc: int) -> str:
    t = err.decode("utf-8", "replace")
    if "encountered an unexpected situation" in t:
        m = re.search(r"Error: ([^\n]{0,120})", t)
        return "ICE|" + (m.group(1).strip() if m else "?")
    if rc < 0:
        return f"SIG{-rc}"
    lines = []
    for ln in t.splitlines():
        m = E.search(ln)
        if m and m.group(1)[0] in "34":   # 只保留 error（E3xxx 解析 / E4xxx 分析），丢掉 warning
            ln = LOC.sub("<loc>", ln)
            ln = QUOTED.sub(lambda m: "<" + m.group(1)[:40] + ">", ln)
            ln = NUM.sub("<n>", ln)
            ln = WS.sub(" ", ln).strip()
            lines.append(ln)
    if not lines:
        return f"rc{rc}|" + WS.sub(" ", LOC.sub("<loc>", t))[:120]
    # 一个输入可能报多条；取前 3 条的唯一集合当类
    uniq = sorted(set(lines))[:3]
    return " || ".join(uniq)


def one(path):
    import random
    wd = CFG["wd"]
    data = open(path, "rb").read()
    if CFG.get("mutate"):
        rng = random.Random(hash(path) & 0xFFFF)
        data = RC.gentle_body(data.decode("utf-8", "replace"), rng).encode("utf-8", "replace")
    dst = os.path.join(wd, "in.mbt")
    open(dst, "wb").write(data)
    if CFG["real"]:
        argv = ([MOONC, "build-package", "in.mbt", "-o", "out.core",
                 "-pkg", "fuzz/p", "-pkg-type", "library", "-target", "wasm-gc",
                 "-g", "-O0", "-workspace-path", "."] + MI)
    else:
        b = os.path.expanduser("~/.moon/lib/core/_build/wasm/release/bundle")
        argv = ([MOONC, "build-package", "in.mbt", "-o", "out.core",
                 "-pkg", "fuzz/p", "-pkg-type", "executable", "-target", "wasm",
                 "-g", "-O0", "-workspace-path", ".",
                 "-i", f"{b}/builtin/builtin.mi:builtin",
                 "-i", f"{b}/prelude/prelude.mi:prelude"])
        if b"fn main" not in data:
            open(dst, "ab").write(b"\n\nfn main { () }\n")
    try:
        p = subprocess.run(argv, cwd=wd, capture_output=True, timeout=120)
        rc, err = p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        rc, err = 124, b"timeout"
    return {"path": path, "rc": rc, "ok": rc == 0, "cls": None if rc == 0 else normalize(err, rc)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus")
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--limit", type=int, default=300)
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--mutate", action="store_true", help="先做函数体变异再编译")
    ap.add_argument("--out")
    a = ap.parse_args()
    files = []
    for dp, _, fs in os.walk(a.corpus):
        files += [os.path.join(dp, f) for f in fs if f.endswith(".mbt")]
    files.sort(key=lambda p: os.path.getsize(p))
    if a.limit and len(files) > a.limit:
        step = len(files) / a.limit
        files = [files[int(i * step)] for i in range(a.limit)]
    CFG["real"] = a.real
    CFG["mutate"] = a.mutate
    with Pool(a.workers, initializer=w_init) as p:
        res = p.map(one, files, chunksize=4)
    ok = sum(r["ok"] for r in res)
    hist = Counter(r["cls"] for r in res if r["cls"])
    out = dict(corpus=a.corpus, real=a.real, mutate=a.mutate, n=len(res), ok=ok,
               classes=len(hist), class_list=sorted(hist),
               hist=[[c, n] for c, n in hist.most_common(60)],
               per_input=[{"path": r["path"], "rc": r["rc"], "cls": r["cls"]} for r in res])
    if a.out:
        json.dump(out, open(a.out, "w"), indent=1)
    print(f"[diag] n={len(res)} ok={ok} ({ok/max(len(res),1):.1%}) "
          f"诊断类={len(hist)}")
    for c, n in hist.most_common(8):
        print(f"  {n:5d}  {c[:150]}")


if __name__ == "__main__":
    main()
