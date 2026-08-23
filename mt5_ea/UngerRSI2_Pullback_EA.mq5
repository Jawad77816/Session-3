//+------------------------------------------------------------------+
//|                        UngerRSI2_Pullback_EA.mq5                  |
//|   Andrea Unger / Larry Connors style RSI(2) pullback (LONG).     |
//|                                                                  |
//|   Rules (verbatim from the strategy video):                      |
//|     * Price ABOVE the 200 MA        -> market is bullish (filter) |
//|     * Temporary pullback BELOW the 5 EMA                         |
//|     * RSI(2) below 20               -> short-term panic selling   |
//|         => smart-money dip buy: ENTER LONG                        |
//|     * Stop loss = "the low" (of the signal candle)               |
//|     * Exit when price CLOSES above the 5 EMA (no fixed target)   |
//|                                                                  |
//|   Demoed on BTCUSD 15m, but the rules are generic. Backtest in   |
//|   the MT5 Strategy Tester before any live use.                   |
//+------------------------------------------------------------------+
#property copyright "Built for the user from the strategy video transcript"
#property version   "1.00"
#property description "RSI(2) pullback in a 200-MA uptrend; exit on a close above the 5 EMA"

#include <Trade/Trade.mqh>

//============================ INPUTS ==============================//
input group "=== Indicators (from the strategy) ==="
input int                Trend_MA_Period  = 200;          // Trend filter MA period ("200 moving average")
input ENUM_MA_METHOD     Trend_MA_Method  = MODE_EMA;     // 200 MA method
input int                Fast_MA_Period   = 5;            // Fast MA period ("5 EMA")
input ENUM_MA_METHOD     Fast_MA_Method   = MODE_EMA;     // 5 MA method
input ENUM_APPLIED_PRICE MA_AppliedPrice  = PRICE_CLOSE;  // MA applied price
input int                RSI_Period       = 2;            // RSI period ("RSI 2 period")
input double             RSI_EntryLevel   = 20.0;         // Long entry when RSI(2) < this ("below 20")

input group "=== Direction ==="
input bool               TradeLongs       = true;         // Long trades (the strategy)
input bool               TradeShorts      = false;        // Optional symmetric short (off = faithful to the video)

input group "=== Stop loss ('stop loss will be the low') ==="
input int                SL_LookbackBars  = 1;            // 1 = signal-bar low; >1 = lowest low of N closed bars
input int                SL_BufferPoints  = 0;            // Extra buffer beyond the low (points)

input group "=== Take profit (video uses none; optional) ==="
input bool               UseTakeProfit    = false;        // Add a fixed reward:risk target
input double             RewardRiskRatio  = 2.0;          // TP = entry + RRR * risk (only if enabled)

input group "=== Exit ==="
input bool               ExitOnFastClose  = true;         // Exit when a bar CLOSES back beyond the 5 EMA

input group "=== Money management ==="
input bool               UseRiskPercent   = true;         // Size by risk %, else fixed lot
input double             RiskPercent      = 1.0;          // Risk per trade (% of balance)
input double             FixedLot         = 0.01;         // Lot when UseRiskPercent = false

input group "=== Filters & housekeeping ==="
input bool               NewBarOnly       = true;         // Evaluate once per closed bar
input int                MaxPositions     = 1;            // Max simultaneous positions (this EA / symbol)
input int                MaxSpreadPoints  = 0;            // Skip entries if spread > this (0 = ignore)
input int                Slippage         = 20;           // Max deviation (points)
input long               MagicNumber      = 200520;       // EA id (unique per chart)
input string             TradeComment     = "UngerRSI2";  // Order comment

//============================ GLOBALS =============================//
CTrade   trade;
int      trendHandle = INVALID_HANDLE;
int      fastHandle  = INVALID_HANDLE;
int      rsiHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trendHandle = iMA(_Symbol, _Period, Trend_MA_Period, 0, Trend_MA_Method, MA_AppliedPrice);
   fastHandle  = iMA(_Symbol, _Period, Fast_MA_Period,  0, Fast_MA_Method,  MA_AppliedPrice);
   rsiHandle   = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

   if(trendHandle == INVALID_HANDLE || fastHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("ERROR: failed to create indicator handle(s).");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   PrintFormat("UngerRSI2_Pullback_EA on %s %s | Trend MA %d, Fast MA %d, RSI %d < %.1f",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
               Trend_MA_Period, Fast_MA_Period, RSI_Period, RSI_EntryLevel);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(trendHandle != INVALID_HANDLE) IndicatorRelease(trendHandle);
   if(fastHandle  != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(rsiHandle   != INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Act once per closed bar (the rules are bar-close based).
   if(NewBarOnly && !IsNewBar())
      return;

   // Need the last closed bar (index 1) for indicators and price.
   int need = MathMax(SL_LookbackBars + 2, 3);
   double trend[], fast[], rsi[];
   ArraySetAsSeries(trend, true);
   ArraySetAsSeries(fast,  true);
   ArraySetAsSeries(rsi,   true);
   if(CopyBuffer(trendHandle, 0, 0, need, trend) < need) return;
   if(CopyBuffer(fastHandle,  0, 0, need, fast)  < need) return;
   if(CopyBuffer(rsiHandle,   0, 0, need, rsi)   < need) return;

   double close1 = iClose(_Symbol, _Period, 1);   // last closed bar
   double trend1 = trend[1];
   double fast1  = fast[1];
   double rsi1   = rsi[1];

   // ---- 1) Manage exits first: close on a bar that closes back beyond the 5 EMA
   if(ExitOnFastClose)
      ManageExits(close1, fast1);

   // ---- 2) Entry filters
   if(MaxSpreadPoints > 0 && (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints)
      return;

   // LONG: bullish trend + pullback below fast MA + RSI(2) oversold
   bool longSignal = TradeLongs
                     && close1 > trend1              // price above the 200 MA (bullish)
                     && close1 < fast1               // temporary pullback below the 5 EMA
                     && rsi1   < RSI_EntryLevel;      // RSI(2) below 20 (panic selling)

   // SHORT (optional mirror, off by default): bearish trend + pullback above fast MA + RSI overbought
   bool shortSignal = TradeShorts
                      && close1 < trend1
                      && close1 > fast1
                      && rsi1   > (100.0 - RSI_EntryLevel);

   if(longSignal && shortSignal) { longSignal = false; shortSignal = false; }

   if(longSignal && CountPositions(POSITION_TYPE_BUY) < MaxPositions
                 && CountPositions(POSITION_TYPE_SELL) == 0)
      OpenTrade(true);

   if(shortSignal && CountPositions(POSITION_TYPE_SELL) < MaxPositions
                  && CountPositions(POSITION_TYPE_BUY) == 0)
      OpenTrade(false);
}

//+------------------------------------------------------------------+
//| Exit rule: close the position when a bar closes back beyond 5 EMA |
//+------------------------------------------------------------------+
void ManageExits(double close1, double fast1)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      // Long exits when price closes ABOVE the fast EMA; short exits when it closes BELOW.
      if(ptype == POSITION_TYPE_BUY  && close1 > fast1) trade.PositionClose(ticket);
      if(ptype == POSITION_TYPE_SELL && close1 < fast1) trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Open a long (isBuy=true) or short trade with SL (= the low/high) |
//+------------------------------------------------------------------+
void OpenTrade(bool isBuy)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;
   double buf   = SL_BufferPoints * _Point;

   // "Stop loss will be the low" -> low of the signal candle (or lowest low of N bars).
   double sl;
   if(isBuy) sl = SwingLow(SL_LookbackBars, 1)  - buf;
   else      sl = SwingHigh(SL_LookbackBars, 1) + buf;

   double risk = MathAbs(entry - sl);
   if(risk <= 0.0) { Print("Trade skipped: non-positive risk distance."); return; }

   double tp = 0.0;
   if(UseTakeProfit)
      tp = isBuy ? entry + RewardRiskRatio * risk : entry - RewardRiskRatio * risk;

   // Respect the broker's minimum stop distance.
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
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

   bool ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment)
                   : trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment);

   if(!ok)
      PrintFormat("Order failed (%s): retcode=%d %s",
                  isBuy ? "BUY" : "SELL", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else
      PrintFormat("%s opened: lots=%.2f entry=%.5f SL=%.5f TP=%.5f",
                  isBuy ? "BUY" : "SELL", lots, entry, sl, tp);
}

//+------------------------------------------------------------------+
//| Position size from risk % over the SL distance (or fixed lot)    |
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   if(!UseRiskPercent)
      return NormalizeVolume(FixedLot);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return NormalizeVolume(FixedLot);

   double lossPerLot = (slDistancePrice / tickSize) * tickValue; // money lost per 1.0 lot
   if(lossPerLot <= 0.0) return NormalizeVolume(FixedLot);

   return NormalizeVolume(riskMoney / lossPerLot);
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
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
}
//+------------------------------------------------------------------+
