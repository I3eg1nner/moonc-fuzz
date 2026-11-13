#!/usr/bin/env python3
"""真程序语料工程（A 层）：把 moonbitlang/core 的源码当输入喂给 moonc。

为什么重要：玩具片段只能走到 typer 浅层。core 自己的 1.4k 个 .mbt 是天然
类型正确、含泛型/trait/迭代器/模式匹配的真实程序，能直接把编译推进到
单态化和 backend。

编译模型：每个 .mbt 文件当成一个独立 library 包编译，依赖全部用
`~/.moon/lib/core/_build/wasm-gc/release/bundle/*.mi`（短别名），
所以不需要 sibling 文件，也不需要网络。

用法：
  python3 realcorpus.py harvest --src ~/.moon/lib/core --out seeds_real \
      --json out/real_core_compile.json
  python3 realcorpus.py rate seeds_real
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cov  # noqa: E402
import mutate as MUT  # noqa: E402

MOONC = os.path.expanduser("~/.moon/bin/moonc")
MI = [t for s in cov.core_mi_args() for t in s.split()]
ICE_MARK = "encountered an unexpected situation"
E_RE = re.compile(r"\[E(\d{4})\]")

CFG = {}


def w_init():
    CFG["wd"] = tempfile.mkdtemp(prefix="real_", dir="/tmp")


def sig_of(rc: int, err: bytes) -> str:
    if ICE_MARK.encode() in err:
        m = re.search(rb"Error: ([^\n]{0,80})", err)
        return "ICE:" + (m.group(1).decode("utf-8", "replace").strip() if m else "?")
    if rc < 0:
        return f"SIG{-rc}"
    codes = sorted(set(E_RE.findall(err.decode("utf-8", "replace"))))
    if codes:
        return "E:" + ",".join(codes[:3])
    return f"rc{rc}"


def compile_one(path):
    wd = CFG["wd"]
    ext = ".mbt"
    dst = os.path.join(wd, "in" + ext)
    try:
        data = open(path, "rb").read()
    except OSError as e:
        return {"path": path, "ok": False, "sig": f"read:{e.errno}"}
    open(dst, "wb").write(data)
    argv = ([MOONC, "build-package", "in.mbt", "-o", "out.core",
             "-pkg", "fuzz/p", "-pkg-type", "library",
             "-target", "wasm-gc", "-g", "-O0", "-workspace-path", "."]
            + MI)
    try:
        p = subprocess.run(argv, cwd=wd, capture_output=True, timeout=120)
        rc, err = p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        rc, err = 124, b"timeout"
    return {"path": path, "ok": rc == 0, "rc": rc, "sig": sig_of(rc, err),
            "size": len(data)}


CORE = os.path.expanduser("~/.moon/lib/core")
BUNDLE = cov.CORE_BUNDLE


IMPORT_BLOCK = re.compile(r"import\s*\{(.*?)\}", re.S)
IMPORT_ITEM = re.compile(r'"([^"]+)"(?:\s*@([A-Za-z0-9_/]+))?')


def pkg_imports(d):
    """按包自己的 moon.pkg 解析 import 列表（含 @alias），这才是真实依赖图。

    core 的别名是"每个消费者自己声明的"：zip 里 `@flate` 指 compress/flate，
    别处可能写成 `@compress/flate`。全局一套别名必然错。
    """
    out = []
    for name in ("moon.pkg", "moon.pkg.json"):
        fp = os.path.join(d, name)
        if not os.path.exists(fp):
            continue
        txt = open(fp, encoding="utf-8", errors="ignore").read()
        txt = re.sub(r"//[^\n]*", "", txt)
        for blk in IMPORT_BLOCK.finditer(txt):
            for path, alias in IMPORT_ITEM.findall(blk.group(1)):
                rel = path[len("moonbitlang/core/"):] if path.startswith("moonbitlang/core/") else None
                if rel is None:
                    continue
                mi = os.path.join(BUNDLE, rel, os.path.basename(rel) + ".mi")
                if not os.path.exists(mi):
                    continue
                out.append((mi, alias or os.path.basename(rel)))
    # 去重（同一个包可能出现在 test import 块里）
    seen, uniq = set(), []
    for mi, a in out:
        if (mi, a) in seen:
            continue
        seen.add((mi, a))
        uniq.append((mi, a))
    return uniq


def _mi_for(d):
    """去掉"自己的 .mi"（否则源码+自引用 mi = 重复定义 E0067）。"""
    rel = os.path.relpath(d, CORE)
    self_mi = os.path.join(BUNDLE, rel, os.path.basename(d) + ".mi")
    out, skip = [], False
    for t in MI:
        if skip:
            skip = False
            if t == self_mi:
                continue
        if t == "-i":
            skip = True
            out.append(t)
            continue
        out.append(t)
    return [t for t in out]


def compile_pkg(d):
    """把一个包目录下所有 .mbt 作为一个包编译（真实编译单元）。"""
    wd = CFG["wd"]
    names = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".mbt"):
            src = os.path.join(d, f)
            if os.path.getsize(src) > 400000:
                continue
            shutil.copy(src, wd)
            names.append(f)
    if not names:
        return {"path": d, "ok": False, "sig": "empty"}
    mi = []
    for m, al in pkg_imports(d):
        mi += ["-i", f"{m}:{al}"]
    rc, err = 2, b""
    for tgt in ("wasm-gc", "js"):
        argv = ([MOONC, "build-package"] + names +
                ["-o", "out.core", "-pkg", "fuzz/p", "-pkg-type", "library",
                 "-target", tgt, "-g", "-O0", "-workspace-path", "."] + mi)
        try:
            p = subprocess.run(argv, cwd=wd, capture_output=True, timeout=300)
            rc, err = p.returncode, p.stderr
        except subprocess.TimeoutExpired:
            rc, err = 124, b"timeout"
        if rc == 0 or b"E4156" not in err:
            break
    return {"path": d, "ok": rc == 0, "rc": rc, "sig": sig_of(rc, err),
            "nfiles": len(names)}


def harvest_pkgs(src, jsonpath, workers, limit):
    dirs = []
    for dp, _, fs in os.walk(src):
        if "moon.pkg" in fs:
            dirs.append(dp)
    dirs.sort()
    if limit:
        dirs = dirs[:limit]
    print(f"[real] {len(dirs)} package dirs from {src}", flush=True)
    with Pool(workers, initializer=w_init) as p:
        res = p.map(compile_pkg, dirs, chunksize=2)
    ok = [r for r in res if r["ok"]]
    hist = Counter(r["sig"] for r in res if not r["ok"])
    out = dict(src=src, n=len(res), ok=len(ok),
               runnable=round(len(ok) / max(len(res), 1), 4),
               errors=dict(hist.most_common(30)),
               files=[{k: r[k] for k in ("path", "ok", "sig")} for r in res])
    if jsonpath:
        json.dump(out, open(jsonpath, "w"), indent=1)
    print(f"[real] pkgs ok={len(ok)}/{len(res)} = {out['runnable']:.1%}")
    for k, v in hist.most_common(12):
        print(f"  {v:5d}  {k}")
    return out


FN_RE = re.compile(rb"(?m)^[ \t]*(?:pub\s+)?(?:async\s+)?fn\s+[A-Za-z_][A-Za-z0-9_]*")
TEST_RE = re.compile(rb"(?m)^[ \t]*test\s+\"[^\"]*\"")


def _brace_match(b, i):
    """b[i]=='{'，返回配对 '}' 的下标（跳过字符串/注释）。"""
    depth, j, n = 0, i, len(b)
    while j < n:
        c = b[j:j + 1]
        if c == b'"':
            j += 1
            while j < n and b[j:j + 1] != b'"':
                j += 2 if b[j:j + 1] == b"\\" else 1
        elif c == b"{" :
            depth += 1
        elif c == b"}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def fn_bodies(b):
    out = []
    for rx in (FN_RE, TEST_RE):
        for m in rx.finditer(b):
            k = b.find(b"{", m.end())
            if k < 0 or k - m.end() > 200:
                continue
            e = _brace_match(b, k)
            if e > k:
                out.append((k + 1, e))
    return out


GENTLE = [
    "int", "cmp", "bool", "dup", "del", "arith", "str",
]


def gentle_body(src: str, rng):
    """只碰函数体里的表达式/语句，不动签名和类型定义（接受型变异）。"""
    b = src.encode("utf-8", "replace")
    bodies = [x for x in fn_bodies(b) if 10 < x[1] - x[0] < 8000]
    if not bodies:
        return src
    s, e = rng.choice(bodies)
    body = b[s:e].decode("utf-8", "replace")
    kind = rng.choice(GENTLE)
    import re as _re
    if kind == "int":
        body = _re.sub(r"(?<![\w.])\d{1,6}(?![\w.])",
                       lambda m: str(rng.choice([0, 1, 2, 3, 7, 10, 42, 255, 256, 1024])),
                       body, count=1)
    elif kind == "cmp":
        body = _re.sub(r"(?<![=!<>])(==|!=|<=|>=|<|>)(?!=)",
                       lambda m: {"==": "!=", "!=": "==", "<": ">", ">": "<",
                                  "<=": ">=", ">=": "<="}[m.group(1)], body, count=1)
    elif kind == "bool":
        body = body.replace("true", "false", 1) if "true" in body else body.replace("false", "true", 1)
    elif kind == "dup":
        lines = body.split("\n")
        cand = [i for i, l in enumerate(lines) if l.strip() and "{" not in l and "}" not in l]
        if cand:
            i = rng.choice(cand)
            lines.insert(i, lines[i])
            body = "\n".join(lines)
    elif kind == "del":
        lines = body.split("\n")
        cand = [i for i, l in enumerate(lines) if l.strip() and "{" not in l and "}" not in l]
        if cand:
            lines.pop(rng.choice(cand))
            body = "\n".join(lines)
    elif kind == "arith":
        body = _re.sub(r"(?<=[\w)\]])\s*\+\s*(?=[\w(\[])",
                       lambda m: " - ", body, count=1)
    elif kind == "str":
        body = _re.sub(r'"[^"\\]{1,40}"', lambda m: '"' + m.group(0)[1:-1] + 'x"', body, count=1)
    return (b[:s] + body.encode("utf-8", "replace") + b[e:]).decode("utf-8", "replace")


BOOT = {}


def boot_init(seeds):
    BOOT["wd"] = tempfile.mkdtemp(prefix="boot_", dir="/tmp")
    BOOT["seeds"] = seeds


def boot_one(i):
    """取一个真程序，只变异函数体，编译通过就留在语料里（B 层自举）。"""
    import random
    rng = random.Random(0xB007 + i)
    src = BOOT["seeds"][i % len(BOOT["seeds"])]
    try:
        txt = open(src, encoding="utf-8", errors="ignore").read()
    except OSError:
        return {"i": i, "ok": False, "sig": "read", "path": None}
    if rng.random() < 0.75:
        mut = gentle_body(txt, rng)
    else:
        mut = MUT.mutate(txt, rng, BOOT["seeds"], body_only=True)
    wd = BOOT["wd"]
    dst = os.path.join(wd, f"m{i}.mbt")
    open(dst, "w", errors="replace").write(mut)
    argv = ([MOONC, "build-package", f"m{i}.mbt", "-o", "out.core",
             "-pkg", "fuzz/p", "-pkg-type", "library",
             "-target", "wasm-gc", "-g", "-O0", "-workspace-path", "."] + MI)
    try:
        p = subprocess.run(argv, cwd=wd, capture_output=True, timeout=120)
        rc, err = p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        rc, err = 124, b"timeout"
    return {"i": i, "ok": rc == 0, "rc": rc, "sig": sig_of(rc, err),
            "path": src, "text": mut if rc == 0 else None}


def bootstrap(seeds_dir, outdir, iters, workers, gens=2):
    seeds = sorted(os.path.join(seeds_dir, f) for f in os.listdir(seeds_dir)
                   if f.endswith(".mbt") and os.path.getsize(os.path.join(seeds_dir, f)) < 20000)
    if not seeds:
        print("no seeds")
        return
    print(f"[boot] gen0={len(seeds)} seeds, iters/gen={iters}", flush=True)
    stats = []
    pool = seeds
    for g in range(gens):
        with Pool(workers, initializer=boot_init, initargs=(pool,)) as p:
            res = p.map(boot_one, list(range(iters)), chunksize=8)
        ok = [r for r in res if r["ok"]]
        hist = Counter(r["sig"] for r in res if not r["ok"])
        rate = len(ok) / max(len(res), 1)
        stats.append({"gen": g, "iters": len(res), "ok": len(ok), "rate": round(rate, 4),
                      "errors": dict(hist.most_common(12))})
        print(f"[boot] gen{g}: ok={len(ok)}/{len(res)} = {rate:.1%}", flush=True)
        for k, v in hist.most_common(6):
            print(f"    {v:6d}  {k}")
        if outdir:
            d = os.path.join(outdir, f"gen{g}")
            os.makedirs(d, exist_ok=True)
            for r in ok:
                open(os.path.join(d, f"g{g}_{r['i']:05d}.mbt"), "w", errors="replace").write(r["text"])
            pool = sorted(os.path.join(d, f) for f in os.listdir(d))
    if outdir:
        json.dump(stats, open(os.path.join(outdir, "stats.json"), "w"), indent=1)
    return stats


def harvest(src, outdir, jsonpath, workers, limit):
    files = []
    for dp, _, fs in os.walk(src):
        for f in fs:
            if f.endswith(".mbt"):
                files.append(os.path.join(dp, f))
    files.sort()
    if limit:
        files = files[:limit]
    print(f"[real] {len(files)} files from {src}", flush=True)
    with Pool(workers, initializer=w_init) as p:
        res = p.map(compile_one, files, chunksize=4)
    ok = [r for r in res if r["ok"]]
    hist = Counter(r["sig"] for r in res if not r["ok"])
    if outdir:
        os.makedirs(outdir, exist_ok=True)
        for r in ok:
            rel = os.path.relpath(r["path"], src).replace(os.sep, "__")
            shutil.copy(r["path"], os.path.join(outdir, rel))
    out = dict(src=src, n=len(res), ok=len(ok),
               runnable=round(len(ok) / max(len(res), 1), 4),
               errors=dict(hist.most_common(30)),
               files=[{k: r[k] for k in ("path", "ok", "sig")} for r in res])
    if jsonpath:
        os.makedirs(os.path.dirname(jsonpath) or ".", exist_ok=True)
        json.dump(out, open(jsonpath, "w"), indent=1)
    print(f"[real] ok={len(ok)}/{len(res)} = {out['runnable']:.1%}")
    for k, v in hist.most_common(10):
        print(f"  {v:6d}  {k}")
    return out


def rate(d):
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(d) for f in fs
             if f.endswith(".mbt")]
    print(f"{len(files)} files")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["harvest", "pkgs", "bootstrap", "rate"])
    ap.add_argument("target")
    ap.add_argument("--src", default=os.path.expanduser("~/.moon/lib/core"))
    ap.add_argument("--out")
    ap.add_argument("--json")
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    if a.mode == "harvest":
        harvest(a.src, a.out, a.json, a.workers, a.limit)
    elif a.mode == "bootstrap":
        bootstrap(a.target, a.out, a.limit or 1000, a.workers)
    elif a.mode == "pkgs":
        harvest_pkgs(a.src, a.json, a.workers, a.limit)
    else:
        rate(a.target)


if __name__ == "__main__":
    main()
