# Sniper Entry — 1-Minute Scalping / 2-Pip Stop Loss

**Strategy reverse-engineered frame-by-frame from the reference video**
`Sniper_Entry__1_Minute_Scalping___2_PIP_Stop_Loss.mp4`
(854×424, 30 fps, 130 s, no voice-over — the method is taught purely through
on-screen chart annotations and a live MT5 order). Instrument shown: **XAUUSD
(Gold)**, 14 January.

This document is the specification the MT5 indicator
(`MQL5/Indicators/SniperEntry_FalseBreakout.mq5`) is built from.

---

## 1. What the video shows (timeline)

| Time (s) | On screen | Meaning |
|---|---|---|
| 0–18 | Title cards: **"MINIMAL RISK"**, **"XAU / USD — JANUARY 14"** | Branding / setup |
| 18–30 | 15-minute XAUUSD chart, a horizontal line drawn under the recent lows | The **support** level is marked |
| 25–36 | Candles labelled **A → B → C → D** | The core structure (see §2) |
| 37–48 | Text: **"ANTICIPATING FALSE BREAKOUT"**, price pokes *below* support | The thesis: the break of support will be *fake* |
| 49–60 | Chart switches to **1-MINUTE**; MT5 **Order** window opens | Drop to the execution timeframe |
| 52–60 | Order = **Pending Order → Buy Stop**, XAUUSD, Vol 1.00, market ≈ 1819.99 / 1820.15 | Entry is armed *above* price, to trigger on the reclaim |
| 61–72 | Text: **"LOOKING FOR BUY SIGNAL"**, dashed entry line | Waiting for price to reclaim the level |
| 73–96 | 1-min: price sweeps the low, then a green candle reclaims; two tight dashed lines (entry + stop) | Entry triggers; stop is placed ~2 pips away |
| 90–98 | MT5 **Trade** tab shows the live position (see §3) | The executed trade |
| 97–130 | Recap on 15-min: descending trendline from A→C broken, big move up; **green reward box vs. thin red risk box** | Result: minimal risk, large reward |

---

## 2. The A-B-C-D structure (the heart of the method)

```
            A  (swing HIGH)
           /\
          /  \        C  (LOWER high – price can't get back to A)
         /    \      /\
        /      \    /  \
 ....../........\../....\.................  <-- SUPPORT  (drawn at B's low)
      /          \/      \
     /           B        \
                           \   <-- price breaks support ...
                            \
                             D  (LOWER low = the FALSE BREAKOUT / liquidity sweep)
                            /
                           /    <-- ... then RECLAIMS support  => BUY ("sniper entry")
```

- **A** — a swing **high** (local top of the prior up-move).
- **B** — the pullback **low** after A. **The horizontal SUPPORT line is drawn here.**
- **C** — the next swing **high**, but **lower than A** (a *lower high* → sellers in control, down-trend into support). A descending trendline can be drawn from **A to C**.
- **D** — price breaks **below** the support and makes a **lower low**. This is the
  **false breakout** — a stop-run / liquidity grab below the obvious support where
  breakout-sellers and long stops sit.
- **Reclaim** — price snaps **back above** the support. That failure of the breakdown
  is the trigger: the move was fake, so we go **long**.

The **SELL** version is the exact mirror: A = low, B = high (resistance),
C = higher low, D = false breakout **above** resistance, then a reclaim back below → short.

---

## 3. Execution (read directly from the MT5 windows in the video)

**Order ticket (≈ 00:55):**
- Symbol **XAUUSD, Gold vs US Dollar**, Volume **1.00**
- Type **Pending Order → Buy Stop** (triggers only when price rises into it = confirmation of the reclaim)
- Market at that moment: Bid **1819.99** / Ask **1820.15**, active tab **XAUUSD, M1**

**Executed position (Trade tab, ≈ 01:32, order #87189629):**

| Field | Value |
|---|---|
| Time | 2022.01.14 **02:37:13** |
| Type / Size | **buy** / 1.00 |
| Symbol | xauusd |
| **Entry (Price)** | **1819.83** |
| **Stop Loss (S/L)** | **1819.63** |
| Take Profit (T/P) | **0.00** (none — ride the reversal) |
| Current price (rising) | 1820.32 → 1820.56 → 1821.65 |

**The 2-pip stop, verified:** `Entry 1819.83 − Stop 1819.63 = 0.20`.
On gold 1 pip = `0.10` (10 points on a 2-decimal quote), so **0.20 = exactly 2 pips**.
The stop sits **just below the sweep low (D)** — if the reversal is real, price will
not revisit that low, which is *why* such a tight stop is viable ("MINIMAL RISK").

---

## 4. The rules (distilled)

**Context / bias (shown on 15M in the video; the indicator detects it on the
attached chart):**
1. Prior up-move makes swing high **A**.
2. Pullback low **B** → draw the **support** line at B.
3. Rally fails below A at **C** (**lower high**) → bearish pressure into support.

**Trigger / entry (executed on 1M):**
4. Price **breaks below support** and prints a lower low **D** — the **false breakout**.
5. Price **reclaims** the support (closes back above it) → **BUY** on the reclaim
   (the video uses a **Buy Stop** parked just above the level, so entry only fires on
   confirmation).

**Risk / target:**
6. **Stop loss = ~2 pips**, just beneath the sweep low D → *minimal risk*.
7. **No fixed take profit** — manage the reversal for a large reward-to-risk ratio
   (the video illustrates a large green reward box against the thin red 2-pip risk box).

**Why it works (intuition):** the obvious support attracts breakout sellers and
resting buy-stops/long-stop-losses. Price dips just far enough to trigger them (the
"false breakout" / liquidity sweep), then reverses. Entering on the *reclaim* with the
stop *under the sweep* gives a tiny, well-defined risk and an asymmetric payoff.

---

## 5. Notes & honest caveats

- The video is a single worked **example**, not a statistical edge claim. It does not
  state exact pivot-strength numbers or a profit target, so the indicator exposes those
  as **inputs** (swing strength, reclaim window, stop pips, reward ratio) with defaults
  chosen to match what is shown (2-pip stop; A-B-C-D context required).
- "2 pips = 0.20" is correct for a **2-decimal XAUUSD** feed. On a 3-decimal gold feed
  (e.g. 1819.830), 1 pip is still 0.10, which the indicator's pip calculation handles.
  On other instruments, set `InpStopPips` to taste.
- An **indicator cannot place orders**. This one *detects, draws and alerts*; execution
  (manual Buy Stop, or an EA) is separate. See the README for how to wire it to an EA
  via `iCustom`.
