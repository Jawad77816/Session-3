# MT5 EA — Strategy from the @tradeiq.with.nitz reel

## Status: DRAFT — waiting on the Hindi audio transcript

The EA (`RSI_MA_MeanReversion_EA.mq5`) is built from **frame-by-frame analysis of the
video**. The exact spoken entry/exit numbers are in the **Hindi narration**, which could
**not be transcribed in this cloud session** (see "Why the audio wasn't transcribed"). So
the logic here is the best reconstruction from the on-screen charts + the user's
correction, with **every rule exposed as an input** to match the spoken rules later.

## What the video shows (visual analysis, high confidence)
- **Creator:** Nitya Tiwari (@tradeiq.with.nitz) — promotional reel for an "AlgoBootcamp",
  referencing Andrea Unger (4× World Trading Champion).
- **Instrument / timeframe on chart:** BTCUSD, **15-minute**.
- **Indicators on the chart:**
  - **Fast 5 EMA** (user-confirmed) — trigger line.
  - **Slow 200 EMA / SMA** — the smooth curved "mean" line price bounces off.
  - **RSI, short period (~2)** — it printed values ~3–5, only possible with RSI(2)-ish.
- **Trade shown:** LONG. Price dips **down to the 200 line** while **RSI is deeply
  oversold**, then reverses up (reclaims the 5 EMA) → buy the bounce.
- **Risk (from the on-chart position tool):** tight stop below the swing low (~0.12–0.26%),
  take-profit a **multiple of risk** (examples showed RR ≈ 1.8 and ≈ 3.4).

## What is NOT yet confirmed (needs the audio)
- Exact **entry trigger**: is it a 5-EMA/200-EMA relationship, a 5-EMA reclaim after the
  dip, or a pure RSI(2) oversold entry? (Draft uses: dip to 200 + RSI oversold + price
  reclaims 5 EMA.)
- Exact **RSI period and oversold/overbought thresholds**.
- Exact **stop-loss rule** (swing low vs fixed % vs ATR) and **take-profit rule**
  (fixed RR vs %, and the RR value).
- **Long-only or long+short**, and any **session/time filter**.

## Why the audio wasn't transcribed (network policy)
This cloud environment runs with **Trusted** network access, which allows package
registries (PyPI, npm) + GitHub but **blocks every host that serves real speech-model
weights**: huggingface.co, Azure (OpenAI Whisper CDN), alphacephei (Vosk), Meta
`dl.fbaipublicfiles`, Google Speech. Confirmed reachable: PyPI, npm, `raw.githubusercontent.com`,
`storage.googleapis.com` — but no usable Hindi ASR model is mirrored on those. So no
model could be downloaded/run here.

## How to finish (pick one)
1. **Enable network + transcribe here (chosen):** change this environment's **Network
   access** from *Trusted* to **Full** (or **Custom** allowing `huggingface.co`,
   `*.huggingface.co`, `*.hf.co`, `*.xethub.hf.co`) at claude.ai/code → environment
   settings, keeping "include default package managers" checked. Start a **new session**
   (the change applies to new sessions), re-attach the video, and ask Claude to transcribe
   + finalize. Whisper `large-v3` handles Hindi well.
2. **Paste a transcript:** run the `Hindi_Urdu_Audio_Model.ipynb` notebook (repo root) in
   Google Colab on this clip and paste the Hindi text — no env change needed.
3. **Type the rules:** just write the entry/exit/SL/TP in a few lines.

## The EA file
`RSI_MA_MeanReversion_EA.mq5` — MQL5 for MT5. CTrade-based, new-bar evaluation,
risk-% position sizing, swing/percent/points/ATR stop modes, RRR/percent/points targets,
optional break-even/trailing/RSI-exit, spread + session filters. Attach to a **BTCUSD M15**
chart (or set inputs to match the confirmed rules). Backtest in the MT5 Strategy Tester
before any live use.
