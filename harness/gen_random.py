#!/usr/bin/env python3
"""从种子出发做 N 次结构感知随机变异，把每个输入都存下来。

用途：和 AFL++ 的覆盖率引导队列做"同等执行预算"的消融对比——
两边都是 1000 次编译执行，比较各自语料并集的边/函数覆盖。
"""
from __future__ import annotations

import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutate as M  # noqa: E402


def load(seed_dir, limit=60):
    out = []
    for dp, _, fs in os.walk(seed_dir):
        for f in fs:
            if f.endswith(".mbt"):
                p = os.path.join(dp, f)
                if 0 < os.path.getsize(p) < 4000:
                    out.append(open(p, encoding="utf-8", errors="replace").read())
    out.sort(key=len)
    return out[:limit]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="/tmp/afl_in")
    ap.add_argument("--n", type=int, default=1000)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    pool = load(a.seeds)
    rng = random.Random(20261111)
    for i in range(a.n):
        src = M.mutate(rng.choice(pool), rng, pool)
        with open(os.path.join(a.out, f"r{i:05d}.mbt"), "w", encoding="utf-8",
                  errors="surrogateescape") as f:
            f.write(src)
    print(f"generated {a.n} -> {a.out}")


if __name__ == "__main__":
    main()
