# Which file to run — one-page guide

All EAs are for **XAUUSD / US30 (gold-like, hedging account)**. Each has a unique
magic number, so any of them can run together without touching each other's trades.

## Pick by what you want

| I want to… | Run this |
|------------|----------|
| **Trade for real with every improvement, and I accept ~0.02-lot risk** | `TrendTrailingEA_PRO` |
| **Same, but keep risk at 0.01 / no partial-TP** | `TrendTrailingEA_PRO_LITE` |
| **A clean, simple base to understand or tune from** | `TrendTrailingEA` |
| **Test if a clean H1→M5 hierarchy alone is enough** | `TrendTrailingEA_1_H1` |
| **Keep M5 responsiveness but tame the whipsaw** | `TrendTrailingEA_2_M5robust` |
| **Belt-and-suspenders: H1 trend + robustness filters** | `TrendTrailingEA_3_H1robust` |
| **Pure pivot-rejection scalper (no trend/grid), TP1/SL6** | `PivotRejectionEA` |

## The files

| File | What it is | Magic | Lot | Notes |
|------|-----------|:-----:|:---:|-------|
| `TrendTrailingEA` | Core: pivot-rejection entry + trend + grid + trailing + session + news + pivots + auto-GMT | 990033 | 0.01 | The base everything else is built from |
| `TrendTrailingEA_1_H1` | Core, H1 trend / M5 signal, no robustness | 990131 | 0.01 | Cleanest hierarchy |
| `TrendTrailingEA_2_M5robust` | Core + robustness, M5 trend / M1 signal | 990132 | 0.01 | Most frequent, filters tame M5 noise |
| `TrendTrailingEA_3_H1robust` | Core + robustness, H1 trend / M5 signal | 990133 | 0.01 | Fewest, cleanest trades |
| `TrendTrailingEA_PRO` | Everything: robustness + spread filter + ATR targets + partial-TP + risk caps + wick/RSI filters + stall exit + D1 confluence | 990077 | 0.02 | Partial-TP needs 0.02 |
| `TrendTrailingEA_PRO_LITE` | PRO with 0.01 lot, partial-TP off | 990078 | 0.01 | Lower risk; A/B vs PRO |
| `PivotRejectionEA` | Standalone rejection scalper, TP1/SL6, no trend/grid | 990044 | 0.01 | Different strategy |

## Install (any file)

1. Copy the `.mq5` into `MQL5/Experts/` (MT5 → File → Open Data Folder).
2. MetaEditor → open → **Compile (F7)**.
3. Attach to a gold chart, enable **Algo Trading**, set inputs.
4. **AutoGMT stays ON for live** (session fixes itself). In the Strategy Tester,
   set `InpBrokerGMTOffset` to your broker's server GMT instead.

## How to test (do this before anything live)

- Strategy Tester → model **"Every tick based on real ticks"**.
- Turn on `InpDebugLogs` and fill `InpManualNewsPKT` (the live calendar is blank in the tester).
- Run the **same period** across the versions you're comparing.
- Judge on **profit factor + max drawdown**, not trade count.
- Only after a version looks good on backtest → demo → tiny live.

## Safety reminders (all versions)

- **Grid averages into losers.** `InpMaxGridTrades` and — in PRO/LITE — the
  **basket stop + daily loss limit** are what keep it survivable. Keep them on.
- **Match the caps to your lot.** LITE trades half of PRO, so the same USD caps
  are twice as loose; halve them for equal protection.
- Gold + US30 are only loosely correlated — but still watch **total** exposure.
