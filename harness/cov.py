#!/usr/bin/env python3
"""覆盖率测量：给 moonc 算"真正的"覆盖率。

两种粒度，服务两个不同目的：

1) `edges` —— AFL++ QEMU 模式（afl-showmap -Q）
   * 定义：对每个被翻译执行的 TB，取 cur_loc = hash(pc) & (MAP_SIZE-1)，
     边 idx = cur_loc ^ (prev_loc) ，prev_loc = cur_loc >> 1（classic AFL edge）。
     输入覆盖 = bitmap 中非零桶的集合；语料覆盖 = 并集。
   * 用途：在线引导 fuzz（~4-20 exec/s/core），hash 有碰撞，桶数 2^16。
   * 报告口径：unique slots、slots/exec、并集增长曲线、槽位利用率。

2) `funcs` —— QEMU user-mode `-d exec` trace + nm 符号化
   * 定义：一次执行命中的 moonc 函数集合 F(exe) = { func(pc) | pc ∈ TB_pcs }。
     语料覆盖 = ∪F；函数总数取 nm 里 T/t/W/w 符号（30576 个）。
   * 用途：离线测量语料"打到了编译器多少代码"，无碰撞、可解释。
   * 代价：~100x slowdown，只适合抽样。

用法：
  python3 cov.py edges seeds --limit 300 --out out/cov_seeds.json
  python3 cov.py funcs out/corpus --limit 300 --out out/cov_corpus.json
  python3 cov.py report out/cov_*.json
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
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import symbolize  # noqa: E402

MOONC = os.path.expanduser("~/.moon/bin/moonc")
AFL_SHOWMAP = "/tmp/AFLplusplus/afl-showmap"
AFL_QEMU = "/tmp/AFLplusplus/afl-qemu-trace"
# bitmap 大小：默认 64K。设 MB_MAP_SIZE=1048576 可避开哈希碰撞（QEMU 模式要同时
# 给 afl-showmap 和 guest 传 AFL_MAP_SIZE / AFL_QEMU_MAP_SIZE）。
MAP_SIZE = int(os.environ.get("MB_MAP_SIZE", "65536"))

CORE_BUNDLE = os.path.expanduser("~/.moon/lib/core/_build/wasm-gc/release/bundle")


def core_mi_args():
    """core 全部 .mi，用短别名（@array / @string …），供真程序单文件编译。"""
    out, seen = [], set()
    for dp, _, fs in os.walk(CORE_BUNDLE):
        rel = os.path.relpath(dp, CORE_BUNDLE).replace(os.sep, "/")
        for f in fs:
            if not f.endswith(".mi"):
                continue
            # 别名必须是源码里实际写的包名：顶层是 `array`，子包是 `encoding/utf8`
            alias = f[:-3] if rel == "." else rel
            if alias in seen:
                continue
            seen.add(alias)
            out.append(f"-i {os.path.join(dp, f)}:{alias}")
    out.sort()
    return out

CFG = {}
PC_RE = re.compile(rb"\[[0-9a-f]+/([0-9a-f]+)/")


def list_inputs(d: str, limit: int, suffixes):
    files = []
    for dp, _, fs in os.walk(d):
        for f in fs:
            if suffixes is None or f.endswith(suffixes):
                p = os.path.join(dp, f)
                if 0 < os.path.getsize(p) < 20000:
                    files.append(p)
    files.sort(key=lambda p: os.path.getsize(p))
    if limit and len(files) > limit:
        step = len(files) / limit
        files = [files[int(i * step)] for i in range(limit)]
    return files


def w_init():
    CFG["wd"] = tempfile.mkdtemp(prefix="cov_", dir="/tmp")
    CFG["sym"] = symbolize.SymTab()


def list_pkg_dirs(root, limit):
    """以"包目录"为输入单元（整包编译，依赖完整的真实编译单元）。"""
    dirs = []
    for dp, _, fs in os.walk(root):
        if "moon.pkg" in fs:
            dirs.append(dp)
    dirs.sort()
    if limit and len(dirs) > limit:
        step = len(dirs) / limit
        dirs = [dirs[int(i * step)] for i in range(limit)]
    return dirs


def _prep(path, wd, cmd):
    """把输入复制成固定名字，返回 (cwd, argv)"""
    if os.path.isdir(path):          # 整包模式
        names = []
        for f in sorted(os.listdir(path)):
            if f.endswith(".mbt"):
                src = os.path.join(path, f)
                if os.path.getsize(src) > 400000:
                    continue
                shutil.copy(src, wd)
                names.append(f)
        argv = []
        for t in cmd:
            if "{file}" in t:
                argv.extend(names)
            else:
                argv.append(t)
        return argv
    ext = os.path.splitext(path)[1]
    if path.endswith(".mbt.md"):
        ext = ".mbt.md"
    if CFG.get("force_mbt"):
        ext = ".mbt"
    dst = os.path.join(wd, "in" + ext)
    with open(path, "rb") as f:
        data = f.read()
    if CFG.get("append_main") and ext == ".mbt" and b"fn main" not in data:
        data += b"\n\nfn main { () }\n"
    with open(dst, "wb") as f:
        f.write(data)
    fname = os.path.basename(dst)
    return [t.format(file=fname) for t in cmd]


# ---------------------------------------------------------------- edges
def edge_one(path):
    wd = CFG["wd"]
    argv = _prep(path, wd, CFG["cmd_edges"])
    env = dict(os.environ, AFL_QUIET="1", AFL_SKIP_CPUFREQ="1",
               AFL_MAP_SIZE=str(MAP_SIZE), AFL_QEMU_MAP_SIZE=str(MAP_SIZE))
    if CFG.get("old_cov"):
        # 旧口径：idx = hash(pc) & (MAP_SIZE-1) ^ (prev_loc) —— 跨进程稳定，可做并集
        env["AFL_QEMU_OLD_COVERAGE"] = "1"
    mp = os.path.join(wd, "map.txt")
    try:
        subprocess.run([AFL_SHOWMAP, "-Q", "-q", "-o", mp, "--"] + argv,
                       cwd=wd, capture_output=True, timeout=CFG["timeout"], env=env)
        with open(mp, "rb") as f:
            slots = [int(l.split(b":")[0]) for l in f if l.strip()]  # showmap 输出是十进制
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        slots = []
    return slots


# ---------------------------------------------------------------- funcs
def func_one(path):
    wd = CFG["wd"]
    argv = _prep(path, wd, CFG["cmd_funcs"])
    log = os.path.join(wd, "exec.log")
    try:
        with open(log, "wb") as lf:
            subprocess.run([AFL_QEMU, "-d", "exec", "-D", log, "--"] + argv,
                           cwd=wd, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=CFG["timeout"])
    except subprocess.TimeoutExpired:
        pass
    sym = CFG["sym"]
    funcs = set()
    total_tb = 0
    try:
        with open(log, "rb") as f:
            for line in f:
                m = PC_RE.search(line)
                if not m:
                    continue
                total_tb += 1
                fn = sym.func_of(int(m.group(1), 16))
                if fn:
                    funcs.add(fn)
    except FileNotFoundError:
        pass
    finally:
        try:
            os.unlink(log)
        except OSError:
            pass
    return sorted(funcs), total_tb


def minimize_corpus(results, files, out_dir):
    """贪心集覆盖：选出能覆盖全部槽位的最小子集。"""
    sets = [set(r) for r in results]
    universe = set().union(*sets) if sets else set()
    uncovered = set(universe)
    chosen = []
    while uncovered:
        best_i, best_gain = -1, 0
        for i, st in enumerate(sets):
            if i in chosen:
                continue
            gain = len(st & uncovered)
            if gain > best_gain:
                best_i, best_gain = i, gain
        if best_i < 0 or best_gain == 0:
            break
        chosen.append(best_i)
        uncovered -= sets[best_i]
    os.makedirs(out_dir, exist_ok=True)
    import shutil
    for i in chosen:
        shutil.copy(files[i], os.path.join(out_dir, os.path.basename(files[i])))
    return len(chosen), len(universe)


def aggregate(results, key):
    union = set()
    per_new, cum = [], []
    for r in results:
        s = set(r)
        new = len(s - union)
        union |= s
        per_new.append(new)
        cum.append(len(union))
    return union, per_new, cum


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["edges", "funcs", "report", "diff"])
    ap.add_argument("corpus", nargs="?")
    ap.add_argument("--limit", type=int, default=300)
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--out")
    ap.add_argument("--stage", default=None, choices=["syncheck", "check", "build"])
    ap.add_argument("--suffix", default=".mbt")
    ap.add_argument("--append-main", action="store_true")
    ap.add_argument("--force-mbt", action="store_true", help="任意文件名都当成 .mbt（AFL 队列用）")
    ap.add_argument("--pkg-type", choices=["library", "executable"], default=None)
    ap.add_argument("--target", help="真程序模式的编译目标（默认 wasm-gc）")
    ap.add_argument("--real", action="store_true",
                    help="真程序语料：library 包 + core 全 .mi（wasm-gc）")
    ap.add_argument("--old-cov", action="store_true",
                    help="用 AFL_QEMU_OLD_COVERAGE 的稳定哈希口径（跨进程可比较，有碰撞）")
    ap.add_argument("--minimize", help="把语料按覆盖率贪心压缩到该目录")
    ap.add_argument("--dump-slots", help="把每个输入的槽集合落盘（后续并集不用重跑）")
    ap.add_argument("--dump-funcs", help="把每个输入的函数集合落盘（算贪心序/并集用）")
    ap.add_argument("--pkg-dirs", action="store_true", help="输入是包目录（整包编译）")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()

    if a.mode == "report":
        paths = ([a.corpus] if a.corpus else []) + list(a.files)
        return report(paths)
    if a.mode == "diff":
        # 覆盖率回归：比较两次快照的函数集合（工程卫生，不占主线）
        _p = ([a.corpus] if a.corpus else []) + list(a.files)
        a_path, b_path = _p[0], _p[1]
        A = set(json.load(open(a_path)).get("funcs") or [])
        B = set(json.load(open(b_path)).get("funcs") or [])
        print(f"baseline={len(A)} current={len(B)}")
        print(f"新增 {len(B - A)} 个函数, 丢失 {len(A - B)} 个函数")
        for f in sorted(A - B)[:20]:
            print("  -", f)
        return 0 if not (A - B) else 1

    if a.stage is None:
        a.stage = "build" if a.real else "syncheck"
    if a.stage == "syncheck":
        cmd = MOONC + " syncheck -error-format json {file}"
    elif a.stage == "check":
        if a.real:
            cmd = (MOONC + " check {file} -o out.mi -pkg fuzz/p -pkg-type library"
                   " -target wasm-gc -workspace-path . " + " ".join(core_mi_args()))
        else:
            b = os.path.expanduser("~/.moon/lib/core/_build/wasm/release/bundle")
            cmd = (MOONC + " check {file} -o out.mi -pkg fuzz/p -pkg-type library"
                   f" -target wasm -i {b}/builtin/builtin.mi:builtin"
                   f" -i {b}/prelude/prelude.mi:prelude -workspace-path .")
    elif a.real:
        # 真程序语料：单文件当 library 包编译，依赖全部用 core 的 .mi（短别名）
        pt = a.pkg_type or "library"
        tgt = a.target or "wasm-gc"
        cmd = (MOONC + f" build-package {{file}} -o out.core -pkg fuzz/p -pkg-type {pt}"
               f" -target {tgt} -g -O0 -workspace-path . " + " ".join(core_mi_args()))
        if pt == "executable":
            a.append_main = True
    else:
        b = os.path.expanduser("~/.moon/lib/core/_build/wasm/release/bundle")
        cmd = (MOONC + " build-package {file} -o out.core -pkg fuzz/p -pkg-type executable"
               f" -i {b}/builtin/builtin.mi:moonbitlang/core/builtin"
               f" -i {b}/prelude/prelude.mi:prelude -pkg-sources fuzz/p:."
               " -target wasm -g -O0 -workspace-path ."
               " -all-pkgs /data/audit/mbtfuzz/harness/all_pkgs.json")
    CFG.update(wd=None, append_main=a.append_main, force_mbt=a.force_mbt,
               old_cov=a.old_cov, timeout=a.timeout,
               cmd_edges=cmd.split(), cmd_funcs=cmd.split())

    suf = (a.suffix,) if a.suffix else (".mbt", ".mbt.md", ".mbtx")
    if a.force_mbt:
        suf = None
    files = (list_pkg_dirs(a.corpus, a.limit) if a.pkg_dirs
             else list_inputs(a.corpus, a.limit, suf))
    if not files:
        print("no inputs")
        return
    print(f"[cov] mode={a.mode} stage={a.stage} n={len(files)} workers={a.workers}", flush=True)

    with Pool(a.workers, initializer=w_init) as p:
        if a.mode == "edges":
            res = p.map(edge_one, files, chunksize=4)
            union, per_new, cum = aggregate(res, "edges")
            out = dict(tool="afl-showmap-qemu-edges", corpus=a.corpus, stage=a.stage,
                       n=len(files), map_size=MAP_SIZE, union_slots=sorted(union),
                       per_input_new=per_new, cumulative=cum,
                       slots=len(union), density=round(len(union) / MAP_SIZE, 4))
        else:
            res = p.map(func_one, files, chunksize=2)
            funcs_list = [r[0] for r in res]
            tbs = [r[1] for r in res]
            union, per_new, cum = aggregate(funcs_list, "funcs")
            mods = {}
            for f in union:
                m = f.split("__")[0]
                mods[m] = mods.get(m, 0) + 1
            out = dict(tool="qemu-exec-trace+nm", corpus=a.corpus, stage=a.stage,
                       n=len(files), funcs=sorted(union), per_input_new=per_new,
                       cumulative=cum, func_count=len(union), tb_per_input=tbs,
                       total_symbols=len(CFG.get("sym").syms) if CFG.get("sym") else None,
                       modules=dict(sorted(mods.items(), key=lambda kv: -kv[1])[:40]))
    if a.dump_funcs and a.mode == "funcs":
        os.makedirs(a.dump_funcs, exist_ok=True)
        with open(os.path.join(a.dump_funcs, "_manifest.jsonl"), "w") as mf:
            for i, (f, fs_) in enumerate(zip(files, funcs_list)):
                with open(os.path.join(a.dump_funcs, f"{i:05d}.funcs"), "w") as sf:
                    sf.write("\n".join(fs_))
                mf.write(json.dumps({"i": i, "path": os.path.relpath(f), "n": len(fs_)}) + "\n")
        print(f"[cov] dumped {len(funcs_list)} func-sets -> {a.dump_funcs}")
    if a.dump_slots and a.mode == "edges":
        os.makedirs(a.dump_slots, exist_ok=True)
        with open(os.path.join(a.dump_slots, "_manifest.jsonl"), "w") as mf:
            for i, (f, st) in enumerate(zip(files, res)):
                rel = os.path.relpath(f)
                with open(os.path.join(a.dump_slots, f"{i:05d}.slots"), "w") as sf:
                    sf.write("\n".join(map(str, sorted(set(st)))))
                mf.write(json.dumps({"i": i, "path": rel, "n": len(set(st))}) + "\n")
        print(f"[cov] dumped {len(res)} slot-sets -> {a.dump_slots}")
    if a.minimize and a.mode == "edges":
        n_sel, n_cov = minimize_corpus(res, files, a.minimize)
        print(f"[cov] minimized {len(files)} -> {n_sel} files, "
              f"union {n_cov} slots unchanged "
              f"(compression {len(files)/max(n_sel,1):.1f}x)")
    if a.out:
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        with open(a.out, "w") as f:
            json.dump(out, f)
        print(f"[cov] wrote {a.out}: {len(union)} {'slots' if a.mode=='edges' else 'funcs'} "
              f"({out.get('density','')})")
    else:
        print(json.dumps(out, indent=2)[:2000])


def report(paths):
    print(f"{'snapshot':34} {'tool':22} {'n':>5} {'edges':>7} {'dens':>6} {'funcs':>7} {'new/exec':>9}")
    for p in paths:
        with open(p) as f:
            d = json.load(f)
        n = d.get("n", 0)
        e = len(d.get("union_slots") or [])
        fc = len(d.get("funcs") or [])
        per = d.get("per_input_new") or []
        print(f"{os.path.basename(p):34} {d.get('tool',''):22} {n:5d} "
              f"{(str(e) if e else '-'):>7} {(f'{e/MAP_SIZE:.3f}' if e else '-'):>6} "
              f"{(str(fc) if fc else '-'):>7} {(f'{sum(per)/max(n,1):.2f}' if per else '-'):>9}")


if __name__ == "__main__":
    main()
