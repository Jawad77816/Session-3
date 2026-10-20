# MD5 Multi-Timeframe Liquidity Sweep + Fair Value Gap (MQL5, non-repaint)

A MetaTrader 5 custom indicator that marks **buy-side** and **sell-side liquidity sweeps across
every major timeframe at once** (M1, M5, M15, M30, H1, H4, D1, and optionally W1), draws the
**price level that was swept**, labels each sweep with the timeframe it belongs to, and plots
**Fair Value Gaps (FVGs)** on the chart timeframe with a **Real vs Fake** classification.

**File:** `MD5_Liquidity_Sweep.mq5`
**Platform:** MetaTrader 5 (any symbol, any timeframe)
**Window:** main chart window (object-based drawing)
**Repainting:** none — every signal is finalised on a *closed* bar of its own timeframe.

> **What changed in v2.00:** sweeps are now **multi-timeframe**. Attach it to one chart (e.g. M1)
> and it shows the sweeps of all enabled timeframes, each labelled `<TF> BSL` / `<TF> SSL`, with
> higher timeframes drawn bigger/bolder. Drawing moved from indicator buffers to chart objects so
> a higher-timeframe event lands at the correct time on your lower-timeframe chart.

---

## 1. The concepts (the "knowledge" baked into the tool)

These are the retail **ICT / Smart-Money-Concepts (SMC)** definitions the indicator implements.
They are one popular trading framework, not proven market mechanics — backtest before you trade them.

### Liquidity
Clusters of resting orders (mostly stop-losses and breakout orders) that sit where many traders
can see them:

* **Buy-side liquidity (BSL)** sits **above** an obvious swing **high** / equal highs — short
  stops (which are *buy* orders) and breakout *buy* stops rest there.
* **Sell-side liquidity (SSL)** sits **below** an obvious swing **low** / equal lows — long stops
  (which are *sell* orders) and breakout *sell* stops rest there.

The naming follows the **orders being filled**, not the direction you then trade.

### Liquidity sweep (stop hunt / liquidity grab)
Price pushes **through** a pool, fills the resting orders, and **fails to hold** — it snaps back
inside the prior range:

* **Buy-side sweep** → wick **above** a prior swing high, **close back below** it → bearish bias →
  **DOWN arrow above the bar**, labelled `<TF> BSL`.
* **Sell-side sweep** → wick **below** a prior swing low, **close back above** it → bullish bias →
  **UP arrow below the bar**, labelled `<TF> SSL`.

The "wick-through + close-back-inside" definition is used because it is decided at the **candle's
close** — that is what makes it non-repainting.

### Fair Value Gap (FVG) / imbalance
A 3-candle imbalance left by a fast move:

* **Bullish FVG:** `low[candle3] > high[candle1]` → the untouched zone is support.
* **Bearish FVG:** `high[candle3] < low[candle1]` → the untouched zone is resistance.

No overlap between candle 1 and candle 3 is required — exactly the condition above — so every gap
drawn is already "clean".

### Real vs Fake FVG
| | **Real FVG** | **Fake FVG** |
|---|---|---|
| Origin | **Displacement** (strong, impulsive candle) | Chop / low momentum |
| Middle candle | Large range **and** dominant body | Small / wicky / doji |
| Gap size | Meaningful | Tiny |
| Context | Often right **after a sweep** / with a structure break | Random, inside consolidation |
| Tendency | Respected, acts as a magnet / reaction zone | Filled quickly, unreliable |

A gap is **REAL** only when **all three** hold: middle-candle range ≥ `InpDispATR × ATR`,
body/range ≥ `InpMinBodyRatio`, and gap ≥ `InpMinGapATR × ATR`. Otherwise **FAKE**. If an aligned
chart-timeframe sweep happened within `InpSweepContextBars` bars, the label gets a **`+sweep`**
tag (the highest-probability case: *FVG formed right after liquidity was taken*).

> Visuals: **Real** FVGs = filled box, solid border. **Fake** FVGs = dotted outline (hide them
> with `InpShowFakeFVG = false`).

---

## 2. How the multi-timeframe engine works

* For each **enabled** timeframe the indicator pulls that timeframe's candles
  (`CopyHigh/Low/Close/Time`), finds swing pivots, and detects sweeps **only on that
  timeframe's closed bars**.
* Each sweep is drawn as a chart object positioned by **time + price**, so an H4 sweep that
  happened at 12:00 is placed on your M1 chart at 12:00, labelled `H4 BSL/SSL`.
* A timeframe is **re-scanned only when it prints a new bar** (detected via its bar-0 time), so the
  tool is light — your M1 chart doesn't re-scan D1 on every tick.
* Higher timeframes get **wider arrows, bigger labels, thicker level lines** (toggle with
  `InpScaleBy​TF`), so a D1 sweep is visually louder than an M1 sweep.

### Timeframe confirmation lag (important)
A higher-timeframe sweep **appears only when that timeframe's candle closes**. On M1 you will see
an H4 sweep up to ~4 hours after the wick happened — because until the H4 candle closes, there is
no confirmed sweep to show. This is the honest cost of being non-repaint; it is *lag, not
repaint*. The mark, once printed, never moves.

---

## 3. Why it does not repaint

* Signals are evaluated **only on closed bars** — in every timeframe, series index `0` (the
  forming bar) is never used for a signal.
* A sweep is decided at its candle's **close** (final high/low/close) and anchored to a fixed bar
  time; once drawn it never moves, recolours, or disappears.
* FVG boxes are confirmed at the 3rd candle's close and extend a **fixed** number of bars (no
  dynamic "mitigation" redraw).
* On history refresh / timeframe change the indicator **rebuilds deterministically** from the same
  closed bars — identical picture.
* Alerts fire **only** when a timeframe prints a *new* closed-bar sweep during the live session,
  never while re-scanning history or on first attach.

---

## 4. Installation

1. Copy `MD5_Liquidity_Sweep.mq5` into your terminal's data folder under `MQL5/Indicators/`
   (in MT5: **File → Open Data Folder**).
2. In **MetaEditor** (F4) open the file and **Compile** (F7) → expect `0 errors`.
3. In MT5 refresh **Navigator → Indicators** and drag **MD5 MTF Liquidity Sweep + FVG** onto a
   chart (M1 or M5 is ideal for scalping).

> Authored and statically reviewed outside MetaEditor — compile once in your own MetaEditor to
> generate the `.ex5`.

---

## 5. Inputs

### Timeframes to scan for sweeps
`InpTF_M1, InpTF_M5, InpTF_M15, InpTF_M30, InpTF_H1, InpTF_H4, InpTF_D1` — all `true` by default.
`InpTF_W1` — `false` by default. Turn off the ones you don't want.

### Liquidity / Sweep
| Input | Default | Meaning |
|---|---|---|
| `InpPivotLength` | `10` | Swing pivot strength: bars on **each** side, applied per timeframe. Higher = fewer, more significant levels + more confirmation lag. |
| `InpBarsPerTF` | `500` | How many bars of history to scan per timeframe. |
| `InpShowSweptLevel` | `true` | Draw the horizontal line at the swept level (swing → sweep). |
| `InpArrowOffsetFrac` | `0.5` | Arrow distance from the candle, as a fraction of the sweep candle's range. |
| `InpScaleByTF` | `true` | Bigger/bolder markers and labels for higher timeframes. |
| `InpLabelFontSize` | `8` | Base label font size. |
| `InpBSLColor` | `clrTomato` | Buy-side sweep colour (all timeframes). |
| `InpSSLColor` | `clrDodgerBlue` | Sell-side sweep colour (all timeframes). |

### Fair Value Gaps (chart timeframe)
| Input | Default | Meaning |
|---|---|---|
| `InpShowFVG` | `true` | Draw Fair Value Gaps. |
| `InpShowFakeFVG` | `true` | Also draw fake (weak) FVGs. |
| `InpATRPeriod` | `14` | ATR period used as the displacement / gap reference. |
| `InpDispATR` | `1.2` | REAL: middle-candle range ≥ this × ATR. |
| `InpMinBodyRatio` | `0.50` | REAL: middle-candle body ÷ range ≥ this. |
| `InpMinGapATR` | `0.10` | REAL: gap size ≥ this × ATR. |
| `InpSweepContextBars` | `10` | Tag an FVG `+sweep` if an aligned chart-TF sweep is within this many bars. |
| `InpFVGExtendBars` | `30` | Bars to extend each FVG box to the right. |
| `InpMaxBars` | `2500` | Max chart bars processed for FVG (0 = all). |
| `InpRealBullColor` / `InpFakeBullColor` | greens | Real / fake bullish FVG colours. |
| `InpRealBearColor` / `InpFakeBearColor` | reds | Real / fake bearish FVG colours. |

### Alerts (optional, off by default)
| Input | Default | Meaning |
|---|---|---|
| `InpAlertPopup` | `false` | Popup on a fresh sweep of **any** enabled timeframe. |
| `InpAlertPush` | `false` | Push notification on a fresh sweep (needs MetaQuotes ID in the terminal). |

### General
| Input | Default | Meaning |
|---|---|---|
| `InpPrefix` | `"MD5LS_"` | Prefix for all chart objects this indicator creates. |

---

## 6. Reading the chart

* `H4 BSL` with a down arrow above a candle → H4 buy-side liquidity was swept (bearish pressure).
* `M5 SSL` with an up arrow below a candle → M5 sell-side liquidity was swept (bullish pressure).
* A coloured line at the arrow's price is the exact **level that was swept**.
* A filled green/red box labelled `FVG` (or `FVG+sweep`) is a **real** FVG; a dotted box labelled
  `fvg?` is a **fake** one.

**Confluence is the point:** the strongest setups are when a **lower-timeframe** sweep happens
right **into a higher-timeframe** swept level or FVG. See the gold scalping strategy
(`Gold_Scalping_Strategy.md`).

---

## 7. Notes & tuning

* Too noisy? Raise `InpPivotLength` (15–20) and turn off the lowest timeframes (`InpTF_M1`).
* Signals feel late? That is the per-timeframe confirmation window; lower `InpPivotLength`.
* Only institutional-grade gaps? Set `InpShowFakeFVG = false`.
* Objects are cleared and rebuilt on reload / timeframe change; per-timeframe sweep objects are
  bounded to the last `InpBarsPerTF` bars.

---

## 8. Disclaimer

A study / charting tool implementing a popular retail framework. The "stop hunt" / "institutional
footprint" narratives are claims made by that community, not established market facts. Not
financial advice. Test on history and demo and manage risk before trading live.
