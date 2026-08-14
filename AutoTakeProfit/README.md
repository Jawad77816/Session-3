# AutoTakeProfit — automatic 10‑pip Take Profit for manual MT5 trades

An MT5 Expert Advisor (EA) that watches your account and, the moment you open a
trade **manually**, automatically sets its Take Profit a fixed number of pips
from your entry price.

**Default behaviour on Gold / XAUUSD:**

| You do this manually | The EA instantly sets |
|----------------------|-----------------------|
| **Buy** at `4000.00`  | TP = `4001.00` (+10 pips) |
| **Sell** at `4000.00` | TP = `3999.00` (−10 pips) |

> ⚠️ **Reality check first:** MetaTrader 5 has **no built‑in setting** that adds
> a TP to manual trades. A small EA (this one) or a third‑party trade‑manager
> tool is the only way. This EA is the clean, free way to do it, and it works
> on Exness MT5.

---

## 1. Install it (one time)

1. Open **MetaTrader 5**.
2. Menu **File → Open Data Folder**.
3. Go into `MQL5` → `Experts`.
4. Copy **`AutoTakeProfit.mq5`** into that `Experts` folder.
5. Back in MT5, open **MetaEditor** (the toolbar icon, or press `F4`), find
   `AutoTakeProfit.mq5` in the Navigator on the left, and click **Compile**
   (or press `F7`). You should see *0 errors, 0 warnings*.
   (You can also just restart MT5 and it will compile on its own.)

## 2. Turn it on

1. In MT5, allow automated trading: **Tools → Options → Expert Advisors →
   ✅ Allow algorithmic trading**, and make sure the **“Algo Trading”** button
   in the top toolbar is green/pressed.
2. In the **Navigator** panel, expand **Expert Advisors**, and **drag
   `AutoTakeProfit` onto the chart** of the symbol you trade (e.g. XAUUSD).
3. In the settings window that pops up, tick **Allow Algo Trading**, set your
   pips if you want to change them, and click **OK**.
4. You’ll see a **smiley face 🙂 in the top‑right of the chart** = the EA is
   running.

That’s it. Now place a manual trade as usual — the TP appears by itself within
a second.

> The EA only needs to be on **one** chart per symbol you want managed. If you
> trade several symbols, either put it on each chart, or set **Symbols scope =
> ALL open symbols** (see settings) and leave it on one chart.

## 3. Verify it’s doing the right thing

Open the **Toolbox → Experts** tab at the bottom of MT5. On startup the EA
prints something like:

```
AutoTakeProfit started on XAUUSD | 1 pip = 0.10 | TP = 10.0 pips = 1.00 in price
Example: a BUY at 4000.00 would get TP at 4001.00 (a SELL would get TP at 3999.00)
```

If that example matches what you expect (Buy 4000 → TP 4001), you’re done. If
the numbers look off for your symbol, adjust **Points per pip** (below).

---

## Settings explained

| Setting | Default | What it does |
|--------|---------|--------------|
| **Take Profit in pips** | `10` | How far the TP sits from your entry. `0` = don’t set a TP. |
| **Stop Loss in pips** | `0` | Optionally auto‑set a SL too. `0` = leave SL alone. |
| **Points per pip** | `0` (auto) | Advanced. `0` lets the EA figure out one pip for you (see note). Set a number to force it. |
| **Manage Buy positions** | `true` | Apply to buys. |
| **Manage Sell positions** | `true` | Apply to sells. |
| **Only manage this magic number** | `-1` | `-1` = all trades **including your manual ones**. Manual trades have magic `0`. Leave at `-1`. |
| **Symbols scope** | `0` | `0` = only the chart the EA is on. `1` = every symbol you have open. |
| **Only add a TP when the position has none** | `true` | Recommended. The EA sets your TP once and then never touches it again, so you can still move or remove the TP yourself afterwards. |
| **Verbose** | `true` | Log every action to the Experts tab. |

### About “pips” on Gold (important)

The word *pip* is ambiguous on gold, so here’s exactly what this EA assumes by
default, and how to change it:

- By default (**Points per pip = 0**) the EA treats **1 pip = `0.10` in price**
  for gold/silver, so **10 pips = `1.00`** → Buy 4000 → TP 4001. This matches
  what you asked for.
- If your broker quotes gold differently, or you want a different amount, set
  **Points per pip** manually. One pip = `Points per pip × point`. Examples for
  XAUUSD quoted with 2 decimals (`point = 0.01`):
  - `Points per pip = 10` → 1 pip = `0.10` → 10 pips = **`1.00`** (default result)
  - `Points per pip = 100` → 1 pip = `1.00` → 10 pips = `10.00`
  - `Points per pip = 1` → 1 pip = `0.01` → 10 pips = `0.10`

Whatever you choose, the startup log line (`1 pip = …`) tells you the exact
price distance, so you can always confirm before trading.

---

## Good to know / limitations

- **Set‑and‑forget your TP:** with *Only add a TP when the position has none =
  true*, the EA sets the TP once. If you later drag the TP line or delete it,
  the EA won’t re‑add it. Turn that setting **off** if you instead want it to
  always force the TP back to your entry ± the set pips.
- **The EA must be running** (smiley on the chart, Algo Trading green) at the
  moment you place the trade. If MT5 is closed, or the EA isn’t on a chart, no
  TP is added. It will, however, set the TP the next time it runs if the trade
  is still open with no TP.
- **Price already ran past the TP / broker minimum distance:** if your 10‑pip
  TP would be too close to the current market price (broker “stops level”), the
  EA logs a note and skips it — set that one manually. On most Exness accounts
  the stops level is 0, so this is rare.
- **It manages positions, not pending orders.** A pending order (Buy Limit,
  etc.) gets its TP when it triggers and becomes a live position.
- **Works on netting and hedging accounts** (Exness MT5 is hedging by default).
- This is a trading tool: **test it on a demo account first.** Nothing here is
  financial advice.
