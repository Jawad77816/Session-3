//+------------------------------------------------------------------+
//|                                             TrendTrailingEA.mq5   |
//|                                                                  |
//|  Strategy:                                                       |
//|   1. Trend on a higher (configurable) timeframe via a moving      |
//|      average filter.                                              |
//|   2. Open a 0.01 lot trade ONLY when a candle rejects a pivot     |
//|      level IN the trend direction, with fixed TP/SL (default      |
//|      6 USD each on 0.01 lot Gold => a 6.00 price move).           |
//|   3. Trailing stop that activates after a small favourable move.  |
//|                                                                  |
//|  Features:                                                       |
//|   - Entry gated by a pivot-point rejection aligned with trend.    |
//|   - Session window in PKT (default 12:00-20:00); running trades   |
//|     are never force-closed.                                       |
//|   - News filter (manual list + optional MT5 economic calendar).   |
//|   - Grid: every N USD of adverse move against the FIRST trade,    |
//|     add another same-direction trade. PRICE-DRIVEN ONLY - never   |
//|     waits for a rejection.  *** Averaging into losers - risk. *** |
//|   - Pivots (Standard/Fibonacci/Camarilla/Woodie) as continuous    |
//|     horizontal lines.                                             |
//|   - On-chart dashboard (left side) + optional debug journal logs. |
//|                                                                  |
//|  v4.00 changes:                                                  |
//|   - Trailing hardened: silent skip conditions removed, every      |
//|     failed modify is logged, optional debug log of every move.    |
//|   - Grid adds decoupled from session/news gate by default         |
//|     (InpGridRespectFilters to re-enable the old behaviour).       |
//|   - Dashboard: session, news, trend, SL/TP, trailing state,       |
//|     next grid add, floating P/L, spread, balance/equity.          |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "4.00"
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
input group "=== Trend Filter (higher timeframe) ==="
input ENUM_TIMEFRAMES    InpTrendTF        = PERIOD_H1;      // Higher timeframe for trend
input int                InpMAPeriod       = 50;             // Trend MA period
input ENUM_MA_METHOD     InpMAMethod       = MODE_EMA;       // Trend MA method
input ENUM_APPLIED_PRICE InpMAPrice        = PRICE_CLOSE;    // Trend MA applied price

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

input group "=== Session (Pakistan time, PKT = UTC+5) ==="
input int                InpBrokerGMTOffset = 3;             // Broker server GMT offset in hours (e.g. +2 or +3)
input int                InpStartHourPKT    = 12;            // Start hour PKT (12 = 12:00 PM)
input int                InpEndHourPKT      = 20;            // End hour PKT (20 = 8:00 PM) - no new trades from here

input group "=== News Filter ==="
input bool               InpUseNewsFilter   = true;          // Enable news blackout
input int                InpNewsMinsBefore  = 15;            // Stop trading this many minutes BEFORE news
input int                InpNewsMinsAfter   = 15;            // Resume this many minutes AFTER news
input string             InpManualNewsPKT   = "";            // Manual news times PKT, comma sep: "2026.07.28 17:30,2026.07.29 12:30"
input bool               InpUseCalendarAuto = true;          // Also use MT5 economic calendar (live only)
input int                InpNewsImportance  = 3;             // Min importance: 1=Low 2=Moderate 3=High
input string             InpNewsCurrencies  = "USD";         // Currencies to watch (comma sep), "" = all

input group "=== Grid (average into adverse moves) ==="
input bool               InpEnableGrid      = true;          // Add trades as price moves against the first
input double             InpGridStepUSD     = 4.0;           // Adverse move per added trade (USD or price)
input int                InpMaxGridTrades   = 5;             // Max total trades in a cycle (incl. first)
input bool               InpGridRespectFilters = false;      // Grid adds also blocked by session window / news

input group "=== Pivot Points ==="
input bool               InpShowPivots      = true;          // Draw pivot S/R lines
input ENUM_PIVOT_METHOD  InpPivotMethod     = PIVOT_STANDARD;// Pivot calculation method
input ENUM_TIMEFRAMES    InpPivotTF         = PERIOD_D1;     // Pivot calculation timeframe

input group "=== Dashboard & Debug ==="
input bool               InpShowDashboard   = true;          // Show info panel on the chart (left side)
input bool               InpDebugLogs       = false;         // Print trailing/grid decisions to the journal

//============================ GLOBALS ==============================//
CTrade    trade;
int       maHandle = INVALID_HANDLE;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

datetime  g_newsTimes[];        // parsed manual news times (PKT wall-clock)
datetime  g_lastPivotPeriod = 0;
datetime  g_lastSignalBar   = 0;

double    g_levels[7];          // P, R1, R2, R3, S1, S2, S3 (for rejection detection)
int       g_numLevels = 7;

// calendar cache (refreshed at most once per 60s)
bool      g_calBlackout   = false;
datetime  g_calLastCheck  = 0;
datetime  g_calNextTime   = 0;   // server time of nearest upcoming calendar event
string    g_calNextName   = "";

//--- everything the EA knows about the currently open cycle
struct CycleInfo
  {
   int      count;
   long     baseType;
   ulong    baseTicket;
   double   basePrice;
   double   baseSL;
   double   baseTP;
   double   totalLots;
   double   floatPL;
   datetime baseTime;
  };

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
//| Convert a raw price distance into account money (for display)    |
//+------------------------------------------------------------------+
double MoneyFromDistance(double dist)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return 0.0;
   return dist / tickSize * tickValue * InpLots;
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
//| Short name of a timeframe ("H1", "M15", ...)                     |
//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf)
  {
   if(tf == PERIOD_CURRENT)
      tf = (ENUM_TIMEFRAMES)_Period;
   return StringSubstr(EnumToString(tf), 7);
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

   maHandle = iMA(_Symbol, InpTrendTF, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
   if(maHandle == INVALID_HANDLE)
     {
      Print("Failed to create MA handle");
      return(INIT_FAILED);
     }

   ArrayInitialize(g_levels, 0.0);
   ParseNewsList();
   EventSetTimer(1);   // keeps the dashboard clock alive between ticks

   PrintFormat("Resolved (price): TP=%.5f SL=%.5f TrailStart=%.5f TrailDist=%.5f GridStep=%.5f",
               DistanceToPrice(InpTakeProfit), DistanceToPrice(InpStopLoss),
               DistanceToPrice(InpTrailStart), DistanceToPrice(InpTrailDistance),
               DistanceToPrice(InpGridStepUSD));
   PrintFormat("Broker min stop distance: %d points (%.5f price)",
               (int)g_stopsLevelPts, g_stopsLevelPts * g_point);
   PrintFormat("Session PKT %02d:00-%02d:00 | Broker GMT offset %+d | Manual news entries: %d",
               InpStartHourPKT, InpEndHourPKT, InpBrokerGMTOffset, ArraySize(g_newsTimes));

   double minStopPrice = g_stopsLevelPts * g_point;
   if(DistanceToPrice(InpStopLoss) < minStopPrice ||
      DistanceToPrice(InpTakeProfit) < minStopPrice ||
      DistanceToPrice(InpTrailDistance) < minStopPrice)
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
   EventKillTimer();
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
   ObjectsDeleteAll(0, "PIV_");
   ObjectsDeleteAll(0, "DB_");
  }

//+------------------------------------------------------------------+
//| Trend: +1 up, -1 down, 0 undecided                               |
//+------------------------------------------------------------------+
int TrendDirection()
  {
   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 1, ma) < 1)
      return 0;
   double closeHTF = iClose(_Symbol, InpTrendTF, 1);
   if(closeHTF <= 0.0) return 0;
   if(closeHTF > ma[0]) return  1;
   if(closeHTF < ma[0]) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Within the PKT trading session?                                  |
//+------------------------------------------------------------------+
bool IsWithinSession()
  {
   MqlDateTime st;
   TimeToStruct(PKTNow(), st);
   return (st.hour >= InpStartHourPKT && st.hour < InpEndHourPKT);
  }

//+------------------------------------------------------------------+
//| MT5 economic-calendar scan (live only), cached for 60s.          |
//| Sets blackout state and the nearest upcoming event for the       |
//| dashboard.                                                       |
//+------------------------------------------------------------------+
bool CalendarBlackout()
  {
   if(!InpUseCalendarAuto) return false;

   datetime now = TimeCurrent();
   if(now - g_calLastCheck < 60)
      return g_calBlackout;
   g_calLastCheck = now;
   g_calBlackout  = false;
   g_calNextTime  = 0;
   g_calNextName  = "";

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
         g_calBlackout = true;

      if(et > now && (g_calNextTime == 0 || et < g_calNextTime))
        {
         g_calNextTime = et;
         g_calNextName = evt.name;
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
//| Nearest upcoming news event as display text                      |
//+------------------------------------------------------------------+
string NextNewsText()
  {
   datetime nowPKT  = PKTNow();
   datetime bestPKT = 0;
   string   label   = "";

   for(int i = 0; i < ArraySize(g_newsTimes); i++)
      if(g_newsTimes[i] > nowPKT && (bestPKT == 0 || g_newsTimes[i] < bestPKT))
        {
         bestPKT = g_newsTimes[i];
         label   = "manual";
        }

   if(g_calNextTime > 0)
     {
      datetime calPKT = (datetime)((long)g_calNextTime + (5 - InpBrokerGMTOffset) * 3600);
      if(calPKT > nowPKT && (bestPKT == 0 || calPKT < bestPKT))
        {
         bestPKT = calPKT;
         label   = g_calNextName;
        }
     }

   if(bestPKT == 0)
      return "none in next 12h";

   long secs = (long)(bestPKT - nowPKT);
   string cd = (secs >= 3600) ? StringFormat("%dh%02dm", (int)(secs / 3600), (int)((secs % 3600) / 60))
                              : StringFormat("%dm", (int)(secs / 60));
   string txt = StringFormat("%s PKT (in %s)", TimeToString(bestPKT, TIME_MINUTES), cd);
   if(label != "" && label != "manual")
      txt += " " + label;
   return txt;
  }

//+------------------------------------------------------------------+
//| Collect everything about the open cycle in one pass              |
//+------------------------------------------------------------------+
bool CollectCycle(CycleInfo &ci)
  {
   ci.count = 0;  ci.totalLots = 0;  ci.floatPL = 0;
   ci.baseTicket = 0;  ci.basePrice = 0;  ci.baseSL = 0;  ci.baseTP = 0;
   ci.baseType = -1;  ci.baseTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      ci.count++;
      ci.totalLots += PositionGetDouble(POSITION_VOLUME);
      ci.floatPL   += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ci.baseTicket == 0 || ot < ci.baseTime)
        {
         ci.baseTime   = ot;
         ci.baseTicket = ticket;
         ci.basePrice  = PositionGetDouble(POSITION_PRICE_OPEN);
         ci.baseSL     = PositionGetDouble(POSITION_SL);
         ci.baseTP     = PositionGetDouble(POSITION_TP);
         ci.baseType   = PositionGetInteger(POSITION_TYPE);
        }
     }
   return (ci.count > 0);
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
//| Grid: purely price-driven adds against the FIRST trade.          |
//| Add #k opens once price is k * GridStep beyond the base entry.   |
//| Never waits for a rejection.                                     |
//+------------------------------------------------------------------+
void ManageGrid()
  {
   CycleInfo ci;
   if(!CollectCycle(ci)) return;
   if(ci.count >= InpMaxGridTrades) return;

   if(InpGridRespectFilters && (!IsWithinSession() || IsNewsBlackout()))
     {
      if(InpDebugLogs)
         Print("GRID: add suppressed by session/news filter (InpGridRespectFilters=true)");
      return;
     }

   double step = DistanceToPrice(InpGridStepUSD);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ci.baseType == POSITION_TYPE_SELL)
     {
      double adverse = bid - ci.basePrice;            // price rising = against a sell
      if(adverse >= step * ci.count)
        {
         if(InpDebugLogs)
            PrintFormat("GRID: adding SELL #%d (adverse %.5f >= %.5f)", ci.count + 1, adverse, step * ci.count);
         OpenTrade(-1);
        }
     }
   else if(ci.baseType == POSITION_TYPE_BUY)
     {
      double adverse = ci.basePrice - ask;            // price falling = against a buy
      if(adverse >= step * ci.count)
        {
         if(InpDebugLogs)
            PrintFormat("GRID: adding BUY #%d (adverse %.5f >= %.5f)", ci.count + 1, adverse, step * ci.count);
         OpenTrade(+1);
        }
     }
  }

//+------------------------------------------------------------------+
//| Trailing stop for every position of this EA.                     |
//| Runs every tick, never gated by session or news.                 |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double startDist = DistanceToPrice(InpTrailStart);
   double trailDist = DistanceToPrice(InpTrailDistance);
   double stepDist  = DistanceToPrice(InpTrailStep);
   double minStop   = g_stopsLevelPts * g_point;
   if(trailDist < minStop) trailDist = minStop;      // clamp instead of skipping

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
         if(bid - entry < startDist) continue;               // trailing not armed yet
         double newSL = NormalizeDouble(bid - trailDist, g_digits);
         if(newSL <= curSL) continue;                        // never loosen the stop
         if(curSL > 0 && newSL - curSL < stepDist - g_point * 0.5) continue; // move in >= step increments
         if(trade.PositionModify(ticket, newSL, curTP))
           {
            if(InpDebugLogs)
               PrintFormat("TRAIL BUY #%I64u: SL %.5f -> %.5f (bid %.5f)", ticket, curSL, newSL, bid);
           }
         else
            PrintFormat("TRAIL BUY #%I64u modify FAILED: %d %s",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(entry - ask < startDist) continue;               // trailing not armed yet
         double newSL = NormalizeDouble(ask + trailDist, g_digits);
         if(curSL > 0 && newSL >= curSL) continue;           // never loosen the stop
         if(curSL > 0 && curSL - newSL < stepDist - g_point * 0.5) continue; // move in >= step increments
         if(trade.PositionModify(ticket, newSL, curTP))
           {
            if(InpDebugLogs)
               PrintFormat("TRAIL SELL #%I64u: SL %.5f -> %.5f (ask %.5f)", ticket, curSL, newSL, ask);
           }
         else
            PrintFormat("TRAIL SELL #%I64u modify FAILED: %d %s",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }
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

//============================ DASHBOARD ============================//
//+------------------------------------------------------------------+
//| Background panel                                                 |
//+------------------------------------------------------------------+
void DashPanel()
  {
   string obj = "DB_bg";
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 22);
      ObjectSetInteger(0, obj, OBJPROP_XSIZE, 274);
      ObjectSetInteger(0, obj, OBJPROP_YSIZE, 278);
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'16,20,28');
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, C'70,80,100');
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| One text row of the dashboard                                    |
//+------------------------------------------------------------------+
void DashLabel(int row, string text, color clr)
  {
   string obj = StringFormat("DB_r%02d", row);
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 14);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 30 + row * 16);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0,  obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0,  obj, OBJPROP_TEXT, (text == "") ? " " : text);
  }

//+------------------------------------------------------------------+
//| Refresh the whole dashboard                                      |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;
   // objects are invisible in a non-visual tester run - skip the work
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   color cText = clrSilver, cGood = clrLimeGreen, cBad = clrTomato,
         cWarn = clrOrange, cHead = clrGold, cDim = C'90,100,120';

   DashPanel();
   int r = 0;

   DashLabel(r++, "TrendTrailingEA v4.0  " + _Symbol, cHead);

   MqlDateTime pt;
   TimeToStruct(PKTNow(), pt);
   DashLabel(r++, StringFormat("PKT %02d:%02d:%02d  (srv %s)",
             pt.hour, pt.min, pt.sec, TimeToString(TimeCurrent(), TIME_MINUTES)), cText);

   bool inSes = IsWithinSession();
   DashLabel(r++, StringFormat("Session: %s (%02d-%02d PKT)",
             inSes ? "OPEN" : "CLOSED", InpStartHourPKT, InpEndHourPKT),
             inSes ? cGood : cBad);

   bool blackout = IsNewsBlackout();
   DashLabel(r++, blackout ? "News: BLACKOUT - entries paused" : "News: clear",
             blackout ? cBad : cGood);
   DashLabel(r++, "Next: " + NextNewsText(), cText);

   int trend = TrendDirection();
   string ts = (trend > 0) ? "UP" : (trend < 0) ? "DOWN" : "FLAT";
   DashLabel(r++, StringFormat("Trend [%s MA%d]: %s", TFName(InpTrendTF), InpMAPeriod, ts),
             (trend > 0) ? cGood : (trend < 0) ? cBad : cText);

   string pm = (InpPivotMethod == PIVOT_FIBONACCI) ? "Fibonacci" :
               (InpPivotMethod == PIVOT_CAMARILLA) ? "Camarilla" :
               (InpPivotMethod == PIVOT_WOODIE)    ? "Woodie"    : "Standard";
   DashLabel(r++, StringFormat("Pivots: %s %s  P %.2f", pm, TFName(InpPivotTF), g_levels[0]), cText);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DashLabel(r++, StringFormat("Spread: %d pts", (int)MathRound((ask - bid) / g_point)), cText);

   DashLabel(r++, "-------------------------------", cDim);

   CycleInfo ci;
   if(!CollectCycle(ci))
     {
      DashLabel(r++, "Positions: none", cText);
      DashLabel(r++, "Waiting: trend-aligned pivot", cText);
      DashLabel(r++, "rejection on " + TFName(InpSignalTF) + " close", cText);
      DashLabel(r++, "", cText);
      DashLabel(r++, "", cText);
     }
   else
     {
      string side = (ci.baseType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      DashLabel(r++, StringFormat("Positions: %d/%d %s  %.2f lots",
                ci.count, InpMaxGridTrades, side, ci.totalLots),
                (ci.baseType == POSITION_TYPE_BUY) ? cGood : cBad);
      DashLabel(r++, StringFormat("Base %.2f SL %.2f TP %.2f",
                ci.basePrice, ci.baseSL, ci.baseTP), cText);

      double startDist = DistanceToPrice(InpTrailStart);
      double moved = (ci.baseType == POSITION_TYPE_BUY) ? (bid - ci.basePrice)
                                                        : (ci.basePrice - ask);
      if(moved >= startDist)
        {
         double lockedPrice = (ci.baseType == POSITION_TYPE_BUY)
                              ? (ci.baseSL - ci.basePrice)
                              : (ci.basePrice - ci.baseSL);
         DashLabel(r++, StringFormat("Trail: ACTIVE  SL locks %+.2f USD",
                   MoneyFromDistance(lockedPrice)), cGood);
        }
      else
         DashLabel(r++, StringFormat("Trail: arms at +%.2f (now %+.2f)", startDist, moved), cWarn);

      if(InpEnableGrid && ci.count < InpMaxGridTrades)
        {
         double step = DistanceToPrice(InpGridStepUSD);
         double nextAdd = (ci.baseType == POSITION_TYPE_SELL)
                          ? ci.basePrice + step * ci.count
                          : ci.basePrice - step * ci.count;
         DashLabel(r++, StringFormat("Grid: next add @ %.2f", nextAdd), cText);
        }
      else
         DashLabel(r++, InpEnableGrid ? "Grid: max trades reached" : "Grid: off", cWarn);

      DashLabel(r++, StringFormat("Float P/L: %+.2f USD", ci.floatPL),
                (ci.floatPL >= 0) ? cGood : cBad);
     }

   DashLabel(r++, StringFormat("Bal %.2f  Eq %.2f",
             AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)), cText);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Timer: keeps the dashboard clock alive between ticks             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdatePivots();                    // pivots + levels for rejection entries
   ManageTrailing();                  // exits managed every tick, never gated
   if(InpEnableGrid)
      ManageGrid();                   // price-driven adds, every tick

   bool newBar = IsNewSignalBar();    // consume the bar even when we can't trade

   UpdateDashboard();

   // ------- new-cycle entries only below this line -------
   if(!IsWithinSession() || IsNewsBlackout()) return;

   CycleInfo ci;
   if(CollectCycle(ci)) return;       // cycle already open: grid handles adds

   if(!newBar) return;                // evaluate rejections once per candle close

   int trend = TrendDirection();
   int rej;
   if(trend != 0 && CheckRejection(rej) && rej == trend)
     {
      if(InpDebugLogs)
         PrintFormat("ENTRY: trend %s + pivot rejection -> open", trend > 0 ? "UP" : "DOWN");
      OpenTrade(trend);
     }
  }
//+------------------------------------------------------------------+
