# Liquidity Sweeper Scalper — EA (backtestable)

Expert Advisor version of the indicator. It trades the **same confirmed BUY/SELL signals**
(liquidity sweep + reversal-half close + follow-through confirmation) on a **timeframe you choose in
the inputs**, so you can backtest the strategy in the MT5 Strategy Tester.

**File:** `Liquidity_Sweeper_Scalper_EA.mq5` → put it in `MQL5/Experts/`.

---

## "1:3" — what it means here

In trading, **1:3 = risk-to-reward**: you risk 1 and target 3. That is the input **`InpRR = 3.0`**
→ the take-profit is placed **3× the stop distance** away. Stop-loss sits just beyond the sweep
wick; TP = 3 × that risk.

> *Profit factor* (gross profit ÷ gross loss) is a **result** the tester reports after a run — you
> don't set it. With a fixed 1:3 payoff you're net profitable once the **win rate is above ~25%**
> (ignoring costs). The backtest tells you the real win rate, profit factor, drawdown, etc.

---

## Pick your signal timeframe

**`InpSignalTF`** is a timeframe dropdown — set it to **M5, M15, M30 or H1** (or anything). The EA
takes signals from that timeframe no matter which chart/tester timeframe it runs on. Change it and
re-run to compare, e.g. H1 vs M15 vs M5.

`InpTradeBuys` / `InpTradeSells` let you test one direction at a time.

---

## How to backtest (MT5 Strategy Tester)

1. Copy the file to `MQL5/Experts/` and **Compile** (F7) in MetaEditor.
2. **View → Strategy Tester** (Ctrl+R). Expert: **Liquidity Sweeper Scalper EA**. Symbol: e.g.
   `XAUUSD`.
3. **Set the tester "timeframe" to M1** and **Modeling: "Every tick based on real ticks"** (best) or
   **"1 minute OHLC"**. This is so stop-loss / take-profit fills *inside* a bar are simulated
   accurately — the EA still reads signals from `InpSignalTF`, independent of this setting.
4. Pick a date range, set your deposit, and run. Read the **Report** tab for net profit, **profit
   factor**, win rate, max drawdown, and the equity curve.
5. Change `InpSignalTF` (and `InpRR`, risk, filters) and re-run to compare.

> Backtest quality depends on your broker's history and spread. Use real-tick data where possible,
> set a realistic spread, and forward-test on demo before trading live.

---

## Inputs

### Signal source
| Input | Default | Meaning |
|---|---|---|
| `InpSignalTF` | `M15` | Timeframe the BUY/SELL signals come from (M5/M15/M30/H1…). |
| `InpTradeBuys` / `InpTradeSells` | `true` | Enable each direction. |

### Sweep detection (identical to the indicator)
| Input | Default | Meaning |
|---|---|---|
| `InpPivotLength` | `10` | Swing pivot strength (bars each side). |
| `InpBarsScan` | `300` | Signal-TF history scanned each new bar. |
| `InpSignalStrongClose` | `true` | Sweep must close in the reversal half of its range. |
| `InpUseConfirm` | `true` | Require a follow-through candle to break the sweep's extreme (enter next bar). |
| `InpUseTrendFilter` | `false` | Only trade with the signal-TF EMA trend. |
| `InpTrendEMAPeriod` | `50` | EMA period for that filter. |

### Risk / money management
| Input | Default | Meaning |
|---|---|---|
| `InpRR` | `3.0` | Reward:Risk. **1:3 → 3.0.** TP = RR × stop distance. |
| `InpSLBufferPoints` | `30` | Extra SL distance beyond the sweep wick, in **points** (adjust per broker digits). |
| `InpLotMode` | `1` | `0` = fixed lot, `1` = % risk of balance. |
| `InpFixedLot` | `0.01` | Lot when `InpLotMode = 0`. |
| `InpRiskPercent` | `1.0` | Risk % per trade when `InpLotMode = 1`. |
| `InpMaxOpenTrades` | `1` | Max simultaneous positions from this EA. |
| `InpMoveToBE` | `false` | Move SL to break-even once price reaches +1R. |
| `InpSlippagePoints` | `20` | Max slippage (points). |
| `InpMagic` | `775311` | Magic number (keep unique per EA/chart). |

### Filters (optional)
| Input | Default | Meaning |
|---|---|---|
| `InpUseSession` | `false` | Restrict trading to an hour window (server time). |
| `InpStartHour` / `InpEndHour` | `7` / `20` | Session window (supports overnight if start > end). |
| `InpMaxSpreadPoints` | `0` | Skip entries when spread exceeds this (0 = ignore). |

---

## How entries work (non-repaint)

1. A sweep forms on `InpSignalTF` and closes in the reversal half of its range.
2. The **next candle confirms** it (closes beyond the sweep's extreme).
3. On the **open of the following bar**, the EA enters at market — no look-ahead.
4. **SL** just beyond the sweep wick (+ `InpSLBufferPoints`, and never tighter than the broker's
   minimum stop). **TP** = `InpRR` × risk. Optional break-even at +1R.

One position at a time by default; each signal is taken once.

---

## Notes

- `InpSLBufferPoints` is in **points** — on a 2-digit gold feed 30 points = \$0.30, on a 3-digit
  feed = \$0.03. Check your symbol's digits and adjust.
- `% risk` sizing uses the symbol's tick value/size, normalised to the broker's lot step.
- This EA mirrors the indicator's detection so the backtest reflects what you see on the chart.
- Not financial advice. Validate on demo before any live use.
