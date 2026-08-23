# Strategy source — video transcript

Creator: **Nitya Tiwari (@tradeiq.with.nitz)**. Strategy attributed to **Andrea Unger**
(4× World Trading Champion). This is a classic **RSI(2) pullback** (Larry Connors style).

## Transcript (English)
> Number one algo trader in the world, Andrea Unger — won the World Trading
> Championships four times, and with algo trading. His students have also won
> championships. Let's understand one of his strategies. **RSI is not only used for
> overbought/oversold — it's also used as a filter.** The strategy is simple:
> **price is above the 200 moving average → the market is bullish.** A **temporary
> pullback came below the 5 moving average.** **RSI 2-period is below 20 → short-term
> panic selling has happened.** This is where **smart money dip-buys** — we take an
> **entry here.** **Stop loss will be the low,** and **exit when price gives a close
> above the 5 EMA.** We'll also build the algo and check its accuracy…

## Rules extracted (implemented in the EA)
| Element | Rule |
|---|---|
| Direction | **Long only** |
| Trend filter | Close **>** 200 MA (bullish) |
| Pullback | Close **<** 5 EMA |
| Momentum trigger | **RSI(2) < 20** |
| Entry | Buy when all three true |
| Stop loss | **The low** of the signal candle |
| Exit | Close **>** 5 EMA (no fixed take-profit) |

Note: on the chart it was demoed on **BTCUSD, 15m**, but the rules are generic — attach
to any symbol/timeframe.
