#!/usr/bin/env python3
"""Win rate vs expectancy for every SL/TP combo — shows the high-win-rate trap."""
import os, itertools
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from grid_search import load, signals, evaluate, summarize

BASE = os.path.dirname(os.path.abspath(__file__))
SURFACE="#fcfcfb"; INK="#0b0b0b"; INK2="#52514e"; GRID="#e6e5e1"
GOOD="#1baf7a"; BAD="#eb6834"; BLUE="#2a78d6"
SL=[5,10,20,30,50,80,120,200,300]; TP=[1,2,3,5,8,10,15,20,30]

def grid(path, max_hold, spread):
    o,h,l,c = load(path); sg = signals(o,h,l,c,L=5)
    pts=[]
    for sl,tp in itertools.product(SL,TP):
        s=summarize(evaluate(o,h,l,c,sg,sl,tp,max_hold=max_hold,spread_pips=spread))
        if s: pts.append((s["wr"], s["exp"], sl, tp))
    return pts

panels=[("1-minute gold", "gold_1m.csv", 240), ("5-minute gold", "gold_5m.csv", 120)]
fig, axes = plt.subplots(1,2, figsize=(12.6,5.6), sharey=True)
fig.patch.set_facecolor(SURFACE)

for ax,(label,fname,mh) in zip(axes,panels):
    pts = grid(os.path.join(BASE,fname), mh, 2.0)
    ax.set_facecolor(SURFACE)
    # shaded "you asked for" band: win rate >= 90
    ax.axvspan(90,100, color="#f2efe6", zorder=0)
    ax.axhline(0, color=INK2, lw=1.2, ls="-", zorder=2)
    for wr,exp,sl,tp in pts:
        col = GOOD if exp>0 else BAD
        ax.scatter(wr, exp, s=42, color=col, edgecolor=SURFACE, linewidth=1.0, zorder=3)
    # annotate the best-win-rate point
    best = max(pts, key=lambda p:p[0])
    ax.annotate(f"  best win rate: {best[0]:.1f}%\n  (SL {best[2]} / TP {best[3]} pip)\n  loses {best[1]:.1f} pip/trade",
                (best[0],best[1]), xytext=(-4,34), textcoords="offset points",
                fontsize=8.3, color=INK, ha="right",
                arrowprops=dict(arrowstyle="->", color=INK2, lw=1))
    ax.set_title(label, color=INK, fontsize=11, fontweight="bold", loc="left", pad=8)
    ax.set_xlabel("Win rate", color=INK2, fontsize=10)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v,_:f"{v:.0f}%"))
    ax.tick_params(colors=INK2)
    for s in ["top","right"]: ax.spines[s].set_visible(False)
    for s in ["left","bottom"]: ax.spines[s].set_color(GRID)
    ax.grid(color=GRID, lw=0.7, zorder=0)
    ax.text(95, ax.get_ylim()[1]*0.92 if ax.get_ylim()[1]>0 else -0.5,
            "you asked\nfor here", ha="center", color=INK2, fontsize=8, style="italic")

axes[0].set_ylabel("Expectancy  (pips per trade, after 2-pip spread)", color=INK2, fontsize=10)
# legend proxies
from matplotlib.lines import Line2D
leg=[Line2D([0],[0],marker='o',color='none',markerfacecolor=GOOD,markersize=9,label='profitable (expectancy > 0)'),
     Line2D([0],[0],marker='o',color='none',markerfacecolor=BAD,markersize=9,label='loses money (expectancy < 0)')]
axes[0].legend(handles=leg, frameon=False, loc="lower left", fontsize=9, labelcolor=INK)
fig.suptitle("The high-win-rate trap: every 90%+ setting loses money  (Sniper Entry, real gold)",
             color=INK, fontsize=13, fontweight="bold", y=0.985)
fig.text(0.5, 0.005,
         "Each dot = one stop/target combo. Win rate rises to 99% only by using a huge stop + tiny target — "
         "but one loss erases dozens of wins, so expectancy stays negative. Win rate is the wrong thing to maximize.",
         ha="center", color=INK2, fontsize=8.3)
fig.tight_layout(rect=[0,0.03,1,0.95])
out=os.path.join(BASE,"winrate_trap.png")
fig.savefig(out, dpi=160, facecolor=SURFACE); print("saved",out)
