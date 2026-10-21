# Liquidity Sweeper Scalper (MQL5, non-repaint, multi-timeframe)

A MetaTrader 5 custom indicator for sweep-based scalping. By default the chart stays **clean** and
shows only two things:

1. A small **circle** on every **liquidity sweep**, on every enabled timeframe (M1, M5, M15, M30,
   H1, H4, D1, W1 optional) — at the **top** of the candle for a buy-side (high) sweep, at the
   **bottom** for a sell-side (low) sweep.
2. Prominent, confirmed **BUY / SELL signals** — BUY (aqua) below the bar, SELL (red) above it.

Everything else still runs in the backend but is **hidden by default** and can be switched back on:
the verbose BSL/SSL arrows + labels + swept-level lines (`InpShowSweeps`), and the **Fair Value
Gaps** real-vs-fake engine (`InpShowFVG`).

**File:** `Liquidity_Sweeper_Scalper.mq5`
**Platform:** MetaTrader 5 (any symbol, any timeframe)
**Window:** main chart window (object-based drawing)
**Repainting:** none — every signal is finalised on a *closed* bar of its own timeframe.

> **What changed in v3.00:** the chart is reduced to sweep **circles** + **BUY/SELL** signals.
> The FVG boxes and the verbose per-timeframe BSL/SSL markers are now **off by default** (toggle
> them back on any time). All detection logic is unchanged underneath.

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

### Buy / Sell signals (the strategy trigger)
On top of the raw sweep markers, the indicator prints **prominent, per-timeframe BUY / SELL
signals** straight from the gold-scalping logic:

* **BUY** (blue/aqua, up arrow below the bar, bold `<TF> BUY`) = a **sell-side sweep reclaimed** —
  price wicked below a swing low and closed back above it (bullish grab).
* **SELL** (red, down arrow above the bar, bold `<TF> SELL`) = a **buy-side sweep reclaimed** —
  price wicked above a swing high and closed back below it (bearish grab).

They are multi-timeframe exactly like the sweeps: on an M1 chart you get `M1 BUY/SELL`,
`M5 BUY/SELL`, `H1 BUY/SELL`, etc., with higher timeframes drawn bigger. By default a signal only
prints when the sweep candle **closes in the reversal half of its range** (`InpSignalStrongClose`),
which filters out weak, non-committal sweeps. Turn the raw sweep layer off (`InpShowSweeps = false`)
for a clean BUY/SELL-only chart.

> A signal is a *trigger to look*, not a blind entry. The highest-probability ones line up with the
> higher-timeframe bias, land into a higher-TF level, and leave a Real FVG — see
> `Gold_Scalping_Strategy.md`.

#### Signal quality filters (why a sweep may NOT produce a signal)
A raw sweep is marked (`<TF> BSL/SSL`) but a **BUY/SELL signal is only printed when it passes the
quality filters** — this is what stops the counter-trend "falling-knife" signals:

1. **Strong close** (`InpSignalStrongClose`, on): the sweep must close in the reversal half of its
   own range — no half-hearted reclaims.
2. **Follow-through confirmation** (`InpUseConfirm`, on, the key one): the **next closed candle must
   break the sweep candle's extreme** — close *above* the sweep high for a BUY, *below* the sweep
   low for a SELL. A reversal with no follow-through (exactly why two counter-trend M1 buys failed
   in a strong down-move) is rejected, while a sweep with real displacement after it (e.g. a sell at
   a top that drops hard) still fires. Cost: the signal prints **one candle after** the sweep.
3. **EMA trend filter** (`InpUseTrendFilter`, off by default): if on, only BUY when the close is
   above that timeframe's EMA and only SELL when below. It blocks counter-trend signals outright,
   but also suppresses genuine reversals at tops/bottoms — leave it off unless you only want
   trend-continuation signals.

So you will still see the `<TF> SSL`/`<TF> BSL` sweep marker, but no `<TF> BUY`/`SELL` until the
move is confirmed. Fewer signals, materially higher quality. (No filter makes signals "always
right" — these cut the obvious low-probability ones, nothing can remove risk entirely.)

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

1. Copy `Liquidity_Sweeper_Scalper.mq5` into your terminal's data folder under `MQL5/Indicators/`
   (in MT5: **File → Open Data Folder**).
2. In **MetaEditor** (F4) open the file and **Compile** (F7) → expect `0 errors`.
3. In MT5 refresh **Navigator → Indicators** and drag **Liquidity Sweeper Scalper** onto a
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
| `InpShowSweptLevel` | `true` | Draw the swept-level line (only relevant when the verbose markers are on). |
| `InpArrowOffsetFrac` | `0.5` | Marker distance from the candle, as a fraction of the sweep candle's range. |
| `InpScaleByTF` | `true` | Bigger markers/labels/circles for higher timeframes. |
| `InpLabelFontSize` | `8` | Base label font size. |
| `InpBSLColor` | `clrTomato` | Buy-side verbose-marker colour. |
| `InpSSLColor` | `clrDodgerBlue` | Sell-side verbose-marker colour. |

### Liquidity sweep circles (the clean default highlight)
| Input | Default | Meaning |
|---|---|---|
| `InpShowSweepCircle` | `true` | Mark every sweep with a circle — top of the candle for a high/buy-side sweep, bottom for a low/sell-side sweep. |
| `InpSweepCircleColor` | `clrGold` | Circle colour. |
| `InpSweepCircleCode` | `159` | Circle symbol (Wingdings; `159` = dot, `108` = larger filled circle). |
| `InpSweepCircleSize` | `2` | Circle base size (scaled up on higher timeframes if `InpScaleByTF`). |

### Buy / Sell signals
| Input | Default | Meaning |
|---|---|---|
| `InpShowSignals` | `true` | Draw the prominent BUY/SELL signals. |
| `InpShowSweeps` | `false` | Draw the verbose sweep arrows + labels + swept-level lines. Off by default — the circles replace them. |
| `InpSignalStrongClose` | `true` | Only signal when the sweep closes in the reversal half of its range. |
| `InpBuyColor` | `clrAqua` | BUY colour ("lime blue" — set to whatever you like, e.g. `clrDodgerBlue`, `clrLime`). |
| `InpSellColor` | `clrRed` | SELL colour. |
| `InpSignalWidth` | `4` | BUY/SELL arrow size (prominence). |
| `InpSignalFontSize` | `12` | BUY/SELL label font size. |
| `InpSignalExtraOffsetFrac` | `0.9` | Extra distance the signal sits beyond the raw sweep marker. |

### Signal quality filters
| Input | Default | Meaning |
|---|---|---|
| `InpUseConfirm` | `true` | Require a follow-through candle to break the sweep's extreme before signalling (prints 1 candle later; filters counter-trend failures). |
| `InpUseTrendFilter` | `false` | Only signal with that timeframe's EMA trend (BUY above EMA, SELL below). Blocks counter-trend but also mutes reversal tops/bottoms. |
| `InpTrendEMAPeriod` | `50` | EMA period for the trend filter. |

### Fair Value Gaps (chart timeframe)
| Input | Default | Meaning |
|---|---|---|
| `InpShowFVG` | `false` | Draw Fair Value Gaps (off by default; the engine still runs when on). |
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

## 6. Reading the chart (default clean view)

* A **gold circle on top of a candle** → a buy-side (high) liquidity sweep occurred there.
* A **gold circle under a candle** → a sell-side (low) liquidity sweep occurred there.
* Circles appear for **every** sweep on every enabled timeframe (bigger on higher timeframes) — they
  show you where liquidity was taken, nothing more.
* A big aqua **`<TF> BUY`** below a candle / red **`<TF> SELL`** above a candle → a *confirmed*,
  tradeable sweep on that timeframe (it passed the quality filters).

So: **circles = all sweeps; BUY/SELL = the ones worth trading.** Turn on `InpShowSweeps` /
`InpShowFVG` if you also want the verbose levels or the FVG boxes back.

**Confluence is the point:** the strongest setups are when a **lower-timeframe** BUY/SELL fires
right **into a higher-timeframe** sweep circle (liquidity level). See the gold scalping strategy
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
