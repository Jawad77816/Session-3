//+------------------------------------------------------------------+
//|                                           PivotRejectionEA.mq5    |
//|                                                                  |
//|  Strategy:                                                       |
//|   - Draw daily pivot points as continuous horizontal S/R lines.  |
//|   - When a completed candle REJECTS a pivot level (wick pierces   |
//|     the level, body closes back on the other side) -> trade in    |
//|     the rejection direction.                                      |
//|       * Wick above a level, bearish close below it  -> SELL       |
//|       * Wick below a level, bullish close above it  -> BUY        |
//|   - Fixed TP / SL (default TP = 1 USD, SL = 6 USD on 0.01 lot).   |
//|   - Same PKT session window and news filter as TrendTrailingEA.   |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- How the distance inputs are interpreted
enum ENUM_TARGET_MODE
  {
   MODE_MONEY_USD    = 0,  // Inputs are in account currency (USD) per trade
   MODE_PRICE_POINTS = 1   // Inputs are in raw price distance (e.g. 6.0 = 6.00)
  };

//============================ INPUTS ================================//
input group "=== Entry / Targets ==="
input double             InpLots           = 0.01;           // Lot size
input long               InpMagic          = 990044;         // Magic number
input ENUM_TARGET_MODE   InpTargetMode     = MODE_MONEY_USD; // How TP/SL inputs are read
input double             InpTakeProfit     = 1.0;            // Take profit (USD or price)
input double             InpStopLoss       = 6.0;            // Stop loss  (USD or price)
input ENUM_TIMEFRAMES    InpSignalTF       = PERIOD_CURRENT; // Timeframe whose candles are checked for rejections
input double             InpRejectionBuffer = 0.0;           // Extra distance (USD/price) the body must close beyond the level
input bool               InpOneTradeAtATime = true;          // Only one open position at a time

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

input group "=== Pivot Points ==="
input bool               InpShowPivots      = true;          // Draw pivot S/R lines
input ENUM_TIMEFRAMES    InpPivotTF         = PERIOD_D1;     // Pivot calculation timeframe

//============================ GLOBALS ==============================//
CTrade    trade;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

datetime  g_newsTimes[];
datetime  g_lastPivotPeriod = 0;
datetime  g_lastSignalBar   = 0;

double    g_levels[7];          // P, R1, R2, R3, S1, S2, S3
int       g_numLevels = 7;

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

   ArrayInitialize(g_levels, 0.0);
   ParseNewsList();

   PrintFormat("Resolved (price): TP=%.5f SL=%.5f  | Session PKT %02d:00-%02d:00 | Broker GMT offset %+d",
               DistanceToPrice(InpTakeProfit), DistanceToPrice(InpStopLoss),
               InpStartHourPKT, InpEndHourPKT, InpBrokerGMTOffset);
   PrintFormat("Broker min stop distance: %d points (%.5f price) | Manual news entries: %d",
               (int)g_stopsLevelPts, g_stopsLevelPts * g_point, ArraySize(g_newsTimes));

   double slP = DistanceToPrice(InpStopLoss);
   double tpP = DistanceToPrice(InpTakeProfit);
   double minStopPrice = g_stopsLevelPts * g_point;
   if(slP < minStopPrice || tpP < minStopPrice)
      Print("WARNING: TP or SL is below the broker minimum stop level; orders may be rejected.");
   if(DistanceToPrice(InpTakeProfit) < DistanceToPrice(InpStopLoss))
      Print("NOTE: TP is smaller than SL (risk:reward is against you). Needs a high win rate to be profitable.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "PIV_");
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
//| MT5 economic-calendar blackout (live only), throttled to 60s     |
//+------------------------------------------------------------------+
bool CalendarBlackout()
  {
   if(!InpUseCalendarAuto) return false;

   datetime now = TimeCurrent();
   if(now - g_calLastCheck < 60)
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
      if(!trade.Buy(InpLots, _Symbol, ask, sl, tp, "PivotRejection BUY"))
         PrintFormat("Buy failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else if(dir < 0)
     {
      double sl = NormalizeDouble(bid + slDist, g_digits);
      double tp = NormalizeDouble(bid - tpDist, g_digits);
      if(!trade.Sell(InpLots, _Symbol, bid, sl, tp, "PivotRejection SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
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
   if(H <= 0 || L <= 0 || C <= 0) return;

   double P  = (H + L + C) / 3.0;
   double R1 = 2 * P - L;
   double S1 = 2 * P - H;
   double R2 = P + (H - L);
   double S2 = P - (H - L);
   double R3 = H + 2 * (P - L);
   double S3 = L - 2 * (H - P);

   // store for the rejection logic
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
   UpdatePivots();

   if(!IsNewSignalBar()) return;          // evaluate only on candle close

   if(!IsWithinSession() || IsNewsBlackout()) return;
   if(InpOneTradeAtATime && CountPositions() > 0) return;

   int dir;
   if(CheckRejection(dir))
      OpenTrade(dir);
  }
//+------------------------------------------------------------------+
