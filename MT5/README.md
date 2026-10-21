# EMA Ribbon Reversal Scalper (MT5)

An MT5 custom **indicator** that implements the exact strategy from the video
**"The Only EMA Settings You'll Ever Need (Unbelievable Win Rate)"** (TRIPPATRADING).
Everything is drawn on the chart — the two channels, the trend filter, mechanical
**buy/sell signals**, **SL/TP** levels, a live **info panel**, and **alerts**.

Built for **scalping on M1 / M5** and works on any instrument — **Gold (XAUUSD),
crypto (BTC/ETH), FX, indices**, etc. (nothing is hard-coded to a symbol).

> File to compile: **`EMA_Ribbon_Reversal_Scalper.mq5`**

---

## The strategy (extracted from the video — frame-by-frame + transcript)

### Structure — 5 EMAs forming 2 channels + 1 trend filter

| Group | EMAs | Role |
|-------|------|------|
| **White channel** | EMA **5** on **High** + EMA **5** on **Low** | Short-term momentum / microstructure. Detects the exact moment a pullback ends. |
| **Green channel** | EMA **100** on **High** + EMA **100** on **Low** | Medium-term retracement zone — the dynamic **pullback area**. |
| **Orange line** | EMA **200** on **Close** | Structural **trend filter** (bias). Price above = bullish, below = bearish. |

This is a **reversal / pullback** system (catch the start of a new trend), **not** a
crossover-chasing system.

### BUY — four mechanical steps
1. **Bias flip:** price **closes above** the orange 200 EMA (possible new uptrend).
2. **Momentum alignment:** the **whole white channel** (both 5-EMAs) is **above** the 200 EMA.
3. **Pullback:** price pulls back and **at least touches the green channel** (100 EMA).
   *No pullback = no trade (don't chase).*
4. **Trigger:** a candle **closes above the white channel** → **BUY**.
   - **Stop loss:** just **below** the green channel.
   - **Take profit:** a configurable **R multiple** of the risk (default 2R).

### SELL — exact mirror
1. Price **closes below** the 200 EMA.
2. Whole white channel **below** the 200 EMA.
3. Price retraces up and **touches the green channel** (and doesn't close back above the 200 EMA).
4. A candle **closes below the white channel** → **SELL**. SL just **above** the green channel, TP at R.

### Filters built in
- **No pullback → skipped** (price that just runs without touching green is ignored).
- **Touched green but didn't close beyond white → skipped** (pullback not finished).
- **Choppy guard:** if price keeps crossing the 200 EMA too often in a window, signals are suppressed.
- **Fresh-reversal mode** (`RequireFreshCross`): require a recent 200-EMA cross so you only
  take genuine reversals. Turn it **off** to also take trend-**continuation** pullback entries
  (more signals — useful for pure scalping).

---

## Install & compile

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `EMA_Ribbon_Reversal_Scalper.mq5` into **`MQL5/Indicators/`**
   (a subfolder like `MQL5/Indicators/TrippaTrading/` is fine too).
3. Open **MetaEditor** (F4), open the file, and press **Compile** (F7).
   It should compile with **0 errors** (a few harmless "unused parameter" warnings are normal).
4. Back in MT5, open the **Navigator** (Ctrl+N) → **Indicators**, and drag
   **EMA Ribbon Reversal Scalper** onto an M1 or M5 chart.
5. Enable **AutoTrading/alerts** permissions if you want push/email notifications
   (Tools → Options → Notifications for push; Email tab for email).

---

## Inputs (grouped)

**EMA Structure** — `FastLength` (5), `MidLength` (100), `TrendLength` (200), `MaMethod` (EMA).
Change these only if you want to experiment; the video defaults are 5 / 100 / 200.

**Colours & Style** — line colours/widths, and `ShowFills` + `FillAlpha` to shade the
white and green channels so they're instantly readable.

**Signals**
- `ShowSignals` — draw buy/sell arrows.
- `ArrowOffsetATR` — how far the arrow sits from the candle (scales per instrument via ATR).
- `RequireFreshCross` — true = only fresh reversals; false = also continuation entries.
- `CrossLookback` / `PullbackLookback` — how many bars the setup stays valid.
- `AvoidChop` / `MaxCrossesInWindow` — choppy-market filter.

**Stop Loss / Take Profit** — `ShowSLTP`, `RiskReward` (R multiple for TP),
`SL_BufferATR` (extra room beyond the green channel), `SLTP_Signals` (how many recent
setups to draw levels for), `SLTP_RightBars` (how far the lines extend).

**Alerts** — `AlertPopup`, `AlertPush` (mobile), `AlertEmail`, `AlertSound` — fire once on
each newly **closed-bar** signal (no repainting of the alert).

**Info Panel** — on-chart status: current bias, momentum alignment, what the setup is
waiting for next, the last signal, and the R:R.

---

## How signals behave (important)

- Signals are evaluated **only on closed candles** — the arrow is printed when the trigger
  candle closes (matching the "wait for the candle to close" rule). This means the signal
  for the current forming candle appears **after** it closes; it does **not repaint**.
- Each arrow marks the **entry candle**. SL/TP lines are drawn from that candle.
- Because this is a mechanical translation of a discretionary strategy, treat the signals as
  **high-quality setups to confirm**, not blind auto-entries. Always apply your own risk
  management — no strategy wins 100%.

---

## Notes
- Pure **indicator** (no auto-trading). It visualises the strategy and alerts you; you place
  the trades.
- Multi-instrument & multi-timeframe: it reads the chart's own symbol/period, so the same file
  works on XAUUSD, BTCUSD, EURUSD, US30, etc., on M1/M5 (or any timeframe).
