#!/usr/bin/env python3
"""Syntax-boundary conformance campaign (codex option 2).

Three questions, each with an explicit abandon line:

  A. boundary mutation -- take grammatically valid bases (precedence,
     newline/semicolon, interpolation, patterns, delimiters, strings,
     generics, loops, lambdas/pipe, labels, nested match), mutate exactly
     the boundary tokens (delete / duplicate / confuse / truncate), and
     look for ICE, crash, timeout, silent failure or a *new* diagnostic
     signature.  Stop rule: 20,000 cases without a new failure signature.

  B. size scaling -- grow one boundary dimension at a time (paren depth,
     block depth, operator chain, semicolon count, match arms, string
     interpolation parts, array/tuple elements) and fit log-log time /
     peak-RSS slopes.  Flag time slope > 1.5 or RSS slope > 1.2, or a
     >20x RSS spike vs the smallest size in the series.

  C. formatter round-trip -- for every case that parses, run moonfmt and
     require: fmt exits 0, output re-parses, fmt is idempotent, and no
     structural delimiter is *removed*.  The valid bases are also run
     through `moon run` before/after formatting and their stdout compared.

Usage:
  python3 harness/syntax_boundary.py selftest
  python3 harness/syntax_boundary.py gen   [--n 20000] [--out out/sb_cases.jsonl]
  python3 harness/syntax_boundary.py run   [--cases out/sb_cases.jsonl] [--budget 1800]
  python3 harness/syntax_boundary.py scale [--out out/sb_scale.json]
  python3 harness/syntax_boundary.py fmt   [--cases out/sb_cases.jsonl] [--limit 0]
  python3 harness/syntax_boundary.py report
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOONC = os.path.expanduser("~/.moon/bin/moonc")
MOONFMT = os.path.expanduser("~/.moon/bin/moonfmt")
MOON = os.path.expanduser("~/.moon/bin/moon")
TMP = os.path.join(ROOT, "out", "sb_tmp")
OUT = os.path.join(ROOT, "out")

BASES = {
    "prec": """fn f() -> Int {
  (1 + 2 * 3 - 4 / 2 % 3) << 1 >> 1 & 7 | (8 ^ 2)
}
fn main { println(f().to_string()) }
""",
    "semi": """fn f() -> Int {
  let a = 1;
  let b = 2
  let c = a + b
  c
}
fn main { println(f().to_string()) }
""",
    "interp": """fn f(x : Int) -> String {
  "a\\{x}b\\{(x + 1).to_string()}c\\{"q"}d"
}
fn main { println(f(2)) }
""",
    "pat": """enum E { A(Int); B; C }
fn f(e : E) -> Int {
  match e {
    A(n) if n > 0 => n
    A(_) | B => 0
    C => -1
  }
}
fn main { println(f(A(3)).to_string()) }
""",
    "delim": """fn f() -> Int {
  let a = [1, 2, 3]
  let t = (1, (2, 3))
  let u = ((a[0] + t.0) * (t.1.0))
  u
}
fn main { println(f().to_string()) }
""",
    "str": """fn f() -> String {
  let s = "a\\"b\\\\c\\n\\t\\u{4e2d}"
  let c = 'x'
  s + c.to_string() + "\\{c}"
}
fn main { println(f()) }
""",
    "gen": """fn[T] id(x : T) -> T { x }
fn[T] pair(a : T, b : T) -> (T, T) { (a, b) }
fn f() -> Int {
  let p : (Int, Int) = pair(id(1), id(2))
  p.0 + p.1
}
fn main { println(f().to_string()) }
""",
    "loop": """fn f() -> Int {
  let mut s = 0
  for i in 0..<10 {
    if i % 2 == 0 { continue }
    s = s + i
  }
  while s > 20 { s = s - 10 }
  s
}
fn main { println(f().to_string()) }
""",
    "lambda": """fn f() -> Int {
  let g = fn(x : Int) -> Int { x + 1 }
  let h = fn() { 2 }
  g(1) + h()
}
fn main { println(f().to_string()) }
""",
    "pipe": """fn inc(x : Int) -> Int { x + 1 }
fn f() -> Int {
  let a = 1 |> inc
  let b = 1 |> x => { x + 2 }
  a + b
}
fn main { println(f().to_string()) }
""",
    "label": """fn f(x~ : Int, y? : Int = 1) -> Int { x + y }
fn main { println(f(x=2).to_string()) }
""",
    "matchnest": """fn f() -> Int {
  let a = match (1, 2) {
    (0, _) => 0
    (x, y) => {
      let z = match x { 1 => y; _ => x }
      (z + y) * 2
    }
  }
  a
}
fn main { println(f().to_string()) }
""",
}

# longest first so "=>" wins over "="
TOKENS = [
    "..<", "=>", "->", "|>", "||", "&&", "==", "!=", "<=", ">=", "<<", ">>",
    "..", "(", ")", "{", "}", "[", "]", ",", ";", "|", ":", "=", "<", ">",
    "+", "-", "*", "/", "%", ".", "@", "!", "?", "\\", '"', "'", "~", "&", "^",
]

CONFUSE = {
    "(": "[", ")": "]", "{": "[", "}": "]", "[": "(", "]": ")",
    ";": ",", ",": ";", "=>": "=", "=": "=>", "..": ".", ".": ",",
    "|": "||", "||": "|", "->": "=>", "<": ">", ">": "<", "==": "=",
    "!=": "=", "+": "-", "-": "+", "*": "/", "/": "*", ":": "=",
    "&": "|", "^": "&", "!": "?", "~": "-", "@": ".",
}

TOKEN_RE = re.compile("|".join(re.escape(t) for t in sorted(TOKENS, key=len, reverse=True)))
POS_RE = re.compile(r":[0-9]+:[0-9]+-[0-9]+:[0-9]+")


def occurrences(src, tok):
    return [m.start() for m in TOKEN_RE.finditer(src) if m.group(0) == tok]


def apply_mut(src, pos, tok, op):
    if op == "del":
        return src[:pos] + src[pos + len(tok):]
    if op == "dup":
        return src[:pos] + tok + tok + src[pos + len(tok):]
    if op == "conf":
        return src[:pos] + CONFUSE[tok] + src[pos + len(tok):]
    raise ValueError(op)


# --------------------------------------------------------------------------
# measured execution
# --------------------------------------------------------------------------

def run_measured(argv, cwd, timeout, out_path, err_path, mem_gb=4):
    """fork/exec + wait4 so we get per-child wall time and peak RSS."""
    t0 = time.perf_counter()
    pid = os.fork()
    if pid == 0:  # child
        try:
            import resource
            lim = int(mem_gb * (1 << 30))
            resource.setrlimit(resource.RLIMIT_AS, (lim, lim))
            fd1 = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
            fd2 = os.open(err_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
            os.dup2(fd1, 1)
            os.dup2(fd2, 2)
            os.chdir(cwd)
            os.execv(argv[0], argv)
        except BaseException:
            os._exit(127)
    timed_out = False
    while True:
        wpid, status, ru = os.wait4(pid, os.WNOHANG)
        if wpid == pid:
            break
        if time.perf_counter() - t0 > timeout:
            timed_out = True
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            wpid, status, ru = os.wait4(pid, 0)
            break
        time.sleep(0.001)
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    if timed_out:
        rc = None
    elif os.WIFSIGNALED(status):
        rc = -os.WTERMSIG(status)
    else:
        rc = os.WEXITSTATUS(status)
    with open(out_path, "rb") as f:
        so = f.read()
    with open(err_path, "rb") as f:
        se = f.read()
    return {"rc": rc, "ms": round(elapsed_ms, 1), "rss_kb": ru.ru_maxrss,
            "timed_out": timed_out,
            "stdout": so.decode("utf-8", "replace"),
            "stderr": se.decode("utf-8", "replace")}


def classify(res):
    if res["timed_out"]:
        return "timeout", "TIMEOUT"
    rc = res["rc"]
    err = res["stderr"]
    if rc is not None and rc < 0:
        return "crash", "SIGNAL_%d" % (-rc)
    if rc == 0:
        return ("ok_quiet" if res["stdout"].strip() else "ok"), "OK"
    codes = re.findall(r"\[(E\d{4})\]", err)
    if not err.strip():
        return "silent", "SILENT_FAIL"
    if rc == 199 or "Oops, the compiler" in err:
        return "ice", "ICE_" + (codes[0] if codes else "NOCODE")
    first = next((l.strip() for l in err.splitlines() if l.strip()), "")
    first = POS_RE.sub(":L:C", first)
    first = re.sub(r"`[^`]*`", "`X`", first)
    first = re.sub(r"\s+", " ", first)[:120]
    code = codes[0] if codes else "E_NOCODE"
    return "err", code + " " + first


# --------------------------------------------------------------------------
# case generation
# --------------------------------------------------------------------------

def single_cases():
    cases = []
    for bname, src in BASES.items():
        for tok in TOKENS:
            poss = occurrences(src, tok)
            if not poss:
                continue
            idxs = poss if len(poss) <= 24 else poss[:: max(1, len(poss) // 24)]
            for pos in idxs:
                for op in ("del", "dup", "conf"):
                    if op == "conf" and tok not in CONFUSE:
                        continue
                    m = apply_mut(src, pos, tok, op)
                    if m == src:
                        continue
                    cases.append({"base": bname, "kind": "single", "tok": tok,
                                  "op": op, "pos": pos, "src": m,
                                  "mut": "%s:%s@%d" % (op, tok, pos)})
        poss = [m.start() for m in TOKEN_RE.finditer(src)]
        if len(poss) > 30:
            poss = poss[:: max(1, len(poss) // 30)]
        for pos in poss:
            m = src[:pos]
            if m.strip():
                cases.append({"base": bname, "kind": "prefix", "tok": "<eof>",
                              "op": "trunc", "pos": pos, "src": m,
                              "mut": "trunc@%d" % pos})
        for suffix, label in (('"', "open_quote"), ("{", "open_brace"),
                              ("/*", "open_comment"), ("\\", "open_escape")):
            cases.append({"base": bname, "kind": "unterm", "tok": suffix,
                          "op": "append", "pos": len(src), "src": src + suffix,
                          "mut": label})
    return cases


def random_cases(n, seed=0x5B01):
    rng = random.Random(seed)
    out, seen = [], set()
    bases = list(BASES.items())
    attempts = 0
    while len(out) < n and attempts < n * 6:
        attempts += 1
        bname, src = rng.choice(bases)
        occ = [(m.start(), m.group(0)) for m in TOKEN_RE.finditer(src)
               if m.group(0) in CONFUSE or m.group(0) in (";", ")", "]", "}")]
        if len(occ) < 2:
            continue
        rng.shuffle(occ)
        muts, used = [], 0
        for pos, tok in occ:
            if any(abs(pos - p) <= len(t) for p, t, _ in muts):
                continue
            op = rng.choice(["del", "dup", "conf"])
            if op == "conf" and tok not in CONFUSE:
                continue
            muts.append((pos, tok, op))
            used += 1
            if used >= rng.choice([2, 2, 3]):
                break
        if len(muts) < 2:
            continue
        m = src
        for pos, tok, op in sorted(muts, key=lambda x: -x[0]):
            m = apply_mut(m, pos, tok, op)
        h = hashlib.sha1(m.encode()).hexdigest()
        if h in seen or m == src:
            continue
        seen.add(h)
        out.append({"base": bname, "kind": "rand", "tok": "+".join(t for _, t, _ in muts),
                    "op": "+".join(o for _, _, o in muts), "pos": muts[0][0], "src": m,
                    "mut": ";".join("%s:%s@%d" % (o, t, p) for p, t, o in muts)})
    return out


def cmd_gen(args):
    os.makedirs(OUT, exist_ok=True)
    cases = single_cases()
    have = len(cases)
    want = max(0, args.n - len(cases))
    cases += random_cases(want)
    seen, uniq = set(), []
    for c in cases:
        h = hashlib.sha1(c["src"].encode()).hexdigest()
        if h in seen:
            continue
        seen.add(h)
        c["id"] = h[:16]
        uniq.append(c)
    with open(args.out, "w") as f:
        for c in uniq:
            f.write(json.dumps(c) + "\n")
    print("generated %d cases (%d deterministic, %d random) -> %s"
          % (len(uniq), have, len(uniq) - have, args.out))


# --------------------------------------------------------------------------
# campaign runner
# --------------------------------------------------------------------------

def cmd_run(args):
    d = os.path.join(TMP, "run")
    os.makedirs(d, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    cases = [json.loads(l) for l in open(args.cases)]
    res_path = args.results
    done = set()
    if os.path.exists(res_path) and not args.fresh:
        for l in open(res_path):
            try:
                done.add(json.loads(l)["id"])
            except Exception:
                pass
    todo = [c for c in cases if c["id"] not in done]
    print("cases=%d done=%d todo=%d" % (len(cases), len(done), len(todo)))
    cpath = os.path.join(d, "c.mbt")
    opath = os.path.join(d, "o")
    epath = os.path.join(d, "e")
    t_start = time.time()
    n_new_sig = 0
    seen_sig = set()
    out = open(res_path, "a")
    for i, c in enumerate(todo, 1):
        if args.budget and time.time() - t_start > args.budget:
            print("budget exhausted after %d cases" % (i - 1))
            break
        with open(cpath, "w") as f:
            f.write(c["src"])
        r = run_measured([MOONC, "syncheck", "c.mbt"], d, args.timeout, opath, epath)
        status, sig = classify(r)
        if sig not in seen_sig:
            seen_sig.add(sig)
            n_new_sig += 1
        rec = {"id": c["id"], "base": c["base"], "kind": c["kind"], "tok": c["tok"],
               "op": c["op"], "mut": c["mut"], "status": status, "sig": sig,
               "rc": r["rc"], "ms": r["ms"], "rss_kb": r["rss_kb"],
               "stderr": r["stderr"][:400]}
        out.write(json.dumps(rec) + "\n")
        if i % 200 == 0:
            out.flush()
            print("  %d/%d  %.1fs  sigs=%d  status=%s" % (i, len(todo),
                  time.time() - t_start, len(seen_sig), status), flush=True)
    out.close()
    print("done in %.1fs; results -> %s" % (time.time() - t_start, res_path))


# --------------------------------------------------------------------------
# scaling
# --------------------------------------------------------------------------

KS = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]


def gen_series():
    out = []
    for k in KS:
        out.append(("paren_depth", k, "fn f() -> Int { %s1%s }\n" % ("(" * k, ")" * k)))
        out.append(("block_depth", k,
                    "fn f() -> Int { %s1%s }\n" % ("{ " * k, " }" * k)))
        out.append(("if_depth", k, "fn f() -> Int { " +
                    "".join("if true { " for _ in range(k)) + "1" +
                    "".join(" }" for _ in range(k)) + " }\n"))
        out.append(("chain", k, "fn f() -> Int { " + " + ".join(["1"] * k) + " }\n"))
        out.append(("semi", k, "fn f() -> Int { " +
                    "".join("let a%d = %d; " % (i, i) for i in range(k)) +
                    "a%d }\n" % (k - 1)))
        out.append(("interp", k, 'fn f() -> String { "%s" }\n' %
                    "".join("\\{%d}" % i for i in range(k))))
        out.append(("array", k, "fn f() -> Int { [%s].length() }\n" %
                    ", ".join(["0"] * k)))
        out.append(("tuple", k, "fn f() -> Int { (%s).0 }\n" % ", ".join(["0"] * k)))
        if k <= 512:
            names = [("A%d" % i) for i in range(k)]
            body = "".join("    %s => %d\n" % (nm, i) for i, nm in enumerate(names))
            out.append(("match_arms", k,
                        "enum E { %s }\nfn f(e : E) -> Int {\n  match e {\n%s  }\n}\n"
                        % ("; ".join(names), body)))
    return out


def fit_slope(xs, ys):
    pts = [(math.log(x), math.log(y)) for x, y in zip(xs, ys) if x > 0 and y > 0]
    if len(pts) < 3:
        return None
    n = len(pts)
    sx = sum(p[0] for p in pts)
    sy = sum(p[1] for p in pts)
    sxx = sum(p[0] ** 2 for p in pts)
    sxy = sum(p[0] * p[1] for p in pts)
    den = n * sxx - sx * sx
    if abs(den) < 1e-12:
        return None
    return (n * sxy - sx * sy) / den


def cmd_scale(args):
    d = os.path.join(TMP, "scale")
    os.makedirs(d, exist_ok=True)
    cpath = os.path.join(d, "s.mbt")
    opath = os.path.join(d, "o")
    epath = os.path.join(d, "e")
    fpath = os.path.join(d, "s_fmt.mbt")
    rows = []
    for name, k, src in gen_series():
        with open(cpath, "w") as f:
            f.write(src)
        r = run_measured([MOONC, "syncheck", "s.mbt"], d, args.timeout, opath, epath)
        status, sig = classify(r)
        # formatter on the same program
        fr = run_measured([MOONFMT, "s.mbt", "-o", "s_fmt.mbt"], d, args.timeout, opath, epath)
        fstatus, fsig = classify(fr)
        row = {"series": name, "k": k, "bytes": len(src), "status": status, "sig": sig,
               "ms": r["ms"], "rss_kb": r["rss_kb"],
               "fmt_status": fstatus, "fmt_ms": fr["ms"], "fmt_rss_kb": fr["rss_kb"],
               "fmt_sig": fsig}
        if fstatus.startswith("ok") and os.path.exists(fpath):
            row["fmt_bytes"] = os.path.getsize(fpath)
        rows.append(row)
        print("%-11s k=%-5d %-8s %7.1fms %8dkB | fmt %-8s %7.1fms %8dkB"
              % (name, k, status, r["ms"], r["rss_kb"], fstatus, fr["ms"], fr["rss_kb"]))
    # slopes
    series = {}
    for r in rows:
        series.setdefault(r["series"], []).append(r)
    summary = []
    for name, rs in series.items():
        ok = [r for r in rs if r["status"].startswith("ok")]
        fok = [r for r in rs if r["fmt_status"].startswith("ok")]
        tslope = fit_slope([r["k"] for r in ok], [r["ms"] for r in ok])
        rslope = fit_slope([r["k"] for r in ok], [r["rss_kb"] for r in ok])
        ftslope = fit_slope([r["k"] for r in fok], [r["fmt_ms"] for r in fok])
        frss = fit_slope([r["k"] for r in fok], [r["fmt_rss_kb"] for r in fok])
        base_rss = ok[0]["rss_kb"] if ok else 0
        maxrss = max((r["rss_kb"] for r in ok), default=0)
        flags = []
        if tslope is not None and tslope > 1.5:
            flags.append("time_superlinear")
        if rslope is not None and rslope > 1.2:
            flags.append("rss_superlinear")
        if base_rss and maxrss > 20 * base_rss:
            flags.append("rss_spike")
        if ftslope is not None and ftslope > 1.5:
            flags.append("fmt_time_superlinear")
        if frss is not None and frss > 1.2:
            flags.append("fmt_rss_superlinear")
        bad = [r["k"] for r in rs if not r["status"].startswith("ok")]
        if bad and min(bad) <= 64:
            flags.append("fails_at_small_k")
        # adjacent-doubling ratios catch superlinearity that a global slope
        # over a wide k range dilutes (interp: 1.15 global vs 10x per step)
        def dbl(vals, ks):
            d = dict(zip(ks, vals))
            return max((d[2 * k] / d[k] for k in ks if 2 * k in d and d[k] > 0),
                       default=None)
        oks = [r for r in rs if r["status"].startswith("ok")]
        tdbl = dbl([r["ms"] for r in oks], [r["k"] for r in oks])
        rdbl = dbl([r["rss_kb"] for r in oks], [r["k"] for r in oks])
        foks = [r for r in rs if r["fmt_status"].startswith("ok")]
        ftdbl = dbl([r["fmt_ms"] for r in foks], [r["k"] for r in foks])
        frdbl = dbl([r["fmt_rss_kb"] for r in foks], [r["k"] for r in foks])
        if tdbl and tdbl > 3:
            flags.append("time_doubling_x%.1f" % tdbl)
        if rdbl and rdbl > 2.5:
            flags.append("rss_doubling_x%.1f" % rdbl)
        def outdbl(rs):
            d = {r["k"]: r.get("fmt_bytes") or 0 for r in rs if r.get("fmt_bytes")}
            return max((d[2 * k] / d[k] for k in d if 2 * k in d and d[k] > 0), default=None)
        odbl = outdbl(rs)
        if odbl and odbl > 3:
            flags.append("fmt_output_size_x%.1f(indent)" % odbl)
        elif ftdbl and ftdbl > 3:
            flags.append("fmt_time_doubling_x%.1f" % ftdbl)
        if frdbl and frdbl > 2.5:
            flags.append("fmt_rss_doubling_x%.1f" % frdbl)
        fbad = [r["k"] for r in rs if not r["fmt_status"].startswith("ok")]
        if fbad and max(fbad) >= 1024:
            flags.append("fmt_fails_at_k%d" % max(fbad))
        summary.append({"series": name, "time_slope": tslope, "rss_slope": rslope,
                        "fmt_time_slope": ftslope, "fmt_rss_slope": frss,
                        "time_doubling": tdbl, "rss_doubling": rdbl,
                        "fmt_time_doubling": ftdbl, "fmt_rss_doubling": frdbl,
                        "base_rss_kb": base_rss, "max_rss_kb": maxrss,
                        "fail_ks": bad, "fmt_fail_ks": fbad, "flags": flags})
        print("SLOPE %-11s time=%.2f rss=%.2f fmt_time=%.2f fmt_rss=%.2f %s"
              % (name, tslope or 0, rslope or 0, ftslope or 0, frss or 0,
                 ",".join(flags)))
    with open(args.out, "w") as f:
        json.dump({"rows": rows, "summary": summary}, f, indent=1)
    print("-> %s" % args.out)


# --------------------------------------------------------------------------
# formatter round-trip
# --------------------------------------------------------------------------

DELIMS = {"(": ")", "[": "]", "{": "}"}


def counts(src):
    return {ch: src.count(ch) for ch in "()[]{}"}


def cmd_fmt(args):
    d = os.path.join(TMP, "fmt")
    os.makedirs(d, exist_ok=True)
    cases = [json.loads(l) for l in open(args.cases)]
    res = {}
    if os.path.exists(args.results):
        for l in open(args.results):
            try:
                r = json.loads(l)
                res[r["id"]] = r
            except Exception:
                pass
    ok_ids = [cid for cid, r in res.items() if r["status"].startswith("ok")]
    ok_ids.sort()
    if args.limit:
        ok_ids = ok_ids[: args.limit]
    by_id = {c["id"]: c for c in cases}
    out = open(args.fmt_results, "a")
    done = 0
    if os.path.exists(args.fmt_results) and not args.fresh:
        for l in open(args.fmt_results):
            try:
                done += 1
            except Exception:
                pass
    cpath = os.path.join(d, "f.mbt")
    f1 = os.path.join(d, "f1.mbt")
    f2 = os.path.join(d, "f2.mbt")
    opath = os.path.join(d, "o")
    epath = os.path.join(d, "e")
    t0 = time.time()
    n_done = 0
    for cid in ok_ids:
        if cid not in by_id:
            continue
        c = by_id[cid]
        with open(cpath, "w") as f:
            f.write(c["src"])
        r1 = run_measured([MOONFMT, "f.mbt", "-o", "f1.mbt"], d, 30, opath, epath)
        rec = {"id": cid, "base": c["base"], "mut": c["mut"], "fmt_rc": r1["rc"],
               "fmt_status": "ok" if r1["rc"] == 0 else "fail", "fmt_ms": r1["ms"],
               "fmt_rss_kb": r1["rss_kb"], "stderr": r1["stderr"][:300]}
        if r1["rc"] == 0 and os.path.exists(f1):
            r2 = run_measured([MOONFMT, "f1.mbt", "-o", "f2.mbt"], d, 30, opath, epath)
            idem = False
            if r2["rc"] == 0:
                idem = open(f1, "rb").read() == open(f2, "rb").read()
            s1 = open(f1).read()
            rc = run_measured([MOONC, "syncheck", "f1.mbt"], d, 10, opath, epath)
            sstatus, ssig = classify(rc)
            co, cf = counts(c["src"]), counts(s1)
            removed = {d: co[d] - cf[d] for d in co if co[d] > cf[d]}
            rec.update({"idempotent": idem, "reparse": sstatus,
                        "reparse_sig": ssig, "delims_removed": removed,
                        "fmt_bytes": os.path.getsize(f1), "bytes": len(c["src"])})
        out.write(json.dumps(rec) + "\n")
        n_done += 1
        if n_done % 200 == 0:
            out.flush()
            print("  fmt %d/%d %.1fs" % (n_done, len(ok_ids), time.time() - t0), flush=True)
    out.close()
    print("fmt checked %d cases in %.1fs -> %s" % (n_done, time.time() - t0, args.fmt_results))



# --------------------------------------------------------------------------
# focused probe: is the formatter superlinear *because of* interpolation?
# --------------------------------------------------------------------------

PROBE_KS = [128, 256, 512, 1024, 2048]


def probe_expr(family, k):
    if family == "interp_distinct":
        return '"%s"' % "".join("\\{%d}" % i for i in range(k))
    if family == "interp_same":
        return '"%s"' % ("\\{x}" * k)
    if family == "interp_const":
        return '"%s"' % ("\\{0}" * k)
    if family == "plain_string":
        return '"%s"' % ("a" * k)
    if family == "concat":
        return '"a"%s' % (' + "a"' * k)
    raise ValueError(family)


def cmd_probe(args):
    d = os.path.join(TMP, "probe")
    os.makedirs(d, exist_ok=True)
    cpath = os.path.join(d, "p.mbt")
    fpath = os.path.join(d, "p_fmt.mbt")
    opath, epath = os.path.join(d, "o"), os.path.join(d, "e")
    rows = []
    for fam in ("interp_distinct", "interp_same", "interp_const",
                "plain_string", "concat"):
        for k in PROBE_KS:
            src = "fn f(x : Int) -> String { %s }\n" % probe_expr(fam, k)
            with open(cpath, "w") as f:
                f.write(src)
            ts, rs, fts, frss, fstat = [], [], [], [], []
            for _ in range(args.reps):
                r = run_measured([MOONC, "syncheck", "p.mbt"], d, args.timeout, opath, epath)
                st, _ = classify(r)
                ts.append(r["ms"])
                rs.append(r["rss_kb"])
                fr = run_measured([MOONFMT, "p.mbt", "-o", "p_fmt.mbt"], d, args.timeout,
                                  opath, epath)
                fst, _ = classify(fr)
                fts.append(fr["ms"])
                frss.append(fr["rss_kb"])
                fstat.append(fst)
            rows.append({"family": fam, "k": k, "bytes": len(src),
                         "check_ms": statistics.median(ts),
                         "check_rss_kb": statistics.median(rs),
                         "fmt_ms": statistics.median(fts),
                         "fmt_rss_kb": statistics.median(frss),
                         "fmt_status": fstat[-1]})
            print("%-16s k=%-5d check=%7.1fms fmt=%9.1fms rss=%7dkB %s"
                  % (fam, k, rows[-1]["check_ms"], rows[-1]["fmt_ms"],
                     rows[-1]["fmt_rss_kb"], rows[-1]["fmt_status"]), flush=True)
    # doubling table
    print("\nfamily            " + "  ".join("%7d" % (2 * k) for k in PROBE_KS[:-1]))
    for fam in ("interp_distinct", "interp_same", "interp_const", "plain_string", "concat"):
        fr = {r["k"]: r for r in rows if r["family"] == fam}
        cells = []
        for k in PROBE_KS[:-1]:
            a, b = fr.get(k), fr.get(2 * k)
            cells.append("%6.2fx" % (b["fmt_ms"] / a["fmt_ms"])
                         if a and b and a["fmt_ms"] > 0 else "     -")
        print("%-16s " % fam + "  ".join(cells))
    with open(args.out, "w") as f:
        json.dump({"rows": rows, "ks": PROBE_KS}, f, indent=1)
    print("-> %s" % args.out)

# --------------------------------------------------------------------------
# base semantic round-trip via moon run
# --------------------------------------------------------------------------

def cmd_rt(args):
    base = os.path.join(TMP, "rt")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(os.path.join(base, "src"))
    with open(os.path.join(base, "moon.mod"), "w") as f:
        f.write('name = "sb/rt"\n\nversion = "0.1.0"\n')
    with open(os.path.join(base, "src", "moon.pkg"), "w") as f:
        f.write('pkgtype(kind: "executable")\n')
    rows = []
    for name, src in BASES.items():
        p = os.path.join(base, "src", "main.mbt")
        with open(p, "w") as f:
            f.write(src)
        r1 = run_measured([MOON, "run", "src"], base, 120,
                          os.path.join(TMP, "o"), os.path.join(TMP, "e"))
        fmt = run_measured([MOON, "fmt", "src"], base, 120,
                           os.path.join(TMP, "o"), os.path.join(TMP, "e"))
        r2 = run_measured([MOON, "run", "src"], base, 120,
                          os.path.join(TMP, "o"), os.path.join(TMP, "e"))
        same = r1["stdout"] == r2["stdout"] and r1["rc"] == 0 and r2["rc"] == 0
        rows.append({"base": name, "before": r1["stdout"].strip(), "after": r2["stdout"].strip(),
                     "fmt_rc": fmt["rc"], "same": same,
                     "fmt_err": fmt["stderr"][:200] if fmt["rc"] else ""})
        print("%-11s before=%-20r after=%-20r fmt_rc=%s same=%s"
              % (name, r1["stdout"].strip()[:20], r2["stdout"].strip()[:20], fmt["rc"], same))
        os.remove(p)
    with open(os.path.join(OUT, "sb_roundtrip.json"), "w") as f:
        json.dump(rows, f, indent=1)


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------

def load_jsonl(p):
    if not os.path.exists(p):
        return []
    return [json.loads(l) for l in open(p) if l.strip()]


def pct(a, b):
    return 100.0 * a / b if b else 0.0


def cmd_report(args):
    res = load_jsonl(os.path.join(OUT, "sb_results.jsonl"))
    fmt = load_jsonl(os.path.join(OUT, "sb_fmt.jsonl"))
    scale = json.load(open(os.path.join(OUT, "sb_scale.json"))) if \
        os.path.exists(os.path.join(OUT, "sb_scale.json")) else None
    rt = json.load(open(os.path.join(OUT, "sb_roundtrip.json"))) if \
        os.path.exists(os.path.join(OUT, "sb_roundtrip.json")) else None
    L = []
    L.append("# Syntax boundary campaign (codex option 2)\n")
    L.append("Harness: `harness/syntax_boundary.py`  ")
    L.append("Cases: `out/sb_cases.jsonl`  results: `out/sb_results.jsonl`  ")
    L.append("Formatter: `out/sb_fmt.jsonl`  scaling: `out/sb_scale.json`\n")

    n = len(res)
    st = {}
    for r in res:
        st[r["status"]] = st.get(r["status"], 0) + 1
    L.append("## A. Boundary mutation\n")
    L.append("Cases run: **%d**\n" % n)
    L.append("| status | n | share |")
    L.append("|---|---:|---:|")
    for k in sorted(st, key=lambda x: -st[x]):
        L.append("| %s | %d | %.1f%% |" % (k, st[k], pct(st[k], n)))
    ok = sum(v for k, v in st.items() if k.startswith("ok"))
    L.append("\nAccepted (parses): **%d / %d = %.2f%%**\n" % (ok, n, pct(ok, n)))

    sigs = {}
    first_seen = {}
    for i, r in enumerate(res):
        sigs[r["sig"]] = sigs.get(r["sig"], 0) + 1
        first_seen.setdefault(r["sig"], i)
    L.append("Distinct signatures: **%d**\n" % len(sigs))
    L.append("### Top signatures\n")
    L.append("| n | first | signature |")
    L.append("|---:|---:|---|")
    for s, c in sorted(sigs.items(), key=lambda x: -x[1])[:25]:
        L.append("| %d | %d | `%s` |" % (c, first_seen[s], s))
    anomalies = [r for r in res if r["status"] in ("ice", "crash", "timeout", "silent")]
    L.append("\n### Anomalies (ICE / crash / timeout / silent): %d\n" % len(anomalies))
    if anomalies:
        L.append("| id | base | mutation | status | rc | ms | rss_kB | stderr |")
        L.append("|---|---|---|---|---:|---:|---:|---|")
        for r in anomalies[:40]:
            L.append("| `%s` | %s | `%s` | %s | %s | %s | %s | `%s` |" % (
                r["id"], r["base"], r["mut"], r["status"], r["rc"], r["ms"],
                r["rss_kb"], (r["stderr"] or "").replace("\n", " ")[:120]))

    # acceptance matrix per token/op
    L.append("\n### Acceptance by token x op (parses / cases)\n")
    mat = {}
    for r in res:
        if r["kind"] != "single":
            continue
        key = (r["tok"], r["op"])
        a = mat.setdefault(key, [0, 0])
        a[1] += 1
        if r["status"].startswith("ok"):
            a[0] += 1
    toks = sorted({t for t, _ in mat}, key=lambda t: -mat[(t, "del")][1] if (t, "del") in mat else 0)
    L.append("| token | del | dup | conf |")
    L.append("|---|---|---|---|")
    for t in toks:
        cells = []
        for op in ("del", "dup", "conf"):
            a = mat.get((t, op))
            cells.append("%d/%d" % (a[0], a[1]) if a else "-")
        L.append("| `%s` | %s | %s | %s |" % (t, *cells))

    L.append("\n### Per-base acceptance\n")
    L.append("| base | cases | ok | crash/ice/timeout/silent |")
    L.append("|---|---:|---:|---:|")
    per = {}
    for r in res:
        a = per.setdefault(r["base"], [0, 0, 0])
        a[0] += 1
        if r["status"].startswith("ok"):
            a[1] += 1
        if r["status"] in ("ice", "crash", "timeout", "silent"):
            a[2] += 1
    for b, a in per.items():
        L.append("| %s | %d | %d | %d |" % (b, a[0], a[1], a[2]))

    # probe
    pp = os.path.join(OUT, "sb_probe.json")
    if os.path.exists(pp):
        probe = json.load(open(pp))
        L.append("\n### B2. Is the formatter blow-up caused by interpolation?\n")
        L.append("Median of 3 runs; `check` = `moonc syncheck`, `fmt` = `moonfmt`. "
                 "Cells are fmt-time ratio per doubling of k.\n")
        ks = probe["ks"]
        fams = ["interp_distinct", "interp_same", "interp_const", "plain_string", "concat"]
        rows = {(r["family"], r["k"]): r for r in probe["rows"]}
        L.append("| family | " + " | ".join("%d->%d" % (k, 2 * k) for k in ks[:-1]) + " |")
        L.append("|---|" + "---:|" * (len(ks) - 1))
        for fam in fams:
            cells = []
            for k in ks[:-1]:
                a, b = rows.get((fam, k)), rows.get((fam, 2 * k))
                cells.append("%.2fx" % (b["fmt_ms"] / a["fmt_ms"])
                             if a and b and a["fmt_ms"] > 0 else "-")
            L.append("| %s | %s |" % (fam, " | ".join(cells)))
        L.append("\n| family | k | syncheck ms | fmt ms | fmt RSS kB |")
        L.append("|---|---:|---:|---:|---:|")
        for fam in fams:
            for k in ks:
                r = rows.get((fam, k))
                if r:
                    L.append("| %s | %d | %.1f | %.1f | %d |" % (
                        fam, k, r["check_ms"], r["fmt_ms"], r["fmt_rss_kb"]))

    # formatter
    L.append("\n## C. Formatter round-trip (parse-accepted mutants)\n")
    if fmt:
        fok = sum(1 for r in fmt if r["fmt_status"] == "ok")
        idem = sum(1 for r in fmt if r.get("idempotent"))
        reparse = sum(1 for r in fmt if str(r.get("reparse", "")).startswith("ok"))
        removed = [r for r in fmt if r.get("delims_removed")]
        L.append("Checked: **%d**  fmt-exit-0: **%d (%.2f%%)**  idempotent: **%d**  re-parses: **%d**  delimiter-removing: **%d**\n"
                 % (len(fmt), fok, pct(fok, len(fmt)), idem, reparse, len(removed)))
        if removed:
            L.append("Delimiter-removing cases (first 20):\n")
            L.append("| id | base | mut | removed |")
            L.append("|---|---|---|---|")
            for r in removed[:20]:
                L.append("| `%s` | %s | `%s` | `%s` |" % (r["id"], r["base"], r["mut"],
                                                          r["delims_removed"]))
        bad = [r for r in fmt if r["fmt_status"] != "ok" or not r.get("idempotent")
               or not str(r.get("reparse", "")).startswith("ok")]
        if bad:
            L.append("\nNon-round-tripping cases (first 20):\n")
            L.append("| id | base | mut | fmt | idem | reparse signature |")
            L.append("|---|---|---|---|---|---|")
            for r in bad[:20]:
                L.append("| `%s` | %s | `%s` | %s | %s | `%s` |" % (
                    r["id"], r["base"], r["mut"], r["fmt_status"], r.get("idempotent"),
                    (r.get("reparse_sig") or r.get("reparse") or "").replace("\n", " ")[:110]))

    cp = os.path.join(OUT, "sb_fmtcorpus.json")
    if os.path.exists(cp):
        fc = json.load(open(cp))
        fbad = [r for r in fc if r.get("reparse") and not r["reparse"].startswith("ok")]
        L.append("\n### C2. Formatter round-trip over real corpus (`seeds_real`)\n")
        L.append("Files: **%d**  fmt exits 0: **%d**  formatted output re-parses: **%d**  "
                 "unparseable: **%d**\n" % (len(fc), sum(1 for r in fc if r["fmt_rc"] == 0),
                                             len(fc) - len(fbad), len(fbad)))
        if fbad:
            for r in fbad[:20]:
                L.append("- `%s` -> `%s`" % (r["file"], r.get("sig", "")[:100]))

    if rt:
        bad = [r for r in rt if not r["same"]]
        L.append("\n### Valid-base semantic round-trip (`moon fmt` then `moon run`)\n")
        L.append("Bases identical: **%d / %d**\n" % (len(rt) - len(bad), len(rt)))
        if bad:
            L.append("| base | before | after | fmt_rc | err |")
            L.append("|---|---|---|---|---|")
            for r in bad:
                L.append("| %s | `%s` | `%s` | %s | `%s` |" % (
                    r["base"], r["before"][:40], r["after"][:40], r["fmt_rc"], r["fmt_err"]))

    if scale:
        # backfill doubling metrics for scale files produced before the patch
        if scale["summary"] and "time_doubling" not in scale["summary"][0]:
            by = {}
            for r in scale["rows"]:
                by.setdefault(r["series"], {})[r["k"]] = r
            for sm in scale["summary"]:
                d = by[sm["series"]]
                def pair(field, k):
                    a, b = d.get(k), d.get(2 * k)
                    return b[field] / a[field] if a and b and a[field] > 0 else None
                ks = sorted(d)
                td = [x for x in (pair("ms", k) for k in ks[:-1]) if x]
                rd = [x for x in (pair("rss_kb", k) for k in ks[:-1]) if x]
                ft = [x for x in (pair("fmt_ms", k) for k in ks[:-1]) if x]
                fr = [x for x in (pair("fmt_rss_kb", k) for k in ks[:-1]) if x]
                sm["time_doubling"] = max(td) if td else None
                sm["rss_doubling"] = max(rd) if rd else None
                sm["fmt_time_doubling"] = max(ft) if ft else None
                sm["fmt_rss_doubling"] = max(fr) if fr else None
                sm["fmt_fail_ks"] = [r["k"] for r in scale["rows"]
                                     if r["series"] == sm["series"]
                                     and not r["fmt_status"].startswith("ok")]
                flags = [fl for fl in sm["flags"] if fl == "ok"]
                if sm["time_doubling"] and sm["time_doubling"] > 3:
                    flags.append("time_doubling_x%.1f" % sm["time_doubling"])
                od = {}
                for r in scale["rows"]:
                    if r["series"] == sm["series"] and r.get("fmt_bytes"):
                        od[r["k"]] = r["fmt_bytes"]
                odbl = max((od[2 * k] / od[k] for k in od if 2 * k in od and od[k] > 0),
                           default=None)
                sm["fmt_output_doubling"] = odbl
                if odbl and odbl > 3:
                    flags.append("fmt_output_size_x%.1f(indent)" % odbl)
                elif sm["fmt_time_doubling"] and sm["fmt_time_doubling"] > 3:
                    flags.append("fmt_time_doubling_x%.1f" % sm["fmt_time_doubling"])
                if sm["fmt_rss_doubling"] and sm["fmt_rss_doubling"] > 2.5:
                    flags.append("fmt_rss_doubling_x%.1f" % sm["fmt_rss_doubling"])
                if sm["fmt_fail_ks"] and max(sm["fmt_fail_ks"]) >= 1024:
                    flags.append("fmt_fails_at_k%d" % max(sm["fmt_fail_ks"]))
                sm["flags"] = flags or ["ok"]
        L.append("\n## B. Size scaling\n")
        L.append("| series | syn time slope | fmt time slope | syn max dbl | fmt max dbl | fmt max dbl RSS | max RSS kB | fmt fail k | flags |")
        L.append("|---|---:|---:|---:|---:|---:|---:|---|---|")
        for s in scale["summary"]:
            L.append("| %s | %s | %s | %s | %s | %s | %d | %s | %s |" % (
                s["series"],
                "%.2f" % s["time_slope"] if s["time_slope"] is not None else "-",
                "%.2f" % s["fmt_time_slope"] if s["fmt_time_slope"] is not None else "-",
                "%.1fx" % s["time_doubling"] if s.get("time_doubling") else "-",
                "%.1fx" % s["fmt_time_doubling"] if s.get("fmt_time_doubling") else "-",
                "%.1fx" % s["fmt_rss_doubling"] if s.get("fmt_rss_doubling") else "-",
                s["max_rss_kb"],
                ",".join(str(x) for x in s.get("fmt_fail_ks", [])) or "-",
                ",".join(s["flags"]) or "ok"))
        L.append("\nNote: slopes are log-log least squares over the sizes that parsed; "
                 "time slope 1.0 = linear in k. Flags use time>1.5, RSS>1.2, "
                 "max RSS > 20x smallest, or failure at k<=64.\n")

    md = "\n".join(L) + "\n"
    path = os.path.join(OUT, "sb_report.md")
    with open(path, "w") as f:
        f.write(md)
    print(md)
    print("-> %s" % path)


# --------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------

def cmd_selftest(args):
    d = os.path.join(TMP, "st")
    os.makedirs(d, exist_ok=True)
    cpath = os.path.join(d, "st.mbt")
    bad = 0
    for name, src in BASES.items():
        with open(cpath, "w") as f:
            f.write(src)
        r = run_measured([MOONC, "syncheck", "st.mbt"], d, 20,
                         os.path.join(d, "o"), os.path.join(d, "e"))
        status, sig = classify(r)
        ok = status.startswith("ok")
        print("%-11s %-6s %s" % (name, status, "" if ok else sig))
        bad += 0 if ok else 1
    print("bases that fail to parse: %d/%d" % (bad, len(BASES)))
    # scaling templates at small k must parse
    for name, k, src in gen_series():
        if k != 16:
            continue
        with open(cpath, "w") as f:
            f.write(src)
        r = run_measured([MOONC, "syncheck", "st.mbt"], d, 20,
                         os.path.join(d, "o"), os.path.join(d, "e"))
        status, sig = classify(r)
        print("scale %-11s k=%d %-6s %s" % (name, k, status, "" if status.startswith("ok") else sig))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen"); g.add_argument("--n", type=int, default=20000)
    g.add_argument("--out", default=os.path.join(OUT, "sb_cases.jsonl"))
    r = sub.add_parser("run")
    r.add_argument("--cases", default=os.path.join(OUT, "sb_cases.jsonl"))
    r.add_argument("--results", default=os.path.join(OUT, "sb_results.jsonl"))
    r.add_argument("--timeout", type=float, default=5.0)
    r.add_argument("--budget", type=float, default=1800.0)
    r.add_argument("--fresh", action="store_true")
    s = sub.add_parser("scale")
    s.add_argument("--out", default=os.path.join(OUT, "sb_scale.json"))
    s.add_argument("--timeout", type=float, default=20.0)
    f = sub.add_parser("fmt")
    f.add_argument("--cases", default=os.path.join(OUT, "sb_cases.jsonl"))
    f.add_argument("--results", default=os.path.join(OUT, "sb_results.jsonl"))
    f.add_argument("--fmt-results", default=os.path.join(OUT, "sb_fmt.jsonl"))
    f.add_argument("--limit", type=int, default=0)
    f.add_argument("--fresh", action="store_true")
    pr = sub.add_parser("probe")
    pr.add_argument("--out", default=os.path.join(OUT, "sb_probe.json"))
    pr.add_argument("--timeout", type=float, default=120.0)
    pr.add_argument("--reps", type=int, default=3)
    sub.add_parser("rt")
    sub.add_parser("report")
    sub.add_parser("selftest")
    args = ap.parse_args()
    {"gen": cmd_gen, "run": cmd_run, "scale": cmd_scale, "fmt": cmd_fmt,
     "probe": cmd_probe, "rt": cmd_rt, "report": cmd_report, "selftest": cmd_selftest}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
