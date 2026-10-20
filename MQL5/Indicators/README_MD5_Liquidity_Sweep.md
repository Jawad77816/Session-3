# MD5 Liquidity Sweep + Fair Value Gap (MQL5, non-repaint)

A MetaTrader 5 custom indicator that marks **buy-side** and **sell-side liquidity sweeps**,
draws the **price level that was swept**, and plots **Fair Value Gaps (FVGs)** with a
**Real vs Fake** classification.

**File:** `MD5_Liquidity_Sweep.mq5`
**Platform:** MetaTrader 5 (any symbol / any timeframe)
**Window:** main chart window
**Repainting:** none — every signal is finalised on a *closed* bar (see
[Why it does not repaint](#why-it-does-not-repaint)).

---

## 1. The concepts (the "knowledge" baked into the tool)

These are the retail **ICT / Smart-Money-Concepts (SMC)** definitions the indicator implements.
They are one popular trading framework, not proven market mechanics — backtest before you trade them.

### Liquidity
"Liquidity" here means **clusters of resting orders**, mostly stop-losses and breakout orders,
that sit where lots of traders can see them:

* **Buy-side liquidity (BSL)** sits **above** an obvious swing **high** / equal highs.
  Shorts park their stop-losses there (a stop on a short is a *buy* order), and breakout
  traders put *buy* stops there. Price is often drawn up to that pool to fill those orders.
* **Sell-side liquidity (SSL)** sits **below** an obvious swing **low** / equal lows.
  Longs park their stop-losses there (a stop on a long is a *sell* order), and breakout
  sellers put *sell* stops there.

The naming follows the **orders being filled**, not the direction you then trade.

### Liquidity sweep (a.k.a. stop hunt / liquidity grab)
A **sweep** is when price pushes **through** one of those pools, fills the resting orders,
and then **fails to hold** beyond the level — it snaps back inside the prior range.
The move is read as a *grab of liquidity* rather than a genuine breakout.

* **Buy-side sweep** → wick **above** a prior swing high, then **close back below** it.
  Bearish bias (the up-move was a trap). → **DOWN arrow above the bar.**
* **Sell-side sweep** → wick **below** a prior swing low, then **close back above** it.
  Bullish bias (the down-move was a trap). → **UP arrow below the bar.**

The indicator uses the **"wick-through + close-back-inside"** definition because it is fully
decided at the **candle's close**, which is what makes the signal non-repainting. Many traders
then wait for a *Break of Structure (BOS)* or *Change of Character (ChoCh)* before acting — that
confirmation step is left to you.

### Fair Value Gap (FVG) / imbalance
An **FVG** is a 3-candle **price imbalance** — a gap the market left behind when it moved too
fast for orders to fill both sides:

* **Bullish FVG:** `low[3rd candle] > high[1st candle]`. The untouched zone between those two
  prices is the gap (support).
* **Bearish FVG:** `high[3rd candle] < low[1st candle]`. The zone between them is the gap
  (resistance).

A textbook FVG requires **no overlap** between candle 1 and candle 3 — exactly the condition
above — so every gap this tool draws is already "clean".

### Real vs Fake FVG
Not every gap matters. The community distinction, and how this tool decides it objectively:

| | **Real FVG** | **Fake FVG** |
|---|---|---|
| Origin | **Displacement** — a strong, impulsive candle | Chop / low momentum |
| Middle candle | Large range **and** dominant body | Small range or wicky / doji |
| Gap size | Meaningful | Tiny |
| Context | Often right **after a liquidity sweep** / with a structure break | Random, inside consolidation |
| Tendency | Respected, acts as a magnet / reaction zone | Filled quickly, unreliable |

This indicator classifies a gap as **REAL** only when **all three** hold:

1. middle-candle range ≥ `InpDispATR × ATR` (displacement), **and**
2. middle-candle body/range ≥ `InpMinBodyRatio` (directional, not a doji), **and**
3. gap size ≥ `InpMinGapATR × ATR` (meaningful).

Otherwise it is **FAKE**. As a bonus, if an aligned sweep happened within the last
`InpSweepContextBars` bars, the gap's label gets a **`+sweep`** tag (the highest-probability case
per the literature: *FVG formed right after liquidity was taken*).

> Visuals: **Real** FVGs are drawn as **filled** boxes with a solid border; **Fake** FVGs as
> lighter **dotted outline** boxes (and can be hidden entirely with `InpShowFakeFVG = false`).

---

## 2. Why it does not repaint

"Repaint" means a signal appears, then later moves or vanishes once you reload / more candles
form. This indicator cannot do that, by design:

* **Signals are only ever evaluated on fully *closed* bars.** The currently-forming bar
  (`rates_total-1`) is never used to print a sweep, level, or FVG. In the main loop the forming
  bar's buffers are cleared and the loop `break`s before any detection runs on it.
* **Sweeps are confirmed at the candle's close** (wick beyond + close back inside). Once that
  bar closes the condition is frozen; the arrow is anchored to that bar's time and never changes.
* **FVGs are confirmed at the close of the 3rd candle** and anchored to fixed bar times. The box
  is extended a *fixed* number of bars to the right (`InpFVGExtendBars`); it is **not** stretched
  dynamically to "mitigation", precisely so nothing updates after the fact.
* **Swing levels use a symmetric pivot** (`InpPivotLength` bars on each side). A level is only
  recognised once those right-hand bars have **closed**. That is **confirmation lag, not
  repainting**: the level appears `InpPivotLength` bars late, but once shown it never moves. This
  lag is the honest cost of a non-repaint swing — lowering `InpPivotLength` reduces the lag but
  marks more (smaller) swings.
* On history refresh / timeframe change the indicator wipes and **rebuilds deterministically from
  the same closed bars**, so it reproduces the identical picture.

Alerts (if enabled) fire **only** for the bar that just closed in real time, never while
re-scanning history — so you won't get a burst of alerts on attach.

---

## 3. Installation

1. Copy `MD5_Liquidity_Sweep.mq5` into your terminal's data folder under
   `MQL5/Indicators/` (in MetaTrader 5: **File → Open Data Folder**).
2. Open **MetaEditor** (F4), select the file, and press **Compile** (F7). You should get
   `0 errors, 0 warnings`.
3. In MetaTrader 5, refresh **Navigator → Indicators**, then drag
   **MD5 Liquidity Sweep + FVG** onto a chart.

> This indicator was authored and statically reviewed outside MetaEditor, so compile it once in
> your own MetaEditor to generate the `.ex5`.

---

## 4. Inputs

### Liquidity / Sweep
| Input | Default | Meaning |
|---|---|---|
| `InpPivotLength` | `10` | Swing pivot strength: bars required on **each** side. Higher = fewer, more significant levels + more confirmation lag. |
| `InpMaxActiveLevels` | `60` | Max liquidity levels tracked at once (oldest dropped). |
| `InpShowSweptLevel` | `true` | Draw the horizontal line at the swept level, from the swing to the sweep bar. |
| `InpArrowOffsetATR` | `0.5` | How far off the candle the arrow sits, in ATR units. |
| `InpBSLColor` | `clrTomato` | Buy-side level + arrow colour. |
| `InpSSLColor` | `clrDodgerBlue` | Sell-side level + arrow colour. |

### Fair Value Gaps
| Input | Default | Meaning |
|---|---|---|
| `InpShowFVG` | `true` | Draw Fair Value Gaps. |
| `InpShowFakeFVG` | `true` | Also draw fake (weak) FVGs. Set `false` to show only real ones. |
| `InpATRPeriod` | `14` | ATR period used as the displacement / gap reference. |
| `InpDispATR` | `1.2` | REAL threshold: middle-candle range ≥ this × ATR. |
| `InpMinBodyRatio` | `0.50` | REAL threshold: middle-candle body ÷ range ≥ this. |
| `InpMinGapATR` | `0.10` | REAL threshold: gap size ≥ this × ATR. |
| `InpSweepContextBars` | `10` | Tag an FVG `+sweep` if an aligned sweep occurred within this many bars. |
| `InpFVGExtendBars` | `30` | How many bars to extend each FVG box to the right. |
| `InpRealBullColor` / `InpFakeBullColor` | green shades | Real / fake bullish FVG colours. |
| `InpRealBearColor` / `InpFakeBearColor` | red shades | Real / fake bearish FVG colours. |

### Alerts (optional, off by default)
| Input | Default | Meaning |
|---|---|---|
| `InpAlertPopup` | `false` | Popup alert on a confirmed sweep (live bar only). |
| `InpAlertPush` | `false` | Push notification on a confirmed sweep (needs MetaQuotes ID set in terminal). |

### General
| Input | Default | Meaning |
|---|---|---|
| `InpMaxBars` | `2500` | Limit how much history is processed/drawn (0 = all). Keeps the chart light. |
| `InpPrefix` | `"MD5LS_"` | Prefix for all chart objects this indicator creates. |

---

## 5. Buffers (for EAs / Data Window)

The two plotted buffers are also readable programmatically (e.g. from an Expert Advisor via
`iCustom` / `CopyBuffer`):

| Buffer | Plot | Meaning | Value on a signal bar |
|---|---|---|---|
| `0` | `BSL Sweep (bearish)` | Buy-side liquidity swept | price of the arrow (above the bar) |
| `1` | `SSL Sweep (bullish)` | Sell-side liquidity swept | price of the arrow (below the bar) |

Non-signal bars hold `EMPTY_VALUE`. Because signals print on closed bars, read them from bar
index `1` or older in an EA — never bar `0`.

---

## 6. Tuning notes

* **Too many / too noisy signals?** Raise `InpPivotLength` (e.g. 15–20) for more significant
  liquidity, and raise `InpDispATR` / `InpMinGapATR` to keep only stronger FVGs.
* **Signals feel late?** That lag is the non-repaint confirmation window. Lower `InpPivotLength`,
  accepting smaller/less significant swings.
* **Only want institutional-grade gaps?** Set `InpShowFakeFVG = false`.
* Prior-day / session / weekly highs and lows and **equal** highs/lows are generally the
  strongest liquidity; the pivot engine captures the swing version of these.

---

## 7. Disclaimer

This is a **study / charting tool** implementing a popular retail trading framework. The
"stop hunt" and "institutional footprint" narratives are claims made by that community and are
not established, peer-reviewed market facts. Nothing here is financial advice. Test on historical
and demo data and manage risk before trading live.
