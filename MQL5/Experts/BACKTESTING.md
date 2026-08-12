# Backtesting the Three-Candle Reversal strategy

MT5's **Strategy Tester runs Expert Advisors only** — it can't backtest an
indicator directly. So use **`ThreeCandleReversalTester.mq5`**, an EA that loads
the `ThreeCandleReversalSignal` indicator via `iCustom`, reads its buy/sell
arrows, and opens trades with TP/SL and trailing. This backtests the **exact
same logic** the indicator draws — no duplicated code that can drift.

## Setup (one time)
1. Put both files in place and compile each with **F7** in MetaEditor:
   - `MQL5/Indicators/ThreeCandleReversalSignal.mq5`  → produces `.ex5`
   - `MQL5/Experts/ThreeCandleReversalTester.mq5`
2. The tester looks for the indicator by name (`InpIndicatorName`,
   default `ThreeCandleReversalSignal`). If you put the indicator in a
   subfolder, set that subpath (e.g. `MyFolder\\ThreeCandleReversalSignal`).

## Run the test
1. **View → Strategy Tester** (Ctrl+R).
2. **Expert:** `ThreeCandleReversalTester`.
3. **Symbol:** `XAUUSD`   **Period:** `M1` or `M5`.
4. **Modelling:** "Every tick based on real ticks" (most accurate fills).
5. Pick a date range, set the deposit, and press **Start**.
6. Turn on **Visual mode** to watch arrows + the dashboard as it trades.

## What the parameters do
The tester exposes the same strategy inputs as the indicator (trend filter,
shape rules, confirmation, RSI filter, swing lookback, …) plus the trading
inputs:

| Input | Meaning |
|-------|---------|
| `InpLotSize` | Lot size per trade |
| `InpAutoSLTP` | **On (default):** SL = middle candle's low (buy) / high (sell); TP = `InpRewardRatio` × that risk |
| `InpRewardRatio` | Reward:risk multiple — `3` for 1:3, `4` for 1:4 |
| `InpSLBufferUSD` | Extra distance beyond the middle candle wick for the SL |
| `InpTakeProfit` / `InpStopLoss` | Fixed TP/SL in USD — used only when `InpAutoSLTP = false` |
| `InpUseTrailing` + `InpTrailStartUSD` / `InpTrailGapUSD` | Tight trailing stop (off by default; interferes with a fixed R:R target) |
| `InpUseRSIFilter`, `InpRSIMode`, `InpSwingLookback`, … | Same filters as the indicator |

**Auto SL/TP:** with `InpAutoSLTP = true`, each trade's stop is placed at the
middle (pin) candle's extreme and the target is a fixed multiple of that risk —
so a $0.80 risk with `InpRewardRatio = 3` gives a $2.40 target (1:3). Keep
trailing **off** for a clean R:R test.

Changing a strategy input here changes what the loaded indicator computes, so
the backtest always reflects your current configuration.

## Reading results
After the run, open the **Results** and **Graph** tabs:
- **Profit factor**, **expected payoff**, **win %**, **max drawdown** tell you
  if the edge is real.
- Use the **Optimization** tab to sweep e.g. `InpRSIMode`, `InpSwingLookback`,
  `InpTakeProfit`/`InpStopLoss`, and `InpConfirmCandle` to find robust settings.

## Notes
- Entries are taken at the **open of the bar after** a signal bar closes
  (no look-ahead / no repaint), matching how you'd trade the arrows live.
- Backtest on the same broker's XAUUSD you trade, since spread and the
  `$1` TP/SL scale with the symbol's tick value.
- Results are indicative, not a guarantee — always forward-test on demo before
  going live.
