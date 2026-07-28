# TrendTrailingEA (MT5)

An Expert Advisor that enters on a **pivot-point rejection in the direction of a
higher-timeframe trend**, then manages the trade with a fixed TP/SL, a trailing
stop, and optional grid averaging — inside a PKT session window with a news filter.

## What it does

1. **Trend filter (higher timeframe).** Reads a moving average on a configurable
   higher timeframe (`InpTrendTF`, default H1). If the last closed higher-TF
   candle closed **above** the MA → uptrend (buy); **below** → downtrend (sell).
   Change the timeframe/MA freely in the inputs.
2. **Entry — pivot rejection *in the trend direction*.** The first trade of a cycle
   only opens when a completed candle on `InpSignalTF` **rejects a pivot level** and
   that rejection agrees with the trend:
   - Uptrend + **bullish** rejection at a level (wick pierces below, body closes
     back above) → **BUY**.
   - Downtrend + **bearish** rejection (wick pierces above, body closes back below)
     → **SELL**.
   A rejection against the trend, or on a candle with conflicting signals, is
   ignored. `InpRejectionBuffer` can require the body to close a bit beyond the
   level. After the first trade opens, the **grid** takes over (below) and further
   rejections are ignored until the position is flat.
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

Pivots computed from the previous `InpPivotTF` (default D1) candle and drawn as
`OBJ_HLINE` — **continuous horizontal lines** that span the whole chart and
auto-recalculate each new day: `P`, `R1/R2/R3`, `S1/S2/S3`.

The calculation method is selectable via **`InpPivotMethod`**:

- **`PIVOT_STANDARD`** — Classic / Floor pivots (default).
- **`PIVOT_FIBONACCI`** — Fibonacci pivots (R/S at 0.382, 0.618, 1.000 of range).
- **`PIVOT_CAMARILLA`** — Camarilla pivots (levels off the close × 1.1/12, /6, /4).
- **`PIVOT_WOODIE`** — Woodie pivots (pivot uses the current period's open).

They are **visual only** — they do not currently gate entries. (Say the word if you
want entries filtered by pivots.)

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
| `InpSignalTF` | current | Candle timeframe checked for pivot rejections |
| `InpRejectionBuffer` | 0 | Extra distance body must close beyond the level |
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
| `InpPivotMethod` | STANDARD | Standard / Fibonacci / Camarilla / Woodie |
| `InpPivotTF` | D1 | Pivot calculation timeframe |
| `InpGridRespectFilters` | false | If true, grid adds are also blocked by session/news |
| `InpShowDashboard` | true | On-chart info panel (left side) |
| `InpDebugLogs` | false | Journal log of every trailing/grid decision |

## v4.0 — trailing/grid fixes and dashboard

- **Trailing hardened.** Silent skip conditions removed (broker stop-level is now
  clamped, not skipped); every rejected `PositionModify` is logged; with
  `InpDebugLogs=true` every SL move is printed to the journal.
- **Grid adds are purely price-driven.** Add #k opens the moment price is
  `k × GridStep` beyond the FIRST trade's entry — never waits for a rejection.
  By default adds are **no longer blocked** by the session window or news
  blackout (set `InpGridRespectFilters=true` to restore that gating). New-cycle
  entries are still session/news gated as before.
- **Dashboard** (left side of the chart): PKT clock, session OPEN/CLOSED, news
  status + next upcoming event, trend direction on the chosen TF, pivot method,
  spread, open positions with base entry/SL/TP, trailing state (armed at / ACTIVE
  with locked USD), next grid add price, floating P/L, balance/equity. Hidden
  automatically in non-visual tester runs.

### Testing notes (important)

- Backtest with **"Every tick based on real ticks"** (or at least "Every tick").
  In *Open prices only* mode the EA only runs once per bar, so trailing and grid
  adds will barely fire — this alone can look like "trailing is broken".
- If grid adds seem missing, check the dashboard's **Session** row: if it shows
  CLOSED during your local afternoon, `InpBrokerGMTOffset` is wrong for your
  broker, and (with `InpGridRespectFilters=true`) that gate silently blocks adds.
- Turn on `InpDebugLogs` and watch the journal: you'll see `TRAIL ...` and
  `GRID: adding ...` lines for every decision.

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
