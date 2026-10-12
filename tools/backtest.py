#!/usr/bin/env python3
"""Backtest the Sniper Entry false-breakout strategy on real gold (GC=F) data.

Honest simulation:
  * Signal confirmed at CLOSE of bar i (same non-repainting logic as the indicator).
  * Entry = close[i]; exits scanned from bar i+1 (no look-ahead).
  * First-touch exit: if a bar's range hits BOTH stop and target, count it as the
    STOP (pessimistic — we only have OHLC, not ticks).
  * One position at a time (a new signal is skipped while a trade is open).
  * Win rate is reported cost-free (TP before SL); expectancy is reported with a
    realistic spread subtracted per trade.
Gold pip = 0.10  (so 2 pips = 0.20, matching the video's 1819.83 -> 1819.63).
"""
import sys, pandas as pd
from sniper_strategy import detect_buy, detect_sell

PIP = 0.10

def load(path):
    d = pd.read_csv(path)
    return (d.Open.values.astype(float), d.High.values.astype(float),
            d.Low.values.astype(float), d.Close.values.astype(float))

def simulate(o, h, l, c, direction, L=5, reclaim_bars=3, require_abcd=True,
             stop_model="structure", fixed_stop_pips=2.0, stop_buffer_pips=1.0,
             rr=2.0, max_hold=240, one_at_a_time=True):
    detect = detect_buy if direction == "buy" else detect_sell
    rt = len(c); trades = []; busy_until = -1
    for i in range(L + 1, rt - 1):
        if one_at_a_time and i <= busy_until:
            continue
        r = detect(i, rt, o, h, l, c, L=L, reclaim_bars=reclaim_bars, require_abcd=require_abcd)
        if not r:
            continue
        entry = c[i]
        if direction == "buy":
            sl = (entry - fixed_stop_pips * PIP) if stop_model == "fixed" \
                 else (r["sweep"] - stop_buffer_pips * PIP)
            risk = entry - sl
            if risk <= 0: continue
            tp = entry + rr * risk
            outcome = None; exit_i = None
            for j in range(i + 1, min(rt, i + 1 + max_hold)):
                hit_sl = l[j] <= sl; hit_tp = h[j] >= tp
                if hit_sl: outcome = "loss"; exit_i = j; break      # stop-first on ambiguous
                if hit_tp: outcome = "win";  exit_i = j; break
            if outcome is None:
                exit_i = min(rt - 1, i + max_hold)
                pnl = c[exit_i] - entry
                outcome = "win" if pnl > 0 else "loss"; timeout = True
                pnl_pips = pnl / PIP
            else:
                timeout = False
                pnl_pips = (rr * risk / PIP) if outcome == "win" else (-risk / PIP)
        else:  # sell
            sl = (entry + fixed_stop_pips * PIP) if stop_model == "fixed" \
                 else (r["sweep"] + stop_buffer_pips * PIP)
            risk = sl - entry
            if risk <= 0: continue
            tp = entry - rr * risk
            outcome = None; exit_i = None
            for j in range(i + 1, min(rt, i + 1 + max_hold)):
                hit_sl = h[j] >= sl; hit_tp = l[j] <= tp
                if hit_sl: outcome = "loss"; exit_i = j; break
                if hit_tp: outcome = "win";  exit_i = j; break
            if outcome is None:
                exit_i = min(rt - 1, i + max_hold)
                pnl = entry - c[exit_i]
                outcome = "win" if pnl > 0 else "loss"; timeout = True
                pnl_pips = pnl / PIP
            else:
                timeout = False
                pnl_pips = (rr * risk / PIP) if outcome == "win" else (-risk / PIP)
        trades.append(dict(i=i, outcome=outcome, timeout=timeout,
                           risk_pips=risk / PIP, pnl_pips=pnl_pips, bars=exit_i - i))
        busy_until = exit_i
    return trades

def stats(trades, spread_pips=0.0):
    n = len(trades)
    if n == 0: return None
    wins = [t for t in trades if t["outcome"] == "win"]
    wr = len(wins) / n * 100
    net = [t["pnl_pips"] - spread_pips for t in trades]
    gp = sum(x for x in net if x > 0); gl = -sum(x for x in net if x < 0)
    pf = (gp / gl) if gl > 0 else float("inf")
    exp = sum(net) / n
    avg_risk = sum(t["risk_pips"] for t in trades) / n
    nto = sum(1 for t in trades if t["timeout"])
    return dict(n=n, wr=wr, exp=exp, pf=pf, avg_risk=avg_risk,
                total=sum(net), timeouts=nto)

def run_tf(path, label, L=5, max_hold=240):
    o, h, l, c = load(path)
    print(f"\n{'='*94}\n{label}   ({len(c)} bars)   swing={L}, max_hold={max_hold} bars\n{'='*94}")
    for stop_model, sdesc in [("fixed", "FIXED 2-pip stop (literal, as in the video title)"),
                              ("structure", "STRUCTURE stop (just below the sweep low D)")]:
        print(f"\n  --- {sdesc} ---")
        print(f"  {'R:R':>5} | {'trades':>6} | {'win%':>6} | {'avgRisk(pip)':>12} | "
              f"{'exp/trade(pip)':>14} | {'exp w/2pip sprd':>15} | {'PF(0sprd)':>9} | {'timeouts':>8}")
        for rr in [1, 1.5, 2, 3, 5, 10]:
            allt = []
            for d in ("buy", "sell"):
                allt += simulate(o, h, l, c, d, L=L, stop_model=stop_model, rr=rr,
                                 max_hold=max_hold)
            s0 = stats(allt, 0.0); s2 = stats(allt, 2.0)
            if not s0:
                print(f"  {rr:>5} |   no trades"); continue
            pf = f"{s0['pf']:.2f}" if s0['pf'] != float('inf') else "inf"
            print(f"  {rr:>5} | {s0['n']:>6} | {s0['wr']:>5.1f}% | {s0['avg_risk']:>12.1f} | "
                  f"{s0['exp']:>14.2f} | {s2['exp']:>15.2f} | {pf:>9} | {s0['timeouts']:>8}")

if __name__ == "__main__":
    import os
    base = os.path.dirname(os.path.abspath(__file__))
    run_tf(os.path.join(base, "gold_1m.csv"),  "1-MINUTE  GC=F (truest to the strategy)", L=5, max_hold=240)
    run_tf(os.path.join(base, "gold_5m.csv"),  "5-MINUTE  GC=F", L=5, max_hold=120)
    run_tf(os.path.join(base, "gold_15m.csv"), "15-MINUTE GC=F (the video's context TF)", L=5, max_hold=96)
    run_tf(os.path.join(base, "gold_1h.csv"),  "1-HOUR    GC=F (2-year sample)", L=5, max_hold=72)
