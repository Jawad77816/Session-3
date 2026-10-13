#!/usr/bin/env python3
"""Stress-test the one config that survived OOS: 1-minute, swing=5, SL=100 / TP=250
(R:R 1:2.5). Multiple splits, consistency over time-thirds, equity curve & drawdown.
Also draw the in-sample vs out-of-sample robustness chart across timeframes."""
import os, itertools
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from grid_search import load, signals, evaluate, summarize

BASE=os.path.dirname(os.path.abspath(__file__))
SURFACE="#fcfcfb"; INK="#0b0b0b"; INK2="#52514e"; GRID="#e6e5e1"
BLUE="#2a78d6"; ORANGE="#eb6834"; GOOD="#1baf7a"; BAD="#eb6834"

def trades_of(path, L, sl, rr, max_hold, spread=2.0):
    o,h,l,c = load(path); sg=signals(o,h,l,c,L=L)
    # reuse evaluate but need per-trade pnl list -> re-implement lightly
    from grid_search import PIP
    rt=len(c); sl_d=sl*PIP; tp_d=rr*sl*PIP; out=[]; busy=-1
    for i,d in sg:
        if i<=busy: continue
        entry=c[i]
        if d=="buy": SL=entry-sl_d; TP=entry+tp_d
        else: SL=entry+sl_d; TP=entry-tp_d
        oc=None; ex=None
        for j in range(i+1, min(rt,i+1+max_hold)):
            hs=(l[j]<=SL) if d=="buy" else (h[j]>=SL)
            ht=(h[j]>=TP) if d=="buy" else (l[j]<=TP)
            if hs: oc="loss"; ex=j; break
            if ht: oc="win"; ex=j; break
        if oc is None:
            ex=min(rt-1,i+max_hold); pnl=(c[ex]-entry) if d=="buy" else (entry-c[ex])
            pp=pnl/PIP; oc="win" if pnl>0 else "loss"
        else:
            pp=(rr*sl) if oc=="win" else -sl
        out.append((i, oc, pp-spread)); busy=ex
    return out

def eq_stats(trades):
    eq=0; peak=0; mdd=0; curve=[]
    for _,_,p in trades:
        eq+=p; peak=max(peak,eq); mdd=min(mdd, eq-peak); curve.append(eq)
    wins=sum(1 for _,o,_ in trades if o=="win"); n=len(trades)
    return dict(n=n, wr=wins/n*100 if n else 0, total=eq, mdd=mdd, curve=curve)

# ---- 1m config stress test ----
L,sl,rr,mh = 5,100,2.5,240
tr = trades_of(os.path.join(BASE,"gold_1m.csv"), L, sl, rr, mh)
full = eq_stats(tr)
print(f"1m config swing={L} SL={sl} TP={rr*sl:.0f} (1:{rr}):  n={full['n']}  win={full['wr']:.1f}%  "
      f"total={full['total']:.0f} pip  maxDD={full['mdd']:.0f} pip")
# thirds
th = len(tr)//3
for k,seg in enumerate([tr[:th], tr[th:2*th], tr[2*th:]]):
    s=eq_stats(seg)
    print(f"   third {k+1}: n={s['n']:>3}  win={s['wr']:.1f}%  total={s['total']:>6.0f} pip")
# multiple split ratios OOS
print("  OOS at different split points (train->test PF):")
o,h,l,c = load(os.path.join(BASE,"gold_1m.csv")); sg=signals(o,h,l,c,L=L); n=len(c)
for frac in (0.5,0.6,0.7):
    sp=int(n*frac)
    teS=summarize(evaluate(o,h,l,c,[s for s in sg if s[0]>=sp], sl, rr*sl, max_hold=mh, spread_pips=2.0))
    if teS:
        print(f"     split {int(frac*100)}%: OOS win {teS['wr']:.1f}% PF {teS['pf']:.2f} exp {teS['exp']:.2f} n={teS['n']}")

# ---- OOS robustness across timeframes (recompute best-in-sample -> OOS) ----
def best_oos(path, max_hold):
    o,h,l,c=load(path); n=len(c); sp=int(n*0.6)
    best=None
    for Lx in (3,5,8):
        sgx=signals(o,h,l,c,L=Lx); trx=[s for s in sgx if s[0]<sp]; tex=[s for s in sgx if s[0]>=sp]
        for rrx,slx in itertools.product((2.0,2.5,3.0),(15,20,30,40,50,70,100,150)):
            s=summarize(evaluate(o,h,l,c,trx,slx,rrx*slx,max_hold=max_hold,spread_pips=2.0))
            if not s or s["n"]<30: continue
            if best is None or s["pf"]>best[0]["pf"]: best=(s,Lx,rrx,slx,tex)
    sIn,Lx,rrx,slx,tex=best
    sOut=summarize(evaluate(o,h,l,c,tex,slx,rrx*slx,max_hold=max_hold,spread_pips=2.0))
    return sIn["pf"], (sOut["pf"] if sOut else 0)

tfs=[("1-min","gold_1m.csv",240),("5-min","gold_5m.csv",120),("15-min","gold_15m.csv",96),("1-hour","gold_1h.csv",72)]
pf_in=[]; pf_out=[]
for lab,f,mh2 in tfs:
    pin,pout=best_oos(os.path.join(BASE,f),mh2); pf_in.append(pin); pf_out.append(pout)
    print(f"  {lab}: in-sample PF {pin:.2f} -> OOS PF {pout:.2f}")

# ---- chart ----
fig,axes=plt.subplots(1,2,figsize=(12.6,5.3)); fig.patch.set_facecolor(SURFACE)
ax=axes[0]; ax.set_facecolor(SURFACE)
x=range(len(tfs)); w=0.38
ax.bar([i-w/2 for i in x], pf_in, w, color=BLUE, label="in-sample (fit here)", zorder=3)
ax.bar([i+w/2 for i in x], pf_out, w, color=ORANGE, label="out-of-sample (unseen)", zorder=3)
ax.axhline(1.0, color=INK, lw=1.3, ls="--", zorder=2)
ax.text(len(tfs)-0.5, 1.02, "break-even (PF = 1)", ha="right", color=INK2, fontsize=8.5)
for i,(pi,po) in enumerate(zip(pf_in,pf_out)):
    ax.text(i-w/2, pi+0.02, f"{pi:.2f}", ha="center", fontsize=8.5, color=INK, fontweight="bold")
    ax.text(i+w/2, po+0.02, f"{po:.2f}", ha="center", fontsize=8.5,
            color=(GOOD if po>=1 else BAD), fontweight="bold")
ax.set_xticks(list(x)); ax.set_xticklabels([t[0] for t in tfs], color=INK2)
ax.set_ylabel("Profit factor", color=INK2, fontsize=10); ax.set_ylim(0,1.4)
ax.set_title("Only 1-minute survives out-of-sample  (R:R ≥ 1:2, best config per TF)",
             color=INK, fontsize=10.5, fontweight="bold", loc="left", pad=8)
ax.tick_params(colors=INK2)
for s in ["top","right"]: ax.spines[s].set_visible(False)
for s in ["left","bottom"]: ax.spines[s].set_color(GRID)
ax.grid(axis="y", color=GRID, lw=0.7, zorder=0); ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper right")

ax2=axes[1]; ax2.set_facecolor(SURFACE)
ax2.plot(range(1,len(full["curve"])+1), full["curve"], color=BLUE, lw=2, zorder=3)
ax2.axhline(0, color=INK2, lw=1, zorder=2)
ax2.fill_between(range(1,len(full["curve"])+1), full["curve"], 0,
                 where=[v>=0 for v in full["curve"]], color=GOOD, alpha=0.12, zorder=1)
ax2.set_title(f"1-min SL100/TP250 (1:2.5) equity — {full['wr']:.0f}% win, +{full['total']:.0f} pip, maxDD {full['mdd']:.0f} pip",
              color=INK, fontsize=10.5, fontweight="bold", loc="left", pad=8)
ax2.set_xlabel("Trade number (28 days)", color=INK2, fontsize=10)
ax2.set_ylabel("Cumulative pips", color=INK2, fontsize=10)
ax2.tick_params(colors=INK2)
for s in ["top","right"]: ax2.spines[s].set_visible(False)
for s in ["left","bottom"]: ax2.spines[s].set_color(GRID)
ax2.grid(color=GRID, lw=0.7, zorder=0)

fig.suptitle("Sniper Entry at proper R:R (≥1:2): what's real vs. curve-fit  (real gold)",
             color=INK, fontsize=13, fontweight="bold", y=0.99)
fig.text(0.5,0.005,"Win rate ~33-36% is normal and correct at 1:2.5 (break-even is 28.6%). ~$10 risk/trade on gold; expect 10+ losers in a row. "
         "One instrument, ~28 days — forward-test before trusting.", ha="center", color=INK2, fontsize=8)
fig.tight_layout(rect=[0,0.03,1,0.95])
out=os.path.join(BASE,"sniper_rr2_validation.png"); fig.savefig(out,dpi=160,facecolor=SURFACE); print("saved",out)
