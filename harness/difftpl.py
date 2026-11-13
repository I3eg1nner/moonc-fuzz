#!/usr/bin/env python3
"""差分测试流水线：模板 + 函数体变异 + 强制可运行门槛 + 跨后端比对。

设计目标（对着"1.5% 可运行率"这个痛点）：
  * 输入形态是"固定骨架 + 只改函数体"，因此 fn main / 输出语句永远在；
  * 门槛：wasm 与 js 都必须 编译通过、链接通过、运行不超时，才进入比对；
  * 输出确定性：模板里禁止 HashMap 迭代、时间、随机数；
  * 差分分类：先做数值/格式归一化，把"格式差异"和"真误编译"分开。

用法：
  python3 difftpl.py probe <file-or-dir>          # 第一步：手写探针
  python3 difftpl.py run --workers 64 --duration 300   # 模板 campaign
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutate as M  # noqa: E402

HOME = os.path.expanduser("~")
MOONC = os.path.join(HOME, ".moon/bin/moonc")
MOONRUN = os.path.join(HOME, ".moon/bin/moonrun")
CORE = os.path.join(HOME, ".moon/lib/core")
ROOT = "/data/audit/mbtfuzz"
ALL_PKGS = os.path.join(ROOT, "harness/all_pkgs.json")
MOON_PKG = os.path.join(ROOT, "harness/moon.pkg")
PKG = "fuzz/p"

CFG = {}


def bundles(target):
    return os.path.join(CORE, f"_build/{target}/release/bundle")


def cores(target):
    b = bundles(target)
    # 只取 bundle 顶层：moon 自己也是这个范围；递归会带进嵌套包的 core，
    # 造成 link-core 里符号冲突（实测 ICE: Key_not_found("$_M0L5inputS208")）
    return sorted(glob.glob(os.path.join(b, "*", "*.core")))


def run(cmd, cwd, timeout):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=CFG["env"])
        return dict(rc=p.returncode, out=p.stdout, err=p.stderr, timeout=False)
    except subprocess.TimeoutExpired:
        return dict(rc=None, out=b"", err=b"", timeout=True)


def compile_and_run(wd, src, target):
    """返回 dict(stage, ok, out, rc)。stage 指出卡在哪一步。"""
    path = os.path.join(wd, "in.mbt")
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    b = bundles(target)
    bp = [MOONC, "build-package", "in.mbt", "-o", f"{target}.core", "-pkg", PKG,
          "-pkg-type", "executable",
          "-i", f"{b}/builtin/builtin.mi:moonbitlang/core/builtin",
          "-i", f"{b}/prelude/prelude.mi:prelude",
          "-pkg-sources", f"{PKG}:.", "-target", target, "-g", "-O0",
          "-workspace-path", ".", "-all-pkgs", ALL_PKGS]
    r = run(bp, wd, CFG["compile_timeout"])
    if r["rc"] != 0 or r["timeout"]:
        return dict(stage="build", ok=False, out=b"", rc=r["rc"], err=r["err"][:2000])
    out = f"{target}.js" if target == "js" else f"{target}.wasm"
    lk = [MOONC, "link-core", *cores(target), f"{target}.core", "-main", PKG, "-o", out,
          "-pkg-config-path", MOON_PKG, "-pkg-sources", f"{PKG}:.",
          "-pkg-sources", f"moonbitlang/core:{CORE}", "-target", target, "-g", "-O0"]
    if target == "wasm":
        lk.append("-wasi")
    r = run(lk, wd, CFG["compile_timeout"])
    if r["rc"] != 0 or r["timeout"]:
        return dict(stage="link", ok=False, out=b"", rc=r["rc"], err=r["err"][:2000])
    cmd = ["node", out] if target == "js" else [MOONRUN, out]
    r = run(cmd, wd, CFG["run_timeout"])
    return dict(stage="run", ok=(r["rc"] == 0 and not r["timeout"]), out=r["out"],
                rc=r["rc"], err=r["err"][:2000], timeout=r["timeout"])


NUM_RE = re.compile(rb"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def normalize(out: bytes) -> bytes:
    """只归一"表示形式"的差异，不做任何会吞掉值的操作。

    修订（2026-11-11，codex review 指出）：
    * 旧版对整个输出 `.lower()`，导致 "A" 与 "a" 被判成 FORMAT_DIFF —— 真实差异被吞；
    * 旧版把所有数字过 float，2^53 以上的整数（9007199254740992 / ...93）会塌成同一个值。
    现在：整数用 int 精确保留，只有带小数点/指数的才走 float；nan 只按 token 归一。
    """

    def f(m):
        s = m.group(0)
        try:
            if b"." in s or b"e" in s or b"E" in s:
                v = float(s)
                if v != v:
                    return b"nan"
                if v == 0:
                    return b"0"
                if v == int(v) and abs(v) < 2**53:
                    return str(int(v)).encode()
                return repr(v).encode()
            return str(int(s)).encode()
        except Exception:
            return s

    return re.sub(rb"(?i)\bnan\b", b"nan", NUM_RE.sub(f, out))


def diff_one(wd, src):
    """逐对比较所有后端，不再"只看 wasm/js，其它情况降级成 WASM_*"。

    修订（2026-11-11）：旧版里 wasm/js 失败、wasm-gc 成功会被打成 WASM_RUN，
    跨后端差异丢失；现在对任意两两组合分类并标注是哪一对。
    """
    targets = ["wasm", "js"] + (["wasm-gc"] if CFG.get("triple") else [])
    res = {t: compile_and_run(wd, src, t) for t in targets}
    pairs, kinds = [], []
    names = list(res)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            x, y = names[i], names[j]
            a, b = res[x], res[y]
            pair = f"{x}|{y}"
            if a["ok"] and b["ok"]:
                if a["out"] == b["out"]:
                    kinds.append("SAME")
                elif normalize(a["out"]) == normalize(b["out"]):
                    kinds.append(f"FORMAT_DIFF:{pair}")
                else:
                    kinds.append(f"REAL_DIFF:{pair}")
                    pairs.append((f"REAL_DIFF:{pair}", a, b))
            elif a["ok"] and b["stage"] == "run":
                kinds.append(f"TRAP_DIFF:{pair}")
                pairs.append((f"TRAP_DIFF:{pair}", a, b))
            elif b["ok"] and a["stage"] == "run":
                kinds.append(f"TRAP_DIFF:{pair}")
                pairs.append((f"TRAP_DIFF:{pair}", b, a))
            elif a["ok"] and b["stage"] in ("build", "link"):
                kinds.append(f"BUILD_DIFF:{pair}")
                pairs.append((f"BUILD_DIFF:{pair}", a, b))
            elif b["ok"] and a["stage"] in ("build", "link"):
                kinds.append(f"BUILD_DIFF:{pair}")
                pairs.append((f"BUILD_DIFF:{pair}", b, a))
            else:
                kinds.append(f"BOTH_FAIL:{pair}")
    if not pairs:
        return dict(kind="SAME" if kinds and all(k == "SAME" for k in kinds) else kinds[0],
                    a=res[names[0]], b=res[names[-1]], note=",".join(kinds))
    k, a, b = pairs[0]
    return dict(kind=k, a=a, b=b, note=",".join(kinds))

def probe(paths):
    wd = tempfile.mkdtemp(prefix="dt_", dir="/tmp")
    rows = []
    for p in paths:
        src = open(p, encoding="utf-8", errors="replace").read()
        t0 = time.time()
        r = diff_one(wd, src)
        a, b = r["a"], r["b"]
        kind = r["kind"]
        rows.append((os.path.basename(p), kind, a["stage"], (b or {}).get("stage", "-"),
                     round(time.time() - t0, 2),
                     a["out"][:40].decode("utf-8", "replace").replace("\n", "\\n")))
        if kind in ("REAL_DIFF", "FORMAT_DIFF"):
            rows.append(("  wasm:", "", "", "", "", a["out"][:200].decode("utf-8", "replace").replace("\n", "|")))
            rows.append(("  js:  ", "", "", "", "", b["out"][:200].decode("utf-8", "replace").replace("\n", "|")))
    print(f"{'program':16} {'result':12} {'wasm':6} {'js':6} {'s':>5}  stdout")
    for r in rows:
        print(f"{r[0]:16} {r[1]:12} {r[2]:6} {r[3]:6} {str(r[4]):>5}  {r[5]}")


def rate_worker(path):
    wd = tempfile.mkdtemp(prefix="dtr_", dir="/tmp")
    try:
        src = open(path, encoding="utf-8", errors="surrogateescape").read()
    except OSError:
        return "READ"
    try:
        return diff_one(wd, src)["kind"]
    finally:
        shutil.rmtree(wd, ignore_errors=True)


def rate(paths, workers):
    with Pool(workers) as p:
        kinds = p.map(rate_worker, paths, chunksize=2)
    from collections import Counter
    c = Counter(kinds)
    n = len(kinds)
    ok = c.get("SAME", 0) + c.get("REAL_DIFF", 0) + c.get("FORMAT_DIFF", 0) + c.get("TRAP_DIFF", 0)
    print(f"n={n} 两类后端都跑通={ok} ({100*ok/max(n,1):.1f}%)")
    for k, v in c.most_common():
        print(f"  {k:16} {v:5d}  {100*v/max(n,1):5.1f}%")


# ---------------------------------------------------------------- templates
BODY_RE = re.compile(r"(fn\s+compute\s*\([^)]*\)\s*(?:->\s*[^{]+)?\{)", re.S)


INT_LIT = re.compile(r"(?<![\w.])-?\d{1,18}(?![\w.])")
FLT_LIT = re.compile(r"(?<![\w.])-?\d+\.\d+(?:[eE][-+]?\d+)?")
STR_LIT = re.compile(r'"(?:\\.|[^"\\])*"')
CMP = {"==": "!=", "!=": "==", "<": "<=", "<=": "<", ">": ">=", ">=": ">"}
ARITH = ["+", "-", "*", "%", "&", "|", "^", "<<", ">>"]
BOOL = {"&&": "||", "||": "&&"}
EDGE_INT = ["0", "1", "-1", "2147483647", "-2147483648", "255", "65535", "1073741824"]
EDGE_FLT = ["0.0", "-0.0", "1.0", "-1.0", "1e308", "-1e308", "0.1", "1.0e-300"]
EDGE_STR = ['""', '"a"', '"中"', '"\\u{1F600}"', '"x\\ny"', '"\\t"']


def gentle_body(body, rng):
    """只做"类型安全"的变异：字面量边界替换、同类型运算符互换、语句复制。"""
    kind = rng.random()
    if kind < 0.45:
        ms = list(INT_LIT.finditer(body))
        if ms:
            m = rng.choice(ms)
            return body[:m.start()] + rng.choice(EDGE_INT) + body[m.end():]
    if kind < 0.6:
        ms = list(FLT_LIT.finditer(body))
        if ms:
            m = rng.choice(ms)
            return body[:m.start()] + rng.choice(EDGE_FLT) + body[m.end():]
    if kind < 0.72:
        ms = list(STR_LIT.finditer(body))
        if ms:
            m = rng.choice(ms)
            return body[:m.start()] + rng.choice(EDGE_STR) + body[m.end():]
    if kind < 0.88:
        for op, rep in list(CMP.items()) + list(BOOL.items()):
            idx = [i for i in range(len(body)) if body.startswith(op, i)]
            if idx:
                i = rng.choice(idx)
                return body[:i] + rep + body[i + len(op):]
        return body
    # 复制一个配平的小块（语句级）
    bs = [b for b in M._boundaries(body) if 2 < b[1] - b[0] < 300]
    if bs:
        a, b = rng.choice(bs)
        return body[:b + 1] + "\n" + body[a:b + 1] + body[b + 1:]
    return body


def mutate_body(src, rng):
    """只改 compute 函数体，保留签名与 main。"""
    m = BODY_RE.search(src)
    if not m:
        return src
    start = m.end()
    depth, i = 1, start
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    end = i - 1
    body = src[start:end]
    for _ in range(rng.randint(1, 2)):
        if rng.random() < CFG.get("gentle", 0.85):
            body = gentle_body(body, rng)
        else:
            fn = rng.choice([M.m_replace_token, M.m_insert_stmt, M.m_wrap, M.m_dup_block])
            try:
                body = fn(body, rng)
            except Exception:
                pass
    return src[:start] + body + src[end:]


def tpl_worker(idx):
    rng = random.Random(20261111 + idx)
    tpls = CFG["templates"]
    wd = tempfile.mkdtemp(prefix="dtw_", dir="/tmp")
    stats = {"exec": 0, "same": 0, "real": 0, "fmt": 0, "trap": 0,
             "build": 0, "link": 0, "run": 0, "new": 0, "tpl": 0}
    end = time.time() + CFG["duration"]
    outdir = os.path.join(CFG["out"], "diffs")
    os.makedirs(outdir, exist_ok=True)
    while time.time() < end:
        src = mutate_body(rng.choice(tpls), rng)
        stats["exec"] += 1
        stats["tpl"] += 1
        r = diff_one(wd, src)
        k = r["kind"]
        if k == "SAME":
            stats["same"] += 1
        elif k == "FORMAT_DIFF":
            stats["fmt"] += 1
        elif k == "REAL_DIFF":
            stats["real"] += 1
        elif k == "TRAP_DIFF":
            stats["trap"] += 1
        elif k.startswith("WASM_"):
            stats["build" if k == "WASM_BUILD" else ("link" if k == "WASM_LINK" else "run")] += 1
        elif k.startswith("JS_"):
            stats["build" if k == "JS_BUILD" else ("link" if k == "JS_LINK" else "run")] += 1
        if k in ("REAL_DIFF", "FORMAT_DIFF", "TRAP_DIFF"):
            # 语义去重：同一根因（同样的一对输出）只存一份，别按内容哈希
            import hashlib
            ao = normalize(r["a"]["out"])
            bo = normalize((r["b"] or {}).get("out", b""))
            h = hashlib.sha1(k.encode() + b"|" + ao + b"|" + bo).hexdigest()[:12]
            d = os.path.join(outdir, k, h)
            if not os.path.isdir(d):
                os.makedirs(d, exist_ok=True)
                open(os.path.join(d, "case.mbt"), "w", encoding="utf-8").write(src)
                json.dump({"kind": k,
                           "wasm": r["a"]["out"][:4000].decode("utf-8", "replace"),
                           "js": (r["b"] or {}).get("out", b"")[:4000].decode("utf-8", "replace")},
                          open(os.path.join(d, "meta.json"), "w"), indent=2)
                stats["new"] += 1
        if stats["exec"] % 50 == 0:
            json.dump(stats, open(os.path.join(CFG["out"], f"dstats{idx}.json"), "w"))
    json.dump(stats, open(os.path.join(CFG["out"], f"dstats{idx}.json"), "w"))
    return stats


def load_templates(d):
    out = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".mbt"):
            out.append(open(os.path.join(d, f), encoding="utf-8").read())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["probe", "run", "rate"])
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--templates", default=os.path.join(ROOT, "templates"))
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--duration", type=int, default=120)
    ap.add_argument("--out", default=os.path.join(ROOT, "out/diff"))
    ap.add_argument("--compile-timeout", type=int, default=40)
    ap.add_argument("--run-timeout", type=int, default=20)
    ap.add_argument("--triple", action="store_true", help="wasm vs js 之后再加入 wasm-gc")
    a = ap.parse_args()
    CFG.update(env=dict(os.environ, OCAMLRUNPARAM="b"), out=a.out, triple=a.triple,
               compile_timeout=a.compile_timeout, run_timeout=a.run_timeout)
    os.makedirs(a.out, exist_ok=True)

    if a.mode == "rate":
        d = a.paths[0]
        paths = [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".mbt")][:a.limit]
        return rate(paths, a.workers)

    if a.mode == "probe":
        paths = a.paths
        if len(paths) == 1 and os.path.isdir(paths[0]):
            paths = [os.path.join(paths[0], f) for f in sorted(os.listdir(paths[0]))
                     if f.endswith(".mbt")]
        return probe(paths)

    CFG["templates"] = load_templates(a.templates)
    if not CFG["templates"]:
        print("no templates")
        return
    CFG["duration"] = a.duration
    print(f"[diff] templates={len(CFG['templates'])} workers={a.workers} duration={a.duration}s")
    with Pool(a.workers, initializer=lambda: None) as p:
        res = p.map(tpl_worker, range(a.workers))
    agg = {}
    for r in res:
        for k, v in r.items():
            agg[k] = agg.get(k, 0) + v
    n = max(agg.get("exec", 1), 1)
    runnable = agg.get("same", 0) + agg.get("real", 0) + agg.get("fmt", 0) + agg.get("trap", 0)
    print(f"[diff] exec={agg.get('exec')} runnable={runnable} ({100*runnable/n:.1f}%) "
          f"same={agg.get('same')} real_diff={agg.get('real')} fmt_diff={agg.get('fmt')}")
    print(f"[diff] 失败分布: build={agg.get('build')} link={agg.get('link')} run={agg.get('run')}")
    print(f"[diff] 差分候选/万次执行: {10000*agg.get('real',0)/n:.2f} (real), "
          f"{10000*agg.get('fmt',0)/n:.2f} (format), {10000*agg.get('trap',0)/n:.2f} (trap)")


if __name__ == "__main__":
    main()
