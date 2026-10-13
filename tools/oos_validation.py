#!/usr/bin/env python3
"""Out-of-sample check for the R:R>=1:2 configs. Optimize (by profit factor) on the
first 60% of the data, then evaluate that EXACT config on the unseen last 40%.
If the edge only shows up in-sample, it's curve-fitting."""
import os, itertools
from grid_search import load, signals, evaluate, summarize

BASE = os.path.dirname(os.path.abspath(__file__))

def split_signals(sigs, split_idx):
    return ([s for s in sigs if s[0] < split_idx],
            [s for s in sigs if s[0] >= split_idx])

def run(path, label, max_hold, spread=2.0):
    o, h, l, c = load(path)
    n = len(c); split = int(n * 0.60)
    print(f"\n{'='*96}\n{label}  ({n} bars; train=first {split}, test=last {n-split})\n{'='*96}")
    Ls = (3, 5, 8); RRs = (2.0, 2.5, 3.0)
    SLs = (15, 20, 30, 40, 50, 70, 100, 150)
    best = None
    for L in Ls:
        sg = signals(o, h, l, c, L=L)
        tr, te = split_signals(sg, split)
        for rr, sl in itertools.product(RRs, SLs):
            s = summarize(evaluate(o, h, l, c, tr, sl, rr*sl, max_hold=max_hold, spread_pips=spread))
            if not s or s["n"] < 30:
                continue
            if best is None or s["pf"] > best[0]["pf"]:
                best = (s, L, rr, sl, te)
    if not best:
        print("  no config with enough train trades"); return
    s_tr, L, rr, sl, te = best
    s_te = summarize(evaluate(o, h, l, c, te, sl, rr*sl, max_hold=max_hold, spread_pips=spread))
    print(f"  Best IN-SAMPLE config: swing={L}, R:R=1:{rr:g}, SL={sl}pip, TP={rr*sl:.0f}pip")
    def line(tag, s):
        if not s: print(f"    {tag}: (no trades)"); return
        pf = f"{s['pf']:.2f}" if s['pf']!=float('inf') else "inf"
        verdict = "PROFITABLE" if s['exp']>0 else "losing"
        print(f"    {tag:>16}: win {s['wr']:>5.1f}% | exp {s['exp']:>7.2f} pip | PF {pf:>5} | total {s['total']:>7.0f} pip | n={s['n']:>4}  -> {verdict}")
    line("IN-SAMPLE (train)", s_tr)
    line("OUT-OF-SAMPLE (test)", s_te)

if __name__ == "__main__":
    run(os.path.join(BASE, "gold_1m.csv"),  "1-MINUTE GC=F",  240)
    run(os.path.join(BASE, "gold_5m.csv"),  "5-MINUTE GC=F",  120)
    run(os.path.join(BASE, "gold_15m.csv"), "15-MINUTE GC=F", 96)
    run(os.path.join(BASE, "gold_1h.csv"),  "1-HOUR GC=F",    72)
