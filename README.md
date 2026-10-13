# Sniper Entry — False-Breakout Reversal Indicator for MT5

An **MetaTrader 5 (MQL5) indicator** that detects, draws and alerts the
**"Sniper Entry — 1-Minute Scalping / 2-Pip Stop Loss"** strategy, reverse-engineered
frame-by-frame from the reference video (XAUUSD / Gold).

> Full strategy breakdown: **[`docs/SniperEntry_Strategy.md`](docs/SniperEntry_Strategy.md)**

- **File:** [`MQL5/Indicators/SniperEntry_FalseBreakout.mq5`](MQL5/Indicators/SniperEntry_FalseBreakout.mq5)
- **What it is:** a false-breakout / liquidity-sweep reversal detector with the
  **A-B-C-D** structure, a **2-pip stop** model and a reward-to-risk projection.
- **What it is not:** it does **not** send orders (that is an Expert Advisor's job).
  It marks the setup, draws Entry / Stop / Target and the reward/risk boxes, and alerts you.

### Two builds in this repo

| File | Design |
|---|---|
| `SniperEntry_FalseBreakout.mq5` | **Single-timeframe.** Detects the A-B-C-D structure, sweep and reclaim on the chart it's attached to. Both long & short. |
| `SniperEntry_Combo.mq5` | **Multi-timeframe.** Support/resistance is a confirmed pivot on a **higher timeframe (M15 by default)** — the way the video marks the level on M15 then executes on M1 — plus a pending-stop guide, tick-normalised levels, setup expiry/cooldown, a same-candle ambiguity note and an on-chart panel. Attach to **M1**, context **M15**. Self-contained (no external header). |

Both are non-repainting (closed-bar signals) and place no orders.

---

## The setup in one picture

```
        A                                     ← swing high
       / \          C                         ← lower high (sellers in control)
      /   \        / \        reclaim → BUY ↑
 ----/-----\------/---\------●────────────────  support (drawn at B)
    /       \    /     \    / \
   /         B  /       \  /   \   Entry ≈ reclaim close
               (support) \/     \  Stop  = 2 pips below  (just under D)  → MINIMAL RISK
                          D         Target = ride the reversal (large R:R)
                 (false breakout / liquidity sweep below support)
```

Buy: price sweeps **below** support (fake breakdown), then **reclaims** it → long,
stop ~2 pips under the sweep low. **Sell** is the mirror (sweep above resistance).

---

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `MQL5/Indicators/SniperEntry_FalseBreakout.mq5` into the data folder's
   `MQL5\Indicators\` directory.
3. In MetaTrader, open **Navigator** (Ctrl+N) → right-click **Indicators → Refresh**.
4. Open **MetaEditor** (F4), select the file, press **Compile** (F7). It should compile
   with 0 errors.
5. Drag **SniperEntry_FalseBreakout** from the Navigator onto a chart.

Designed to be used the way the video does it: identify the structure on **M15**, then
run/execute on **M1**. The indicator works on any symbol and timeframe — attach it to
**M1 XAUUSD** to mirror the video exactly.

---

## How the indicator maps to the strategy

| Strategy step (video) | In the indicator |
|---|---|
| Swing high **A**, pullback low **B** (support), lower high **C** | Pivot detection (`InpSwingLength`); anchored on **C** so the sweep low is never mistaken for support |
| **D** = false breakout below support | Lowest low after C must pierce below B's low |
| Reclaim → buy signal | First **bullish close back above** support within `InpReclaimBars` → **one** arrow |
| Buy Stop entry | Entry marked at the reclaim close (place a Buy Stop there in practice) |
| **2-pip** stop under the sweep | `InpStopPips = 2.0` (or `InpUseStructureStop` = just beyond D) |
| Ride for large R:R | Target drawn at `InpRewardRatio` (default **1:10**); green reward / red risk boxes |
| "Anticipating false breakout" | The whole detection *is* the false-breakout + reclaim |

Signals are evaluated on **closed bars only** — the indicator **does not repaint**
(an arrow, once printed on a closed bar, stays put).

---

## Inputs

**Structure detection (A-B-C-D)**
| Input | Default | Meaning |
|---|---|---|
| `InpSwingLength` | 5 | Pivot strength — bars required on each side of a swing high/low. Lower = more (smaller) structures. |
| `InpLookbackPivots` | 150 | How many bars back to search for the A-B-C-D. |
| `InpRequireABCD` | true | Require the full lower-high (buy) / higher-low (sell) context. Set false for a looser pure sweep-&-reclaim. |
| `InpReclaimBars` | 3 | Max bars from the sweep extreme (D) to the reclaim close. |
| `InpRequireSweepClose` | false | If true, the sweep bar must also *close* beyond the level (stricter than a wick-only sweep). |

**Risk model (from the video)**
| Input | Default | Meaning |
|---|---|---|
| `InpDirection` | Buy & Sell | Allowed signal direction. |
| `InpStopPips` | 2.0 | Stop distance in pips. **2.0 = the video's 2-pip stop** (0.20 on gold). |
| `InpUseStructureStop` | false | Put the stop just beyond the sweep extreme D instead of a fixed pip distance. |
| `InpStopBufferPips` | 1.0 | Extra buffer beyond D when `InpUseStructureStop` is on. |
| `InpRewardRatio` | 10.0 | Take-profit target as a reward:risk multiple (1:10 by default). |

**Visuals**
| Input | Default | Meaning |
|---|---|---|
| `InpShowABCD` | true | Draw the A / B / C / D labels. |
| `InpShowLevels` | true | Draw Entry / SL / TP lines + price tags of the latest setup. |
| `InpShowSRLine` | true | Draw the swept support/resistance level. |
| `InpShowRRBoxes` | true | Draw the green reward box / red risk box (as in the video). |
| `InpProjectBars` | 16 | How far to project the lines/boxes to the right. |
| `Inp*Color` | — | Colours for arrows, S/R, entry, stop, TP, boxes and labels. |

**Alerts**
| Input | Default | Meaning |
|---|---|---|
| `InpAlertPopup` | true | Terminal pop-up on a new signal. |
| `InpAlertPush` | false | Push notification to the MT5 mobile app. |
| `InpAlertEmail` | false | E-mail (configure in Tools → Options → Email). |
| `InpAlertSound` / `InpSoundFile` | false / `alert.wav` | Play a sound. |

Alerts fire only on the **freshly closed** signal bar, once per signal, and never during
the initial history load.

---

## Buffers (for EAs / `iCustom`)

| # | Buffer | Value |
|---|---|---|
| 0 | Sniper Buy | price (candle low) on a buy-signal bar, else empty |
| 1 | Sniper Sell | price (candle high) on a sell-signal bar, else empty |

An EA can read the signal and manage the actual Buy Stop / Sell Stop:

```mql5
int h = iCustom(_Symbol, PERIOD_CURRENT, "SniperEntry_FalseBreakout");
double buy[];  CopyBuffer(h, 0, 1, 1, buy);    // buffer 0, last closed bar
if(buy[0] != EMPTY_VALUE && buy[0] != 0.0)
   { /* arm a Buy Stop just above the reclaim, SL = InpStopPips below */ }
```

---

## Validation

The detection algorithm was ported to Python and checked against synthetic data: it
fires exactly **one** buy on an ideal A-B-C-D false-breakout (correct A/B/C/D pivots,
entry, 2-pip stop and 1:10 target), fires the **sell** mirror, and produces **zero**
signals on flat noise, on a genuine breakdown with no reclaim, and when there is no
sweep below support. See `tools/validate_logic.py`.

## Backtest & win rate

Full results and method: **[`docs/Backtest_Report.md`](docs/Backtest_Report.md)**.

Tested on real gold (GC=F) — 1m (~28d), 5m/15m (~60d), 1h (~2y), non-repainting
signals, first-touch exits (stop-first on ambiguous bars), spread-aware.

- **Win rate depends on your target.** Structure stop (just below the sweep): **~45–49%
  at 1:1**, ~30–35% at 1:2, ~24–28% at 1:3, ~18–21% at 1:5, ~13–18% at 1:10.
- The **literal fixed 2-pip stop is not viable at today's gold volatility** (~$4,400,
  median 1m range ~16 pips) — win rate ~2–19%, negative expectancy.
- Overall the strategy is **roughly break-even** on this data — not a guaranteed edge.
  Size the stop to the sweep, not to a fixed 2 pips, and test in MT5's Strategy Tester
  on your own broker's M1 XAUUSD feed.

![Win rate vs target](docs/sniper_winrate.png)

Reproduce: `tools/fetch_data.py` → `tools/backtest.py` → `tools/make_chart.py`.

---

## Disclaimer

For education and research. A single video example is not a guarantee of profitability.
Test on a demo account and in the Strategy Tester before risking real capital. Trading
leveraged instruments such as gold carries substantial risk.
