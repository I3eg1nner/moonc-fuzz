#!/usr/bin/env python3
"""Scaling probe over 20 syntactic dimensions.

For each dimension and k, measure moonc syncheck and moonfmt wall time / peak
RSS / output bytes.  Flag a dimension when time more than triples per doubling
and the formatted output does not grow comparably (output-driven growth such as
indentation is not a defect).

Usage:
  python3 harness/scale_probe.py selftest
  python3 harness/scale_probe.py run --out out/scale_probe.json
"""
from __future__ import annotations
import argparse, json, math, os, sys
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,HERE); import syntax_boundary as sb
MOONC=os.path.expanduser("~/.moon/bin/moonc"); FMT=os.path.expanduser("~/.moon/bin/moonfmt")
TMP=os.path.join(ROOT,"out","scale_probe_tmp"); KS=[4,8,16,32,64,128,256,512]

def series():
    S=[]
    for k in KS:
        ty="T0"
        for i in range(1,k): ty="(%s, T%d)"%(ty,i)
        S.append(("gen_params",k,"fn[%s] f(x : %s) -> T0 { x.0 }\n"%(", ".join("T%d"%i for i in range(k)),ty)))
        S.append(("labels",k,"fn f(%s) -> Int { a0 }\n"%(", ".join("a%d~ : Int"%i for i in range(k)))))
        S.append(("match_or",k,"fn f(x : Int) -> Int { match x { %s => 1; _ => 0 } }\n"%(" | ".join(str(i) for i in range(k)))))
        S.append(("nested_array_type",k,"fn f(x : %sInt%s) -> Int { 0 }\n"%("Array["*k,"]"*k)))
        S.append(("nested_tuple_type",k,"fn f(x : %sInt%s) -> Int { 0 }\n"%("("*k,")"*k)))
        body="1"
        for _ in range(k): body="match 1 { _ => %s }"%body
        S.append(("nested_match",k,"fn f() -> Int { %s }\n"%body))
        body="1"
        for _ in range(k): body="try { %s } catch { _ => 0 }"%body
        S.append(("nested_try",k,"suberror E\nfn f() -> Int { %s }\n"%body))
        S.append(("async_fns",k,"".join("async fn f%d() -> Int { 1 }\n"%i for i in range(k))))
        S.append(("array_pattern",k,"fn f(a : Array[Int]) -> Int { match a { [%s] => 0; _ => 1 } }\n"%(", ".join("x%d"%i for i in range(k)))))
        S.append(("trait_methods",k,"trait T { %s }\n"%("; ".join("m%d(Self) -> Int"%i for i in range(k)))))
        S.append(("impl_methods",k,"struct S { x : Int }\n"+"".join("impl S with m%d(self) -> Int { 0 }\n"%i for i in range(k))))
        S.append(("doc_comments",k,"".join("/// doc %d\n"%i for i in range(k))+"fn f() -> Int { 0 }\n"))
        S.append(("enum_ctors",k,"enum E { %s }\n"%("; ".join("C%d"%i for i in range(k)))))
        S.append(("struct_fields",k,"struct S { %s }\n"%("; ".join("f%d : Int"%i for i in range(k)))))
        S.append(("semi_lets",k,"fn f() -> Int { %sa%d }\n"%("".join("let a%d = %d; "%(i,i) for i in range(k)),k-1)))
        S.append(("externs",k,"".join('extern "C" fn e%d(x : Int) -> Int = "e%d"\n'%(i,i) for i in range(k))))
        S.append(("or_pattern_arms",k,"fn f(x : Int) -> Int { match x { %s; _ => 0 } }\n"%("; ".join("%d => %d"%(i,i) for i in range(k)))))
        S.append(("nested_if",k,"fn f() -> Int { %s1%s }\n"%("if true { "*k," }"*k)))
        S.append(("interp",k,'fn f() -> String { "%s" }\n'%("".join("\\{%d}"%i for i in range(k)))))
    return S

def fit(xs,ys):
    pts=[(math.log(x),math.log(y)) for x,y in zip(xs,ys) if x>0 and y>0]
    if len(pts)<3: return None
    n=len(pts); sx=sum(p[0] for p in pts); sy=sum(p[1] for p in pts)
    sxx=sum(p[0]**2 for p in pts); sxy=sum(p[0]*p[1] for p in pts)
    den=n*sxx-sx*sx
    return (n*sxy-sx*sy)/den if abs(den)>1e-12 else None

def run(out):
    d=os.path.join(TMP,"w"); os.makedirs(d,exist_ok=True)
    o,e=os.path.join(d,"o"),os.path.join(d,"e")
    rows=[]
    for name,k,src in series():
        p=os.path.join(d,"s.mbt"); open(p,"w").write(src)
        r=sb.run_measured([MOONC,"syncheck","s.mbt"],d,20,o,e)
        st,sig=sb.classify(r)
        fr=sb.run_measured([FMT,"s.mbt","-o","sf.mbt"],d,30,o,e)
        fst,fsig=sb.classify(fr)
        fb=os.path.getsize(os.path.join(d,"sf.mbt")) if fst.startswith("ok") and os.path.exists(os.path.join(d,"sf.mbt")) else None
        rows.append({"series":name,"k":k,"bytes":len(src),"status":st,"sig":sig,"ms":r["ms"],"rss_kb":r["rss_kb"],
                     "fmt_status":fst,"fmt_ms":fr["ms"],"fmt_rss_kb":fr["rss_kb"],"fmt_sig":fsig,"fmt_bytes":fb})
        print("%-18s k=%-4d syn %-8s %7.1fms | fmt %-8s %8.1fms %s"%(name,k,st,r["ms"],fst,fr["ms"],fb))
    summ=[]
    for name in dict.fromkeys(r["series"] for r in rows):
        rs=[r for r in rows if r["series"]==name]
        ok=[r for r in rs if r["status"].startswith("ok")]
        fok=[r for r in rs if r["fmt_status"].startswith("ok")]
        def pair(vals,ks,field):
            dd={k:v for k,v in zip(ks,vals)}
            return max((dd[2*k]/dd[k] for k in ks if 2*k in dd and dd[k]>0),default=None)
        td=pair([r["ms"] for r in ok],[r["k"] for r in ok],None)
        fd=pair([r["fmt_ms"] for r in fok],[r["k"] for r in fok],None)
        od=pair([r["fmt_bytes"] for r in fok if r["fmt_bytes"]],[r["k"] for r in fok if r["fmt_bytes"]],None)
        flags=[]
        if td and td>3: flags.append("syn_time_x%.1f"%td)
        if fd and fd>3:
            if od and od>3: flags.append("fmt_output_x%.1f"%od)
            else: flags.append("fmt_time_x%.1f"%fd)
        bad=[r["k"] for r in rs if not r["status"].startswith("ok")]
        fbad=[r["k"] for r in rs if not r["fmt_status"].startswith("ok")]
        if bad: flags.append("syn_fail")
        if fbad: flags.append("fmt_fail")
        summ.append({"series":name,"syn_doubling":td,"fmt_doubling":fd,"fmt_out_doubling":od,
                     "bad_k":bad,"fmt_bad_k":fbad,"flags":flags})
        print("SLOPE %-18s syn=%.1f fmt=%.1f out=%.1f %s"%(name,td or 0,fd or 0,od or 0,",".join(flags) or "ok"))
    json.dump({"rows":rows,"summary":summ},open(out,"w"),indent=1)
    print("->",out)
    return 0

def selftest():
    d=os.path.join(TMP,"st"); os.makedirs(d,exist_ok=True); o,e=os.path.join(d,"o"),os.path.join(d,"e")
    bad=0
    for name,k,src in series():
        if k!=8: continue
        open(os.path.join(d,"s.mbt"),"w").write(src)
        r=sb.run_measured([MOONC,"syncheck","s.mbt"],d,10,o,e); st,sig=sb.classify(r)
        print("%-18s %-8s %s"%(name,st,"" if st.startswith("ok") else sig[:90])); bad+=0 if st.startswith("ok") else 1
    print("bad",bad,"/20")
    return 1 if bad else 0

if __name__=="__main__":
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest="cmd",required=True)
    r=sub.add_parser("run"); r.add_argument("--out",default=os.path.join(ROOT,"out","scale_probe.json"))
    sub.add_parser("selftest"); a=ap.parse_args()
    sys.exit(run(a.out) if a.cmd=="run" else selftest())
