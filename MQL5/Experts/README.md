# Three-Candle Reversal EA (XAUUSD, M1/M5)

A robust MetaTrader 5 Expert Advisor that trades a three-candle reversal
pattern on **gold (XAUUSD)** on the **M1 and M5** timeframes only.

---

## The strategy

The EA looks at the **three most recently closed candles** on every new bar.
Using MT5 shift indexing (shift `0` = the bar still forming, which is ignored):

| Role in pattern | Bar shift |
|-----------------|-----------|
| **First** candle (oldest) | `3` |
| **Middle** candle | `2` |
| **Third** candle (latest closed) | `1` |

### Buy setup
1. First candle is **red** (bearish).
2. Middle candle is **green** (bullish).
3. Third candle is **green** (bullish).
4. The middle candle's **low (including the wick)** is lower than the low of
   both the first and the third candle.
5. The third candle's **body** (its close, since it's green) closes **above the
   high** of the first candle — i.e. the body, not just a wick, engulfs the
   first candle's high (including that candle's wick).
6. → Open a **BUY**.

### Sell setup
1. First candle is **green** (bullish).
2. Middle candle is **red** (bearish).
3. Third candle is **red** (bearish).
4. The middle candle's **high (including the wick)** is higher than the high of
   both the first and the third candle.
5. The third candle's **body** (its close, since it's red) closes **below the
   low** of the first candle — the body, not just a wick, engulfs the first
   candle's low (including that candle's wick).
6. → Open a **SELL**.

Each trade is opened with a fixed **Take Profit** and **Stop Loss**, both fully
adjustable (default **$1 / $1**).

---

## Inputs

### Money Management
| Input | Default | Meaning |
|-------|---------|---------|
| `InpLotSize` | `0.01` | Fixed lot size per trade. |
| `InpTpSlMode` | `Distance in USD` | How TP/SL are interpreted (see below). |
| `InpTakeProfit` | `1.0` | Take Profit value. |
| `InpStopLoss` | `1.0` | Stop Loss value. |

**`InpTpSlMode` options**
- **`TPSL_PRICE_USD`** (default) — TP/SL are a **price distance in USD**. For
  gold, `1.0` = a `$1.00` price move (e.g. buy at `4051.00` → TP `4052.00`,
  SL `4050.00`). This is the usual meaning of "TP of 1 USD" for gold traders.
- **`TPSL_MONEY_USD`** — TP/SL are a **target profit/loss in account currency**.
  The EA converts the money target into the correct price distance using the
  symbol's tick value and your lot size.

### Trailing Stop (fixed USD, no ATR)
| Input | Default | Meaning |
|-------|---------|---------|
| `InpUseTrailing` | `true` | Enable the tight trailing stop. |
| `InpTrailStartUSD` | `0.5` | Trailing activates once the trade is this many USD in profit. |
| `InpTrailGapUSD` | `0.1` | Once active, the SL is kept this far (USD) behind price — smaller = tighter. |
| `InpTrailStepUSD` | `0.0` | Minimum SL improvement before it moves again (`0` = update every tick). |

**How it works:** the initial `$1` stop stays as protection until price is
`InpTrailStartUSD` in profit. From then on the SL follows price, staying
`InpTrailGapUSD` behind, and only ever moves in your favour (never loosens).
For a buy the stop ratchets **up**; for a sell it ratchets **down**. If the
requested gap is tighter than your broker's minimum stop distance, it is
widened to that minimum automatically.

> **Tighter = more sensitive.** A very small `InpTrailGapUSD` (e.g. `0.1`) locks
> profit fast but is easily clipped by normal M1 noise; `0.2`–`0.3` is a common
> balance. Adjust to taste.

### Trade Filters
| Input | Default | Meaning |
|-------|---------|---------|
| `InpEnableBuy` | `true` | Allow buy trades. |
| `InpEnableSell` | `true` | Allow sell trades. |
| `InpMaxPositions` | `1` | Max simultaneous EA positions on this symbol. |
| `InpMaxSpreadUSD` | `0.0` | Skip entries if spread exceeds this (USD). `0` = off. |

### Trend / Reversal Filter (M5 recommended)
Stops the pattern from firing mid-trend, so **sells only trigger at the top of
an up-move and buys only at the bottom of a down-move**.

| Input | Default | Meaning |
|-------|---------|---------|
| `InpUseTrendFilter` | `true` | Master switch for the reversal filter. |
| `InpSwingLookback` | `12` | The middle candle must be the highest high (sell) / lowest low (buy) of this many bars — i.e. a genuine local top/bottom. `0` = skip. |
| `InpMAPeriod` | `50` | Trend MA. Sell requires the MA **rising** into the pattern (up-trend); buy requires it **falling** (down-trend). `0` = skip. |
| `InpMAMethod` | `EMA` | MA method (EMA/SMA/…). |
| `InpMASlopeBars` | `5` | How many bars back the MA slope is measured over. |

**How it decides a reversal:** a signal is only taken when **both** conditions
hold (each can be turned off individually):
1. **Local extreme** — the pattern's middle candle is the swing high/low of the
   last `InpSwingLookback` bars, so the signal sits at a real top/bottom.
2. **Opposite prior trend** — the MA is sloping the other way, confirming the
   move being reversed (up-trend before a sell, down-trend before a buy).

Filtered-out patterns are logged as *"… found but filtered out"* so you can see
what was skipped. Loosen by lowering `InpSwingLookback`, or disable a check by
setting it to `0`. **M5 is more reliable for this strategy than M1.**

### Instrument / Timeframe Guards
| Input | Default | Meaning |
|-------|---------|---------|
| `InpRestrictSymbol` | `true` | Refuse to run on non-gold symbols. |
| `InpRestrictTimeframe` | `true` | Refuse to run on anything but M1/M5. **M5 recommended.** |

### Execution
| Input | Default | Meaning |
|-------|---------|---------|
| `InpMagicNumber` | `20250804` | Identifies this EA's trades. |
| `InpDeviationPts` | `30` | Max slippage in points. |
| `InpTradeComment` | `3CandleEA` | Comment attached to trades. |

---

## Robustness features

- **Symbol guard** — only runs on XAUUSD/gold-style symbols (matches `XAU`
  or `GOLD`, so broker suffixes like `XAUUSD.m` work).
- **Timeframe guard** — only M1 and M5; refuses to initialise elsewhere.
- **New-bar-only evaluation** — the pattern is checked once per closed bar, so
  it never fires mid-candle or duplicates an entry within the same bar.
- **Position cap** — respects `InpMaxPositions` (per symbol + magic).
- **Broker stop-level clamp** — if the requested TP/SL is closer than the
  broker's minimum stop distance, it is safely widened (with a log warning) so
  orders are not rejected.
- **Spread filter** — optional maximum-spread guard.
- **Trade-permission checks** — verifies terminal, account, EA and symbol are
  all allowed to trade before sending an order.
- **Auto fill-mode** — fill policy is selected from the symbol.
- **Detailed logging** — every detected pattern and order result is printed to
  the Experts log for auditing.

---

## Installation

1. Open MetaTrader 5 → **File → Open Data Folder**.
2. Copy `ThreeCandleReversalEA.mq5` into `MQL5/Experts/`.
3. In **MetaEditor**, open the file and press **F7** (Compile).
4. In MT5, open a **XAUUSD** chart set to **M1** or **M5**.
5. Drag the EA onto the chart, enable **Algo Trading**, and confirm
   "Allow Algo Trading" is ticked in the EA dialog.

### Backtesting
Use the **Strategy Tester** with symbol `XAUUSD` and period `M1` or `M5`.
"Every tick based on real ticks" gives the most accurate fills.

---

## Notes
- TP and SL default to `$1` each; change `InpTakeProfit` / `InpStopLoss` any
  time to adjust your risk-reward.
- The "engulf" rules require the third candle's **body** (close price) to pass
  the first candle's extreme — a wick alone is not enough, exactly as specified.
