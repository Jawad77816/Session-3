# MSB-OB — Market Structure Break + Order Block (MetaTrader 5)

MQL5 recreation of the **"MSB-OB"** TradingView indicator/strategy shown in the
source video. Two separate files:

| File | Type | Purpose |
|------|------|---------|
| `Indicators/MSB_OB.mq5` | Indicator | Visualises swing structure, marks MSB breaks, draws bullish/bearish order-block zones. |
| `Experts/MSB_OB_EA.mq5` | Expert Advisor | Automatically trades the OB retest after a confirmed structure break. |

Both are built and tuned for the **M5 (5-minute)** timeframe.

## The strategy (from the video)

1. **Swing structure** – a ZigZag/pivot engine (`ZigZag Length = 9`) marks the
   most recent confirmed swing high and swing low. A pivot needs `Length` bars on
   each side to confirm.
2. **Market Structure Break (MSB)**
   - **Bullish MSB** – price *closes above* the last swing high.
   - **Bearish MSB** – price *closes below* the last swing low.
   - The break must clear the level by a **Fib factor of the impulse leg**
     (`Fib Factor = 0.273`) to filter false breaks.
3. **Order Block (OB)** – the last *opposite-colour* candle before the impulsive
   break is the entry **AREA**:
   - Bullish OB (green) = last bearish candle before an up-break → **demand**.
   - Bearish OB (red)  = last bullish candle before a down-break → **supply**.
4. **Trade** – wait for price to retrace into the OB and trade in the break's
   direction: **BUY** the bullish OB, **SELL** the bearish OB. Stop just beyond
   the OB, target at a fixed reward:risk.

## Indicator inputs (`MSB_OB.mq5`)

| Input | Default | Meaning |
|-------|---------|---------|
| `InpZigZagLength` | 9 | Pivot lookback each side |
| `InpShowZigzag` | false | Draw the ZigZag structure line |
| `InpFibFactor` | 0.273 | Breakout-confirmation buffer (× impulse leg) |
| `InpOBExtendBars` | 30 | How far to extend OB boxes to the right |
| `InpBullColor` / `InpBearColor` | Lime / Red | Zone & MSB colours |
| `InpMaxSetups` | 50 | Recent drawings to keep on chart |

Up/down arrows mark the MSB bar; horizontal lines label **MSB**; filled
rectangles are the order blocks.

## EA inputs (`MSB_OB_EA.mq5`)

Structure inputs mirror the indicator (`InpZigZagLength`, `InpFibFactor`). Trading:

| Input | Default | Meaning |
|-------|---------|---------|
| `InpEntryAtMid` | false | Enter at OB midpoint (else proximal edge) |
| `InpRiskReward` | 2.0 | Take-profit reward : risk |
| `InpSLBufferPoints` | 20 | Extra stop distance beyond the OB (points) |
| `InpPendingExpiryBars` | 24 | Cancel unfilled limit order after N bars |
| `InpOnePositionOnly` | true | Max one position at a time |
| `InpUseRiskPercent` | true | Size lots from risk % of balance |
| `InpRiskPercent` | 1.0 | Risk per trade (%) |
| `InpFixedLots` | 0.10 | Lots when risk % is disabled |
| `InpMagic` | 5507701 | Order magic number |
| `InpMaxSpreadPoints` | 40 | Skip when spread is wider (0 = ignore) |

**How it trades:** on each new M5 bar the EA re-scans structure. On a fresh
bullish MSB it places a **BUY LIMIT** at the bullish OB (SL below the OB, TP at
`InpRiskReward`); on a bearish MSB a **SELL LIMIT** at the bearish OB. Each new
break replaces the previous unfilled setup.

## Installation

1. Copy `MSB_OB.mq5` into `MQL5/Indicators/` and `MSB_OB_EA.mq5` into
   `MQL5/Experts/` of your MT5 data folder
   (*File → Open Data Folder* in the terminal).
2. In MetaEditor press **F7** to compile each file (produces `.ex5`).
3. Attach to an **M5** chart. For the EA, enable *Algo Trading*.

## Notes & tuning

- The **Fib factor** is implemented as a fraction of the swing-to-swing impulse
  leg added beyond the broken level. Raise it to demand stronger breaks; lower it
  for earlier (but noisier) signals.
- Pivots confirm with a lag of `ZigZagLength` bars (unavoidable for any ZigZag);
  the EA only acts on fully closed, confirmed structure — no look-ahead.
- Backtest in the **Strategy Tester** on your broker's data before live use, and
  adjust `InpSLBufferPoints`, `InpRiskReward` and risk % to the instrument.
