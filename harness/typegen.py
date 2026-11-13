#!/usr/bin/env python3
"""类型导向生成（codex 第 9 轮排第一）：用老编译器的 typer 当"假设来源"。

六个形状（4 个应通过 / 2 个应报错）：
  A generic_trait   泛型 + trait 约束 + impl
  B enum_match      枚举（单元/元组/带标签）+ 穷尽 match
  C nested_generic  Array[Option[T]] + 闭包 + 循环
  D visibility      priv 类型 + pub 访问器 + 跨包
  E no_impl         调用泛型但缺 impl（预期 E4xxx）
  F bad_visibility  跨包访问私有类型（预期 E4xxx）

用法：
  python3 typegen.py gen --n 240 --out /tmp/tg240
  python3 typegen.py run --dir /tmp/tg240 --workers 24 --out out/typegen.json
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
from collections import Counter
from multiprocessing import Pool

MOON = os.path.expanduser("~/.moon/bin/moon")
CFG = {}
E_RE = re.compile(r"\[E?(\d{4})\]")

MOD = 'name = "tg/p{i:03d}"\nversion = "0.1.0"\npreferred_target = "wasm"\n'
LIB_PKG = "import {\n}\n"
CMD_PKG = ('import {{\n  "tg/p{i:03d}/lib" @lib,\n}}\n\npkgtype(kind: "executable")\n')

LIB_HEAD = """trait Shown {
  shown(Self) -> String
}
"""


def shape_generic_trait(rng, i):
    k = rng.randrange(1, 4)
    structs = "\n".join(
        f"struct S{j} {{ x : Int }}\nimpl Shown for S{j} with shown(self) {{ \"S{j}=\\{{self.x}}\" }}"
        for j in range(k))
    calls = "\n".join(f'  println(@lib.render(@lib.S{j}::{{ x: {j} }}))' for j in range(k))
    lib = LIB_HEAD + "\n" + structs + """
pub fn[T : Shown] render(x : T) -> String { x.shown() }
"""
    main = f"""fn main {{
{calls}
  println(@lib.render(@lib.S0::{{ x: 9 }}))
}}
"""
    return lib, main, True, None


def shape_enum_match(rng, i):
    n = rng.randrange(1, 4)
    variants = "; ".join([f"V{j}(Int)" for j in range(n)])
    arms = "\n".join(f"    V{j}(v) => v + {j}" for j in range(n))
    lib = f"""pub enum E {{ {variants} }}

pub fn eval(e : E) -> Int {{
  match e {{
{arms}
  }}
}}
"""
    calls = "\n".join(f'  println(@lib.eval(@lib.E::V{j}({j + 1})))' for j in range(n))
    main = f"""fn main {{
{calls}
}}
"""
    return lib, main, True, None


def shape_nested_generic(rng, i):
    d = rng.randrange(1, 4)
    lib = """pub fn nest(xs : Array[Option[Int]]) -> Int {
  let mut acc = 0
  for o in xs {
    match o {
      Some(v) => acc = acc + v
      None => acc = acc + 0
    }
  }
  acc
}

pub fn apply(f : (Int) -> Int, x : Int) -> Int { f(x) }
"""
    main = f"""fn main {{
  let xs : Array[Option[Int]] = [Some(1), None, Some(3)]
  println(@lib.nest(xs))
  println(@lib.apply(fn(x) {{ x * {d} }}, 7))
}}
"""
    return lib, main, True, None


def shape_visibility(rng, i):
    lib = """priv struct Secret { v : Int }

fn peek(s : Secret) -> Int { s.v }

pub fn make(v : Int) -> Int { peek(Secret::{ v: v }) }
"""
    main = """fn main {
  println(@lib.make(5))
}
"""
    return lib, main, True, None


def shape_no_impl(rng, i):
    lib = LIB_HEAD + """
struct NoImpl { x : Int }

pub fn[T : Shown] render(x : T) -> String { x.shown() }
"""
    main = """fn main {
  println(@lib.render(NoImpl::{ x: 1 }))
}
"""
    return lib, main, False, "E4"


def shape_bad_visibility(rng, i):
    lib = """priv struct Secret { v : Int }

pub fn make(v : Int) -> Int { v }
"""
    main = """fn main {
  let s = @lib.Secret::{ v: 1 }
  println(@lib.make(2))
}
"""
    return lib, main, False, "E4"


SHAPES = [shape_generic_trait, shape_enum_match, shape_nested_generic,
          shape_visibility, shape_no_impl, shape_bad_visibility]


def gen_one(i):
    rng = random.Random(0x7E9 + i)
    sh = SHAPES[i % len(SHAPES)]
    lib, main, valid, exp = sh(rng, i)
    p = os.path.join(CFG["out"], f"p{i:03d}")
    for sub in ("lib", "cmd/main"):
        os.makedirs(os.path.join(p, sub), exist_ok=True)
    open(os.path.join(p, "moon.mod"), "w").write(MOD.format(i=i))
    open(os.path.join(p, "lib", "moon.pkg"), "w").write(LIB_PKG)
    open(os.path.join(p, "cmd", "main", "moon.pkg"), "w").write(CMD_PKG.format(i=i))
    if sh is not shape_bad_visibility:
        # 单包形态：把 lib 内容并进 main，去掉跨包前缀
        main = (lib + "\n" + main).replace("@lib.", "")
        lib = ""
    open(os.path.join(p, "lib", "lib.mbt"), "w").write(lib)
    open(os.path.join(p, "cmd", "main", "main.mbt"), "w").write(main)
    json.dump({"i": i, "shape": sh.__name__.replace("shape_", ""),
               "valid": valid, "expect": exp}, open(os.path.join(p, "meta.json"), "w"))
    return p


def run_one(arg):
    i, p = arg
    meta = json.load(open(os.path.join(p, "meta.json")))
    try:
        r = subprocess.run([MOON, "check", "--target", "wasm-gc"], cwd=p,
                           capture_output=True, timeout=CFG["timeout"])
        rc = r.returncode
        err = (r.stdout + r.stderr).decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        rc, err = 124, "timeout"
    codes = sorted(set(E_RE.findall(err)))
    return {"i": i, "shape": meta["shape"], "valid": meta["valid"],
            "expect": meta["expect"], "rc": rc, "codes": codes,
            "err": err[:300]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["gen", "run"])
    ap.add_argument("--n", type=int, default=240)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--workers", type=int, default=24)
    ap.add_argument("--timeout", type=int, default=120)
    a = ap.parse_args()
    if a.mode == "gen":
        CFG["out"] = a.out
        if os.path.exists(a.out):
            shutil.rmtree(a.out)
        os.makedirs(a.out, exist_ok=True)
        with Pool(32) as p:
            ps = p.map(gen_one, range(a.n), chunksize=4)
        print(f"[tg] generated {len(ps)} -> {a.out}")
        return
    CFG["timeout"] = a.timeout
    projs = sorted(os.path.join(a.dir, d) for d in os.listdir(a.dir)
                   if os.path.isdir(os.path.join(a.dir, d)))
    with Pool(a.workers) as p:
        res = p.map(run_one, list(enumerate(projs)), chunksize=1)
    by = {}
    for r in res:
        b = by.setdefault(r["shape"], Counter())
        b["n"] += 1
        b["ok" if r["rc"] == 0 else "fail"] += 1
    valid = [r for r in res if r["valid"]]
    invalid = [r for r in res if not r["valid"]]
    acc = sum(1 for r in valid if r["rc"] == 0) / max(len(valid), 1)
    rej = sum(1 for r in invalid if r["rc"] != 0) / max(len(invalid), 1)
    cls = Counter()
    for r in invalid:
        for c in r["codes"]:
            cls[c] += 1
    out = dict(n=len(res), valid_n=len(valid), valid_rate=round(acc, 4),
               invalid_n=len(invalid), reject_rate=round(rej, 4),
               by_shape={k: dict(v) for k, v in by.items()},
               invalid_codes=dict(cls.most_common(15)),
               samples=[r for r in res if r["rc"] != 0][:10])
    json.dump(out, open(a.out, "w"), indent=1)
    print(f"[tg] n={out['n']} 应通过={len(valid)} 接受率={acc:.1%} | "
          f"应报错={len(invalid)} 拒绝率={rej:.1%}")
    for k, v in out["by_shape"].items():
        print(f"   {k:16} {v}")
    print("   invalid codes:", out["invalid_codes"])
    for s in out["samples"][:3]:
        print("   ", s["i"], s["shape"], s["codes"], s["err"][:100].replace("\n", " "))


if __name__ == "__main__":
    main()
