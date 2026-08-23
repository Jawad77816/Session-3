# MT5 EA — Andrea Unger / Connors RSI(2) pullback

## Status: FINAL — built from the confirmed video transcript ✅

**EA file:** `UngerRSI2_Pullback_EA.mq5`
**Strategy source:** `STRATEGY_TRANSCRIPT.md` (the video's narration, provided by the user)

## The strategy (exact rules)
Long-only RSI(2) mean-reversion pullback in an uptrend (Larry Connors style, taught here
via Andrea Unger):

| Element | Rule | Input |
|---|---|---|
| Trend filter | Close **>** 200 MA (market bullish) | `Trend_MA_Period=200`, `Trend_MA_Method=EMA` |
| Pullback | Close **<** 5 EMA | `Fast_MA_Period=5`, `Fast_MA_Method=EMA` |
| Trigger | **RSI(2) < 20** | `RSI_Period=2`, `RSI_EntryLevel=20` |
| Entry | Buy when all three true | `TradeLongs=true` |
| Stop loss | The **low** of the signal candle | `SL_LookbackBars=1` |
| Exit | Close **>** 5 EMA (no fixed TP) | `ExitOnFastClose=true` |
| Direction | Long only | `TradeShorts=false` (optional mirror available) |

Everything is an input, so the periods/levels can be tuned. Risk-% position sizing
(`RiskPercent`) sizes the lot from the SL distance; set `UseRiskPercent=false` for a fixed lot.

## How to use
1. Copy `UngerRSI2_Pullback_EA.mq5` to `MQL5/Experts/` in your MT5 data folder.
2. Open **MetaEditor** → open the file → **Compile** (F7). It should compile with 0 errors.
3. Attach it to a chart (demoed on **BTCUSD, M15**) and enable **AutoTrading**.
4. **Backtest first** in the Strategy Tester (99%-quality ticks) before any live/demo use.

## History (for context)
- The strategy rules come from the Hindi/Urdu narration of the reel by @tradeiq.with.nitz.
- This session's network is firewalled off HuggingFace/Azure, so Whisper couldn't run here;
  the user supplied the transcript directly. See `STRATEGY_TRANSCRIPT.md`.
- An earlier draft (`RSI_MA_MeanReversion_EA.mq5`) was based on chart-only guesses and was
  **replaced** by this file once the transcript confirmed the real rules.
