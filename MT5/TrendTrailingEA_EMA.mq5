//+------------------------------------------------------------------+
//|                                             TrendTrailingEA.mq5   |
//|                                                                  |
//|  Strategy:                                                       |
//|   1. Trend via a 200/20/50 EMA stack: price vs 200 EMA is the     |
//|      gate, confirmed by 20/50 EMA alignment. Any timeframe.       |
//|   2. Open a 0.01 lot trade ONLY when a candle rejects a pivot     |
//|      level IN the trend direction, with fixed TP/SL (default      |
//|      6 USD each on 0.01 lot Gold => a 6.00 price move).           |
//|   3. Trailing stop that activates after a small favourable move.  |
//|                                                                  |
//|  Added features:                                                 |
//|   - Entry is gated by a pivot-point rejection aligned with trend  |
//|     (bullish rejection at support in an uptrend -> buy, etc.).    |
//|   - Runs 24/7 (no session window); only a news halt blocks entry. |
//|   - No NEW trades during a news blackout, but running trades are  |
//|     left to hit their own TP/SL.                                  |
//|   - News filter (manual list + optional MT5 economic calendar),   |
//|     30 min before -> 30 min after.                                |
//|   - Grid: every N USD the price moves AGAINST the first trade,    |
//|     add another trade in the same direction (same lot/TP/SL/      |
//|     trailing).  *** Averaging into losers - high risk. ***        |
//|   - Daily pivot points drawn as continuous horizontal S/R lines.  |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "3.10"
#property strict

#include <Trade/Trade.mqh>

//--- How the distance inputs are interpreted
enum ENUM_TARGET_MODE
  {
   MODE_MONEY_USD    = 0,  // Inputs are in account currency (USD) per trade
   MODE_PRICE_POINTS = 1   // Inputs are in raw price distance (e.g. 6.0 = 6.00)
  };

//--- Pivot calculation method
enum ENUM_PIVOT_METHOD
  {
   PIVOT_STANDARD  = 0,   // Classic / Floor pivots
   PIVOT_FIBONACCI = 1,   // Fibonacci pivots
   PIVOT_CAMARILLA = 2,   // Camarilla pivots
   PIVOT_WOODIE    = 3    // Woodie pivots
  };

//============================ INPUTS ================================//
input group "=== Trend Filter (200/20/50 EMA stack) ==="
input ENUM_TIMEFRAMES    InpTrendTF            = PERIOD_CURRENT; // Timeframe for the trend EMAs (CURRENT = chart TF, applies to any TF)
input int                InpEMATrend           = 200;           // Master trend EMA (price above=up, below=down)
input int                InpEMAFast            = 20;            // Fast EMA (20>50 confirms buy, 20<50 confirms sell)
input int                InpEMASlow            = 50;            // Slow EMA
input bool               InpRequireTrendFilter = true;          // Enforce the 200-EMA direction gate (never counter-trend)
input bool               InpUseTrendSlope      = false;         // Also require the 200 EMA to be sloping (off by default)
input int                InpTrendSlopeBars     = 3;             // Slope measured over this many bars
input double             InpMinSlopeUSD        = 0.0;           // Min 200-EMA move (price) over those bars

input group "=== Entry ==="
input double             InpLots           = 0.01;           // Lot size
input long               InpMagic          = 990033;         // Magic number

input group "=== Pivot-Rejection Entry Trigger ==="
input ENUM_TIMEFRAMES    InpSignalTF       = PERIOD_CURRENT; // Timeframe whose candles are checked for rejections
input double             InpRejectionBuffer = 0.0;           // Extra distance (USD/price) the body must close beyond the level

input group "=== Targets & Trailing ==="
input ENUM_TARGET_MODE   InpTargetMode     = MODE_MONEY_USD; // How TP/SL/trailing inputs are read
input double             InpTakeProfit     = 6.0;            // Take profit (USD or price)
input double             InpStopLoss       = 6.0;            // Stop loss  (USD or price)
input double             InpTrailStart     = 0.3;            // Favourable move before trailing starts
input double             InpTrailDistance  = 0.3;            // Gap kept between price and trailing SL
input double             InpTrailStep      = 0.05;           // Min SL improvement before it is moved

input group "=== Time (broker offset for news) ==="
input int                InpBrokerGMTOffset = 3;             // Broker server GMT offset in hours (only used to read manual news PKT times)

input group "=== News Filter ==="
input bool               InpUseNewsFilter   = true;          // Enable news blackout
input int                InpNewsMinsBefore  = 30;            // Stop trading this many minutes BEFORE news
input int                InpNewsMinsAfter   = 30;            // Resume this many minutes AFTER news
input string             InpManualNewsPKT   = "";            // Manual news times PKT, comma sep: "2026.07.28 17:30,2026.07.29 12:30"
input bool               InpUseCalendarAuto = true;          // Also use MT5 economic calendar (live only)
input int                InpNewsImportance  = 3;             // Min importance: 1=Low 2=Moderate 3=High
input string             InpNewsCurrencies  = "USD";         // Currencies to watch (comma sep), "" = all

input group "=== Grid (average into adverse moves) ==="
input bool               InpEnableGrid      = true;          // Add trades as price moves against the first
input double             InpGridStepUSD     = 4.0;           // Adverse move per added trade (USD or price)
input int                InpMaxGridTrades   = 5;             // Max total trades in a cycle (incl. first)

input group "=== Pivot Points ==="
input bool               InpShowPivots      = true;          // Draw pivot S/R lines
input ENUM_PIVOT_METHOD  InpPivotMethod     = PIVOT_STANDARD;// Pivot calculation method
input ENUM_TIMEFRAMES    InpPivotTF         = PERIOD_D1;     // Pivot calculation timeframe

//============================ GLOBALS ==============================//
CTrade    trade;
int       maTrendH = INVALID_HANDLE;
int       maFastH  = INVALID_HANDLE;
int       maSlowH  = INVALID_HANDLE;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

datetime  g_newsTimes[];        // parsed manual news times (PKT wall-clock)
datetime  g_lastPivotPeriod = 0;
datetime  g_lastSignalBar   = 0;

double    g_levels[7];          // P, R1, R2, R3, S1, S2, S3 (for rejection detection)
int       g_numLevels = 7;

// calendar throttle
bool      g_calBlackout   = false;
datetime  g_calLastCheck  = 0;

//+------------------------------------------------------------------+
//| Convert a "USD or price" input into a raw price distance         |
//+------------------------------------------------------------------+
double DistanceToPrice(double value)
  {
   if(InpTargetMode == MODE_PRICE_POINTS)
      return value;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || InpLots <= 0.0)
      return value;
   return value * tickSize / (tickValue * InpLots);
  }

//+------------------------------------------------------------------+
//| Server time -> PKT wall-clock (UTC+5)                            |
//+------------------------------------------------------------------+
datetime PKTNow()
  {
   // PKT = GMT+5;  GMT = server - offset;  so PKT = server + (5 - offset)
   int shiftSec = (5 - InpBrokerGMTOffset) * 3600;
   return (datetime)((long)TimeCurrent() + shiftSec);
  }

//+------------------------------------------------------------------+
//| Parse the manual news list (PKT wall-clock datetimes)            |
//+------------------------------------------------------------------+
void ParseNewsList()
  {
   ArrayFree(g_newsTimes);
   string parts[];
   int n = StringSplit(InpManualNewsPKT, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "") continue;
      datetime t = StringToTime(s);
      if(t > 0)
        {
         int sz = ArraySize(g_newsTimes);
         ArrayResize(g_newsTimes, sz + 1);
         g_newsTimes[sz] = t;
        }
     }
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

   maTrendH = iMA(_Symbol, InpTrendTF, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE);
   maFastH  = iMA(_Symbol, InpTrendTF, InpEMAFast,  0, MODE_EMA, PRICE_CLOSE);
   maSlowH  = iMA(_Symbol, InpTrendTF, InpEMASlow,  0, MODE_EMA, PRICE_CLOSE);
   if(maTrendH == INVALID_HANDLE || maFastH == INVALID_HANDLE || maSlowH == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle(s)");
      return(INIT_FAILED);
     }

   ParseNewsList();

   double tpP    = DistanceToPrice(InpTakeProfit);
   double slP    = DistanceToPrice(InpStopLoss);
   double startP = DistanceToPrice(InpTrailStart);
   double distP  = DistanceToPrice(InpTrailDistance);
   PrintFormat("Resolved (price): TP=%.5f SL=%.5f TrailStart=%.5f TrailDist=%.5f GridStep=%.5f",
               tpP, slP, startP, distP, DistanceToPrice(InpGridStepUSD));
   PrintFormat("Broker min stop distance: %d points (%.5f price)",
               (int)g_stopsLevelPts, g_stopsLevelPts * g_point);
   PrintFormat("24/7 mode | Broker GMT offset %+d | News blackout %d/%d min | Manual news entries: %d",
               InpBrokerGMTOffset, InpNewsMinsBefore, InpNewsMinsAfter, ArraySize(g_newsTimes));

   double minStopPrice = g_stopsLevelPts * g_point;
   if(slP < minStopPrice || tpP < minStopPrice || distP < minStopPrice)
      Print("WARNING: A distance is below the broker minimum stop level; orders/trailing may be rejected.");
   if(InpEnableGrid)
      Print("WARNING: Grid mode averages into losing trades. Risk grows with each added trade. Use a wide SL and test carefully.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(maTrendH != INVALID_HANDLE) IndicatorRelease(maTrendH);
   if(maFastH  != INVALID_HANDLE) IndicatorRelease(maFastH);
   if(maSlowH  != INVALID_HANDLE) IndicatorRelease(maSlowH);
   ObjectsDeleteAll(0, "PIV_");
  }

//+------------------------------------------------------------------+
//| Trend: +1 up, -1 down, 0 undecided                               |
//+------------------------------------------------------------------+
int TrendDirection()
  {
   double t[], f[], sl[];
   if(CopyBuffer(maTrendH, 0, 1, 1, t)  < 1) return 0;
   if(CopyBuffer(maFastH,  0, 1, 1, f)  < 1) return 0;
   if(CopyBuffer(maSlowH,  0, 1, 1, sl) < 1) return 0;
   double emaTrend = t[0], emaFast = f[0], emaSlow = sl[0];
   double close = iClose(_Symbol, InpTrendTF, 1);
   if(close <= 0 || emaTrend <= 0 || emaFast <= 0 || emaSlow <= 0) return 0;

   // Optional: require the 200 EMA to be sloping (off by default)
   double slope = 0.0;
   if(InpUseTrendSlope)
     {
      double tN[];
      int bars = (int)MathMax(1, InpTrendSlopeBars);
      if(CopyBuffer(maTrendH, 0, 1 + bars, 1, tN) < 1) return 0;
      slope = emaTrend - tN[0];
     }

   // 200 EMA gate (mandatory when InpRequireTrendFilter); 20/50 alignment always required.
   bool buyGate  = InpRequireTrendFilter ? (close > emaTrend) : true;
   bool sellGate = InpRequireTrendFilter ? (close < emaTrend) : true;

   if(buyGate  && emaFast > emaSlow && (!InpUseTrendSlope || slope >=  InpMinSlopeUSD)) return  1;
   if(sellGate && emaFast < emaSlow && (!InpUseTrendSlope || slope <= -InpMinSlopeUSD)) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| MT5 economic-calendar blackout (live only), throttled to 60s     |
//+------------------------------------------------------------------+
bool CalendarBlackout()
  {
   if(!InpUseCalendarAuto) return false;

   datetime now = TimeCurrent();
   if(now - g_calLastCheck < 60)      // reuse cached result within the minute
      return g_calBlackout;
   g_calLastCheck = now;
   g_calBlackout  = false;

   MqlCalendarValue values[];
   datetime from = now - 12 * 3600;
   datetime to   = now + 12 * 3600;
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt)) continue;
      if((int)evt.importance < InpNewsImportance) continue;

      if(InpNewsCurrencies != "")
        {
         MqlCalendarCountry country;
         if(!CalendarCountryById((long)evt.country_id, country)) continue;
         if(StringFind(InpNewsCurrencies, country.currency) < 0) continue;
        }

      datetime et = values[i].time;
      if(now >= et - InpNewsMinsBefore * 60 && now <= et + InpNewsMinsAfter * 60)
        {
         g_calBlackout = true;
         break;
        }
     }
   return g_calBlackout;
  }

//+------------------------------------------------------------------+
//| Are we in a news blackout right now?                             |
//+------------------------------------------------------------------+
bool IsNewsBlackout()
  {
   if(!InpUseNewsFilter) return false;

   datetime nowPKT = PKTNow();
   for(int i = 0; i < ArraySize(g_newsTimes); i++)
     {
      datetime et = g_newsTimes[i];
      if(nowPKT >= et - InpNewsMinsBefore * 60 && nowPKT <= et + InpNewsMinsAfter * 60)
         return true;
     }
   return CalendarBlackout();
  }

//+------------------------------------------------------------------+
//| Count positions belonging to this EA on this symbol              |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         c++;
     }
   return c;
  }

//+------------------------------------------------------------------+
//| Find the FIRST (oldest) trade of the current cycle               |
//+------------------------------------------------------------------+
bool FindBasePosition(double &basePrice, long &baseType)
  {
   datetime oldest = 0;
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(!found || ot < oldest)
        {
         oldest    = ot;
         basePrice = PositionGetDouble(POSITION_PRICE_OPEN);
         baseType  = PositionGetInteger(POSITION_TYPE);
         found     = true;
        }
     }
   return found;
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

   if(dir > 0)
     {
      double sl = NormalizeDouble(ask - slDist, g_digits);
      double tp = NormalizeDouble(ask + tpDist, g_digits);
      if(!trade.Buy(InpLots, _Symbol, ask, sl, tp, "TrendTrailing BUY"))
         PrintFormat("Buy failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else if(dir < 0)
     {
      double sl = NormalizeDouble(bid + slDist, g_digits);
      double tp = NormalizeDouble(bid - tpDist, g_digits);
      if(!trade.Sell(InpLots, _Symbol, bid, sl, tp, "TrendTrailing SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Grid: add same-direction trades as price moves against the first |
//+------------------------------------------------------------------+
void ManageGrid()
  {
   int n = CountPositions();
   if(n <= 0 || n >= InpMaxGridTrades) return;

   double basePrice;
   long   baseType;
   if(!FindBasePosition(basePrice, baseType)) return;

   double step = DistanceToPrice(InpGridStepUSD);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(baseType == POSITION_TYPE_SELL)
     {
      double adverse = bid - basePrice;          // price rising = against a sell
      if(adverse >= step * n)
         OpenTrade(-1);
     }
   else if(baseType == POSITION_TYPE_BUY)
     {
      double adverse = basePrice - ask;          // price falling = against a buy
      if(adverse >= step * n)
         OpenTrade(+1);
     }
  }

//+------------------------------------------------------------------+
//| Trailing stop for every position of this EA                      |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double startDist = DistanceToPrice(InpTrailStart);
   double trailDist = DistanceToPrice(InpTrailDistance);
   double stepDist  = DistanceToPrice(InpTrailStep);
   double minStop   = g_stopsLevelPts * g_point;
   if(trailDist < minStop) trailDist = minStop;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - entry < startDist) continue;
         double newSL = NormalizeDouble(bid - trailDist, g_digits);
         if(bid - newSL < minStop) continue;
         if(newSL <= curSL + stepDist) continue;
         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("BUY trail failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(entry - ask < startDist) continue;
         double newSL = NormalizeDouble(ask + trailDist, g_digits);
         if(newSL - ask < minStop) continue;
         if(curSL != 0.0 && newSL >= curSL - stepDist) continue;
         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("SELL trail failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw / refresh one horizontal (continuous) line                  |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, int style, int width, string label)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0,  name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0,  name, OBJPROP_TEXT, label);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, label);
  }

//+------------------------------------------------------------------+
//| Compute pivot levels for the selected method                     |
//+------------------------------------------------------------------+
void ComputePivots(double H, double L, double C, double O,
                   double &P, double &R1, double &R2, double &R3,
                   double &S1, double &S2, double &S3)
  {
   double range = H - L;

   switch(InpPivotMethod)
     {
      case PIVOT_FIBONACCI:
         P  = (H + L + C) / 3.0;
         R1 = P + 0.382 * range;   S1 = P - 0.382 * range;
         R2 = P + 0.618 * range;   S2 = P - 0.618 * range;
         R3 = P + 1.000 * range;   S3 = P - 1.000 * range;
         break;

      case PIVOT_CAMARILLA:
         P  = (H + L + C) / 3.0;   // reference pivot (Camarilla levels are off close)
         R1 = C + range * 1.1 / 12.0;  S1 = C - range * 1.1 / 12.0;
         R2 = C + range * 1.1 /  6.0;  S2 = C - range * 1.1 /  6.0;
         R3 = C + range * 1.1 /  4.0;  S3 = C - range * 1.1 /  4.0;
         break;

      case PIVOT_WOODIE:
         P  = (H + L + 2.0 * O) / 4.0;   // uses current period open
         R1 = 2 * P - L;   S1 = 2 * P - H;
         R2 = P + range;   S2 = P - range;
         R3 = H + 2 * (P - L);   S3 = L - 2 * (H - P);
         break;

      default: // PIVOT_STANDARD
         P  = (H + L + C) / 3.0;
         R1 = 2 * P - L;   S1 = 2 * P - H;
         R2 = P + range;   S2 = P - range;
         R3 = H + 2 * (P - L);   S3 = L - 2 * (H - P);
         break;
     }
  }

//+------------------------------------------------------------------+
//| Recompute + redraw pivots when a new pivot period starts         |
//+------------------------------------------------------------------+
void UpdatePivots()
  {
   datetime curPeriod = iTime(_Symbol, InpPivotTF, 0);
   if(curPeriod == 0 || curPeriod == g_lastPivotPeriod) return;

   double H = iHigh(_Symbol,  InpPivotTF, 1);
   double L = iLow(_Symbol,   InpPivotTF, 1);
   double C = iClose(_Symbol, InpPivotTF, 1);
   double O = iOpen(_Symbol,  InpPivotTF, 0);   // current period open (Woodie)
   if(H <= 0 || L <= 0 || C <= 0) return;

   double P, R1, R2, R3, S1, S2, S3;
   ComputePivots(H, L, C, O, P, R1, R2, R3, S1, S2, S3);

   // store for the rejection entry logic (needed even if lines are hidden)
   g_levels[0] = P;
   g_levels[1] = R1;
   g_levels[2] = R2;
   g_levels[3] = R3;
   g_levels[4] = S1;
   g_levels[5] = S2;
   g_levels[6] = S3;

   if(InpShowPivots)
     {
      DrawHLine("PIV_P",  P,  clrGold,       STYLE_SOLID, 2, "Pivot");
      DrawHLine("PIV_R1", R1, clrTomato,     STYLE_DOT,   1, "R1");
      DrawHLine("PIV_R2", R2, clrTomato,     STYLE_DOT,   1, "R2");
      DrawHLine("PIV_R3", R3, clrTomato,     STYLE_DASH,  1, "R3");
      DrawHLine("PIV_S1", S1, clrDodgerBlue, STYLE_DOT,   1, "S1");
      DrawHLine("PIV_S2", S2, clrDodgerBlue, STYLE_DOT,   1, "S2");
      DrawHLine("PIV_S3", S3, clrDodgerBlue, STYLE_DASH,  1, "S3");
      ChartRedraw();
     }

   g_lastPivotPeriod = curPeriod;
  }

//+------------------------------------------------------------------+
//| Detect a pivot-level rejection on the last closed candle         |
//|  dir = +1 buy, -1 sell, 0 none/ambiguous                         |
//+------------------------------------------------------------------+
bool CheckRejection(int &dir)
  {
   dir = 0;
   double buf = DistanceToPrice(InpRejectionBuffer);

   double O = iOpen(_Symbol,  InpSignalTF, 1);
   double H = iHigh(_Symbol,  InpSignalTF, 1);
   double L = iLow(_Symbol,   InpSignalTF, 1);
   double C = iClose(_Symbol, InpSignalTF, 1);
   if(O <= 0 || H <= 0 || L <= 0 || C <= 0) return false;

   int sellVotes = 0, buyVotes = 0;
   for(int i = 0; i < g_numLevels; i++)
     {
      double lvl = g_levels[i];
      if(lvl <= 0) continue;

      // Bearish rejection at resistance: wick pierced above, body closed below
      if(H >= lvl && C <= lvl - buf && C < O)
         sellVotes++;

      // Bullish rejection at support: wick pierced below, body closed above
      if(L <= lvl && C >= lvl + buf && C > O)
         buyVotes++;
     }

   if(sellVotes > 0 && buyVotes == 0) { dir = -1; return true; }
   if(buyVotes  > 0 && sellVotes == 0) { dir =  1; return true; }
   return false;   // none, or conflicting signals -> skip
  }

//+------------------------------------------------------------------+
//| True once per newly-closed signal-timeframe candle               |
//+------------------------------------------------------------------+
bool IsNewSignalBar()
  {
   datetime t = iTime(_Symbol, InpSignalTF, 0);
   if(t == 0 || t == g_lastSignalBar) return false;
   g_lastSignalBar = t;
   return true;
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdatePivots();        // pivots (also stores levels for rejection entries)
   ManageTrailing();      // always manage exits, even outside the session

   // Track candle closes every tick so rejections are only ever acted on once,
   // and rejections that occur while a position is open are consumed (ignored).
   bool newBar = IsNewSignalBar();

   if(IsNewsBlackout()) return;   // 24/7: only a news blackout blocks new entries

   int positions = CountPositions();
   if(positions == 0)
     {
      // First trade of a cycle: only on a pivot rejection that agrees with trend.
      if(newBar)
        {
         int trend = TrendDirection();
         int rej;
         if(trend != 0 && CheckRejection(rej) && rej == trend)
            OpenTrade(trend);
        }
     }
   else if(InpEnableGrid)
     {
      // Position already open: TrendTrailing's 4-USD grid adds more (rejections
      // are ignored until flat, per configuration).
      ManageGrid();
     }
  }
//+------------------------------------------------------------------+
