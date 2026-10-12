#!/usr/bin/env python3
"""Win-rate vs reward:risk chart for the Sniper Entry backtest (real GC=F data)."""
import os, json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from backtest import load, simulate, stats

BASE = os.path.dirname(os.path.abspath(__file__))
RRS = [1, 1.5, 2, 3, 5, 10]
TFS = [("gold_1m.csv", "1-minute", 240),
       ("gold_5m.csv", "5-minute", 120),
       ("gold_15m.csv", "15-minute", 96),
       ("gold_1h.csv", "1-hour", 72)]
PAL = {"1-minute": "#2a78d6", "5-minute": "#eb6834",
       "15-minute": "#1baf7a", "1-hour": "#eda100"}
SURFACE = "#fcfcfb"; INK = "#0b0b0b"; INK2 = "#52514e"; GRID = "#e6e5e1"

def winrate_grid(stop_model):
    grid = {}
    for fname, label, mh in TFS:
        o, h, l, c = load(os.path.join(BASE, fname))
        wrs = []
        for rr in RRS:
            allt = []
            for d in ("buy", "sell"):
                allt += simulate(o, h, l, c, d, L=5, stop_model=stop_model, rr=rr, max_hold=mh)
            s = stats(allt, 0.0)
            wrs.append(s["wr"] if s else 0.0)
        grid[label] = wrs
    return grid

grid_struct = winrate_grid("structure")
grid_fixed = winrate_grid("fixed")
json.dump({"structure": grid_struct, "fixed": grid_fixed, "rr": RRS},
          open(os.path.join(BASE, "winrate_grid.json"), "w"), indent=2)

x = list(range(len(RRS)))
fig, axes = plt.subplots(1, 2, figsize=(12.6, 5.3), sharey=True)
fig.patch.set_facecolor(SURFACE)
panels = [("STRUCTURE stop  (just below the sweep low — the robust interpretation)", grid_struct),
          ("FIXED 2-pip stop  (literal from the video title)", grid_fixed)]

for ax, (title, grid) in zip(axes, panels):
    ax.set_facecolor(SURFACE)
    for label, _, _ in [(t[1], None, None) for t in TFS]:
        wrs = grid[label]
        ax.plot(x, wrs, "-o", color=PAL[label], lw=2, ms=7, label=label,
                markeredgecolor=SURFACE, markeredgewidth=1.5, zorder=3)
        ax.annotate(f"{wrs[-1]:.0f}%", (x[-1], wrs[-1]), xytext=(8, 0),
                    textcoords="offset points", color=PAL[label], fontsize=9,
                    va="center", fontweight="bold")
    ax.axhline(50, color=GRID, lw=1, ls="--", zorder=1)
    ax.set_title(title, color=INK, fontsize=10.5, fontweight="bold", pad=10, loc="left")
    ax.set_xticks(x); ax.set_xticklabels([f"1:{r:g}" for r in RRS], color=INK2)
    ax.set_xlabel("Reward : Risk target", color=INK2, fontsize=10)
    ax.set_ylim(0, 58)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.0f}%"))
    ax.tick_params(colors=INK2)
    for s in ["top", "right"]:
        ax.spines[s].set_visible(False)
    for s in ["left", "bottom"]:
        ax.spines[s].set_color(GRID)
    ax.grid(axis="y", color=GRID, lw=0.8, zorder=0)

axes[0].set_ylabel("Win rate  (TP hit before stop)", color=INK2, fontsize=10)
axes[0].legend(frameon=False, loc="upper right", fontsize=9, labelcolor=INK)
fig.suptitle("Sniper Entry — false-breakout reversal: win rate vs. target  (real gold / GC=F)",
             color=INK, fontsize=13.5, fontweight="bold", x=0.5, y=0.99)
fig.text(0.5, 0.005,
         "Win rate falls as you demand a bigger target. Fixed 2-pip stop is far inside one gold candle's range today "
         "(median 1m range ≈ 16 pips) → not viable.  First-touch exits, stop-first on ambiguous bars (pessimistic).",
         ha="center", color=INK2, fontsize=8.3)
fig.tight_layout(rect=[0, 0.03, 1, 0.96])
out = os.path.join(BASE, "sniper_winrate.png")
fig.savefig(out, dpi=160, facecolor=SURFACE)
print("saved", out)
print(json.dumps({"structure_1m": grid_struct["1-minute"], "rr": RRS}, indent=0))
