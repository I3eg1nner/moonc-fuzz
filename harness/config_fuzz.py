#!/usr/bin/env python3
"""Bounded mutation campaign over config/document parsers read by moonc.

Stages (all via the current moonc, one temp dir per case):
  pkg     : cwd/moon.pkg, command `moonc syncheck t.mbt` (auto-loads it)
  mbtmd   : doc.mbt.md, command `moonc syncheck doc.mbt.md`
  mbti    : x.mbti, command `moonc build-interface -pkg x/y -i prelude -o x.mi x.mbti`

Mutations: byte flip/insert/delete/replace, truncation, and token swaps from a
small config alphabet.  Classification reuses syntax_boundary.classify; a case
is an anomaly on ICE (rc=199/SIGSEGV/timeout/silent), otherwise an ordinary
diagnostic.  Known signatures (F1 SIGSEGV, F4 MalFormed) are labelled, not
counted as new.

Usage:
  python3 harness/config_fuzz.py gen --n 10000 --out out/cfg_cases.jsonl
  python3 harness/config_fuzz.py run --cases out/cfg_cases.jsonl --budget 900
  python3 harness/config_fuzz.py report
"""
from __future__ import annotations
import argparse, hashlib, json, os, random, sys
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,HERE); import syntax_boundary as sb
MOONC=os.path.expanduser("~/.moon/bin/moonc")
PRE=os.path.expanduser("~/.moon/lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi")
TMP=os.path.join(ROOT,"out","cfg_tmp")

SEEDS={
 "pkg": ("moon.pkg", 'pkgtype(kind: "library")\nimport { "moonbitlang/core/builtin" }\n'),
 "mbtmd": ("doc.mbt.md", '# demo\n\n```mbt\nfn f() -> Int { 1 }\n```\n'),
 "mbti": ("x.mbti", 'package "x/y"\npub fn f(Int) -> Int\n'),
}
TOKENS=["pkgtype","kind","library","executable","import","{","}","(",")",'"',",",";","\n","#","`","```mbt","package","pub","fn","->","Int","x","y",":","="]

def mutate(rng, s):
    s=list(s)
    op=rng.choice(["flip","del","ins","rep","trunc","dup","tok"])
    if not s: return ""
    if op=="flip":
        i=rng.randrange(len(s)); s[i]=rng.choice('{}()[]",;:\\n#`0aZ')
    elif op=="del":
        i=rng.randrange(len(s)); del s[i]
    elif op=="ins":
        i=rng.randrange(len(s)+1); s[i:i]=list(rng.choice('{}()[]",;:\\n#`0aZ'))
    elif op=="rep":
        i=rng.randrange(len(s)); n=min(len(s)-i,rng.randint(1,4)); s[i:i+n]=list(rng.choice(TOKENS))
    elif op=="trunc":
        s=s[:rng.randrange(len(s))]
    elif op=="dup":
        i=rng.randrange(len(s)); n=min(len(s)-i,rng.randrange(1,8)); s[i:i]=s[i:i+n]
    else:
        t=rng.choice(TOKENS); i=rng.randrange(len(s)); s[i:i]=list(t)
    return "".join(s)

def gen(n, out, seed=0xCF6):
    rng=random.Random(seed); seen=set(); ncase=0
    with open(out,"w") as f:
        names=list(SEEDS)
        while ncase<n:
            st=rng.choice(names); fn,src=SEEDS[st]
            m=mutate(rng,src)
            h=hashlib.sha1((st+m).encode()).hexdigest()
            if h in seen or m==src: continue
            seen.add(h); f.write(json.dumps({"id":h[:16],"stage":st,"file":fn,"src":m})+"\n"); ncase+=1
    print("generated",ncase,"->",out)

def one(c):
    d=os.path.join(TMP,c["stage"]); os.makedirs(d,exist_ok=True)
    for junk in os.listdir(d):
        try: os.unlink(os.path.join(d,junk))
        except OSError: pass
    open(os.path.join(d,c["file"]),"w").write(c["src"])
    o,e=os.path.join(d,"o"),os.path.join(d,"e")
    if c["stage"]=="pkg":
        r=sb.run_measured([MOONC,"syncheck","moon.pkg"],d,5,o,e)
    elif c["stage"]=="mbtmd":
        r=sb.run_measured([MOONC,"syncheck","doc.mbt.md"],d,5,o,e)
    else:
        r=sb.run_measured([MOONC,"build-interface","-pkg","x/y","-i",PRE,"-o","x.mi","x.mbti"],d,5,o,e)
    st,sig=sb.classify(r)
    return {"id":c["id"],"stage":c["stage"],"src":c["src"],"status":st,"sig":sig,
            "rc":r["rc"],"ms":r["ms"],"rss_kb":r["rss_kb"],"stderr":r["stderr"][:300]}

def run(cases,out,budget):
    import time
    rows=[]; t0=time.time()
    for i,line in enumerate(open(cases)):
        c=json.loads(line)
        if time.time()-t0>budget: print("budget exhausted at",i); break
        rows.append(one(c))
        if (i+1)%1000==0:
            print(" ",i+1,"%.1fs"%(time.time()-t0),flush=True)
    with open(out,"w") as f:
        for r in rows: f.write(json.dumps(r)+"\n")
    print("ran",len(rows),"in %.1fs"%(time.time()-t0),"->",out)

def report():
    import collections
    rows=[json.loads(l) for l in open(os.path.join(ROOT,"out","cfg_results.jsonl"))]
    print("n",len(rows),"stages",dict(collections.Counter(r["stage"] for r in rows)))
    print("status",dict(collections.Counter(r["status"] for r in rows)))
    an=[r for r in rows if r["status"] in ("ice","crash","timeout","silent")]
    print("anomalies",len(an))
    for r in an[:15]: print(" ",r["stage"],r["status"],r["rc"],r["sig"][:100],"|",r["src"][:60].replace("\n"," "))
    sigs=collections.Counter(r["sig"] for r in rows)
    print("top sigs")
    for s,c in sigs.most_common(10): print(" ",c,s[:110])

if __name__=="__main__":
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest="cmd",required=True)
    g=sub.add_parser("gen"); g.add_argument("--n",type=int,default=10000); g.add_argument("--out",default=os.path.join(ROOT,"out","cfg_cases.jsonl"))
    r=sub.add_parser("run"); r.add_argument("--cases",default=os.path.join(ROOT,"out","cfg_cases.jsonl")); r.add_argument("--out",default=os.path.join(ROOT,"out","cfg_results.jsonl")); r.add_argument("--budget",type=float,default=900)
    sub.add_parser("report"); a=ap.parse_args()
    if a.cmd=="gen": gen(a.n,a.out)
    elif a.cmd=="run": run(a.cases,a.out,a.budget)
    else: report()
