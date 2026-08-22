//+------------------------------------------------------------------+
//|                                     RSI_MA_MeanReversion_EA.mq5   |
//|   Mean-reversion EA: pullback to a slow MA + short-period RSI     |
//|   extreme, then trade the reversion back toward the mean.         |
//|                                                                  |
//|   Reconstructed from the on-screen strategy in the reel by        |
//|   @tradeiq.with.nitz (BTCUSD, 15m). Indicators seen on chart:     |
//|   a fast 5 EMA + a slow 200 EMA/SMA + a short-period RSI. Setup:   |
//|   price dips to the 200 line with RSI oversold, then reclaims the  |
//|   5 EMA -> long the bounce (symmetric short optional).            |
//|                                                                  |
//|   ****  DRAFT v0.2  ****                                          |
//|   The EXACT spoken entry/exit numbers are in the video's Hindi    |
//|   narration and are NOT yet confirmed. Every rule below is an     |
//|   input so the strategy can be matched precisely once the audio   |
//|   is transcribed. Defaults follow what was visible on the charts. |
//+------------------------------------------------------------------+
#property copyright "Built for the user from video strategy analysis"
#property version   "1.00"
#property description "MA-pullback + RSI-extreme mean reversion (configurable long/short)"

#include <Trade/Trade.mqh>

//====================== ENUMS =====================================//
enum ENUM_SL_MODE { SL_SWING, SL_PERCENT, SL_POINTS, SL_ATR };
enum ENUM_TP_MODE { TP_RRR, TP_PERCENT, TP_POINTS, TP_NONE };

//====================== INPUTS ====================================//
input group "=== Slow MA (mean line, ~200) ==="
input int                MA_Period        = 200;            // Slow MA period (the line price reverts to)
input ENUM_MA_METHOD     MA_Method        = MODE_EMA;       // Slow MA method (user confirmed 200 EMA)
input ENUM_APPLIED_PRICE MA_AppliedPrice  = PRICE_CLOSE;    // Slow MA applied price
input double             MA_TouchTolPct   = 0.05;           // How close to MA counts as a "touch" (% of price)

input group "=== Fast EMA (trigger line, ~5) ==="
input bool               UseFastEMAConfirm = true;          // Confirm bounce by price reclaiming the fast EMA
input int                FastEMA_Period   = 5;              // Fast EMA period (user confirmed a 5 EMA on chart)
input ENUM_APPLIED_PRICE FastEMA_Price    = PRICE_CLOSE;    // Fast EMA applied price

input group "=== RSI (momentum extreme) ==="
input int                RSI_Period       = 2;              // RSI period (short = Connors style; chart hit ~3-5)
input double             RSI_Oversold     = 10.0;           // Long trigger: RSI at/below this
input double             RSI_Overbought   = 90.0;           // Short trigger: RSI at/above this

input group "=== Entry logic ==="
input bool               TradeLongs             = true;     // Allow long (buy-the-dip) trades
input bool               TradeShorts            = true;     // Allow short (fade-the-spike) trades
input int                SignalLookbackBars     = 2;        // Bars back to look for the dip+RSI extreme
input bool               RequireReversalCandle  = true;     // Require a reversal candle to confirm the bounce
input bool               RequireSideOfMA        = true;     // Long only when price is below MA (short when above)

input group "=== Stop Loss ==="
input ENUM_SL_MODE       SL_Mode          = SL_SWING;       // How to place the stop
input int                SL_SwingBars     = 5;              // SWING: lookback bars for swing hi/lo
input double             SL_Percent       = 0.30;           // PERCENT: stop distance as % of entry
input int                SL_Points        = 2000;           // POINTS: stop distance in points
input double             SL_ATR_Mult      = 1.5;            // ATR: stop = ATR * this
input int                SL_ATR_Period    = 14;             // ATR period for SL/ATR modes
input int                SL_BufferPoints  = 50;             // Extra buffer beyond swing (points)

input group "=== Take Profit ==="
input ENUM_TP_MODE       TP_Mode          = TP_RRR;         // How to place the target
input double             RewardRiskRatio  = 2.0;            // RRR: target = this * risk (chart showed ~1.8-3.4)
input double             TP_Percent       = 0.80;           // PERCENT: target as % of entry
input int                TP_Points        = 6000;           // POINTS: target distance in points

input group "=== Money management ==="
input bool               UseRiskPercent   = true;           // true: size by risk %, false: fixed lot
input double             RiskPercent      = 1.0;            // Risk per trade (% of balance)
input double             FixedLot         = 0.01;           // Lot used when UseRiskPercent = false

input group "=== Trade management (optional) ==="
input bool               UseBreakEven     = false;          // Move SL to entry after some profit
input double             BreakEvenRR       = 1.0;           // Trigger BE once open profit >= this * risk
input bool               UseTrailing      = false;          // Trail the stop
input int                TrailPoints      = 1500;           // Trailing distance in points
input bool               UseRSIExit       = false;          // Close early when RSI reverts to a level
input double             RSIExitLong      = 55.0;           // Long exit when RSI >= this
input double             RSIExitShort     = 45.0;           // Short exit when RSI <= this

input group "=== Filters & housekeeping ==="
input bool               NewBarOnly       = true;           // Evaluate signals once per closed bar
input int                MaxPositionsPerDir = 1;            // Max simultaneous positions per direction
input int                MaxSpreadPoints  = 0;              // Skip if spread > this (0 = ignore)
input bool               UseSessionFilter = false;          // Restrict trading hours (server time)
input int                StartHour        = 0;              // Session start hour (0-23)
input int                EndHour          = 24;             // Session end hour (1-24)
input int                Slippage         = 20;             // Max price deviation (points)
input long               MagicNumber      = 260886;         // EA id (must be unique per chart)
input string             TradeComment     = "RSI_MA_MR";    // Order comment

//====================== GLOBALS ===================================//
CTrade   trade;
int      maHandle     = INVALID_HANDLE;
int      fastMaHandle = INVALID_HANDLE;
int      rsiHandle    = INVALID_HANDLE;
int      atrHandle    = INVALID_HANDLE;
datetime lastBarTime  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   maHandle     = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_AppliedPrice);
   fastMaHandle = iMA(_Symbol, _Period, FastEMA_Period, 0, MODE_EMA, FastEMA_Price);
   rsiHandle    = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   atrHandle    = iATR(_Symbol, _Period, SL_ATR_Period);

   if(maHandle == INVALID_HANDLE || fastMaHandle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: failed to create indicator handle(s).");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("RSI_MA_MeanReversion_EA initialised on ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(maHandle     != INVALID_HANDLE) IndicatorRelease(maHandle);
   if(fastMaHandle != INVALID_HANDLE) IndicatorRelease(fastMaHandle);
   if(rsiHandle    != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(atrHandle    != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Manage existing trades every tick (trailing / BE / RSI-exit)
   ManageOpenPositions();

   // Signal evaluation: optionally only on a fresh bar
   if(NewBarOnly && !IsNewBar())
      return;

   if(UseSessionFilter && !WithinSession())
      return;

   if(MaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > MaxSpreadPoints)
         return;
   }

   // Pull indicator values (index 1 = last closed bar)
   int need = MathMax(SignalLookbackBars + 2, 3);
   double ma[], rsi[], fema[];
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(fema, true);
   if(CopyBuffer(maHandle, 0, 0, need, ma)      < need) return;
   if(CopyBuffer(rsiHandle, 0, 0, need, rsi)    < need) return;
   if(CopyBuffer(fastMaHandle, 0, 0, need, fema) < need) return;

   bool longSetup  = false;
   bool shortSetup = false;

   // Look back over recent closed bars for a dip-to-MA + RSI extreme
   for(int i = 1; i <= SignalLookbackBars; i++)
   {
      double maI  = ma[i];
      double rsiI = rsi[i];
      double lowI  = iLow(_Symbol, _Period, i);
      double highI = iHigh(_Symbol, _Period, i);
      double tol   = maI * (MA_TouchTolPct / 100.0);

      // LONG: price dipped to/below the MA while RSI oversold
      if(TradeLongs && rsiI <= RSI_Oversold && lowI <= (maI + tol))
         longSetup = true;

      // SHORT: price spiked to/above the MA while RSI overbought
      if(TradeShorts && rsiI >= RSI_Overbought && highI >= (maI - tol))
         shortSetup = true;
   }

   // Reversal-candle confirmation on the last closed bar
   double o1 = iOpen(_Symbol,  _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   bool bullishBar = (c1 > o1);
   bool bearishBar = (c1 < o1);
   double maLast = ma[1];

   if(RequireReversalCandle)
   {
      longSetup  = longSetup  && bullishBar;
      shortSetup = shortSetup && bearishBar;
   }
   if(RequireSideOfMA)
   {
      // Only revert from the correct side of the mean line
      longSetup  = longSetup  && (c1 <= maLast);
      shortSetup = shortSetup && (c1 >= maLast);
   }
   if(UseFastEMAConfirm)
   {
      // Bounce confirmation: price reclaims the fast EMA (long) / loses it (short)
      double femaLast = fema[1];
      longSetup  = longSetup  && (c1 > femaLast);
      shortSetup = shortSetup && (c1 < femaLast);
   }

   // Never take both directions on the same bar
   if(longSetup && shortSetup)
   { longSetup = false; shortSetup = false; }

   if(longSetup  && CountPositions(POSITION_TYPE_BUY)  < MaxPositionsPerDir)
      OpenTrade(true);

   if(shortSetup && CountPositions(POSITION_TYPE_SELL) < MaxPositionsPerDir)
      OpenTrade(false);
}

//+------------------------------------------------------------------+
//| Open a long (isBuy=true) or short trade with SL/TP + sizing      |
//+------------------------------------------------------------------+
void OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;

   double sl = CalcStopLoss(isBuy, entry);
   if(sl <= 0.0) { Print("Trade skipped: invalid SL."); return; }

   double risk = MathAbs(entry - sl);
   if(risk <= 0.0) { Print("Trade skipped: zero risk distance."); return; }

   double tp = CalcTakeProfit(isBuy, entry, risk);

   // Respect the broker's minimum stop distance
   long   stopsLvl   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLvl * _Point;
   if(minDist > 0.0)
   {
      if(isBuy)
      {
         if(entry - sl < minDist) sl = entry - minDist;
         if(tp > 0.0 && tp - entry < minDist) tp = entry + minDist;
      }
      else
      {
         if(sl - entry < minDist) sl = entry + minDist;
         if(tp > 0.0 && entry - tp < minDist) tp = entry - minDist;
      }
      risk = MathAbs(entry - sl);
   }

   double lots = CalcLots(risk);
   if(lots <= 0.0) { Print("Trade skipped: lot size 0."); return; }

   sl = NormalizeDouble(sl, _Digits);
   tp = (tp > 0.0) ? NormalizeDouble(tp, _Digits) : 0.0;

   bool ok;
   if(isBuy) ok = trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment);
   else      ok = trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment);

   if(!ok)
      PrintFormat("Order failed (%s): retcode=%d %s",
                  isBuy ? "BUY" : "SELL", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else
      PrintFormat("%s opened: lots=%.2f entry=%.2f SL=%.2f TP=%.2f",
                  isBuy ? "BUY" : "SELL", lots, entry, sl, tp);
}

//+------------------------------------------------------------------+
double CalcStopLoss(bool isBuy, double entry)
{
   switch(SL_Mode)
   {
      case SL_PERCENT:
         return isBuy ? entry * (1.0 - SL_Percent / 100.0)
                      : entry * (1.0 + SL_Percent / 100.0);

      case SL_POINTS:
         return isBuy ? entry - SL_Points * _Point
                      : entry + SL_Points * _Point;

      case SL_ATR:
      {
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2) return 0.0;
         double dist = atr[1] * SL_ATR_Mult;
         return isBuy ? entry - dist : entry + dist;
      }

      case SL_SWING:
      default:
      {
         double buf = SL_BufferPoints * _Point;
         if(isBuy)
         {
            double lo = SwingLow(SL_SwingBars, 1);
            return lo - buf;
         }
         else
         {
            double hi = SwingHigh(SL_SwingBars, 1);
            return hi + buf;
         }
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
double CalcTakeProfit(bool isBuy, double entry, double risk)
{
   switch(TP_Mode)
   {
      case TP_NONE:    return 0.0;
      case TP_PERCENT: return isBuy ? entry * (1.0 + TP_Percent / 100.0)
                                    : entry * (1.0 - TP_Percent / 100.0);
      case TP_POINTS:  return isBuy ? entry + TP_Points * _Point
                                    : entry - TP_Points * _Point;
      case TP_RRR:
      default:         return isBuy ? entry + RewardRiskRatio * risk
                                    : entry - RewardRiskRatio * risk;
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Position size: risk % of balance over the SL distance, or fixed  |
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   if(!UseRiskPercent)
      return NormalizeVolume(FixedLot);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeVolume(FixedLot);

   double lossPerLot = (slDistancePrice / tickSize) * tickValue; // money lost per 1.0 lot
   if(lossPerLot <= 0.0)
      return NormalizeVolume(FixedLot);

   double lots = riskMoney / lossPerLot;
   return NormalizeVolume(lots);
}

//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0) vstep = 0.01;

   lots = MathFloor(lots / vstep) * vstep;
   lots = MathMax(vmin, MathMin(vmax, lots));

   int digits = (int)MathMax(0, MathRound(-MathLog10(vstep)));
   return NormalizeDouble(lots, digits);
}

//+------------------------------------------------------------------+
double SwingLow(int bars, int startShift)
{
   double lo = DBL_MAX;
   for(int i = startShift; i < startShift + bars; i++)
      lo = MathMin(lo, iLow(_Symbol, _Period, i));
   return lo;
}
double SwingHigh(int bars, int startShift)
{
   double hi = -DBL_MAX;
   for(int i = startShift; i < startShift + bars; i++)
      hi = MathMax(hi, iHigh(_Symbol, _Period, i));
   return hi;
}

//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Trailing stop, break-even and optional RSI-based early exit      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UseBreakEven && !UseTrailing && !UseRSIExit)
      return;

   double rsi[];
   bool haveRSI = false;
   if(UseRSIExit)
   {
      ArraySetAsSeries(rsi, true);
      haveRSI = (CopyBuffer(rsiHandle, 0, 0, 2, rsi) >= 2);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool   isBuy     = (ptype == POSITION_TYPE_BUY);
      double priceNow  = isBuy ? bid : ask;

      // ---- RSI-based early exit ----
      if(UseRSIExit && haveRSI)
      {
         if(isBuy  && rsi[1] >= RSIExitLong)  { trade.PositionClose(ticket); continue; }
         if(!isBuy && rsi[1] <= RSIExitShort) { trade.PositionClose(ticket); continue; }
      }

      double newSL = curSL;

      // ---- Break-even ----
      if(UseBreakEven && curSL != openPrice)
      {
         double riskDist = MathAbs(openPrice - curSL);
         if(riskDist > 0.0)
         {
            if(isBuy && (priceNow - openPrice) >= BreakEvenRR * riskDist)
               newSL = MathMax(newSL, openPrice);
            if(!isBuy && (openPrice - priceNow) >= BreakEvenRR * riskDist)
               newSL = (newSL == 0.0) ? openPrice : MathMin(newSL, openPrice);
         }
      }

      // ---- Trailing stop ----
      if(UseTrailing)
      {
         double trail = TrailPoints * _Point;
         if(isBuy)
         {
            double cand = priceNow - trail;
            if(cand > newSL && cand > openPrice) newSL = cand;
         }
         else
         {
            double cand = priceNow + trail;
            if((newSL == 0.0 || cand < newSL) && cand < openPrice) newSL = cand;
         }
      }

      if(newSL != curSL && newSL > 0.0)
      {
         newSL = NormalizeDouble(newSL, _Digits);
         trade.PositionModify(ticket, newSL, curTP);
      }
   }
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool WithinSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int h = now.hour;
   if(StartHour <= EndHour)
      return (h >= StartHour && h < EndHour);
   // Wrap-around window (e.g. 22 -> 6)
   return (h >= StartHour || h < EndHour);
}
//+------------------------------------------------------------------+
