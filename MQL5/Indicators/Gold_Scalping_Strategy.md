# Gold (XAUUSD) Scalping Strategy — using the MD5 MTF Liquidity Sweep + FVG indicator

A practical, rules-based way to scalp gold with this indicator. The core idea: **trade with the
higher-timeframe liquidity story, and enter on a lower-timeframe sweep that snaps back into a
higher-timeframe level or Fair Value Gap.** Everything waits for candle **close** (non-repaint),
so you are reacting to confirmed events, not guessing.

> Gold moves fast, spreads widen around news, and it loves to run stops. This strategy is built
> around that behaviour. It is education, not financial advice — demo it first.

---

## 1. Why this works on gold

Gold is a highly liquid, headline-driven instrument that repeatedly spikes through obvious highs
and lows to trigger stops, then reverses. That "spike-and-reverse" is exactly a **liquidity
sweep**. The indicator confirms the sweep only at candle close and marks which timeframe it
happened on, so you can align a quick scalp with where the real pressure just showed up.

---

## 2. Setup & timeframes

**Chart to trade on:** M1 or M5 (execution). Attach the indicator there — it will also display the
M15, M30, H1, H4, D1 sweeps on the same chart.

**Roles:**
| Timeframe | Role | What you use it for |
|---|---|---|
| **D1 / H4** | Bias & key levels | Which side of the market to favour; the big swept levels that act as targets/reversal zones. |
| **H1 / M30** | Context | The intermediate liquidity the price is reaching for. |
| **M5 / M1** | Execution | The actual sweep you enter on, plus the Real FVG for entry refinement. |

**Suggested indicator settings for gold scalping:**
- `InpPivotLength = 7` (M1/M5) up to `10` — lower = more, faster swings.
- Keep all timeframe toggles **on** (that's the whole point here); turn `InpTF_M1` off if M1 is too noisy.
- `InpShowFVG = true`, `InpShowFakeFVG = false` (trade only Real FVGs for scalps).
- `InpDispATR = 1.2`, `InpMinGapATR = 0.10` (raise `InpDispATR` to 1.5 for stricter gaps).
- `InpAlertPopup = true` so you're pinged when a fresh sweep prints on any timeframe.

---

## 3. Best times to trade gold

* **London open** ≈ 07:00–10:00 London, and the **London–New York overlap** ≈ 13:00–16:00 London
  (08:00–11:00 New York). These carry the volume that makes sweeps meaningful.
* The **first 15–30 min after major news** (US CPI, NFP, FOMC, PPI) is where gold sweeps hardest —
  high reward but widened spreads and whipsaw. Scalp it only if you're experienced.
* **Avoid** the dead Asian-session chop for sweep-reversal scalps (lots of fake FVGs), and avoid
  the seconds around a red-folder news release (spread spikes).

---

## 4. The A+ setup (bias + sweep + confluence)

Enter only when these line up:

1. **Higher-timeframe draw / bias (D1/H4/H1).**
   Note the nearest **unswept** H4/H1 swing high and low — price is usually "drawn" toward one of
   them. Recent **D1/H4 BSL** marks above = expect bearish reaction there; **D1/H4 SSL** below =
   expect bullish reaction.

2. **A sweep into a higher-timeframe level.**
   Price runs into an H1/H4 level (or an H4/H1 Real FVG) and the indicator prints a sweep there.

3. **Lower-timeframe confirmation sweep (your trigger).**
   On M1/M5 you get a fresh **SSL sweep** (for longs) or **BSL sweep** (for shorts) *in the same
   direction as the higher-timeframe reaction*.

4. **Real FVG in your favour (optional but strong).**
   The reversal leg leaves a **Real FVG** (ideally `FVG+sweep`). That gap is your refined entry
   zone and your line in the sand.

**Long scalp** = higher-TF sell-side level + **M1/M5 SSL sweep** (wick below a low, close back up),
preferably leaving a bullish Real FVG.
**Short scalp** = higher-TF buy-side level + **M1/M5 BSL sweep** (wick above a high, close back
down), preferably leaving a bearish Real FVG.

---

## 5. Entry rules (precise, non-repaint)

The indicator's on-chart **BUY / SELL signal** is your trigger (BUY = reclaimed sell-side sweep,
SELL = reclaimed buy-side sweep). With `InpUseConfirm` on (default), a signal only prints **after a
follow-through candle breaks the sweep's extreme**, so it already waits for confirmation for you —
it fires one candle after the sweep. Only act on a signal that agrees with step 1–2 above (higher-TF
bias + swept into a higher-TF level) — a signal *against* a fresh higher-TF level is the trap side,
skip it. If you want the indicator itself to hide counter-trend signals, switch on
`InpUseTrendFilter` (trend-continuation mode).

Pick one (B is tighter):

* **Entry A — close confirmation:** Enter at the **open of the candle after** the M1/M5 sweep
  candle closes. Simple and robust.
* **Entry B — FVG retest:** After the sweep, wait for price to **pull back into the Real FVG** left
  by the reversal leg and enter on the first lower-timeframe rejection inside the gap. Better price,
  occasionally missed.

Never enter on a wick that hasn't closed — the indicator intentionally only confirms sweeps on
closed bars, and so should you.

---

## 6. Stop loss

* Place the stop **just beyond the sweep wick** (the extreme of the sweep candle) plus a buffer for
  gold's spread/noise: roughly **+1.5 to +2.0 × the spread**, or a few tenths of a dollar.
  - Long: stop below the low of the SSL sweep candle.
  - Short: stop above the high of the BSL sweep candle.
* If entering from an FVG retest, the stop can sit just past the **far edge of the Real FVG**.
* Typical gold M1/M5 scalp stop is often **$0.80–$2.50** depending on volatility — let the
  structure decide, not a fixed number.

The logic: if price trades back beyond the sweep extreme, the "grab and reverse" idea is wrong —
you want out.

---

## 7. Take profit / targets

Scalps, so bank quickly and manage with structure:

1. **TP1 (primary):** the **opposite liquidity** on your execution timeframe — the nearest M5/M15
   swing high (for longs) / low (for shorts), i.e. the next pool the move is likely to run.
2. **TP2:** the next higher-timeframe level (H1/H4) or the **fill of a higher-TF FVG**.
3. Aim for a **minimum 1.5:1**, ideally **2:1+**, reward-to-risk. If structure only offers <1:1 to
   the next liquidity, skip the trade.

**Management:** take partials at TP1, move stop to break-even, let a runner go to TP2. Many gold
scalps are "hit TP1, trail the rest."

---

## 8. Risk management (gold-specific)

* **Risk 0.25–0.5% of account per scalp.** Gold's dollar range is large; size from your **stop
  distance in price**, not a fixed lot.
  - Lots ≈ (account × risk%) ÷ (stop distance in $ × contract value per 1.00 move per lot).
    On most brokers 1.00 lot ≈ $100 per $1 move on XAUUSD, 0.10 lot ≈ $10 — **check your broker's
    contract size.**
* **Mind the spread & commission** — gold spreads can be 15–40 cents and balloon at news/rollover.
  A 50-cent spread ruins a 1-dollar scalp.
* **Daily guardrails:** stop after **2–3 losers** or a set daily loss (e.g. −1.5%). Don't revenge
  trade gold.
* **One setup at a time.** Don't stack correlated gold scalps.
* **No trades in the final seconds before red-folder news.**

---

## 9. Filters — skip the trade when…

* The sweep is **with** the higher-timeframe draw, not against a level (sweeps *into* an HTF level
  reverse; sweeps in open space often continue).
* Only a **fake FVG** forms after the sweep (weak displacement → likely continuation, not reversal).
* Spread is abnormally wide, or you're in dead Asian chop.
* Price just swept **and kept going** (close did **not** snap back) — that's a breakout, not a
  sweep; the indicator won't mark it, and neither should you trade it as a reversal.
* Reward to the nearest opposite liquidity is less than your stop.

---

## 10. Worked example (short)

1. D1 shows price rallying into a **D1 BSL** level (old daily high) — bias: look for shorts there.
2. On M5 the indicator prints **M5 BSL** — price wicked above a recent M5 high and closed back
   below (sell-side... i.e. buy-side liquidity taken), right at the daily level.
3. The down-leg leaves a bearish **Real FVG (`FVG+sweep`)**.
4. **Entry B:** price retraces into that FVG; you short on the first M1 rejection inside it.
5. **Stop:** just above the M5 BSL sweep wick + spread buffer.
6. **TP1:** the nearest M5 swing low (sell-side liquidity below). Take partials, go break-even.
7. **TP2:** the next H1 low / H1 FVG fill. Trail the runner.

---

## 11. Pre-trade checklist

- [ ] Session is London / NY overlap (or a clean post-news trend)?
- [ ] Higher-TF bias and nearest unswept H1/H4 level identified?
- [ ] Fresh M1/M5 sweep **into** that level, in my direction, closed (not a live wick)?
- [ ] Real FVG supports the entry (bonus: `+sweep`)?
- [ ] Stop beyond the sweep wick + spread buffer; reward ≥ 1.5× risk to nearest liquidity?
- [ ] Risk ≤ 0.5%, spread normal, no imminent red-folder news?
- [ ] Daily loss limit not hit?

If every box is ticked, take it. If not, wait — gold prints these setups several times a session.

---

## 12. Disclaimer

This is an educational framework, not financial advice. ICT/SMC "liquidity" and "stop hunt" ideas
are popular interpretations, not proven market mechanics. Trading gold with leverage can lose money
rapidly. Backtest and forward-test on demo, and only risk capital you can afford to lose.
