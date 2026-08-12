# First Candle Rule — MT5 indicator (`FirstCandleRule.mq5`)

Rebuilt from the **TradersNotes / Jason** video ("the first candle rule"). It is a
**signal indicator** (arrows + alerts, it does not place trades).

## The rule it implements
1. At the session open, take the **first 5-minute candle** (e.g. 9:30–9:35 EST) and
   mark its **HIGH** and **LOW** — the day's key levels ("First Candle Range").
2. On the 1-minute chart, wait for price to **break a level with a gap between
   candle wicks** (a displacement / fair-value-gap = "real force").
3. Wait for a **retest** of that level (wick back to it, close held beyond it).
4. A **candle engulfing** in the break direction = the entry.
5. Target a **fixed risk-to-reward**.
   - The video uses **3:1**. This indicator **defaults to 1:2** (`InpRR = 2.0`) and
     is **manually adjustable** — set `InpRR` to `3.0` to match the video.

Break **above the high → BUY**; break **below the low → SELL**.

## Install (MT5)
1. **File → Open Data Folder → MQL5 → Indicators**, copy `FirstCandleRule.mq5` there.
2. In MetaEditor press **Compile**, then drag **First Candle Rule** onto the **M1**
   chart of your instrument.
3. For mobile push: **Tools → Options → Notifications** (set MetaQuotes ID). Email
   on the **Email** tab.

## ⏰ Important — set the session time
MT5 uses **broker server time**, not EST. Set **`InpSessionHour` / `InpSessionMin`**
to whatever **9:30 EST is on your broker's clock** (check the clock in Market Watch;
many brokers run GMT+2/+3, so 9:30 EST is often ~15:30/16:30 server time).

## Key inputs
- `InpSessionHour` / `InpSessionMin` — session open (server time).
- `InpFirstCandleMin` (5) — first-candle length. `InpEntryWindowMin` (90) — how long
  after the open to hunt entries.
- `InpRR` (**2.0 = 1:2**, adjustable) — risk-to-reward for the target.
- `InpRequireGap` (true) — require the wick-gap displacement on the break.
- `InpAllowLong` / `InpAllowShort`, `InpMaxPerDay` (1 per direction).
- Alerts: `InpAlertPopup`, `InpAlertSound` (+ sound files), `InpPush`, `InpEmail`.

## Notes / honesty
- Signals fire on **closed bars** (no repaint).
- The "gap + retest + engulfing" mechanics are a faithful, tunable reconstruction of
  the video's visuals and captions. Because "gap between wicks" and "retest" are
  described qualitatively, the exact detection is parameterised — if it triggers too
  often/rarely, adjust `InpRequireGap`, `InpEntryWindowMin`, and the session time.
