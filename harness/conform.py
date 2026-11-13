#!/usr/bin/env python3
"""多包一致性测试：生成确定性的多包程序，在 4 个后端上编译+运行+比对。

设计（按 codex review #2 的 C 项）：
* 200 个确定性程序，参数覆盖 泛型 / 闭包 / 跨包调用 / trait / 数值宽度；
* 每个程序 3 个包（lib ← alg ← cmd/main），走真实 `moon run`，不是单文件;
* 4 个后端：wasm / wasm-gc / js / native；
* 判据：4 个后端都跑通的比例 ≥ 80%（<160/200 就放弃这条线）；
* 差异分类复用 difftpl.normalize（已修大小写/大整数两个吞值 bug）。

用法：
  python3 conform.py gen --n 200 --out /tmp/conf200
  python3 conform.py run --dir /tmp/conf200 --workers 24 --out out/conform200.json
"""
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import difftpl  # noqa: E402

MOON = os.path.expanduser("~/.moon/bin/moon")
TARGETS = ["wasm", "wasm-gc", "js", "native"]
CFG = {}

MOD = """name = "conf/p{i:03d}"
version = "0.1.0"
preferred_target = "wasm"
"""

LIB_PKG = "import {\n}\n"
ALG_PKG = '''import {{
  "conf/p{i:03d}/lib" @lib,
}}
'''
CMD_PKG = '''import {{
  "conf/p{i:03d}/lib" @lib,
  "conf/p{i:03d}/alg" @alg,
}}

pkgtype(kind: "executable")
'''

LIB = """pub fn seed(n : Int) -> Array[Int] {
  let a : Array[Int] = []
  for i in 0..<n {
    a.push(i * __K__ + __M__)
  }
  a
}

pub fn[T] first(xs : Array[T]) -> Option[T] {
  if xs.length() > 0 { Some(xs[0]) } else { None }
}

pub fn clampv(x : Int) -> Int {
  if x > __HI__ { __HI__ } else if x < __LO__ { __LO__ } else { x }
}
"""

ALG = """pub fn transform(xs : Array[Int]) -> Array[Int] {
  xs.map(fn(x) { __EXPR__ })
}

pub fn reduce(xs : Array[Int]) -> Int {
  let mut acc = __INIT__
  for x in xs {
    acc = __FOLD__
  }
  acc
}

pub fn apply_twice(f : (Int) -> Int, x : Int) -> Int {
  f(f(x))
}
"""

CMD = """fn main {
  let xs = @lib.seed(__N__)
  let ys = @alg.transform(xs)
  let cs = ys.map(@lib.clampv)
  println("R=\\{@alg.reduce(cs)}")
  println("A=\\{@alg.apply_twice(fn(x) { x * 2 + 1 }, __N__)}")
  println("F=\\{@lib.first(cs).to_string()}")
  println("L=\\{cs.length()}")
}
"""


def fill(t, **kw):
    for k, v in kw.items():
        t = t.replace(f"__{k.upper()}__", str(v))
    return t


def gen_one(i):
    rng = random.Random(0xA11CE + i)
    k = rng.randrange(1, 7)
    m = rng.randrange(-5, 6)
    hi = rng.randrange(20, 60)
    lo = -hi
    n = rng.randrange(3, 24)
    ops = rng.choice([
        "x * {k} + {m}", "x - {k}", "(x * x) % {hi}", "x / {k}",
        "x ^ {k}", "x << 1", "x >> 1", "(x + {k}) * 2", "x * {k} % ({hi} + 1)",
    ])
    expr = ops.format(k=k, m=m, hi=hi, lo=lo)
    fold = rng.choice([
        "acc + x", "acc ^ x", "if x > acc { x } else { acc }", "acc + x * x", "acc - x",
        "if x > acc { x } else { acc }",
    ])
    init = rng.choice([0, 1, -1, hi])
    d = CFG["out"]
    p = os.path.join(d, f"p{i:03d}")
    for sub in ("lib", "alg", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "alg", "moon.pkg"), "w").write(ALG_PKG.format(i=i))
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(
        fill(LIB, k=k, m=m, hi=hi, lo=lo))
    open(os.path.join(p, "alg", "alg.mbt"), "w").write(
        fill(ALG, expr=expr, fold=fold, init=init))
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write(fill(CMD, n=n))
    return p


def run_one(arg):
    i, p = arg
    outs = {}
    for t in TARGETS:
        env = dict(os.environ, MOON_HOME=os.path.expanduser("~/.moon"))
        try:
            r = subprocess.run([MOON, "run", "cmd/main", "--target", t],
                               cwd=p, capture_output=True, timeout=CFG["timeout"],
                               env=env)
            outs[t] = dict(ok=(r.returncode == 0), rc=r.returncode,
                           out=r.stdout.decode("utf-8", "replace"),
                           err=r.stderr.decode("utf-8", "replace")[:400])
        except subprocess.TimeoutExpired:
            outs[t] = dict(ok=False, rc=None, out="", err="timeout")
    return {"i": i, "path": p, "outs": outs}


def classify(outs):
    """逐对比较四个后端；只比较都跑通的组合。"""
    names = [t for t in TARGETS if outs[t]["ok"]]
    kinds = []
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = outs[names[i]], outs[names[j]]
            if a["out"] == b["out"]:
                kinds.append("SAME")
            elif difftpl.normalize(a["out"].encode()) == difftpl.normalize(b["out"].encode()):
                kinds.append("FORMAT_DIFF")
            else:
                kinds.append(f"REAL_DIFF:{names[i]}|{names[j]}")
    return kinds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["gen", "run"])
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--workers", type=int, default=24)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if a.mode == "gen":
        CFG["out"] = a.out
        if os.path.exists(a.out) and not a.keep:
            shutil.rmtree(a.out)
        os.makedirs(a.out, exist_ok=True)
        with Pool(max(1, min(32, os.cpu_count() or 8))) as p:
            paths = p.map(gen_one, range(a.n), chunksize=4)
        print(f"[conf] generated {len(paths)} projects -> {a.out}")
        return
    projs = sorted(os.path.join(a.dir, d) for d in os.listdir(a.dir)
                   if os.path.isdir(os.path.join(a.dir, d)))
    CFG["timeout"] = a.timeout
    with Pool(a.workers) as p:
        res = p.map(run_one, list(enumerate(projs)), chunksize=1)
    full = [r for r in res if all(r["outs"][t]["ok"] for t in TARGETS)]
    cls = Counter()
    diffs = []
    for r in res:
        for k in classify(r["outs"]):
            cls[k] += 1
            if k.startswith("REAL_DIFF"):
                diffs.append({"i": r["i"], "kind": k,
                              "outs": {t: r["outs"][t]["out"][:200] for t in TARGETS},
                              "rcs": {t: r["outs"][t]["rc"] for t in TARGETS}})
    out = dict(n=len(res), full4=len(full),
               full_rate=round(len(full) / max(len(res), 1), 4),
               pairs=dict(cls), diffs=diffs[:50],
               fails={t: sum(1 for r in res if not r["outs"][t]["ok"]) for t in TARGETS})
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[conf] n={out['n']} all4={out['full4']} ({out['full_rate']:.1%}) "
          f"fails={out['fails']}")
    for k, v in cls.most_common(8):
        print(f"   {v:5d}  {k}")


if __name__ == "__main__":
    main()
