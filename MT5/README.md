# TrendTrailingEA (MT5)

An Expert Advisor that trades in the direction of a higher-timeframe trend, with
a fixed TP/SL and a trailing stop that activates after a small favourable move.

## What it does

1. **Trend filter (higher timeframe).** Reads a moving average on a configurable
   higher timeframe (`InpTrendTF`, default H1). If the last closed higher-TF
   candle closed **above** the MA → uptrend (buy); **below** → downtrend (sell).
   Change the timeframe/MA freely in the inputs.
2. **Entry.** Opens `InpLots` (default 0.01) in the trend direction with a fixed
   take-profit and stop-loss.
3. **Trailing.** Once price moves in favour by `InpTrailStart` (default 0.3), the
   stop-loss starts following price, keeping a gap of `InpTrailDistance` behind it,
   only ever moving in the favourable direction.

## The "6 USD" = "6.00 price" point

Your example (price 4000 → TP 4006 / SL 3994) is **Gold (XAUUSD) at 0.01 lot**.
On XAUUSD, 0.01 lot means a **$1 price move ≈ $1 profit**, so a **6.00 price move
= ~$6 profit**. The two numbers only coincide for gold at 0.01 lot.

To keep it correct on any symbol/lot, the EA has `InpTargetMode`:

- `MODE_MONEY_USD` (default): `InpTakeProfit=6`, `InpStopLoss=6`,
  `InpTrailStart=0.3`, `InpTrailDistance=0.3` are read as **US dollars** and the
  EA converts them to the correct price distance using the symbol's tick value.
  For gold at 0.01 lot this resolves to exactly 6.00 / 6.00 / 0.30 / 0.30 price.
- `MODE_PRICE_POINTS`: the same inputs are read as **raw price distance**
  (6.0 = a 6.00 move) regardless of money value.

## Key inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpTrendTF` | H1 | Higher timeframe for trend |
| `InpMAPeriod` / `InpMAMethod` | 50 / EMA | Trend MA |
| `InpLots` | 0.01 | Lot size |
| `InpOnePosition` | true | Only one open trade at a time |
| `InpTargetMode` | MONEY_USD | Interpret targets as USD or price |
| `InpTakeProfit` / `InpStopLoss` | 6 / 6 | TP / SL |
| `InpTrailStart` | 0.3 | Favourable move before trailing starts |
| `InpTrailDistance` | 0.3 | Gap between price and trailing SL |
| `InpTrailStep` | 0.05 | Min SL improvement before it is moved |

## Install

1. Copy `TrendTrailingEA.mq5` into `MQL5/Experts/` in your MT5 data folder
   (*File → Open Data Folder* in the terminal).
2. Open it in MetaEditor and press **Compile** (F7).
3. Attach it to a **Gold (XAUUSD)** chart, allow algo trading, and set inputs.
4. **Test in the Strategy Tester and on a demo account first.**

## Will it work? — honest assessment

**Mechanically: yes.** It compiles, detects trend, opens the trade with the exact
TP/SL from your example, and trails the stop after a 0.3 move. That part does what
you asked.

**As a money-maker: be careful.** The design has real practical risks:

- **Spread & commission eat a 6-point target.** Gold spread is often 15–40 points
  ($0.15–$0.40 on 0.01 lot), plus commission. With a $6 target and $0.30 trailing
  trigger, cost is a large fraction of the target — and the trailing gap (0.30) is
  near typical spread, so a normal spread widening can stop you out immediately.
- **Broker minimum stop distance.** Some brokers won't allow SL/TP or trailing
  closer than a minimum (`SYMBOL_TRADE_STOPS_LEVEL`). The EA warns on init and
  clamps the trailing distance, but very tight stops may still be rejected.
- **1:1 risk/reward + a trend MA filter is not an edge by itself.** Whether it's
  profitable depends entirely on your gold's behaviour, costs, and slippage. It
  needs backtesting and forward-testing on a demo before any live use.

**Bottom line:** it will run and behave exactly as specified. Treat the numbers as
a starting point and validate in the Strategy Tester before risking real money.
