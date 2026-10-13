#!/usr/bin/env python3
"""Validate + backtest the COMBO logic: Codex's higher-timeframe (M15) support
context + my sweep/reclaim A-B-C-D trigger on M1. Compares three on the same data:
  A) MINE   - single-TF A-B-C-D sweep/reclaim on M1
  C) COMBO  - M15 pivot-low support, M1 sweep-below + bullish reclaim
Gold pip = 0.10; first-touch exits, stop-first on ambiguous bars; 2-pip spread."""
import os, bisect
import numpy as np, pandas as pd
from grid_search import load, signals, evaluate, summarize   # MINE
PIP = 0.10
BASE = os.path.dirname(os.path.abspath(__file__))

# ---------- build M15 from M1 ----------
df = pd.read_csv(os.path.join(BASE, "gold_1m.csv"), parse_dates=["Datetime"]).set_index("Datetime")
m1 = df[["Open","High","Low","Close"]].astype(float)
m15 = m1.resample("15min").agg({"Open":"first","High":"max","Low":"min","Close":"last"}).dropna()
print(f"M1 bars={len(m1)}  M15 bars={len(m15)}")

o1,h1,l1,c1 = m1.Open.values,m1.High.values,m1.Low.values,m1.Close.values
t1 = m1.index.view("int64")//10**9                      # unix seconds
oH,hH,lH,cH = m15.Open.values,m15.High.values,m15.Low.values,m15.Close.values
tH = m15.index.view("int64")//10**9
HTF_SEC = 15*60

def htf_pivots(strength):
    n=len(lH); lastClosed=n-2                            # ignore possibly-forming last bar
    lows=[]; highs=[]
    for p in range(strength, lastClosed-strength+1):
        if all(lH[p]<lH[p+k] and lH[p]<lH[p-k] for k in range(1,strength+1)):
            conf = tH[p+strength]+HTF_SEC                # available only after right bars close
            lows.append((conf, tH[p], lH[p], p))
        if all(hH[p]>hH[p+k] and hH[p]>hH[p-k] for k in range(1,strength+1)):
            conf = tH[p+strength]+HTF_SEC
            highs.append((conf, tH[p], hH[p], p))
    return lows, highs

def combo_signals(strength=2, zone_pips=15.0, max_dist_pips=250.0, require_abcd=False,
                  expiry=20, cooldown=10):
    lows, highs = htf_pivots(strength)
    lc = [x[0] for x in lows]
    zone = zone_pips*PIP; maxd = max_dist_pips*PIP
    out=[]; active=False; level=0.0; extreme=0.0; armbar=-1; cool=0
    for i in range(len(c1)):
        if cool>0: cool-=1
        if active:
            extreme=min(extreme,l1[i])
            if i-armbar>expiry:
                active=False
            elif extreme<level and c1[i]>level and c1[i]>o1[i]:   # sweep then bullish reclaim
                out.append((i,"buy")); active=False; cool=cooldown
            continue
        if cool>0:
            continue
        t=t1[i]
        kmax=bisect.bisect_right(lc,t)                     # all available M15 pivot lows
        # nearest available pivot low to current price, within lookback window & max distance
        support=None; bestd=1e18; pB=-1
        for j in range(kmax-1, max(-1,kmax-1-60), -1):
            lev=lows[j][2]; d=abs(c1[i]-lev)
            if d<bestd and d<=maxd:
                bestd=d; support=lev; pB=lows[j][3]
        if support is None: continue
        if require_abcd:
            A=[hp for hp in highs if hp[3]<pB and hp[0]<=t]
            C=[hp for hp in highs if hp[3]>pB and hp[0]<=t]
            if not(A and C and C[-1][2]<A[-1][2]): continue
        if l1[i] <= support+zone:                          # price trades down into the support zone -> arm
            active=True; level=support; extreme=l1[i]; armbar=i
    return out

def eval_sig(sig, sl, rr, max_hold=240, spread=2.0):
    return summarize(evaluate(o1,h1,l1,c1, sig, sl, rr*sl, max_hold=max_hold, spread_pips=spread))

print("\nsignal counts:  combo(abcd off)=%d  combo(abcd on)=%d" % (
      len(combo_signals(require_abcd=False)), len(combo_signals(require_abcd=True))))
print("\n--- best config at R:R 1:2.5, SL 100 (the setting that survived OOS for MINE) ---")
mine = [s for s in signals(o1,h1,l1,c1,L=5) if s[1]=="buy"]   # mine, buy only for fair compare
combo = combo_signals(strength=2, require_abcd=False)
for name,sig in [("MINE (M1 A-B-C-D, buy)",mine),("COMBO (M15 support + M1 reclaim)",combo)]:
    s = eval_sig(sig,100,2.5)
    if s:
        pf=f"{s['pf']:.2f}" if s['pf']!=float('inf') else "inf"
        print(f"  {name:38}: n={s['n']:>4}  win={s['wr']:>5.1f}%  exp={s['exp']:>6.2f}  PF={pf}  total={s['total']:>6.0f}")

print("\n--- COMBO across R:R (SL swept), buy-only, 1m ---")
print(f"  {'SL':>4} {'RR':>4} | {'n':>4} | {'win%':>6} | {'exp':>7} | {'PF':>5} | {'total':>7}")
best=None
for rr in (2.0,2.5,3.0):
    for sl in (30,50,70,100,150):
        s=eval_sig(combo,sl,rr)
        if not s or s['n']<25: continue
        pf=f"{s['pf']:.2f}" if s['pf']!=float('inf') else "inf"
        print(f"  {sl:>4} {rr:>4} | {s['n']:>4} | {s['wr']:>5.1f}% | {s['exp']:>7.2f} | {pf:>5} | {s['total']:>7.0f}")
        if best is None or s['pf']>best[2]['pf']: best=(sl,rr,s)
if best is None:
    print("  (no combo config with >=25 trades)")
else:
    print(f"  >> COMBO best PF: SL={best[0]} RR=1:{best[1]} win {best[2]['wr']:.1f}% PF {best[2]['pf']:.2f} exp {best[2]['exp']:.2f} n={best[2]['n']}")
    n=len(c1); sp=int(n*0.6)
    tr=[s for s in combo if s[0]<sp]; te=[s for s in combo if s[0]>=sp]
    sIn=eval_sig(tr,best[0],best[1]); sOut=eval_sig(te,best[0],best[1])
    if sIn and sOut:
        print(f"  >> COMBO OOS: in-sample PF {sIn['pf']:.2f} (win {sIn['wr']:.1f}%) -> out-of-sample PF {sOut['pf']:.2f} (win {sOut['wr']:.1f}%, n={sOut['n']})")
