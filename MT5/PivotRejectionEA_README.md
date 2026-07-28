# PivotRejectionEA (MT5)

Trades **rejections of daily pivot levels**. Same pivot lines, PKT session window
and news filter as `TrendTrailingEA`, but a completely different entry: it waits
for a candle to reject a pivot level, then trades the bounce.

## Entry logic

Pivots (P, R1–R3, S1–S3) are computed from the previous `InpPivotTF` (default D1)
candle and drawn as continuous horizontal lines. On the **close of each candle**
on `InpSignalTF` (default = the chart timeframe), the last closed candle is checked
against every pivot level:

- **SELL** — the candle's **wick pierced above** a level (`High ≥ level`) but its
  **body closed back below** it (`Close < level`) and it's a bearish candle
  (`Close < Open`). A rejection from resistance.
- **BUY** — the candle's **wick pierced below** a level (`Low ≤ level`) but its
  **body closed back above** it (`Close > level`) and it's a bullish candle
  (`Close > Open`). A rejection from support.

If both a buy and a sell trigger on the same candle (rare), it's treated as
ambiguous and **skipped**. `InpRejectionBuffer` (USD/price) can require the body to
close a bit *beyond* the level to count, filtering marginal touches.

## Targets — ⚠️ read this

Default **TP = 1 USD, SL = 6 USD** (on 0.01 lot gold that's a 1.00 / 6.00 price
move). That is a **6:1 risk-to-reward against you** — you risk $6 to make $1. To
break even you need to win **~6 out of every 7 trades** (before spread/commission).
Pivot rejections can have a high hit-rate, but a handful of losers wipes out many
winners, so this **must** be validated in the Strategy Tester before any live use.
Change `InpTakeProfit` / `InpStopLoss` freely if you want a saner ratio.

## Sessions & news

Identical to `TrendTrailingEA`:

- **Session:** new trades only between `InpStartHourPKT`–`InpEndHourPKT` (12:00–20:00
  PKT). **Set `InpBrokerGMTOffset` to your broker's server GMT offset** or the
  window will be shifted. Running trades are never force-closed at the cutoff.
- **News:** blackout 15 min before → 15 min after. Manual PKT list
  (`InpManualNewsPKT`, works in the tester) plus optional MT5 economic calendar
  (`InpUseCalendarAuto`, live only).

## Key inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpLots` | 0.01 | Lot size |
| `InpTargetMode` | MONEY_USD | Read TP/SL as USD or raw price |
| `InpTakeProfit` / `InpStopLoss` | 1 / 6 | TP / SL |
| `InpSignalTF` | current | Candle timeframe checked for rejections |
| `InpRejectionBuffer` | 0 | Extra distance body must close beyond the level |
| `InpOneTradeAtATime` | true | Only one open position |
| `InpBrokerGMTOffset` | 3 | **Broker server GMT offset — set correctly** |
| `InpStartHourPKT` / `InpEndHourPKT` | 12 / 20 | PKT session window |
| `InpUseNewsFilter` … `InpNewsCurrencies` | — | News filter (same as other EA) |
| `InpShowPivots` / `InpPivotTF` | true / D1 | Pivot lines |

## Install

1. Copy `PivotRejectionEA.mq5` into `MQL5/Experts/`.
2. Compile in MetaEditor (F7).
3. Attach to a **Gold (XAUUSD)** chart on the timeframe you want signals from,
   allow algo trading, set `InpBrokerGMTOffset`, and (for backtests) fill
   `InpManualNewsPKT`.
4. **Strategy-test and demo first** — especially given the 1:6 reward-to-risk.

> Not compiled in this environment (no MetaEditor on Linux). If F7 flags anything,
> send me the errors and I'll fix them.
