//+------------------------------------------------------------------+
//|                                                     MSB_OB_EA.mq5 |
//|              Market Structure Break + Order Block - Expert Advisor|
//|                                                                  |
//|  Trades the MSB-OB strategy from the video on MetaTrader 5:      |
//|                                                                  |
//|   1. A ZigZag (pivot) engine tracks swing highs / swing lows.   |
//|   2. Bullish MSB  = close breaks above the last swing high       |
//|      (by a Fib-factor buffer of the impulse leg).               |
//|      Bearish MSB  = close breaks below the last swing low.       |
//|   3. The last opposite candle before the break is the Order      |
//|      Block (OB) - the entry AREA shown in the video.            |
//|   4. Entry: a BUY LIMIT (after bullish MSB) / SELL LIMIT (after  |
//|      bearish MSB) is placed at the OB so we trade the retest.    |
//|      SL sits just beyond the OB, TP at a fixed reward:risk.      |
//|                                                                  |
//|  Intended for the M5 timeframe (warns otherwise).               |
//+------------------------------------------------------------------+
#property copyright "MSB-OB strategy recreation"
#property version   "1.00"
#property description "Expert Advisor for the Market Structure Break + Order Block (MSB-OB) strategy. Places OB-retest limit orders after a confirmed structure break. Built for M5."

#include <Trade\Trade.mqh>

//--- Strategy / structure inputs (mirror the indicator) ------------
input group "=== Structure detection ==="
input int    InpZigZagLength   = 9;      // ZigZag Length (pivot lookback each side)
input double InpFibFactor      = 0.273;  // Fib Factor for breakout confirmation
input int    InpLookbackBars   = 600;    // Bars analysed for structure

//--- Entry / exit inputs -------------------------------------------
input group "=== Entry / Exit ==="
input bool   InpEntryAtMid     = false;  // Entry at OB midpoint (else at proximal edge)
input double InpRiskReward      = 2.0;   // Reward : Risk for take profit
input int    InpSLBufferPoints  = 20;    // Extra SL buffer beyond OB (points)
input int    InpPendingExpiryBars = 24;  // Cancel unfilled pending after N bars
input bool   InpOnePositionOnly = true;  // Only one open position at a time

//--- Money management ----------------------------------------------
input group "=== Money management ==="
input bool   InpUseRiskPercent = true;   // Size lots from risk %
input double InpRiskPercent    = 1.0;    // Risk % of balance per trade
input double InpFixedLots       = 0.10;  // Fixed lots (if risk % disabled)

//--- Trade controls ------------------------------------------------
input group "=== Trade controls ==="
input long   InpMagic          = 5507701;// Magic number
input int    InpMaxSpreadPoints = 40;    // Skip if spread above this (0 = ignore)
input string InpComment        = "MSB-OB";

//--- Globals
CTrade   trade;
datetime g_lastBarTime = 0;
datetime g_brokenHighTime = 0;   // last swing high already traded/broken
datetime g_brokenLowTime  = 0;   // last swing low  already traded/broken

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(_Period != PERIOD_M5)
      Print("MSB-OB EA: designed for the M5 timeframe; current chart is ", EnumToString(_Period));

   Print("MSB-OB EA initialised on ", _Symbol, " ", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }
//+------------------------------------------------------------------+
void OnTick()
  {
   // Act once per newly closed bar.
   datetime curBarTime = (datetime)iTime(_Symbol, _Period, 0);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;

   CleanupExpiredPendings();

   // Copy the recent history as series arrays (index 0 = current bar).
   int need = InpLookbackBars;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, need, rates);
   int L = MathMax(1, InpZigZagLength);
   if(copied < 2*L + 5) return;

   // Find the most recent confirmed swing high / low as of the last
   // CLOSED bar (shift 1). A pivot at shift p is confirmed only when it
   // has L closed bars on each side -> require p-L >= 1 and p+L <= copied-1.
   int   phShift=-1, plShift=-1;
   double phPrice=0, plPrice=0;
   datetime phTime=0, plTime=0;

   for(int p = L + 1; p <= copied - 1 - L; p++)
     {
      if(phShift < 0 && IsPivotHighSeries(rates, p, L, copied))
        { phShift=p; phPrice=rates[p].high; phTime=rates[p].time; }
      if(plShift < 0 && IsPivotLowSeries(rates, p, L, copied))
        { plShift=p; plPrice=rates[p].low;  plTime=rates[p].time; }
      if(phShift >= 0 && plShift >= 0) break;
     }

   double closed = rates[1].close;   // last closed bar
   double legRange = (phPrice > 0 && plPrice > 0) ? MathAbs(phPrice - plPrice) : 0.0;
   double buffer   = InpFibFactor * legRange;

   //--- Bullish MSB -> arm a BUY LIMIT at the bullish order block ----
   if(phShift > 0 && phTime != g_brokenHighTime && closed > phPrice + buffer)
     {
      g_brokenHighTime = phTime;
      int obShift = FindOrderBlock(rates, true, phShift, 1);
      if(obShift > 0)
         PlaceSetup(true, rates[obShift].high, rates[obShift].low);
     }

   //--- Bearish MSB -> arm a SELL LIMIT at the bearish order block ---
   if(plShift > 0 && plTime != g_brokenLowTime && closed < plPrice - buffer)
     {
      g_brokenLowTime = plTime;
      int obShift = FindOrderBlock(rates, false, plShift, 1);
      if(obShift > 0)
         PlaceSetup(false, rates[obShift].high, rates[obShift].low);
     }
  }
//+------------------------------------------------------------------+
//| Series pivot tests (index 0 = most recent)                       |
//+------------------------------------------------------------------+
bool IsPivotHighSeries(const MqlRates &r[], int p, int L, int n)
  {
   if(p - L < 0 || p + L >= n) return(false);
   double v = r[p].high;
   for(int k = 1; k <= L; k++)
     {
      if(r[p-k].high > v) return(false);
      if(r[p+k].high > v) return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool IsPivotLowSeries(const MqlRates &r[], int p, int L, int n)
  {
   if(p - L < 0 || p + L >= n) return(false);
   double v = r[p].low;
   for(int k = 1; k <= L; k++)
     {
      if(r[p-k].low < v) return(false);
      if(r[p+k].low < v) return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Find OB candle: last opposite-colour candle before the break     |
//| (series indices: fromShift is older/larger, toShift is newer)    |
//+------------------------------------------------------------------+
int FindOrderBlock(const MqlRates &r[], bool bullish, int fromShift, int toShift)
  {
   for(int k = toShift; k < fromShift; k++)
     {
      bool bearCandle = (r[k].close < r[k].open);
      bool bullCandle = (r[k].close > r[k].open);
      if(bullish && bearCandle) return(k);   // demand OB = last down candle
      if(!bullish && bullCandle) return(k);  // supply OB = last up candle
     }
   return(fromShift);
  }
//+------------------------------------------------------------------+
//| Place the pending OB-retest order with SL/TP and sized lots       |
//+------------------------------------------------------------------+
void PlaceSetup(bool bullish, double obTop, double obBot)
  {
   if(!TradingAllowed()) return;

   // Replace any previous strategy setup; respect one-position rule.
   DeleteStrategyPendings();
   if(InpOnePositionOnly && HasOpenPosition()) return;

   double point = _Point;
   double buf   = InpSLBufferPoints * point;
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double entry, sl, tp;
   ENUM_ORDER_TYPE type;

   if(bullish)
     {
      entry = InpEntryAtMid ? (obTop + obBot) * 0.5 : obTop;   // proximal edge = OB top
      sl    = obBot - buf;
      double risk = entry - sl;
      if(risk <= point) return;
      tp    = entry + InpRiskReward * risk;
      type  = ORDER_TYPE_BUY_LIMIT;
      if(entry >= ask - point) return;   // limit must sit below market
     }
   else
     {
      entry = InpEntryAtMid ? (obTop + obBot) * 0.5 : obBot;   // proximal edge = OB bottom
      sl    = obTop + buf;
      double risk = sl - entry;
      if(risk <= point) return;
      tp    = entry - InpRiskReward * risk;
      type  = ORDER_TYPE_SELL_LIMIT;
      if(entry <= bid + point) return;   // limit must sit above market
     }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = NormalizeDouble(tp,    _Digits);

   double lots = CalcLots(MathAbs(entry - sl));
   if(lots <= 0) return;

   datetime expiry = TimeCurrent() + (datetime)(InpPendingExpiryBars * PeriodSeconds());

   bool ok = trade.OrderOpen(_Symbol, type, lots, 0.0, entry, sl, tp,
                             ORDER_TIME_SPECIFIED, expiry, InpComment);
   if(!ok)
      PrintFormat("MSB-OB EA: order failed (%d) %s", trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
   else
      PrintFormat("MSB-OB EA: %s @ %.*f SL %.*f TP %.*f lots %.2f",
                  (bullish ? "BUY LIMIT" : "SELL LIMIT"),
                  _Digits, entry, _Digits, sl, _Digits, tp, lots);
  }
//+------------------------------------------------------------------+
//| Lot size from risk % of balance and SL distance                  |
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
  {
   double lots;
   if(!InpUseRiskPercent)
      lots = InpFixedLots;
   else
     {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0 || tickValue <= 0) return(0.0);
      double moneyPerLot = (slDistancePrice / tickSize) * tickValue;
      if(moneyPerLot <= 0) return(0.0);
      lots = riskMoney / moneyPerLot;
     }
   return(NormalizeLots(lots));
  }
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   if(lots < minL) lots = minL;
   if(lots > maxL) lots = maxL;
   return(NormalizeDouble(lots, 2));
  }
//+------------------------------------------------------------------+
bool TradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return(false);
   if(InpMaxSpreadPoints > 0)
     {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints) return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
void DeleteStrategyPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         trade.OrderDelete(tk);
     }
  }
//+------------------------------------------------------------------+
//| Safety net: remove pendings older than the expiry window         |
//| (broker-side expiry usually handles this; this is a backstop).   |
//+------------------------------------------------------------------+
void CleanupExpiredPendings()
  {
   datetime cutoff = TimeCurrent() - (datetime)(InpPendingExpiryBars * PeriodSeconds());
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(setup < cutoff) trade.OrderDelete(tk);
     }
  }
//+------------------------------------------------------------------+
