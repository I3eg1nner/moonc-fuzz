#!/usr/bin/env python3
"""mbtfuzz — MoonBit 编译器黑盒/灰盒 fuzz 驱动。

设计要点（针对闭源但带 DWARF/OCaml 符号的 moonc）：
  T1  moonc syncheck        : lexer+parser+语法层检查, ~10ms, 吞吐优先
  T2  moonc build-package   : typer -> core IR -> wasm 代码生成, ~30ms
  T3  moonc link-core + 运行 : 链接 + moonrun 执行, 以及 wasm/js 差分

Oracle:
  * 信号崩溃 / exit 199("Oops, the compiler has encountered") / OCaml 未捕获异常
  * 超时（parser 卡死、指数回溯）
  * 多后端差分（wasm vs js 的接受性与 stdout 不一致）
  * 语料新颖性：新诊断码组合 / 新"接受"程序 -> 入队
"""
from __future__ import annotations

import argparse
import hashlib
import glob
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import traceback
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutate as M  # noqa: E402

HOME = os.path.expanduser("~")
MOONC = os.path.join(HOME, ".moon/bin/moonc")
MOONRUN = os.path.join(HOME, ".moon/bin/moonrun")
CORE = os.path.join(HOME, ".moon/lib/core")
BUNDLES = {t: os.path.join(CORE, f"_build/{t}/release/bundle") for t in ("wasm", "js", "wasm-gc")}
PKG = "minie135/tpl/cmd/main"

# 每种输入形态对应一个入口。mbt 走完整三级流水线，其余只做"解析器"级别 fuzz。
MODES = {
    "mbt":   dict(fname="in.mbt",    deep=True),
    "pkg":   dict(fname="moon.pkg",  deep=False),
    "mod":   dict(fname="moon.mod",  deep=False),
    "mbtmd": dict(fname="in.mbt.md", deep=False),
    "mbtx":  dict(fname="in.mbtx",   deep=False),
    "mbti":  dict(fname="in.mbti",   deep=False),
}
ROOT = "/data/audit/mbtfuzz"
ALL_PKGS = os.path.join(ROOT, "harness/all_pkgs.json")
MOON_PKG = os.path.join(ROOT, "harness/moon.pkg")

ENV = dict(os.environ)
ENV["OCAMLRUNPARAM"] = "b"  # 打开 OCaml backtrace，便于崩溃归并
ENV.pop("MOON_NEW_ENGINE", None)

CFG = {}


# ---------------------------------------------------------------- execution
def run(cmd, cwd, timeout):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=ENV)
        return dict(rc=p.returncode, out=p.stdout, err=p.stderr,
                    ms=int((time.time() - t0) * 1000), timeout=False)
    except subprocess.TimeoutExpired:
        return dict(rc=None, out=b"", err=b"", ms=int((time.time() - t0) * 1000), timeout=True)
    except OSError as e:
        return dict(rc=-999, out=b"", err=str(e).encode(), ms=0, timeout=False)


def text_of(st):
    return (st["err"] + st["out"]).decode("utf-8", "replace")


ICE_MARK = "Oops, the compiler has encountered"


def classify(st):
    """返回 (kind, detail) —— kind in {None,'ICE','SIG','OCAML_EXN','STACK','HANG','ASSERT'}"""
    if st["timeout"]:
        return "HANG", "timeout"
    t = text_of(st)
    if ICE_MARK in t:
        m = re.search(r"^Error: (.*)$", t, re.M)
        return "ICE", (m.group(1)[:200] if m else "ice")
    if "Fatal error: exception" in t:
        m = re.search(r"Fatal error: exception (.*)", t)
        return "OCAML_EXN", (m.group(1)[:200] if m else "exn")
    if "Stack overflow" in t or "Stack_overflow" in t:
        return "STACK", "stack overflow"
    if "Assert_failure" in t:
        return "ASSERT", "assert"
    if st["rc"] is not None and st["rc"] < 0:
        try:
            name = signal.Signals(-st["rc"]).name
        except Exception:
            name = str(-st["rc"])
        return "SIG", name
    return None, ""


def backtrace_frames(t, limit=4):
    frames = re.findall(r"(?:Raised at|Called from) (\S+) in file \"([^\"]+)\"", t)
    return ["%s@%s" % (f[0], os.path.basename(f[1])) for f in frames[:limit]]


def sig_hash(stage, kind, detail, frames):
    key = "|".join([stage, kind, detail] + frames)
    return hashlib.sha1(key.encode()).hexdigest()[:16], key


# ---------------------------------------------------------------- stages
def std_flags(target):
    b = BUNDLES[target]
    return [
        "-i", f"{b}/builtin/builtin.mi:moonbitlang/core/builtin",
        "-i", f"{b}/prelude/prelude.mi:prelude",
    ]


def with_main(src):
    if re.search(r"\bfn\s+main\b", src):
        return src
    return src + "\n\nfn main { () }\n"


def stage1(wd, src):
    mode = CFG["mode"]
    fname = MODES[mode]["fname"]
    path = os.path.join(wd, fname)
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    if mode == "mbti":
        b = BUNDLES["wasm"]
        cmd = [MOONC, "build-interface", fname, "-o", "out.mi",
               "-i", f"{b}/builtin/builtin.mi:moonbitlang/core/builtin",
               "-i", f"{b}/prelude/prelude.mi:prelude"]
    elif mode == "mbtx":
        cmd = [MOONC, "syncheck", "-mbtx-frontmatter", "true", fname]
    else:
        cmd = [MOONC, "syncheck", "-error-format", "json", fname]
    return run(cmd, wd, CFG["t1_timeout"])


def stage2(wd, src, target="wasm"):
    path = os.path.join(wd, "in.mbt")
    src = with_main(src)
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    cmd = [MOONC, "build-package", "in.mbt", "-o", f"out_{target}.core",
           "-pkg", PKG, "-pkg-type", "executable", *std_flags(target),
           "-pkg-sources", f"{PKG}:.", "-target", target, "-g", "-O0",
           "-workspace-path", ".", "-all-pkgs", ALL_PKGS]
    return run(cmd, wd, CFG["t2_timeout"])


def stage3(wd, target="wasm"):
    b = BUNDLES[target]
    cores = sorted(glob.glob(os.path.join(b, "*", "*.core")))
    out = f"out_{target}.wasm" if target == "wasm" else f"out_{target}.js"
    cmd = [MOONC, "link-core", *cores, f"out_{target}.core", "-main", PKG, "-o", out,
           "-pkg-config-path", MOON_PKG, "-pkg-sources", f"{PKG}:.",
           "-pkg-sources", f"moonbitlang/core:{CORE}", "-target", target, "-g", "-O0"]
    if target == "wasm":
        cmd.append("-wasi")
    st = run(cmd, wd, CFG["t2_timeout"])
    if st["rc"] != 0 or st["timeout"]:
        return st, None
    path = os.path.join(wd, out)
    if target == "wasm":
        ex = run([MOONRUN, out], wd, CFG["t3_timeout"])
    else:
        ex = run(["node", out], wd, CFG["t3_timeout"])
    return st, ex


# ---------------------------------------------------------------- finding I/O
def save_finding(stage, kind, detail, frames, src, st, extra=None):
    h, key = sig_hash(stage, kind, detail, frames)
    d = os.path.join(CFG["out"], "findings", stage, f"{kind}", h)
    if os.path.isdir(d):
        return False
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "case.mbt"), "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    meta = dict(stage=stage, kind=kind, detail=detail, frames=frames, signature=key,
                rc=st["rc"], timeout=st["timeout"], ms=st["ms"], found_at=time.time(),
                moonc=CFG.get("moonc_version", ""))
    meta.update(extra or {})
    with open(os.path.join(d, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(d, "stderr.txt"), "wb") as f:
        f.write(st["err"][-20000:])
    return True


def note_signature(kind, sig, src):
    """无崩溃但有新行为签名 -> 入语料队列（原子 mkdir 去重）。"""
    d = os.path.join(CFG["out"], "sigs", kind)
    os.makedirs(d, exist_ok=True)
    try:
        os.mkdir(os.path.join(d, sig))
    except FileExistsError:
        return False
    q = os.path.join(CFG["out"], "corpus")
    h = hashlib.sha1(src.encode("utf-8", "surrogateescape")).hexdigest()[:16]
    with open(os.path.join(q, h + ".mbt"), "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    return True


# ---------------------------------------------------------------- corpus
SEED_EXT = {
    "mbt": (".mbt",), "pkg": ("moon.pkg",), "mod": ("moon.mod",),
    "mbtmd": (".mbt.md",), "mbtx": (".mbtx",), "mbti": (".mbti",),
}


def load_corpus():
    seeds = []
    exts = SEED_EXT[CFG["mode"]]
    for dp, _, fs in os.walk(os.path.join(ROOT, "seeds")):
        for f in fs:
            if f.endswith(exts):
                p = os.path.join(dp, f)
                try:
                    if os.path.getsize(p) < 12000:
                        with open(p, encoding="utf-8", errors="replace") as fh:
                            seeds.append(fh.read())
                except OSError:
                    pass
    return seeds


def corpus_pool():
    pool = []
    d = os.path.join(CFG["out"], "corpus")
    try:
        names = os.listdir(d)
    except OSError:
        names = []
    rng = random.Random()
    for n in rng.sample(names, min(len(names), 400)):
        try:
            with open(os.path.join(d, n), encoding="utf-8", errors="replace") as f:
                pool.append(f.read())
        except OSError:
            pass
    return pool


# ---------------------------------------------------------------- minimization
def minimize(src, runner, wd, rounds=3):
    """行级 ddmin：删掉不改变崩溃特征的行。"""
    lines = src.splitlines(keepends=True)
    if len(lines) < 2:
        return src
    best = src
    for _ in range(rounds):
        changed = False
        chunk = max(1, len(lines) // 2)
        while chunk >= 1:
            i = 0
            while i < len(lines):
                cand = "".join(lines[:i] + lines[i + chunk:])
                if cand.strip() and runner(cand, wd):
                    lines = lines[:i] + lines[i + chunk:]
                    changed = True
                else:
                    i += chunk
            chunk //= 2
        best = "".join(lines)
        if not changed:
            break
    return best


# ---------------------------------------------------------------- worker
def worker_init():
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    wd = tempfile.mkdtemp(prefix="mbtf_", dir="/tmp")
    CFG["wd"] = wd


def acceptable(st):
    """T2 的"可继续"判定：无错，或仅有 E4067（缺 main，语料多为库文件）。"""
    if st["timeout"] or st["rc"] is None:
        return False
    if st["rc"] == 0:
        return True
    codes = set(re.findall(r"\[([EW]\d{4})\]", st["err"].decode("utf-8", "replace")))
    return bool(codes) and codes <= {"E4067"}


def interesting_signature(st):
    """从 stderr 提取行为签名：诊断码集合 + 是否接受 + 顶层结构大小。"""
    t = st["err"].decode("utf-8", "replace")
    codes = sorted(set(re.findall(r"\[([EW]\d{4})\]", t)))
    toplevel = ""
    m = re.search(r'"toplevel":\{[^}]*\}', st["out"].decode("utf-8", "replace"))
    if m:
        toplevel = m.group(0)[:120]
    return "|".join(["ACC" if st["rc"] == 0 else "ERR"] + codes) + toplevel


def one_iteration(args):
    src, seed_hint = args
    wd = CFG["wd"]
    rng = random.Random()
    src = M.mutate(src, rng, CFG.get("pool_cache") or [], CFG.get("body_only", False))
    stats = {"it": 1, "t1": 0, "t2": 0, "t3": 0, "crash": 0, "new": 0}
    try:
        for f in ("in.mbt", "out_wasm.core", "out_js.core", "out_wasm.wasm",
                  "out_js.js", "out_native.core"):
            try:
                os.unlink(os.path.join(wd, f))
            except OSError:
                pass

        st = stage1(wd, src)
        stats["t1"] = 1
        kind, detail = classify(st)
        frames = backtrace_frames(text_of(st)) if kind else []
        if kind:
            stats["crash"] = 1 if save_finding("t1", kind, detail, frames, src, st) else 0
            return stats
        if MODES[CFG["mode"]]["deep"] and st["rc"] == 0 and rng.random() < CFG["p_deep"]:
            st2 = stage2(wd, src, "wasm")
            stats["t2"] = 1
            kind, detail = classify(st2)
            frames = backtrace_frames(text_of(st2)) if kind else []
            if kind:
                stats["crash"] = 1 if save_finding("t2", kind, detail, frames, src, st2) else 0
                return stats
            core_ok = os.path.exists(os.path.join(wd, "out_wasm.core"))
            if st2["rc"] == 0 and core_ok and rng.random() < CFG["p_run"]:
                st3, ex = stage3(wd, "wasm")
                stats["t3"] = 1
                kind, detail = classify(st3)
                if kind:
                    frames = backtrace_frames(text_of(st3)) if kind else []
                    save_finding("t3-link", kind, detail, frames, src, st3)
                    stats["crash"] = 1
                if ex is not None:
                    k2, d2 = classify(ex)
                    if k2:
                        frames = backtrace_frames(text_of(ex)) if k2 else []
                        stats["crash"] = 1 if save_finding("t3-run", k2, d2, frames, src, ex) else 0
                    # 差分：wasm 能跑则比对 js
                    if CFG["diff"] and st2["rc"] == 0:
                        st2j = stage2(wd, src, "js")
                        if st2j["rc"] == 0:
                            _, exj = stage3(wd, "js")
                            if exj is not None and not exj["timeout"]:
                                a = ex["out"].strip()
                                b = exj["out"].strip()
                                if a != b or (ex["rc"] != exj["rc"]):
                                    stats["crash"] = 1 if save_finding(
                                        "diff", "DIFF", "wasm!=js", [], src, ex,
                                        dict(wasm_out=a[:2000].decode("utf-8", "replace"),
                                             js_out=b[:2000].decode("utf-8", "replace"),
                                             wasm_rc=ex["rc"], js_rc=exj["rc"])) else 0
        sig = interesting_signature(st)
        if note_signature("s1", sig, src):
            stats["new"] = 1
    except Exception:
        stats["err"] = traceback.format_exc()[-500:]
    return stats


def worker_loop(idx):
    rng = random.Random()
    local = {"it": 0, "t1": 0, "t2": 0, "t3": 0, "crash": 0, "new": 0}
    last_pool = 0
    t_end = time.time() + CFG["duration"]
    stats_path = os.path.join(CFG["out"], "stats", f"w{idx}.json")
    while time.time() < t_end:
        if time.time() - last_pool > 20 or not CFG.get("pool_cache"):
            CFG["pool_cache"] = corpus_pool() or CFG["seeds"]
            last_pool = time.time()
        base = rng.choice(CFG["pool_cache"] + CFG["seeds"])
        try:
            s = one_iteration((base, None))
        except Exception:
            s = {"it": 1}
        for k in local:
            local[k] += s.get(k, 0)
        if local["it"] % 25 == 0:
            local["elapsed"] = int(CFG["duration"] - (t_end - time.time()))
            tmp = stats_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(local, f)
            os.replace(tmp, stats_path)
    local["elapsed"] = CFG["duration"]
    with open(stats_path, "w") as f:
        json.dump(local, f)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=max(1, os.cpu_count() // 2))
    ap.add_argument("--duration", type=int, default=600, help="seconds")
    ap.add_argument("--p-deep", type=float, default=0.25, help="进入 T2 的概率")
    ap.add_argument("--p-run", type=float, default=0.15, help="进入 T3 的概率")
    ap.add_argument("--diff", action="store_true", help="对可运行程序做 wasm/js 差分")
    ap.add_argument("--body-only", action="store_true", help="85%% 的变异只改函数体（T2 定向）")
    ap.add_argument("--t1-timeout", type=int, default=8)
    ap.add_argument("--t2-timeout", type=int, default=25)
    ap.add_argument("--t3-timeout", type=int, default=25)
    ap.add_argument("--mode", default="mbt", choices=list(MODES))
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--replay", help="只跑单个文件，打印各阶段结果")
    a = ap.parse_args()

    if a.mode != "mbt":
        a.out = os.path.join(a.out, a.mode)
    CFG.update(dict(body_only=a.body_only, mode=a.mode, workers=a.workers, duration=a.duration, p_deep=a.p_deep,
                    p_run=a.p_run, diff=a.diff, out=a.out,
                    t1_timeout=a.t1_timeout, t2_timeout=a.t2_timeout,
                    t3_timeout=a.t3_timeout))
    for d in ("findings", "sigs", "corpus", "stats"):
        os.makedirs(os.path.join(a.out, d), exist_ok=True)
    # 每次运行前清空统计，避免与历史运行相加
    for f in os.listdir(os.path.join(a.out, "stats")):
        if f.endswith(".json"):
            try:
                os.unlink(os.path.join(a.out, "stats", f))
            except OSError:
                pass
    try:
        CFG["moonc_version"] = subprocess.run([MOONC, "-v"], capture_output=True,
                                              text=True).stdout.strip()[:200]
    except Exception:
        CFG["moonc_version"] = "?"

    if a.replay:
        wd = tempfile.mkdtemp(prefix="mbtf_replay_", dir="/tmp")
        src = open(a.replay, encoding="utf-8", errors="surrogateescape").read()
        for name, fn in (("T1 syncheck", stage1), ("T2 build-package", stage2)):
            st = fn(wd, src) if name.startswith("T1") else fn(wd, src, "wasm")
            print(f"== {name}: rc={st['rc']} {st['ms']}ms")
            print(text_of(st)[:3000])
        return

    CFG["seeds"] = load_corpus()
    if not CFG["seeds"]:
        print("no seeds")
        return
    print(f"[mbtfuzz] mode={a.mode} moonc={CFG['moonc_version']} seeds={len(CFG['seeds'])} "
          f"workers={a.workers} duration={a.duration}s p_deep={a.p_deep} diff={a.diff}")

    t0 = time.time()
    with Pool(a.workers, initializer=worker_init) as p:
        async_res = p.map_async(worker_loop, range(a.workers))
        while not async_res.ready():
            time.sleep(5)
            agg = agg_stats(a.out)
            el = time.time() - t0
            rate = agg["it"] / max(el, 1)
            print(f"[{int(el):5d}s] it={agg['it']:8d} ({rate:6.1f}/s) t2={agg['t2']} "
                  f"t3={agg['t3']} crashes={agg['crash']} new={agg['new']}", flush=True)
        async_res.get()
    agg = agg_stats(a.out)
    print(f"[done] {json.dumps(agg)}")
    print(f"[findings] {len(os.listdir(os.path.join(a.out, 'findings', 't1', 'ICE'))) if os.path.isdir(os.path.join(a.out,'findings','t1','ICE')) else 0} t1-ICE")


def agg_stats(out):
    agg = {"it": 0, "t1": 0, "t2": 0, "t3": 0, "crash": 0, "new": 0}
    d = os.path.join(out, "stats")
    for f in os.listdir(d):
        if not f.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, f)) as fh:
                s = json.load(fh)
        except Exception:
            continue
        for k in agg:
            agg[k] += s.get(k, 0)
    return agg


if __name__ == "__main__":
    main()
