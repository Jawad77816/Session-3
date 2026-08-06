# GoldSAR_Pro — MT5 Expert Advisor

An automated version of the **stop-and-reverse (SAR) gold scalping** idea from the
source video, rebuilt with a **positive-expectancy structure** and hard risk
controls.

> **Read this first — the honest part.**
> No EA can be *guaranteed* to be net-profitable. Anyone selling "always in
> profit, never in loss" is either lying or hiding the losses as floating
> drawdown (the martingale trap that eventually blows the account). This EA does
> **not** do that. Instead it is built so that *over many trades* the wins are
> designed to outweigh the losses — and then it is **your job to backtest and
> demo-test it** before risking real money. **Not financial advice.**

---

## What the video showed vs. what this EA adds

The video demonstrated the *management* trick only: always hold one position,
keep an opposite pending **stop** at the entry, and flip direction when price
turns through it. Its weakness is that it **bleeds in choppy markets** (every
flip pays the spread) and it has **no entry signal** at all.

This EA keeps the stop-and-reverse skeleton and fixes the two holes:

| Mechanism | Why it creates "more profit than loss" |
|---|---|
| **Win big, lose small** — TP and trailing stop are set *wider* than the stop-loss (reward:risk ≈ 2:1 by default). | Expectancy = `WinRate × AvgWin − LossRate × AvgLoss`. With a 2:1 payoff you are net **positive even winning under 50%** of trades. This is the core edge. |
| **Trade only in trends** — a Donchian breakout must be confirmed by **ADX strength** and **EMA direction**. | Keeps the EA out of the sideways chop that kills raw SAR. Fewer trades, better ones. |
| **Trail to let winners run** — the stop follows price once you're in profit. | Turns the occasional big move (like the +\$3.01 run in the video) into the trades that pay for all the small losers. |
| **Hard safety rails** — spread filter, daily-loss cutoff, equity stop, max trades/day. | One bad session can't spiral. Protects the "overall not in loss" goal by capping the downside. |

**There is no martingale, no grid, and no lot-doubling.** Risk per trade is fixed
(or a fixed % of balance), on purpose.

---

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `GoldSAR_Pro.mq5` into `MQL5/Experts/`.
3. In **MetaEditor**, open it and press **Compile** (F7). You should get
   `0 errors`.
4. Back in MT5, refresh the **Navigator → Expert Advisors** list.
5. Drag `GoldSAR_Pro` onto an **XAUUSD** chart (the video used **M1**). Tick
   **Allow Algo Trading**.

## Backtest it before anything else

1. **View → Strategy Tester** (Ctrl+R).
2. Expert: `GoldSAR_Pro`, Symbol: `XAUUSD`, Timeframe: `M1`.
3. Modelling: **Every tick based on real ticks** (most realistic for scalping).
4. Pick a date range of at least a few months and press **Start**.
5. Look at the **Report tab** and judge it on these, not just net profit:
   - **Profit Factor** > 1.3 (gross profit ÷ gross loss).
   - **Expected Payoff** positive.
   - **Max Drawdown** you could actually stomach.
   - A reasonable number of trades (a handful of lucky trades ≠ an edge).
6. Then run **Forward / demo** for a few weeks on a demo account. Only after
   that consider tiny live size.

> The default inputs are a sensible *starting point*, not a tuned solution.
> Every broker's gold spread and tick data differ, so you must validate on
> **your** broker.

---

## Key inputs

| Input | Default | What it does |
|---|---|---|
| `InpBreakoutBars` | 20 | Lookback for the breakout entry/flip trigger. |
| `InpReverseOnOpp` | true | Flip to the opposite side on an opposite breakout (the "SAR"). Set false for plain breakout-with-SL/TP. |
| `InpUseAdx` / `InpAdxMin` | true / 22 | Only trade when the trend is strong enough. Raise to trade less/cleaner. |
| `InpUseEma` | true | Only take breakouts that agree with the EMA trend. |
| `InpSL_ATR` / `InpTP_ATR` | 1.5 / 3.0 | Stop and target in ATR units. **Keep TP > SL** to preserve the edge. |
| `InpUseTrailing` | true | Trail the stop to let winners run. |
| `InpUseRiskPct` / `InpRiskPct` | false / 0.5 | Size by % of balance risked per trade instead of a fixed lot. |
| `InpFixedLot` | 0.01 | Fixed lot (matches the video) when risk-% sizing is off. |
| `InpMaxSpread` | 40 | Skip trades when the spread (points) is too wide. |
| `InpDailyLossPct` | 3.0 | Stop trading for the day after this % loss. |
| `InpEquityStopPct` | 85.0 | Close everything and halt if equity falls below this % of start balance. |
| `InpMaxTradesDay` | 30 | Cap on trades per day (anti-overtrading). |

### Tuning toward "more wins than losses"
- The single biggest lever is **reward:risk** (`InpTP_ATR` vs `InpSL_ATR`).
  Wider targets = you can win less often and still be green.
- Tighter trend filters (`InpAdxMin` up, longer `InpBreakoutBars`) = fewer but
  higher-quality trades and less chop-bleed.
- Use the Strategy Tester's **Optimization** tab on `InpSL_ATR`, `InpTP_ATR`,
  `InpAdxMin`, and `InpBreakoutBars` — but avoid curve-fitting: prefer settings
  that are profitable across a *range* of values, not one magic combination.

---

## Limitations & risks
- Scalping M1 gold is **spread-sensitive**; a wide-spread broker can turn a
  tested edge negative. Test on your own broker's ticks.
- Backtest results are **not** a promise of future returns.
- Slippage, requotes, swap and commission all eat into a scalper's margin.
- This code is provided as an educational starting point. **Trade leveraged gold
  can lose money rapidly. Not financial advice.**
