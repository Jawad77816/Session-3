# VWAP + EMA9 Cross EA — `VwapEma9CrossEA.mq5`

An **MT5 Expert Advisor** rebuilt from the video ("EMA9 / VWAP crisscross" scalp).

## Strategy (from the on-screen rules)
- Indicators: **EMA 9** + **session VWAP**.
- **Signal — 3-minute timeframe:**
  - EMA9 crosses **above** VWAP → bullish (calls / **BUY**)
  - EMA9 crosses **under** VWAP → bearish (puts / **SELL**)
- **Entry — 1-minute timeframe:** after the cross, take the **candle that wicks the
  EMA9 or the VWAP** — a rejection wick in the bias direction.
- **Stop loss:** the video uses −25% of option premium; here it is a **price stop**
  (entry-candle wick / ATR / fixed points, `InpSLMode`).
- **Take-profit:** fixed **R:R, default 1:3** (`InpRR = 3.0`, adjustable).

Multi-timeframe: the 3M cross sets the bias, the 1M wick triggers the entry.
Everything is evaluated on **closed bars**.

## Install (MT5)
1. **File → Open Data Folder → MQL5 → Experts**, copy `VwapEma9CrossEA.mq5` there.
2. In MetaEditor press **Compile**.
3. Enable **Algo Trading**, drag **VwapEma9CrossEA** onto the **M1** chart of your
   instrument, and tick *Allow Algo Trading*.
4. **Test on a DEMO account / Strategy Tester first.**

## Key inputs
- **Timeframes:** `InpSignalTF` (M3), `InpEntryTF` (M1), `InpEmaPeriod` (9).
- **VWAP anchor:** `InpVWAPHour` / `InpVWAPMin` (server time). Default `0:00` =
  daily VWAP (good for FX/crypto). For **stocks/indices set it to the session open**
  in your broker's server time (e.g. 9:30 ET converted to server time).
- **Entry:** `InpMaxBarsSinceCross` (only enter within N 3M-bars of the cross),
  `InpWickTolPts` (how close the wick must get), `InpRequireClose` (reject &
  close back beyond the level), `InpTradeLong/Short`, `InpCloseOnOpposite`.
- **Risk/Reward:** **`InpRR = 3.0` (1:3, adjustable)**, `InpSLMode`
  (Wick / ATR / Fixed), `InpATRmult`, `InpFixedSLPts`, `InpSLBufferPts`.
- **Money management:** `InpUseRiskPct` + `InpRiskPct`, or `InpFixedLots`.
- **Misc:** `InpMagic`, `InpMaxSpreadPts`, `InpSlippagePts`.

## Notes / honesty
- MT5 has **no built-in VWAP**, so it is computed in the EA (session-anchored,
  typical price × tick volume). On FX/crypto tick volume is used; anchor it to the
  right session for the instrument you trade.
- The video is **options-based** (calls/puts, −25% premium stop). This EA maps that
  onto a normal buy/sell instrument with a price stop and a fixed R:R target.
- The **audio could not be transcribed** here, but the strategy was written on-screen
  in the video, so the rules above are taken directly from it; every parameter is an
  input so you can fine-tune.
- **An EA trades real orders — always demo-test and backtest first.** Educational,
  not financial advice.
