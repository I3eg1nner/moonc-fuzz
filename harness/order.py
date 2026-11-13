#!/usr/bin/env python3
"""覆盖率增长曲线：路径序 / 大小序 / 随机序 / 贪心序 / 包轮转序。

为什么需要：`per_input_new` 的中位数 0 只能说明"这批语料彼此冗余"，不能说明
"可达空间见底"。曲线形状强烈依赖输入顺序，所以必须给出贪心（上界）和
多样性序（包轮转）的对照，才能谈"再加输入有没有用"。

用法：
  python3 order.py out/funcs_real [--moonc-only] [--out out/order_real.json]
"""
from __future__ import annotations

import argparse
import json
import os
import random
import statistics
import sys


def load(d, moonc_only=True):
    man = [json.loads(l) for l in open(os.path.join(d, "_manifest.jsonl"))]
    sets = []
    for m in man:
        fns = [x for x in open(os.path.join(d, f"{m['i']:05d}.funcs")).read().split("\n") if x]
        if moonc_only:
            fns = [f for f in fns if f.startswith("camlMoonc")]
        sets.append(set(fns))
    return [m["path"] for m in man], sets


def curve(bits_list, order, universe_bits):
    seen = 0
    out = []
    for i in order:
        seen |= bits_list[i]
        out.append(bin(seen).count("1"))
    return out


def greedy(bits_list, universe_bits):
    n = len(bits_list)
    covered = 0
    left = set(range(n))
    order, cur = [], []
    while left:
        best, best_gain = -1, -1
        for i in left:
            g = bin(bits_list[i] & ~covered).count("1")
            if g > best_gain:
                best, best_gain = i, g
        if best_gain <= 0:
            order.extend(sorted(left))
            break
        covered |= bits_list[best]
        order.append(best)
        left.discard(best)
        cur.append(bin(covered).count("1"))
    return order, cur


def at(c, ns=(100, 232, 500, 1000, 1368)):
    return {n: (c[n - 1] if n <= len(c) else c[-1]) for n in ns}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--all-syms", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args()
    paths, sets = load(a.dir, moonc_only=not a.all_syms)
    uni = sorted(set().union(*sets))
    idx = {f: i for i, f in enumerate(uni)}
    bits = []
    for s in sets:
        v = 0
        for f in s:
            v |= 1 << idx[f]
        bits.append(v)
    all_bits = (1 << len(uni)) - 1

    orders = {}
    orders["path"] = list(range(len(sets)))
    orders["size_asc"] = sorted(range(len(sets)), key=lambda i: len(sets[i]))
    orders["size_desc"] = sorted(range(len(sets)), key=lambda i: -len(sets[i]))
    rnd = random.Random(1)
    for k in range(3):
        o = list(range(len(sets)))
        rnd.shuffle(o)
        orders[f"rand{k}"] = o
    # 包轮转序：按顶层目录分组，组内按大小降序，组间轮流取
    groups = {}
    for i, p in enumerate(paths):
        g = p.split(os.sep)[0] if os.sep in p else p.split("__")[0]
        groups.setdefault(g, []).append(i)
    for g in groups:
        groups[g].sort(key=lambda i: -len(sets[i]))
    round_robin = []
    while any(groups.values()):
        for g in sorted(groups):
            if groups[g]:
                round_robin.append(groups[g].pop(0))
    orders["pkg_round_robin"] = round_robin

    res = {}
    for k, o in orders.items():
        res[k] = at(curve(bits, o, all_bits))
    g_order, g_cur = greedy(bits, all_bits)
    res["greedy"] = at(g_cur)
    res["greedy_order_head"] = [paths[i] for i in g_order[:25]]

    print(f"[order] {len(sets)} inputs, {len(uni)} functions (all symbols)")
    print(f"{'order':18} " + " ".join(f"n={n:<6}" for n in (100, 232, 500, 1000, len(sets))))
    for k in ["path", "size_asc", "size_desc", "rand0", "rand1", "rand2",
              "pkg_round_robin", "greedy"]:
        print(f"{k:18} " + " ".join(f"{res[k][n]:<8}" for n in (100, 232, 500, 1000, len(sets))))
    med = statistics.median(res[k][len(sets)] for k in ("rand0", "rand1", "rand2"))
    print(f"[order] greedy/path at full set = {res['greedy'][len(sets)]}/{res['path'][len(sets)]}")

    if a.out:
        json.dump(dict(dir=a.dir, n=len(sets), universe=len(uni), curves=res), open(a.out, "w"), indent=1)
        print(f"[order] wrote {a.out}")


if __name__ == "__main__":
    main()
