#!/usr/bin/env python3
"""Constrained sweep: reward:risk >= 1:2 (TP >= 2x SL). Adjust SL to find the best
win rate AND the best expectancy. Gold pip = 0.10; 2-pip spread charged per trade.

At 1:2 the break-even win rate is 33.3%; at 1:2.5 it is 28.6%; at 1:3 it is 25%.
A config is GOOD when win rate clears that line (expectancy/profit factor > 1)."""
import os, itertools
from grid_search import load, signals, evaluate, summarize

BASE = os.path.dirname(os.path.abspath(__file__))

def breakeven(rr):  # win rate needed to break even (before spread)
    return 100.0 / (1.0 + rr)

def sweep(path, label, max_hold, Ls=(3, 5, 8), RRs=(2.0, 2.5, 3.0),
          SLs=(10, 15, 20, 30, 40, 50, 70, 100, 150), spread=2.0):
    o, h, l, c = load(path)
    print(f"\n{'='*104}\n{label}  ({len(c)} bars)  spread={spread}pip  max_hold={max_hold}\n{'='*104}")
    # cache signals per swing length
    sig_cache = {L: signals(o, h, l, c, L=L) for L in Ls}
    best_wr = None; best_pf = None
    rows = []
    for L, rr, sl in itertools.product(Ls, RRs, SLs):
        tp = rr * sl
        s = summarize(evaluate(o, h, l, c, sig_cache[L], sl, tp, max_hold=max_hold, spread_pips=spread))
        if not s or s["n"] < 25:        # ignore tiny samples
            continue
        rec = (L, rr, sl, s)
        rows.append(rec)
        if best_wr is None or s["wr"] > best_wr[3]["wr"]: best_wr = rec
        if best_pf is None or s["pf"] > best_pf[3]["pf"]: best_pf = rec

    # focused table at exactly 1:2, swing=5, across SL
    print(f"\n  R:R = 1:2  (break-even win rate = {breakeven(2.0):.1f}%),  swing=5:")
    print(f"  {'SL(pip)':>7} {'TP(pip)':>7} | {'trades':>6} | {'win%':>6} | {'exp(pip)':>9} | {'PF':>5} | {'total(pip)':>10} | {'maxConsecLoss':>13}")
    for L, rr, sl, s in sorted([r for r in rows if r[0]==5 and r[1]==2.0], key=lambda r:r[2]):
        pf = f"{s['pf']:.2f}" if s['pf']!=float('inf') else "inf"
        flag = "  <= beats break-even" if s['wr'] > breakeven(2.0) else ""
        print(f"  {sl:>7} {rr*sl:>7.0f} | {s['n']:>6} | {s['wr']:>5.1f}% | {s['exp']:>9.2f} | {pf:>5} | {s['total']:>10.0f} | {s['mcl']:>13}{flag}")

    print(f"\n  >> BEST WIN RATE (R:R>=1:2): swing={best_wr[0]}, R:R=1:{best_wr[1]:g}, SL={best_wr[2]}pip, TP={best_wr[1]*best_wr[2]:.0f}pip"
          f" -> win {best_wr[3]['wr']:.1f}%, exp {best_wr[3]['exp']:.2f} pip, PF {best_wr[3]['pf']:.2f}, n={best_wr[3]['n']}")
    print(f"  >> BEST PROFIT FACTOR (R:R>=1:2): swing={best_pf[0]}, R:R=1:{best_pf[1]:g}, SL={best_pf[2]}pip, TP={best_pf[1]*best_pf[2]:.0f}pip"
          f" -> win {best_pf[3]['wr']:.1f}%, exp {best_pf[3]['exp']:.2f} pip, PF {best_pf[3]['pf']:.2f}, total {best_pf[3]['total']:.0f}, n={best_pf[3]['n']}")
    # top 5 by profit factor
    print("  top 5 by profit factor:")
    for L, rr, sl, s in sorted(rows, key=lambda r:-r[3]["pf"])[:5]:
        pf = f"{s['pf']:.2f}" if s['pf']!=float('inf') else "inf"
        print(f"     swing={L} R:R=1:{rr:g} SL={sl} TP={rr*sl:.0f} | win {s['wr']:.1f}% | exp {s['exp']:.2f} | PF {pf} | total {s['total']:.0f} | n={s['n']}")
    return rows

if __name__ == "__main__":
    sweep(os.path.join(BASE, "gold_1m.csv"),  "1-MINUTE GC=F",  240)
    sweep(os.path.join(BASE, "gold_5m.csv"),  "5-MINUTE GC=F",  120)
    sweep(os.path.join(BASE, "gold_15m.csv"), "15-MINUTE GC=F", 96)
    sweep(os.path.join(BASE, "gold_1h.csv"),  "1-HOUR GC=F",    72)
