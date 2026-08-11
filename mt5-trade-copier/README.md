# Free MT5 Trade Copier (Demo → Real)

Copy every trade from your **demo** account (where your bought EA/app runs) to your
**real** account automatically, with a different lot size (default **×10**, so
`0.01` on demo becomes `0.10` on real).

- ✅ **100% free** — no monthly copier subscription, no third‑party service.
- ✅ No DLLs, no internet bridge. Both terminals just share one local file.
- ✅ Works when both MT5 terminals run on the **same PC or VPS**.

> This is not financial advice. Test on two demo accounts first. Copying real
> money multiplies both profits **and** losses by your multiplier.

---

## How it works

```
  DEMO MT5 (your bought EA trades here)          REAL MT5 (mirrors the trades)
  ┌───────────────────────────┐                 ┌───────────────────────────┐
  │  TradeCopier_Master.mq5    │                 │  TradeCopier_Slave.mq5     │
  │  writes open positions ──► │  shared file    │ ◄── reads positions        │
  │                            │  in Common\Files│     opens/closes copies    │
  └───────────────────────────┘   (same PC)      │     lot × 10               │
                                                 └───────────────────────────┘
```

Both MT5 installations on one machine share a single folder:
`C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\Common\Files`.
The Master writes `trade_copier_signals.csv` there ~2–3×/second; the Slave reads
it and keeps the real account in sync.

Because it uses the shared **Common** folder, this works even if the demo and
real accounts are two *separate* MT5 installs — as long as they're on the same
Windows user on the same machine/VPS.

---

## Setup (10 minutes)

### 1. Compile both EAs
For **each** MT5 terminal (demo and real):
1. Open MT5 → **File → Open Data Folder** → `MQL5\Experts`.
2. Copy `TradeCopier_Master.mq5` and `TradeCopier_Slave.mq5` into that folder.
3. In MT5 open **MetaEditor** (F4) → select each file → **Compile** (F7).
   You should get `0 errors`.
4. Back in MT5, right‑click **Navigator → Expert Advisors → Refresh**.

### 2. Turn on algo trading (both terminals)
Toolbar **Algo Trading** button must be green, and in
**Tools → Options → Expert Advisors** tick **Allow Algorithmic Trading**.

### 3. Attach the Master (DEMO terminal)
1. Drag **`TradeCopier_Master`** onto any one chart (any symbol/timeframe).
2. Leave defaults. Click **OK**.
3. In the **Experts** tab you should see: `[MASTER] Started. Account #...`.

### 4. Attach the Slave (REAL terminal)
1. Drag **`TradeCopier_Slave`** onto any one chart.
2. Set inputs (see table below). The important one:
   - `InpLotMultiplier = 10.0` → 0.01 becomes 0.10. (Change to taste.)
   - If your real broker's symbols have a suffix like `EURUSD.a`, set
     `InpSymbolSuffix = ".a"`. A prefix like `mEURUSD` → `InpSymbolPrefix = "m"`.
3. Click **OK**. Experts tab shows: `[SLAVE] Started. ... Multiplier=10.00`.

### 5. Test
Open a manual 0.01 trade on the demo → within ~1 second a 0.10 trade appears on
the real account. Close it on demo → the copy closes on real. 🎉

Run **only one Master** (on demo) and **only one Slave** (on real). Don't attach
both EAs to the same terminal.

---

## Choosing the copy lot — you control it

There are two modes, set by `InpLotMode` on the Slave:

- **`LOT_MANUAL_FIXED` (default) — you pick the exact lot.** Every copied trade uses
  a lot *you* set, no matter what the demo does. A 0.01 demo trade becomes whatever
  you choose (0.10, 0.20, …). You can change it **live from the chart**: the Slave
  draws a small panel with `-0.10 / -0.01 / [ 0.10 ] / +0.01 / +0.10` buttons.
  Click to raise/lower it any time — the new value applies to the **next** copies
  and is **saved** across restarts. Set the starting value with `InpManualLot`.
- **`LOT_MULTIPLIER` — copy lot = demo lot × `InpMultiplier`.** e.g. ×10 makes 0.01 → 0.10,
  and it tracks the demo (0.02 demo → 0.20). Use this if you want the real account to
  scale proportionally with the demo instead of a fixed size.

> Changing the lot affects **new** copies only — trades already open keep their lot.

### Slave inputs

| Input | Default | Meaning |
|---|---|---|
| `InpSignalFile` | `trade_copier_signals.csv` | Must match the Master exactly. |
| `InpLotMode` | `LOT_MANUAL_FIXED` | `LOT_MANUAL_FIXED` = you pick the lot (live buttons). `LOT_MULTIPLIER` = demo lot × multiplier. |
| `InpManualLot` | `0.10` | MANUAL mode: starting lot (then adjust live with the buttons). |
| `InpLotStepSmall` | `0.01` | Step for the small +/- buttons. |
| `InpLotStepBig` | `0.10` | Step for the big +/- buttons. |
| `InpMultiplier` | `10.0` | MULTIPLIER mode only: 0.01 × 10 = 0.10. |
| `InpSymbolSuffix` | `""` | Broker suffix, e.g. `.a`, `.pro`, `.m`. |
| `InpSymbolPrefix` | `""` | Broker prefix, e.g. `m` for `mEURUSD`. |
| `InpCopySLTP` | `true` | Copy stop‑loss / take‑profit. |
| `InpEnableTrading` | `true` | Set `false` for a dry run (reads, logs, but places no trades). |
| `InpMaxStaleSec` | `30` | If the demo terminal/EA stops updating the file, the Slave stops **opening** new trades (it still closes copies whose master is gone). |
| `InpShowPanel` | `true` | Show the on-chart lot control panel (MANUAL mode). |

> ⚠️ Bigger lots = bigger risk. A 0.10 copy of a 0.01 demo trade risks ~10× the money.
> Pick a lot sized for the **real** account's balance.

---

## Important notes & limits

- **Use a HEDGING real account.** Each trade maps 1:1 by the master's ticket
  number. On a *netting* account MT5 merges same‑symbol trades into one net
  position and the mapping breaks. Most forex MT5 accounts are hedging; check
  **Account type** with your broker, or open the real account in hedging mode.
- **Same machine required** for the free file method. If the two accounts are on
  different computers, either (a) run both terminals on one cheap/free VPS, or
  (b) point the shared file at a synced folder (Dropbox/OneDrive/Google Drive) —
  reliable but adds a few seconds of latency. Ask if you want that variant.
- **Latency** is ~0.3–1s locally. Fine for most strategies; not for pure
  scalping/HFT.
- **Symbols must exist on the real broker.** If the demo trades an instrument the
  real broker doesn't offer, that trade is skipped (logged in Experts tab).
- **Prices differ slightly** between brokers, so SL/TP copy as price levels from
  the demo. If spreads/pricing differ a lot, consider `InpCopySLTP=false` and
  manage exits yourself, or convert to pip‑distance (ask if you want that).
- **Prop‑firm / broker terms:** these are your own two accounts, so local copying
  is normally fine — but if the *real* account is a funded/prop account, check
  their rules on copiers/EAs before going live.

---

## Do you need anything paid?

**No.** MetaTrader 5, MetaEditor (the compiler), and running EAs are all free.
The only thing you might *optionally* pay for is a **VPS** (~$5–15/mo) if you want
the copier to keep running 24/7 while your PC is off. Even that is optional —
some brokers include a free MT5 VPS, and you can just leave your own PC on.

## Files
- `TradeCopier_Master.mq5` — attach to the **demo** terminal.
- `TradeCopier_Slave.mq5` — attach to the **real** terminal.
