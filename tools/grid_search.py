#!/usr/bin/env python3
"""Sweep stop-loss / take-profit sizes to find the highest win rate for the
Sniper Entry signals, and show expectancy alongside so the number is honest.

Entry = reclaim close of the signal bar (same non-repainting detection).
SL/TP are absolute pip distances from entry. First-touch exit; if a bar covers
BOTH, it is counted as the STOP (pessimistic). Gold pip = 0.10."""
import os, itertools
from sniper_strategy import detect_buy, detect_sell

PIP = 0.10

def load(path):
    import pandas as pd
    d = pd.read_csv(path)
    return (d.Open.values.astype(float), d.High.values.astype(float),
            d.Low.values.astype(float), d.Close.values.astype(float))

def signals(o, h, l, c, L=5, reclaim_bars=3, require_abcd=True):
    """Return list of (i, direction) for every detected signal (both sides)."""
    rt = len(c); out = []
    for i in range(L + 1, rt - 1):
        if detect_buy(i, rt, o, h, l, c, L=L, reclaim_bars=reclaim_bars, require_abcd=require_abcd):
            out.append((i, "buy"));  continue
        if detect_sell(i, rt, o, h, l, c, L=L, reclaim_bars=reclaim_bars, require_abcd=require_abcd):
            out.append((i, "sell"))
    return out

def evaluate(o, h, l, c, sigs, sl_pips, tp_pips, max_hold=240, spread_pips=0.0,
             one_at_a_time=True):
    rt = len(c)
    sl_d = sl_pips * PIP; tp_d = tp_pips * PIP
    trades = []; busy = -1
    for i, d in sigs:
        if one_at_a_time and i <= busy:
            continue
        entry = c[i]
        if d == "buy":
            sl = entry - sl_d; tp = entry + tp_d
        else:
            sl = entry + sl_d; tp = entry - tp_d
        outcome = None; ex = None
        for j in range(i + 1, min(rt, i + 1 + max_hold)):
            if d == "buy":
                hit_sl = l[j] <= sl; hit_tp = h[j] >= tp
            else:
                hit_sl = h[j] >= sl; hit_tp = l[j] <= tp
            if hit_sl: outcome = "loss"; ex = j; break   # stop-first on ambiguous
            if hit_tp: outcome = "win";  ex = j; break
        if outcome is None:
            ex = min(rt - 1, i + max_hold)
            pnl = (c[ex] - entry) if d == "buy" else (entry - c[ex])
            pnl_pips = pnl / PIP
            outcome = "win" if pnl > 0 else "loss"
        else:
            pnl_pips = tp_pips if outcome == "win" else -sl_pips
        trades.append((outcome, pnl_pips - spread_pips))
        busy = ex
    return trades

def summarize(trades):
    n = len(trades)
    if n == 0: return None
    wins = sum(1 for o, _ in trades if o == "win")
    wr = wins / n * 100
    net = [p for _, p in trades]
    gp = sum(x for x in net if x > 0); gl = -sum(x for x in net if x < 0)
    pf = (gp / gl) if gl > 0 else float("inf")
    exp = sum(net) / n
    # max consecutive losses
    mcl = cur = 0
    for o, _ in trades:
        cur = cur + 1 if o == "loss" else 0
        mcl = max(mcl, cur)
    return dict(n=n, wr=wr, exp=exp, pf=pf, total=sum(net), mcl=mcl)

def run(path, label, L=5, max_hold=240, spread=2.0):
    o, h, l, c = load(path)
    sigs = signals(o, h, l, c, L=L)
    print(f"\n{'='*100}\n{label}  ({len(c)} bars, {len(sigs)} raw signals)  spread={spread}pip  max_hold={max_hold}\n{'='*100}")
    SL = [5, 10, 20, 30, 50, 80, 120, 200, 300]
    TP = [1, 2, 3, 5, 8, 10, 15, 20, 30]
    rows = []
    for sl, tp in itertools.product(SL, TP):
        s = summarize(evaluate(o, h, l, c, sigs, sl, tp, max_hold=max_hold, spread_pips=spread))
        if s: rows.append((sl, tp, s))
    # all rows with win rate >= 90, best expectancy first
    hi = [r for r in rows if r[2]["wr"] >= 90]
    hi.sort(key=lambda r: (-r[2]["exp"], -r[2]["wr"]))
    print(f"\n  >>> configs with WIN RATE >= 90%  ({len(hi)} found) — sorted by expectancy:")
    print(f"  {'SL(pip)':>7} {'TP(pip)':>7} | {'trades':>6} | {'win%':>6} | {'exp/trade(pip)':>14} | {'profit factor':>13} | {'total(pip)':>10} | {'maxConsecLoss':>13}")
    for sl, tp, s in hi[:15]:
        pf = f"{s['pf']:.2f}" if s['pf'] != float('inf') else "inf"
        print(f"  {sl:>7} {tp:>7} | {s['n']:>6} | {s['wr']:>5.1f}% | {s['exp']:>14.2f} | {pf:>13} | {s['total']:>10.0f} | {s['mcl']:>13}")
    if not hi:
        best = max(rows, key=lambda r: r[2]["wr"])
        sl, tp, s = best
        print(f"  (none >=90%.  Highest = {s['wr']:.1f}% at SL={sl} TP={tp}, exp {s['exp']:.2f} pip, PF {s['pf']:.2f})")
    # also: best expectancy overall (regardless of win rate)
    be = max(rows, key=lambda r: r[2]["exp"])
    sl, tp, s = be
    pf = f"{s['pf']:.2f}" if s['pf'] != float('inf') else "inf"
    print(f"\n  best EXPECTANCY overall: SL={sl} TP={tp} -> win {s['wr']:.1f}%, exp {s['exp']:.2f} pip, PF {pf}, total {s['total']:.0f} pip, n={s['n']}")
    return rows

if __name__ == "__main__":
    base = os.path.dirname(os.path.abspath(__file__))
    run(os.path.join(base, "gold_1m.csv"),  "1-MINUTE GC=F", L=5, max_hold=240)
    run(os.path.join(base, "gold_5m.csv"),  "5-MINUTE GC=F", L=5, max_hold=120)
    run(os.path.join(base, "gold_15m.csv"), "15-MINUTE GC=F", L=5, max_hold=96)
