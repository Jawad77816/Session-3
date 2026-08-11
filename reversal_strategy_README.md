# Reversal-After-Trend strategy (from the video lesson)

`reversal_after_trend_strategy.pine` is a TradingView **Pine Script v6 strategy**
rebuilt from the price-action video (XAUUSD, 5-minute chart).

## The rule it implements

| | BUY setup | SELL setup |
|---|---|---|
| Context | a run of **red** candles (downtrend) | a run of **green** candles (uptrend) |
| Signal | first **green** (reversal) candle | first **red** (reversal) candle |
| Entry | on the reversal candle | on the reversal candle |
| Stop loss | just **below** the reversal / swing low | just **above** the reversal / swing high |
| Take profit | fixed **Risk:Reward** (1:2, then 1:3) | fixed **Risk:Reward** (1:2, then 1:3) |
| Confirmation | volume spike on the reversal (optional) | volume spike on the reversal (optional) |

## How to test it on TradingView

1. Open TradingView → **XAUUSD**, **5-minute** timeframe.
2. Bottom panel → **Pine Editor** → paste the contents of
   `reversal_after_trend_strategy.pine` → **Save** → **Add to chart**.
3. Open the **Strategy Tester** tab to see the back-test (net profit, win rate,
   drawdown, trade list).
4. Click the strategy's **⚙ Settings** to tune it to the lesson.

## Inputs you will most likely need to adjust

- **Consecutive trend candles before the reversal** (default `5`) — how many
  same-colour candles define "a trend". The video shows ~5–7; set this to the
  exact number the teacher stated.
- **Stop-loss anchor** — `Reversal candle` (tight, matches the video's thin red
  band) or `Swing of the whole move`.
- **Primary / second target R:R** — defaults `1:2` and `1:3`, scaling out 50%
  at the first target.
- **Filters** — optional volume-spike requirement and a trading-session window.

## Honest limitation

The video's **audio could not be transcribed** in this environment (the network
policy blocks the speech-model downloads), so the exact spoken numbers were not
captured. The logic above is reconstructed from the on-screen chart animation,
and every number the teacher might have specified is exposed as an input.
**If you tell me the precise spoken rules** (or the entry/SL wording), I'll hard-set
the defaults to match the lesson exactly.
