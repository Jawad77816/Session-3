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
4. **Session window (PKT).** Only opens new trades between `InpStartHourPKT` and
   `InpEndHourPKT` (default 12:00–20:00 Pakistan time).
5. **News filter.** Blocks new trades 15 min before → 15 min after news.
6. **Grid.** Averages into adverse moves (every N USD against the first trade adds
   another trade in the same direction). **High risk — see below.**
7. **Pivot points.** Daily floor pivots drawn as continuous horizontal S/R lines.

## Session, "don't close at 8 PM", and the broker clock

The session window is in **Pakistan time (PKT = UTC+5, no daylight saving)**. An
MT5 EA only knows the *broker server time*, so you MUST tell it the server's GMT
offset via **`InpBrokerGMTOffset`** (e.g. `+2` in winter, `+3` in summer for many
gold brokers — check *Market Watch* clock vs. GMT). If this is wrong, your window
is shifted by the same number of hours.

- New trades are only opened when PKT hour is `>= 12` and `< 20`.
- A trade opened at 19:59 PKT is **never force-closed at 20:00** — the EA only
  stops *opening* new trades; running trades exit on their own TP/SL/trailing.

## News filter (Rule 3)

Blackout = `InpNewsMinsBefore` (15) before → `InpNewsMinsAfter` (15) after each
event. Two independent sources, either can trigger a blackout:

- **Manual list** — `InpManualNewsPKT`, comma-separated **PKT** datetimes, e.g.
  `2026.07.28 17:30,2026.07.29 12:30`. Works everywhere, **including the Strategy
  Tester** (the tester cannot read the live calendar).
- **MT5 economic calendar** — `InpUseCalendarAuto`. Filters by `InpNewsImportance`
  (1/2/3) and `InpNewsCurrencies` (e.g. `USD`). **Live trading only** — returns
  nothing in the Strategy Tester, so use the manual list for backtests.

As with the session cutoff, a news blackout only blocks *new* entries; open trades
are left alone.

## Grid / averaging (Rule 4) — ⚠️ high risk

If the first trade of a cycle is a **sell** and price rises against it, every
`InpGridStepUSD` (default 4) of adverse move adds **another sell**, same lot, same
6/6 TP/SL, same trailing. Mirror for buys. Up to `InpMaxGridTrades` (default 5)
trades per cycle.

- Grid additions also respect the **session window and news filter** (they are new
  trades), matching "no new trades after 8 PM".
- For the grid to actually build, the first trade's SL must be **wider than the
  grid step** — otherwise it closes at −6 before the +4 add triggers. Increase
  `InpStopLoss` (you said you'd widen it) or the cycle will rarely reach 2+ trades.
- **This is a martingale-style "average into losers" pattern.** It smooths many
  small wins but exposes you to a large loss on a sustained trend against you.
  Size `InpMaxGridTrades` and your account so the *worst case* (all trades open,
  all hit SL) is survivable. Test before going anywhere near live.

## Pivot points (Rule 5)

Standard floor pivots computed from the previous `InpPivotTF` (default D1) candle
and drawn as `OBJ_HLINE` — **continuous horizontal lines** that span the whole
chart and auto-recalculate each new day: `P`, `R1/R2/R3`, `S1/S2/S3`. They are
**visual only** — they do not currently gate entries. (Say the word if you want
entries filtered by pivots.)

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
| `InpTargetMode` | MONEY_USD | Interpret targets as USD or price |
| `InpTakeProfit` / `InpStopLoss` | 6 / 6 | TP / SL |
| `InpTrailStart` | 0.3 | Favourable move before trailing starts |
| `InpTrailDistance` | 0.3 | Gap between price and trailing SL |
| `InpTrailStep` | 0.05 | Min SL improvement before it is moved |
| `InpBrokerGMTOffset` | 3 | **Broker server GMT offset — set this correctly** |
| `InpStartHourPKT` / `InpEndHourPKT` | 12 / 20 | Session window in PKT |
| `InpUseNewsFilter` | true | Enable news blackout |
| `InpNewsMinsBefore` / `InpNewsMinsAfter` | 15 / 15 | Blackout window |
| `InpManualNewsPKT` | "" | Manual news times (PKT), comma-separated |
| `InpUseCalendarAuto` | true | Use MT5 economic calendar (live only) |
| `InpNewsImportance` / `InpNewsCurrencies` | 3 / USD | Calendar filters |
| `InpEnableGrid` | true | Average into adverse moves (⚠️ risk) |
| `InpGridStepUSD` | 4 | Adverse move per added trade |
| `InpMaxGridTrades` | 5 | Max trades per cycle |
| `InpShowPivots` | true | Draw pivot S/R lines |
| `InpPivotTF` | D1 | Pivot calculation timeframe |

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
