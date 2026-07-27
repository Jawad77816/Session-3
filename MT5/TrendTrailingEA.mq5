//+------------------------------------------------------------------+
//|                                             TrendTrailingEA.mq5   |
//|                                                                  |
//|  Strategy:                                                       |
//|   1. Determine trend on a higher (configurable) timeframe using  |
//|      a moving average filter.                                     |
//|   2. Open a 0.01 lot trade in the direction of that trend, with   |
//|      a fixed take-profit and stop-loss (default = 6 USD each on   |
//|      0.01 lot Gold, i.e. a 6.00 price move: 4000 -> TP 4006 /     |
//|      SL 3994 for a buy).                                          |
//|   3. Once price moves in favour of the trade by a small amount    |
//|      (default 0.3 USD), start trailing the stop-loss behind the   |
//|      price, locking in / following the move.                      |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- How the distance inputs below are interpreted
enum ENUM_TARGET_MODE
  {
   MODE_MONEY_USD    = 0,  // Inputs are in account currency (USD) per trade
   MODE_PRICE_POINTS = 1   // Inputs are in raw price distance (e.g. 6.0 = 6.00)
  };

//============================ INPUTS ================================//
input group "=== Trend Filter (higher timeframe) ==="
input ENUM_TIMEFRAMES  InpTrendTF        = PERIOD_H1;      // Higher timeframe for trend analysis
input int              InpMAPeriod       = 50;             // Trend MA period
input ENUM_MA_METHOD   InpMAMethod       = MODE_EMA;       // Trend MA method
input ENUM_APPLIED_PRICE InpMAPrice      = PRICE_CLOSE;    // Trend MA applied price

input group "=== Entry ==="
input double           InpLots           = 0.01;           // Lot size
input bool             InpOnePosition    = true;            // Only one position at a time
input long             InpMagic          = 990033;          // Magic number

input group "=== Targets & Trailing ==="
input ENUM_TARGET_MODE InpTargetMode     = MODE_MONEY_USD; // How TP/SL/trailing inputs are read
input double           InpTakeProfit     = 6.0;            // Take profit (USD or price per mode)
input double           InpStopLoss       = 6.0;            // Stop loss  (USD or price per mode)
input double           InpTrailStart     = 0.3;            // Move in favour before trailing starts
input double           InpTrailDistance  = 0.3;            // Gap kept between price and trailing SL
input double           InpTrailStep      = 0.05;           // Min improvement before SL is moved

//============================ GLOBALS ==============================//
CTrade   trade;
int      maHandle = INVALID_HANDLE;
double   g_point;
int      g_digits;
long     g_stopsLevelPts;   // broker minimum stop distance in points

//+------------------------------------------------------------------+
//| Convert a "USD or price" input into a raw price distance         |
//+------------------------------------------------------------------+
double DistanceToPrice(double value)
  {
   if(InpTargetMode == MODE_PRICE_POINTS)
      return value;

   // MODE_MONEY_USD: convert a target profit (USD) into a price distance
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || InpLots <= 0.0)
      return value; // fallback: treat as price distance

   // profit = (priceDistance / tickSize) * tickValue * lots
   // => priceDistance = target * tickSize / (tickValue * lots)
   double priceDistance = value * tickSize / (tickValue * InpLots);
   return priceDistance;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   maHandle = iMA(_Symbol, InpTrendTF, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
   if(maHandle == INVALID_HANDLE)
     {
      Print("Failed to create MA handle");
      return(INIT_FAILED);
     }

   // Report resolved distances so the user can sanity-check the setup
   double tpP    = DistanceToPrice(InpTakeProfit);
   double slP    = DistanceToPrice(InpStopLoss);
   double startP = DistanceToPrice(InpTrailStart);
   double distP  = DistanceToPrice(InpTrailDistance);
   PrintFormat("Resolved distances (price): TP=%.5f  SL=%.5f  TrailStart=%.5f  TrailDist=%.5f",
               tpP, slP, startP, distP);
   PrintFormat("Broker min stop distance: %d points (%.5f price)",
               (int)g_stopsLevelPts, g_stopsLevelPts * g_point);

   double minStopPrice = g_stopsLevelPts * g_point;
   if(slP < minStopPrice || tpP < minStopPrice || distP < minStopPrice)
      Print("WARNING: One or more distances are below the broker minimum stop level. "
            "Orders/trailing modifications may be rejected. Increase the distance or use a broker with tighter stops.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
  }

//+------------------------------------------------------------------+
//| Return +1 for uptrend, -1 for downtrend, 0 for undecided         |
//+------------------------------------------------------------------+
int TrendDirection()
  {
   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 1, ma) < 1)   // last CLOSED higher-TF bar
      return 0;

   double closeHTF = iClose(_Symbol, InpTrendTF, 1);
   if(closeHTF <= 0.0)
      return 0;

   if(closeHTF > ma[0]) return  1;   // price above MA -> uptrend
   if(closeHTF < ma[0]) return -1;   // price below MA -> downtrend
   return 0;
  }

//+------------------------------------------------------------------+
//| Is there already a position for this symbol/magic?               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Open a trade in the given direction                              |
//+------------------------------------------------------------------+
void OpenTrade(int dir)
  {
   double tpDist = DistanceToPrice(InpTakeProfit);
   double slDist = DistanceToPrice(InpStopLoss);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(dir > 0) // BUY
     {
      double price = ask;
      double sl = NormalizeDouble(price - slDist, g_digits);
      double tp = NormalizeDouble(price + tpDist, g_digits);
      if(!trade.Buy(InpLots, _Symbol, price, sl, tp, "TrendTrailing BUY"))
         PrintFormat("Buy failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else if(dir < 0) // SELL
     {
      double price = bid;
      double sl = NormalizeDouble(price + slDist, g_digits);
      double tp = NormalizeDouble(price - tpDist, g_digits);
      if(!trade.Sell(InpLots, _Symbol, price, sl, tp, "TrendTrailing SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Trailing stop management                                         |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double startDist = DistanceToPrice(InpTrailStart);
   double trailDist = DistanceToPrice(InpTrailDistance);
   double stepDist  = DistanceToPrice(InpTrailStep);
   double minStop   = g_stopsLevelPts * g_point;
   if(trailDist < minStop) trailDist = minStop;   // respect broker minimum

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)      continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic)    continue;

      long   type    = PositionGetInteger(POSITION_TYPE);
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitMove = bid - entry;
         if(profitMove < startDist) continue;              // not enough progress yet

         double newSL = NormalizeDouble(bid - trailDist, g_digits);
         if(bid - newSL < minStop) continue;               // too close to price
         if(newSL <= curSL + stepDist) continue;           // only move up, by at least a step

         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("BUY trail modify failed: %d %s",
                        trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitMove = entry - ask;
         if(profitMove < startDist) continue;              // not enough progress yet

         double newSL = NormalizeDouble(ask + trailDist, g_digits);
         if(newSL - ask < minStop) continue;               // too close to price
         if(curSL != 0.0 && newSL >= curSL - stepDist) continue; // only move down, by at least a step

         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("SELL trail modify failed: %d %s",
                        trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1) Manage trailing on any open position first
   ManageTrailing();

   // 2) Entry logic
   if(InpOnePosition && HasOpenPosition())
      return;

   int dir = TrendDirection();
   if(dir != 0)
      OpenTrade(dir);
  }
//+------------------------------------------------------------------+
