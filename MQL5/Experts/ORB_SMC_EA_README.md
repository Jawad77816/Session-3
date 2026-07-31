# ORB + SMC Expert Advisor (MT5)

An MT5 Expert Advisor that trades the **Opening Range Breakout (ORB)** combined with
**Smart Money Concepts** — Fair Value Gaps (FVG), retest entries, false-breakout
reversals, and a previous-day High/Low liquidity filter — exactly as described in the
strategy video.

> **Honesty first:** No EA is "guaranteed profitable," and anyone who promises that is
> selling something. This is a faithful, fully configurable implementation of the
> strategy. Whether it makes money depends on the instrument, the session, your inputs,
> your broker's spread/commissions, and current market conditions. **Backtest and
> optimize before risking real money.** Treat the default inputs as a starting point,
> not a finished system.

---

## Which chart should I apply it on?

**Recommended:** attach it to a **US index or Gold** chart on the **M5 timeframe**.

| Setting | Recommended value | Why |
|---|---|---|
| **Symbol** | `US30` / `NAS100` (US100) / `US500`, or `XAUUSD` (Gold) | The strategy is built around the 9:30 New York open and previous-day-high/low liquidity. Indices and gold respond to it best. It also works on FX majors and BTCUSD, just less "cleanly." |
| **Chart timeframe** | **M5** | The EA reads the ORB and FVG timeframes internally (M15 / M5), so the chart TF mostly affects how often `OnTick` new-bar logic runs and how the ORB lines draw. M5 aligns with the signal timeframe. M1 is fine too. |
| **ORB timeframe (input)** | **M15** | The 15-minute opening range — the balance of risk/reliability the video recommends. |
| **Signal timeframe (input)** | **M5** | Where breakout closes and FVGs are detected. |

You can run one instance per symbol. Use a **different Magic number** per chart if you run several.

---

## ⚠️ The #1 thing to get right: session time

The whole strategy hinges on the **9:30 AM New York (NYSE) open**. MT5 brokers run on
their **own server time**, which is usually *not* New York time. If this is wrong, the
EA builds the range off the wrong candle and nothing else matters.

Two ways to set it (input **`InpTimeMode`**):

### Option A — `TIME_SERVER_DIRECT` (default, most reliable)
You tell the EA the ORB start **in your broker's server time**.
- Default is **16:30**, which equals 9:30 New York for the common **GMT+3 (summer) brokers**.
- To find your value: open **Market Watch → right-click → Symbols**, or just look at the
  time on the top-right of a chart candle vs. the real UTC/NY time, and compute the offset.
- Quick reference (New York 9:30 → server time):
  - Broker GMT+3 → **16:30**
  - Broker GMT+2 → **15:30**
  - Broker GMT+0 (UTC) → **13:30** (summer / EDT) or **14:30** (winter / EST)

### Option B — `TIME_NY_OFFSET` (auto)
You set **`InpNYtoServerHours`** = how many hours your broker server is *ahead of* New York.
Most GMT+2/+3 brokers that follow US daylight saving are **+7** year-round → the EA
computes 9:30 + 7:00 = **16:30** automatically.

> **Verify once:** After attaching, check the "ORB ready" line in the **Experts** log and
> confirm the ORB High/Low lines are drawn on the correct 9:30-NY candle for your broker.

---

## How the strategy is implemented

1. **Build the range.** After the session opens, the EA waits for the first `InpORBTimeframe`
   (M15) candle to close and records its **High** and **Low** (wick-to-wick) as the ORB.
2. **Detect a breakout.** On each closed `InpSignalTimeframe` (M5) bar, it checks for a
   **close beyond** the ORB high (bullish) or low (bearish) — a wick alone is not a breakout.
3. **Choose an entry** (priority order, whichever is enabled):
   - **Retest + FVG** (`InpUseRetestFVG`, default ON): finds a Fair Value Gap created during
     the breakout impulse that overlaps the ORB level, and places a **limit order** at the
     retest. Stop just beyond the FVG (tight, per the video). *Highest-probability setup.*
   - **Plain retest** (`InpUsePlainRetest`): limit order back at the ORB level, no FVG needed.
   - **Immediate** (`InpUseImmediate`): market order the moment the breakout candle closes.
4. **False-breakout reversal** (`InpUseFalseBreak`, default ON): if a candle **sweeps** beyond
   the ORB level but **closes back inside**, and there's an **opposing FVG** at the level, the
   EA fades it (short a failed high-break, long a failed low-break).
5. **Previous-day liquidity filter** (`InpUsePDHLFilter`, default ON): the video's key mistake
   — don't trade straight into the previous day's High/Low, because price tends to sweep it and
   reverse. The EA skips entries that don't have at least `InpMinRoomPoints` of room to that level.
6. **Risk & targets:** stop beyond the FVG/range, take-profit at `InpRewardR` × risk (default 1.5R),
   position size from `% of balance` / fixed lot / fixed cash. Max `InpMaxTradesPerDay` per day,
   one setup per direction per day, pending orders auto-expire at the end of the trade window.

---

## Key inputs (full list is in the EA, grouped)

| Group | Input | Default | Notes |
|---|---|---|---|
| Session | `InpTimeMode` | `TIME_SERVER_DIRECT` | See "session time" above |
| Session | `InpServerStartHour/Min` | `16:30` | ORB start in server time |
| Session | `InpNYtoServerHours` | `7.0` | Only used in `TIME_NY_OFFSET` mode |
| Session | `InpORBTimeframe` | `M15` | The opening-range candle |
| Session | `InpTradeWindowMin` | `240` | Stop taking/holding new entries after this many minutes |
| Signal | `InpSignalTimeframe` | `M5` | Breakout + FVG detection |
| Signal | `InpMinFVGPoints` | `20` | Minimum FVG size to trust |
| Setups | `InpUseRetestFVG` | `true` | Primary setup |
| Setups | `InpUseFalseBreak` | `true` | Fade failed breakouts |
| Setups | `InpUsePlainRetest` / `InpUseImmediate` | `false` | More trades, lower selectivity |
| Filter | `InpUsePDHLFilter` / `InpMinRoomPoints` | `true` / `150` | Prev-day liquidity guard |
| Risk | `InpRiskMode` | `RISK_PERCENT` | `% / fixed lot / fixed cash` |
| Risk | `InpRiskPercent` | `1.0` | % of balance risked |
| Risk | `InpRewardR` | `1.5` | TP as multiple of risk |
| Risk | `InpSLBufferPoints` | `30` | Buffer beyond structure |
| Risk | `InpMaxTradesPerDay` | `2` | Daily cap |
| Exec | `InpMagic` | `990045` | Unique per chart if running many |
| Exec | `InpMaxSpreadPts` | `50` | Skip entries in wide spread |

---

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `ORB_SMC_EA.mq5` into **`MQL5/Experts/`**.
3. In **MetaEditor**, open it and press **Compile** (F7). It should compile with 0 errors.
4. Back in MT5, drag **ORB_SMC_EA** from the Navigator onto an **M5 chart** of your symbol.
5. Enable **Algo Trading** (the toolbar button), allow it in the EA dialog, and set your inputs
   — **especially the session time for your broker**.

## Backtest / optimize (do this first)

1. **View → Strategy Tester** (Ctrl+R).
2. Select the EA, your symbol, timeframe **M5**, model **"Every tick based on real ticks"**
   (retest/FVG logic needs intrabar detail — "Open prices only" is not accurate enough).
3. Set the **session-time input to match your broker** before running.
4. Optimize the sensitive inputs per instrument: `InpMinFVGPoints`, `InpFVGOverlapPoints`,
   `InpSLBufferPoints`, `InpRewardR`, `InpTradeWindowMin`, and the setup toggles.
5. Judge it on **out-of-sample** data and realistic **spread + commission**, not just a pretty
   in-sample curve.

---

## Limitations & honest caveats

- Results depend heavily on getting the **session time** right for your broker.
- The FVG / retest logic is a rules-based approximation of a discretionary concept; it won't
  match every setup a human would take by eye.
- Backtest fidelity depends on your broker's tick data quality. Forward-test on **demo** first.
- Expect losing streaks. Position sizing (`InpRiskPercent`) is what keeps you in the game.
