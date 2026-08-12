# MTF Trend Alignment — MT5 Indicator

A MetaTrader 5 custom indicator that gives **Buy / Sell signals** only when the
higher timeframes agree with the entry timeframe, and draws the **Entry, Stop
Loss and Take Profit** at a fixed risk-reward ratio (1:3 or 1:4).

## The strategy

1. Read the trend on **H4**, **H1** and **M15**.
2. If **all three are bullish**, drop down to the **M1** (entry) chart.
   - If M1 is also bullish → **BUY** signal.
3. If **all three are bearish**, drop down to the M1 chart.
   - If M1 is also bearish → **SELL** signal.
4. On each signal the indicator plots:
   - an arrow on the signal candle,
   - the **Entry** line,
   - the **SL** line (ATR-based distance),
   - the **TP** line, placed at `SL distance × Reward ratio`
     (default `3.0` → 1:3, set `4.0` for 1:4).

### How "trend" is defined

Two selectable methods (`InpMethod`):

- **EMA Cross (default):** bullish when `Fast EMA > Slow EMA` **and** price is
  above the Fast EMA; bearish is the mirror. Defaults: Fast = 21, Slow = 50.
- **Price vs EMA:** bullish when price is above the Fast EMA, bearish below.

Higher-timeframe trend is read from the **last closed bar** of each timeframe so
it does not repaint intrabar. The entry signal fires on the M1 bar that first
crosses into alignment (a fresh entry, not every bar of a running trend).

## Installation

1. Copy `MTF_Trend_Alignment.mq5` into your terminal's
   `MQL5/Indicators/` folder.
   (In MT5: **File → Open Data Folder → MQL5 → Indicators**.)
2. In MetaEditor press **F7** (Compile).
3. Open an **M1** chart of your symbol and drag the indicator onto it.

## Key inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpTF1 / InpTF2 / InpTF3` | H4 / H1 / M15 | The three higher timeframes that must align |
| `InpEntryTF` | M1 | Entry timeframe (attach the chart to this) |
| `InpMethod` | EMA Cross | Trend definition method |
| `InpFastEMA / InpSlowEMA` | 21 / 50 | EMA periods |
| `InpATRPeriod / InpATRMult` | 14 / 1.5 | ATR-based SL distance |
| `InpRewardRatio` | 3.0 | TP ratio — set `4.0` for 1:4 |
| `InpPopupAlert / InpPushAlert` | on / off | Alerts when a signal prints |
| `InpDrawLevels` | on | Draw Entry / SL / TP lines + labels |

## Notes

- This is an **indicator** (signals + levels only); it does not place trades.
- Signals are evaluated on **closed** bars to avoid repainting.
- The SL/TP lines shown are for the **most recent** signal; historical arrows
  stay on the chart.
