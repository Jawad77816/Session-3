# Momentum Retest Scalper — MT5 Indicator

A faithful MetaTrader 5 (MQL5) implementation of the **Momentum Retest Strategy**
for 1‑minute scalping, decoded frame‑by‑frame from the source teaching video.

The indicator scans price for **break‑and‑retest (role‑reversal)** setups, requires
a **candlestick confirmation** at the retest, and then marks the **entry, stop‑loss and
take‑profit** on the chart and raises an alert.

> ⚠️ **Read this first — honesty about "profitable & extremely accurate".**
> No indicator can *guarantee* profit or accuracy. Markets are probabilistic. What this
> tool does is detect the exact setup taught in the video with sensible, adjustable
> filters, so *you* execute it consistently. Real edge comes from disciplined risk
> management, testing, session/instrument selection, and skipping low‑quality setups.
> **Backtest it in the MT5 Strategy Tester and forward‑test on a demo account before
> risking real money.** This is an educational tool, not financial advice.

---

## The strategy (as taught in the video)

### 1. Market structure (the foundation)
- **Uptrend** = *higher highs (HH)* + *higher lows (HL)*. It is built from an
  **impulsive move** (the principal move, in the trend direction) followed by a
  **retracement move** (against the trend). Best decision in an uptrend: **buy**.
- **Downtrend** = *lower highs (LH)* + *lower lows (LL)*. Impulsive move down, then a
  retracement up. Best decision in a downtrend: **sell**.
- The goal is to trade *with* the impulsive move and **avoid being trapped in the
  retracement**.

### 2. The setup — break and retest (role reversal)
Long example (mirror everything for shorts):

1. **Key level** — the most recent significant **swing high** is the active
   *resistance* (a swing low is the active *support*). In a range these are simply the
   range boundaries.
2. **Breakout** — a candle **closes beyond** the level (an impulsive move through it).
3. **Retest** — price pulls back to the broken level. By the **principle of role
   reversal**, broken **resistance now acts as support** (and broken support acts as
   resistance). This lets you *enter at a better price*.
4. **Confirmation** — at the level, wait for a candlestick signal in the trade
   direction:
   - **Bullish pin bar** (hammer): small body, long **lower** wick, little/no upper wick.
   - **Bullish engulfing**: a green candle whose body completely engulfs the previous
     red candle's body.
   - (Bearish pin bar / bearish engulfing for shorts.)
5. **Entry** — at the **close of the confirmation candle**.
6. **Stop‑loss** — just **beyond the retest swing** (below the retest low for longs,
   above the retest high for shorts).
7. **Take‑profit** — the next key level / a favourable **risk‑reward** target. The video's
   worked examples land around **2.4–4.0 R**. This indicator defaults to **2.0 R**
   (configurable).

### 3. Range‑bound markets
After a trend, price often enters a **range** (sideways). Don't trade inside it — **wait
for a clean breakout** of a range boundary, then the **pullback/retest** of that broken
boundary (now support if broken up, resistance if broken down), confirm, and target the
**next key level**. The same break‑retest engine handles this automatically because the
range boundaries are swing highs/lows.

### Scope
Designed for the **M1** timeframe (1‑min scalping) but works on any timeframe and any
symbol (forex, indices, metals, crypto). ATR‑adaptive buffers keep it consistent across
instruments.

---

## What the indicator draws

| Element | Meaning |
|---|---|
| ▲ green arrow below a bar | **Buy** signal (entry at that bar's close) |
| ▼ red arrow above a bar | **Sell** signal (entry at that bar's close) |
| Gold dotted line | The broken level that was retested (role reversal) |
| Green shaded box | Entry → Take‑Profit zone |
| Red shaded box | Entry → Stop‑Loss zone |
| Text label | Direction + realised **Risk‑Reward** of the setup |

Alerts (popup / push / email) fire once, on the **close** of the confirmation candle.
Signals are computed only on **closed bars**, so the arrows **do not repaint**.

---

## Installation

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `MomentumRetestScalper.mq5` into `MQL5/Indicators/` (or a subfolder there).
3. In **MetaEditor**, open the file and press **Compile** (F7). You should get
   `0 errors, 0 warnings` and a `MomentumRetestScalper.ex5` file.
4. Back in MT5, refresh the **Navigator → Indicators** list, then drag the indicator
   onto an **M1** chart.
5. To receive push notifications, set your MetaQuotes ID in
   **Tools → Options → Notifications**. For email, configure **Tools → Options → Email**.

---

## Inputs reference

**Market Structure**
- `InpSwingLookback` (5) — bars on each side that define a swing pivot. Larger = fewer,
  more significant levels.
- `InpMaxHistoryBars` (1500) — how much history to scan/redraw.

**Breakout & Retest**
- `InpUseATR` (true) — use ATR‑adaptive buffers (recommended; works across instruments).
- `InpATRPeriod` (14) — ATR period.
- `InpBreakoutBufferATR` (0.05) — the close must clear the level by this × ATR to count
  as a breakout (filters noise).
- `InpRetestToleranceATR` (0.20) — how close the wick must revisit the broken level.
- `InpSLBufferATR` (0.10) — extra padding beyond the retest swing for the stop.
- `InpBreakoutBufferPts / InpRetestTolerancePts / InpSLBufferPts` — point‑based
  equivalents used when `InpUseATR = false`.
- `InpMaxBarsForRetest` (20) — if no valid retest happens within this many bars after the
  breakout, the setup is discarded.

**Confirmation Patterns**
- `InpUsePinbar` (true) / `InpUseEngulfing` (true) — which confirmations to accept.
- `InpPinWickBodyRatio` (2.0) — pin bar: dominant wick ≥ X × body.
- `InpPinMaxOppWickPct` (0.35) — pin bar: opposite wick ≤ X × total range.
- `InpPinBodyMaxPct` (0.40) — pin bar: body ≤ X × total range.

**Trade Management**
- `InpRiskReward` (2.0) — reward:risk multiple used for the take‑profit.
- `InpRequireImpulse` (false) — require the breakout candle to be genuinely impulsive.
- `InpMinBreakBodyATR` (0.5) — min breakout‑candle body (× ATR) when impulse is required.

**Visuals**
- `InpShowSLTP`, `InpShowLevel`, `InpMaxSetupsDrawn` (8), and the three colours.

**Alerts**
- `InpAlertPopup` (true), `InpAlertPush` (false), `InpAlertEmail` (false).

---

## Tuning for quality (fewer, cleaner signals)

The video stresses *precise* entries. To raise selectivity:

- Increase `InpSwingLookback` to **7–9** so only meaningful levels are used.
- Turn on `InpRequireImpulse` so weak breakouts are ignored.
- Tighten `InpRetestToleranceATR` toward **0.12–0.15** so the retest must be clean.
- Keep `InpRiskReward` at **2.0+**; a strategy can be profitable well below 50% win rate
  at 2R.
- Trade during **liquid sessions** (London / New York for forex) and avoid major news.

For more signals (lower quality), do the opposite.

---

## Turning signals into trades

This is an **indicator** — it flags setups; you place the orders. For each signal:
- **Buy/Sell** at the confirmation candle's close (the arrow bar).
- Set **SL** at the red box edge and **TP** at the green box edge.
- Risk a **fixed small %** of the account per trade (e.g. 0.5–1%). Position size =
  (risk amount) ÷ (entry − SL distance).

If you later want this fully automated as an **Expert Advisor** (auto entries, SL/TP,
position sizing, trailing), that's a natural next step — ask and it can be built from
this same logic.

---

## How it avoids repainting

- Pivots are only confirmed after `InpSwingLookback` bars have closed to their right.
- Breakout, retest and confirmation are evaluated **only on fully closed bars**.
- A signal is anchored to the confirmation bar, whose OHLC never changes again, so an
  arrow that appears will not move or vanish. Alerts fire once per signal bar.
