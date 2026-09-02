# 4-EMA Ribbon EA — `FourEmaRibbonEA.mq5`

An **MT5 Expert Advisor** (auto-trades) rebuilt from the two-part video lesson.

## Strategy
Four EMAs — **8 (blue), 13 (green), 21 (yellow), 55 (red)** — the Fibonacci ribbon.

- **LONG:** `EMA8` crosses **above** `EMA13` while the ribbon is bullish
  (`EMA13 > EMA21 > EMA55`).
- **SHORT:** `EMA8` crosses **below** `EMA13` while the ribbon is bearish
  (`EMA13 < EMA21 < EMA55`).
- In a trend the 8×13 re-cross happens on pullbacks to the ribbon — that is the
  "green circle" entry shown in the video.
- **Exit:** fixed stop-loss (swing high/low or ATR) and a fixed **take-profit at
  a manually adjustable Risk:Reward — default 1:3** (`InpRR = 3.0`).

Signals are evaluated on **closed bars** (no repaint), entries fill at market.

## Install (MT5)
1. **File → Open Data Folder → MQL5 → Experts**, copy `FourEmaRibbonEA.mq5` there.
2. In MetaEditor press **Compile**.
3. Enable **Algo Trading** (toolbar), then drag **FourEmaRibbonEA** onto a chart
   and tick *Allow Algo Trading* in the dialog.
4. **Test on a DEMO account / Strategy Tester first.**

## Key inputs
- **EMAs:** `InpEma1..4` (8/13/21/55), `InpMaMethod` (EMA), `InpMaPrice`.
  - The legend once read "9" for the fast one — set `InpEma1 = 9` if you prefer.
- **Entry:** `InpRequireStack` (full 4-EMA alignment; off = simple 21/55 trend
  filter), `InpPriceFilter`, `InpCloseOnOpposite`, `InpOneTradeAtATime`,
  `InpTradeLong` / `InpTradeShort`.
- **Risk/Reward:** **`InpRR = 3.0` (1:3, adjustable)**, `InpSLMode`
  (Swing / ATR), `InpSwingLookback`, `InpATRmult`, `InpATRperiod`, `InpSLBufferPts`.
- **Money management:** `InpUseRiskPct` + `InpRiskPct` (risk-% sizing) **or**
  `InpFixedLots`.
- **Progressive lot sizing (v1.10):** `InpUseProgLots` (default **true**) grows the
  lot as the balance grows and **overrides** fixed/risk-% sizing while on.
  `InpProgBaseLot` (0.05) is the lot at `InpProgBaseBalance` ($500); every
  `InpProgStepBalance` ($1000) of balance gained adds `InpProgLotStep` (0.01).
  So 0.05 at $500 → 0.06 at $1500 → 0.07 at $2500 → … (clamped to the broker's
  min/max/step). Set `InpUseProgLots = false` to go back to fixed/risk-% sizing.
- **Daily profit target (v1.10):** `InpDailyProfitTarget` (account currency).
  Once the day's **realised** profit reaches it, no new trades open until the next
  day (open trades still run to their SL/TP). **`0` = no daily limit.**
- **Misc:** `InpMagic`, `InpMaxSpreadPts`, `InpSlippagePts`, `InpComment`.

## Honesty / notes
- The video's **audio could not be transcribed** in this environment, so the exact
  spoken entry trigger wasn't captured. The logic is reconstructed from the on-chart
  labels (8/13/21/55) and the green-circle at the EMA crossover, and **every rule is
  an input** so you can match the lesson.
- An EA trades real orders — **always demo-test and backtest** in the MT5 Strategy
  Tester before any live use. This is educational, not financial advice.
