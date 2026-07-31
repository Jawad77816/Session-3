//+------------------------------------------------------------------+
//|                                                   ORB_SMC_EA.mq5  |
//|            Opening Range Breakout + Smart Money Concepts (FVG)    |
//|                                                                  |
//|  Implements the strategy from the "ORB Breakout + SMC" method:   |
//|    - Build the Opening Range from the first candle after the     |
//|      New York (9:30) session open on a chosen timeframe (M15).   |
//|    - Trade the breakout of the ORB high/low, with a preference   |
//|      for RETEST entries that overlap a Fair Value Gap (FVG).      |
//|    - Also fade FALSE breakouts (sweep + close back inside) using |
//|      an opposing FVG at the ORB level.                           |
//|    - Avoid trading straight into previous-day High/Low liquidity |
//|      (the most common mistake shown in the video).               |
//|                                                                  |
//|  NOTE: No EA is guaranteed profitable. This is a faithful,       |
//|  configurable implementation of the strategy. You MUST backtest  |
//|  and optimize inputs per instrument before any live use.         |
//+------------------------------------------------------------------+
#property copyright "ORB + SMC EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//==================================================================//
//                            INPUTS                                //
//==================================================================//

//--- Session / Opening Range ---------------------------------------
enum ENUM_TIME_MODE
{
   TIME_NY_AUTO_DST   = 0, // AUTO: 9:30 New York -> server, US daylight-saving aware (RECOMMENDED)
   TIME_SERVER_DIRECT = 1, // Set ORB start directly in broker SERVER time
   TIME_NY_OFFSET     = 2  // Fixed: New York 09:30 + a constant offset (no DST handling)
};

input group "=== Opening Range (session) ==="
input ENUM_TIME_MODE  InpTimeMode        = TIME_NY_AUTO_DST; // How to anchor the 9:30 NY open
input double          InpBrokerUTCOffset = 0.0;  // Broker server's FIXED offset from UTC [NY_AUTO_DST]. Exness = 0
input int             InpServerStartHour = 14;   // ORB start hour (SERVER time) [SERVER_DIRECT]
input int             InpServerStartMin  = 30;   // ORB start minute (SERVER time) [SERVER_DIRECT]
input double          InpNYtoServerHours = 0.0;  // Hours broker server is AHEAD of New York [NY_OFFSET]
input ENUM_TIMEFRAMES InpORBTimeframe    = PERIOD_M15; // Timeframe of the ORB candle
input int             InpTradeWindowMin  = 240;  // Minutes after session open to keep taking/holding entries

//--- Signal detection ----------------------------------------------
input group "=== Signal detection ==="
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M5;  // TF for breakout close & FVG detection
input int             InpFVGLookbackBars = 12;   // How many signal bars back to scan for an FVG
input double          InpMinFVGPoints    = 20;   // Minimum FVG size (points) to be valid
input double          InpFVGOverlapPoints= 60;   // Tolerance (points) for FVG overlapping the ORB level

//--- Which setups to trade -----------------------------------------
input group "=== Setups (priority: RetestFVG > Retest > Immediate) ==="
input bool  InpUseRetestFVG   = true;   // Retest of ORB level that overlaps an FVG (highest prob.)
input bool  InpUsePlainRetest = false;  // Plain retest of ORB level (no FVG required)
input bool  InpUseImmediate   = false;  // Immediate entry on breakout candle close
input bool  InpUseFalseBreak  = true;   // Fade false breakouts (sweep + close back inside) via FVG

//--- Previous-day liquidity filter (avoid the common mistake) ------
input group "=== Previous-day High/Low filter ==="
input bool   InpUsePDHLFilter  = true;  // Skip entries with too little room to prev-day H/L
input double InpMinRoomPoints   = 150;  // Min room (points) from entry to the nearby PDH/PDL

//--- Risk / money management ---------------------------------------
enum ENUM_RISK_MODE
{
   RISK_PERCENT   = 0, // % of balance risked per trade
   RISK_FIXED_LOT = 1, // constant lot size
   RISK_FIXED_CASH= 2  // fixed cash amount risked per trade
};

input group "=== Risk management ==="
input ENUM_RISK_MODE InpRiskMode     = RISK_PERCENT; // Sizing method
input double         InpRiskPercent  = 1.0;   // Risk % of balance [RISK_PERCENT]
input double         InpFixedLot     = 0.10;  // Lot size [RISK_FIXED_LOT]
input double         InpFixedCash    = 100.0; // Cash risked per trade [RISK_FIXED_CASH]
input double         InpRewardR      = 1.5;   // Take-profit as multiple of risk (R)
input double         InpSLBufferPoints = 30;  // Extra buffer (points) beyond structure for the stop
input int            InpMaxTradesPerDay = 2;  // Max new trades per day (both directions combined)

//--- Execution -----------------------------------------------------
input group "=== Execution ==="
input long   InpMagic        = 990045;   // Magic number
input int    InpMaxSpreadPts  = 50;      // Max allowed spread (points); 0 = ignore
input int    InpSlippagePts   = 20;      // Deviation/slippage (points)
input bool   InpShowLines     = true;    // Draw ORB high/low lines on the chart
input bool   InpVerbose       = true;    // Verbose logging in the Experts tab

//--- On-chart status panel -----------------------------------------
input group "=== Status panel ==="
input bool             InpShowPanel   = true;             // Show the on-chart status panel
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;// Panel anchor corner
input int              InpPanelX       = 12;              // Panel X offset (px from corner)
input int              InpPanelY       = 20;              // Panel Y offset (px from corner)
input int              InpPanelFont    = 9;               // Panel font size

//==================================================================//
//                          GLOBALS                                 //
//==================================================================//
CTrade   trade;

datetime g_dayStart      = 0;     // 00:00 of the current trading day (server)
datetime g_orbOpenTime   = 0;     // open time of the ORB candle (server)
datetime g_orbCloseTime  = 0;     // close time of the ORB candle (server)
datetime g_windowEnd     = 0;     // end of the trade window (server)

bool     g_orbReady      = false; // ORB computed for today
double   g_orbHigh       = 0.0;
double   g_orbLow        = 0.0;

bool     g_longLocked    = false; // a long setup already placed today
bool     g_shortLocked   = false; // a short setup already placed today
int      g_tradesToday   = 0;

datetime g_lastSignalBar = 0;     // last processed signal-TF bar time

int      g_startHour     = 0;     // computed ORB start hour (server time)
int      g_startMin      = 0;     // computed ORB start minute (server time)
bool     g_isDST         = false; // US daylight saving active for today

#define  PANEL_PREFIX  "ORBP_"    // object-name prefix for the status panel
int      g_panelLines    = 0;     // number of panel label lines currently drawn

//==================================================================//
//                          INIT / DEINIT                           //
//==================================================================//
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   if(InpRewardR <= 0)
   {
      Print("ERROR: InpRewardR must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(!(InpUseRetestFVG || InpUsePlainRetest || InpUseImmediate || InpUseFalseBreak))
   {
      Print("ERROR: Enable at least one setup type.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ResetDay(); // establishes today's session times

   if(InpVerbose)
   {
      PrintFormat("ORB+SMC EA started on %s. ORB TF=%s Signal TF=%s",
                  _Symbol, EnumToString(InpORBTimeframe), EnumToString(InpSignalTimeframe));
      PrintFormat("Session (server) open=%s  ORB close=%s  window end=%s",
                  TimeToString(g_orbOpenTime, TIME_MINUTES),
                  TimeToString(g_orbCloseTime, TIME_MINUTES),
                  TimeToString(g_windowEnd, TIME_MINUTES));
   }
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, "ORB_HIGH");
   ObjectDelete(0, "ORB_LOW");
   ObjectsDeleteAll(0, PANEL_PREFIX);
}

//==================================================================//
//                             TICK                                 //
//==================================================================//
void OnTick()
{
   // 1) Roll the day over if needed.
   HandleNewDay();

   // 2) Try to compute the ORB once the first candle has closed.
   ComputeORBIfReady();

   // 2b) Keep the on-chart status panel current (runs every tick, cheap).
   if(InpShowPanel)
      UpdatePanel();

   // 3) Cancel stale pendings after the trade window ends.
   if(TimeCurrent() > g_windowEnd)
   {
      CancelMyPendings();
      return;
   }

   // 4) Process breakout / false-breakout logic once per new signal bar.
   datetime sigBarTime = iTime(_Symbol, InpSignalTimeframe, 0);
   if(sigBarTime != g_lastSignalBar)
   {
      g_lastSignalBar = sigBarTime;
      ProcessSignals();
   }
}

//==================================================================//
//                        DAY MANAGEMENT                            //
//==================================================================//
void HandleNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today00 = StructToTime(dt);
   if(today00 != g_dayStart)
      ResetDay();
}

void ResetDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_dayStart = StructToTime(dt);

   // Determine ORB start in SERVER time.
   int startH, startM;
   if(InpTimeMode == TIME_SERVER_DIRECT)
   {
      startH = InpServerStartHour;
      startM = InpServerStartMin;
   }
   else if(InpTimeMode == TIME_NY_OFFSET)
   {
      // Fixed offset: 09:30 New York + constant hours ahead (no DST handling).
      int totalMin = 9*60 + 30 + (int)MathRound(InpNYtoServerHours * 60.0);
      totalMin = ((totalMin % 1440) + 1440) % 1440;
      startH = totalMin / 60;
      startM = totalMin % 60;
   }
   else // TIME_NY_AUTO_DST : 09:30 NY -> UTC (US DST aware) -> server (fixed UTC offset)
   {
      // New York offset from UTC: -4 during US daylight saving (EDT), else -5 (EST).
      double nyOffset = IsUSDaylightSaving(g_dayStart) ? -4.0 : -5.0;
      // UTC minutes = NY-local minutes - nyOffset ; server = UTC + broker's fixed UTC offset.
      int utcMin    = 9*60 + 30 - (int)MathRound(nyOffset * 60.0);
      int serverMin = utcMin + (int)MathRound(InpBrokerUTCOffset * 60.0);
      serverMin = ((serverMin % 1440) + 1440) % 1440;
      startH = serverMin / 60;
      startM = serverMin % 60;
   }

   g_startHour = startH;
   g_startMin  = startM;
   g_isDST     = IsUSDaylightSaving(g_dayStart);

   MqlDateTime s = dt;
   s.hour = startH; s.min = startM; s.sec = 0;
   g_orbOpenTime  = StructToTime(s);
   g_orbCloseTime = g_orbOpenTime + PeriodSeconds(InpORBTimeframe);
   g_windowEnd    = g_orbOpenTime + InpTradeWindowMin * 60;

   g_orbReady    = false;
   g_orbHigh     = 0.0;
   g_orbLow      = 0.0;
   g_longLocked  = false;
   g_shortLocked = false;
   g_tradesToday = 0;

   ObjectDelete(0, "ORB_HIGH");
   ObjectDelete(0, "ORB_LOW");
}

// Day-of-month of the Nth Sunday (n=1,2,...) of a given month/year.
int NthSundayOfMonth(int year, int month, int n)
{
   MqlDateTime d;
   d.year = year; d.mon = month; d.day = 1;
   d.hour = 0; d.min = 0; d.sec = 0;
   datetime t = StructToTime(d);
   MqlDateTime dd;
   TimeToStruct(t, dd);
   int dow = dd.day_of_week;               // 0 = Sunday
   int firstSunday = 1 + ((7 - dow) % 7);  // day-of-month of the 1st Sunday
   return firstSunday + (n - 1) * 7;
}

// US daylight saving: 2nd Sunday of March 02:00 -> 1st Sunday of November 02:00.
// Date-level granularity is fine here (the switch is at 02:00, well before 09:30).
bool IsUSDaylightSaving(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   int y = d.year, m = d.mon, day = d.day;

   if(m < 3 || m > 11) return false;   // Jan, Feb, Dec -> standard time
   if(m > 3 && m < 11) return true;    // Apr..Oct       -> daylight saving
   if(m == 3)  return (day >= NthSundayOfMonth(y, 3, 2));   // March: on/after 2nd Sunday
   return (day < NthSundayOfMonth(y, 11, 1));               // November: before 1st Sunday
}

//==================================================================//
//                        ORB COMPUTATION                           //
//==================================================================//
void ComputeORBIfReady()
{
   if(g_orbReady)              return;
   if(TimeCurrent() < g_orbCloseTime) return; // first candle not closed yet

   // Find the bar that covers the session-open time on the ORB timeframe.
   int shift = iBarShift(_Symbol, InpORBTimeframe, g_orbOpenTime, false);
   if(shift < 0) return;

   datetime barTime = iTime(_Symbol, InpORBTimeframe, shift);
   if(barTime <= 0) return;

   // Make sure the located bar actually contains the session open.
   if(barTime + PeriodSeconds(InpORBTimeframe) <= g_orbOpenTime) return;

   double hi = iHigh(_Symbol, InpORBTimeframe, shift);
   double lo = iLow (_Symbol, InpORBTimeframe, shift);
   if(hi <= 0 || lo <= 0 || hi <= lo) return;

   g_orbHigh  = hi;
   g_orbLow   = lo;
   g_orbOpenTime = barTime; // snap to the real bar open
   g_orbCloseTime = barTime + PeriodSeconds(InpORBTimeframe);
   g_orbReady = true;

   if(InpVerbose)
      PrintFormat("ORB ready: High=%s Low=%s (range=%.0f pts)",
                  DoubleToString(g_orbHigh, _Digits),
                  DoubleToString(g_orbLow, _Digits),
                  (g_orbHigh - g_orbLow) / _Point);

   if(InpShowLines)
      DrawORBLines();
}

void DrawORBLines()
{
   datetime t1 = g_orbOpenTime;
   datetime t2 = g_windowEnd;
   DrawHLine("ORB_HIGH", g_orbHigh, clrDodgerBlue, t1, t2);
   DrawHLine("ORB_LOW",  g_orbLow,  clrTomato,     t1, t2);
}

void DrawHLine(string name, double price, color clr, datetime t1, datetime t2)
{
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//==================================================================//
//                        STATUS PANEL                              //
//==================================================================//
// Create or update one text label line of the status panel.
void PanelLabel(int idx, string text, color clr)
{
   string name = PANEL_PREFIX + (string)idx;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + idx * (InpPanelFont + 7));
      ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFont);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdatePanel()
{
   color cTitle = clrGold;
   color cText  = clrGainsboro;
   color cOn    = clrLime;
   color cWarn  = clrOrange;

   int   line   = 0;
   string sess  = StringFormat("%02d:%02d", g_startHour, g_startMin);
   string now   = TimeToString(TimeCurrent(), TIME_MINUTES);

   PanelLabel(line++, "ORB + SMC   " + _Symbol, cTitle);

   PanelLabel(line++, StringFormat("Server %s  |  US DST: %s",
              now, (g_isDST ? "ON (EDT)" : "OFF (EST)")), cText);

   PanelLabel(line++, StringFormat("NY 09:30 open -> server %s  (%s)",
              sess, TimeModeName()), cText);

   // ORB state line.
   if(g_orbReady)
   {
      PanelLabel(line++, StringFormat("ORB High: %s", DoubleToString(g_orbHigh, _Digits)), clrDodgerBlue);
      PanelLabel(line++, StringFormat("ORB Low : %s   (%.0f pts)",
                 DoubleToString(g_orbLow, _Digits), (g_orbHigh - g_orbLow) / _Point), clrTomato);
   }
   else if(TimeCurrent() < g_orbCloseTime)
   {
      PanelLabel(line++, "ORB: building range... closes " +
                 TimeToString(g_orbCloseTime, TIME_MINUTES), cWarn);
      PanelLabel(line++, " ", cText);
   }
   else
   {
      PanelLabel(line++, "ORB: waiting for candle data", cWarn);
      PanelLabel(line++, " ", cText);
   }

   PanelLabel(line++, "Trade window ends: " + TimeToString(g_windowEnd, TIME_MINUTES), cText);

   PanelLabel(line++, StringFormat("Trades today: %d/%d   Long:%s  Short:%s",
              g_tradesToday, InpMaxTradesPerDay,
              (g_longLocked ? "set" : "-"),
              (g_shortLocked ? "set" : "-")),
              (g_tradesToday >= InpMaxTradesPerDay ? cWarn : cOn));

   // Remove any stale lines from a previous, longer render.
   for(int i = line; i < g_panelLines; i++)
      ObjectDelete(0, PANEL_PREFIX + (string)i);
   g_panelLines = line;

   ChartRedraw(0);
}

string TimeModeName()
{
   switch(InpTimeMode)
   {
      case TIME_NY_AUTO_DST:   return "auto-DST";
      case TIME_SERVER_DIRECT: return "server-direct";
      case TIME_NY_OFFSET:     return "ny-offset";
   }
   return "";
}

//==================================================================//
//                        SIGNAL PROCESSING                         //
//==================================================================//
void ProcessSignals()
{
   if(!g_orbReady)                     return;
   if(TimeCurrent() < g_orbCloseTime)  return;
   if(g_tradesToday >= InpMaxTradesPerDay) return;

   // Work on the last CLOSED signal bar (shift 1).
   double c = iClose(_Symbol, InpSignalTimeframe, 1);
   double h = iHigh (_Symbol, InpSignalTimeframe, 1);
   double l = iLow  (_Symbol, InpSignalTimeframe, 1);
   if(c <= 0) return;

   double tol = InpFVGOverlapPoints * _Point;

   //--------------------------------------------------------------//
   //  BULLISH breakout (close above ORB high)                     //
   //--------------------------------------------------------------//
   if(!g_longLocked && c > g_orbHigh)
   {
      TryBullishBreakout();
   }

   //--------------------------------------------------------------//
   //  BEARISH breakout (close below ORB low)                      //
   //--------------------------------------------------------------//
   if(!g_shortLocked && c < g_orbLow)
   {
      TryBearishBreakout();
   }

   //--------------------------------------------------------------//
   //  FALSE breakout of the HIGH -> short (sweep high, close in)  //
   //--------------------------------------------------------------//
   if(InpUseFalseBreak && !g_shortLocked && h > g_orbHigh && c < g_orbHigh)
   {
      double zl, zh;
      if(FindBearishFVG(g_orbHigh, tol, zl, zh))
      {
         // enter as price rallies back up into the bearish gap (bottom edge first)
         double entry = zl;
         double sl    = zh + InpSLBufferPoints * _Point;
         if(PlaceOrder(false, /*market=*/false, entry, sl, "FalseBreak-Short"))
            g_shortLocked = true;
      }
   }

   //--------------------------------------------------------------//
   //  FALSE breakout of the LOW -> long (sweep low, close in)     //
   //--------------------------------------------------------------//
   if(InpUseFalseBreak && !g_longLocked && l < g_orbLow && c > g_orbLow)
   {
      double zl, zh;
      if(FindBullishFVG(g_orbLow, tol, zl, zh))
      {
         double entry = zh; // top of bullish gap (first touch on the way down)
         double sl    = zl - InpSLBufferPoints * _Point;
         if(PlaceOrder(true, false, entry, sl, "FalseBreak-Long"))
            g_longLocked = true;
      }
   }
}

//--- Bullish breakout: pick the highest-priority enabled entry -----
void TryBullishBreakout()
{
   double tol   = InpFVGOverlapPoints * _Point;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 1) Retest + FVG confluence
   if(InpUseRetestFVG)
   {
      double zl, zh;
      if(FindBullishFVG(g_orbHigh, tol, zl, zh))
      {
         double entry = zh;                              // top of gap
         double sl    = zl - InpSLBufferPoints * _Point; // below gap
         if(PlaceOrder(true, false, entry, sl, "Long-RetestFVG"))
         { g_longLocked = true; return; }
      }
   }

   // 2) Plain retest of the ORB high
   if(InpUsePlainRetest)
   {
      double entry = g_orbHigh;
      double sl    = g_orbLow - InpSLBufferPoints * _Point;
      if(PlaceOrder(true, false, entry, sl, "Long-Retest"))
      { g_longLocked = true; return; }
   }

   // 3) Immediate market entry on breakout close
   if(InpUseImmediate)
   {
      double entry = ask;
      double sl    = g_orbLow - InpSLBufferPoints * _Point;
      if(PlaceOrder(true, true, entry, sl, "Long-Immediate"))
      { g_longLocked = true; return; }
   }
}

//--- Bearish breakout ----------------------------------------------
void TryBearishBreakout()
{
   double tol = InpFVGOverlapPoints * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(InpUseRetestFVG)
   {
      double zl, zh;
      if(FindBearishFVG(g_orbLow, tol, zl, zh))
      {
         double entry = zl;                              // bottom of bearish gap
         double sl    = zh + InpSLBufferPoints * _Point; // above gap
         if(PlaceOrder(false, false, entry, sl, "Short-RetestFVG"))
         { g_shortLocked = true; return; }
      }
   }

   if(InpUsePlainRetest)
   {
      double entry = g_orbLow;
      double sl    = g_orbHigh + InpSLBufferPoints * _Point;
      if(PlaceOrder(false, false, entry, sl, "Short-Retest"))
      { g_shortLocked = true; return; }
   }

   if(InpUseImmediate)
   {
      double entry = bid;
      double sl    = g_orbHigh + InpSLBufferPoints * _Point;
      if(PlaceOrder(false, true, entry, sl, "Short-Immediate"))
      { g_shortLocked = true; return; }
   }
}

//==================================================================//
//                         FVG DETECTION                            //
//==================================================================//
// Bullish 3-candle FVG: gap between high[k+2] (older) and low[k] (newer)
// where low[k] > high[k+2]. Zone = [high[k+2], low[k]].
// Only accept gaps that (a) are >= min size, (b) formed at/after the ORB
// close, and (c) overlap the given 'level' within 'tol'.
bool FindBullishFVG(double level, double tol, double &zlow, double &zhigh)
{
   double minGap = InpMinFVGPoints * _Point;
   for(int k = 1; k <= InpFVGLookbackBars; k++)
   {
      double hiOld = iHigh(_Symbol, InpSignalTimeframe, k + 2);
      double loNew = iLow (_Symbol, InpSignalTimeframe, k);
      if(hiOld <= 0 || loNew <= 0) continue;

      double gap = loNew - hiOld;
      if(gap < minGap) continue;

      datetime tMid = iTime(_Symbol, InpSignalTimeframe, k + 1);
      if(tMid < g_orbCloseTime) continue; // must form during/after the breakout

      double zl = hiOld;
      double zh = loNew;
      if(zl <= level + tol && zh >= level - tol) // overlaps the ORB level band
      {
         zlow = zl; zhigh = zh;
         return true;
      }
   }
   return false;
}

// Bearish 3-candle FVG: gap between low[k+2] (older) and high[k] (newer)
// where high[k] < low[k+2]. Zone = [high[k], low[k+2]].
bool FindBearishFVG(double level, double tol, double &zlow, double &zhigh)
{
   double minGap = InpMinFVGPoints * _Point;
   for(int k = 1; k <= InpFVGLookbackBars; k++)
   {
      double loOld = iLow (_Symbol, InpSignalTimeframe, k + 2);
      double hiNew = iHigh(_Symbol, InpSignalTimeframe, k);
      if(loOld <= 0 || hiNew <= 0) continue;

      double gap = loOld - hiNew;
      if(gap < minGap) continue;

      datetime tMid = iTime(_Symbol, InpSignalTimeframe, k + 1);
      if(tMid < g_orbCloseTime) continue;

      double zl = hiNew;       // lower edge of the bearish gap
      double zh = loOld;       // upper edge of the bearish gap
      if(zl <= level + tol && zh >= level - tol)
      {
         zlow = zl; zhigh = zh;
         return true;
      }
   }
   return false;
}

//==================================================================//
//                        ORDER PLACEMENT                           //
//==================================================================//
// isLong  : direction
// market  : true = market order at 'entry' (current price), false = pending limit
// entry   : entry price (retest level)
// sl      : stop-loss price
// tag     : comment / log label
bool PlaceOrder(bool isLong, bool market, double entry, double sl, string tag)
{
   if(g_tradesToday >= InpMaxTradesPerDay) return false;
   if(MyExposure(isLong) > 0)             return false; // already have exposure this side

   // Spread guard
   if(InpMaxSpreadPts > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts)
      {
         if(InpVerbose) PrintFormat("%s skipped: spread %d > max %d", tag, (int)spread, InpMaxSpreadPts);
         return false;
      }
   }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);

   double risk = MathAbs(entry - sl);
   if(risk <= 0)
   {
      if(InpVerbose) Print(tag + " skipped: zero risk distance");
      return false;
   }

   double tp;
   if(isLong) tp = entry + InpRewardR * risk;
   else       tp = entry - InpRewardR * risk;
   tp = NormalizeDouble(tp, _Digits);

   // Sanity: SL/TP must sit on the correct sides.
   if(isLong && (sl >= entry || tp <= entry)) return false;
   if(!isLong && (sl <= entry || tp >= entry)) return false;

   // Previous-day High/Low room filter.
   if(InpUsePDHLFilter && !HasRoomToPDHL(isLong, entry))
   {
      if(InpVerbose) Print(tag + " skipped: too close to previous-day liquidity (PDH/PDL)");
      return false;
   }

   // Broker minimum stop distance.
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * _Point;
   if(minDist > 0 && (risk < minDist || MathAbs(tp - entry) < minDist))
   {
      if(InpVerbose) Print(tag + " skipped: SL/TP inside broker stops level");
      return false;
   }

   double lots = CalcLots(risk);
   if(lots <= 0)
   {
      if(InpVerbose) Print(tag + " skipped: lot size resolved to 0");
      return false;
   }

   bool ok = false;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(market)
   {
      if(isLong) ok = trade.Buy (lots, _Symbol, ask, sl, tp, tag);
      else       ok = trade.Sell(lots, _Symbol, bid, sl, tp, tag);
   }
   else
   {
      // Pending limit orders must be on the correct side of price.
      if(isLong)
      {
         if(entry >= ask) // price already at/below entry -> take market instead
            ok = trade.Buy(lots, _Symbol, ask, sl, tp, tag);
         else
            ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, g_windowEnd, tag);
      }
      else
      {
         if(entry <= bid)
            ok = trade.Sell(lots, _Symbol, bid, sl, tp, tag);
         else
            ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, g_windowEnd, tag);
      }
   }

   if(ok)
   {
      g_tradesToday++;
      if(InpVerbose)
         PrintFormat("%s placed: lots=%.2f entry=%s sl=%s tp=%s (retcode=%u)",
                     tag, lots,
                     DoubleToString(entry, _Digits),
                     DoubleToString(sl, _Digits),
                     DoubleToString(tp, _Digits),
                     trade.ResultRetcode());
   }
   else if(InpVerbose)
   {
      PrintFormat("%s FAILED: retcode=%u (%s)", tag, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   return ok;
}

//==================================================================//
//                        HELPERS / FILTERS                         //
//==================================================================//
double CalcLots(double slDistancePrice)
{
   if(InpRiskMode == RISK_FIXED_LOT)
      return NormalizeLots(InpFixedLot);

   double riskMoney;
   if(InpRiskMode == RISK_FIXED_CASH)
      riskMoney = InpFixedCash;
   else
      riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0)
      return NormalizeLots(InpFixedLot);

   double moneyPerPricePerLot = tickValue / tickSize; // money for a 1.0 price move, 1 lot
   double denom = slDistancePrice * moneyPerPricePerLot;
   if(denom <= 0) return 0.0;

   double lots = riskMoney / denom;
   return NormalizeLots(lots);
}

double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;   // never below broker minimum
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(lots, 2);
}

// Room to the *nearest* previous-day liquidity level in the trade direction.
bool HasRoomToPDHL(bool isLong, double entry)
{
   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow (_Symbol, PERIOD_D1, 1);
   if(pdh <= 0 || pdl <= 0) return true; // no data -> don't block

   double minRoom = InpMinRoomPoints * _Point;

   if(isLong)
   {
      // If PDH sits just above the entry, price is likely to sweep it and reverse.
      if(pdh > entry && (pdh - entry) < minRoom) return false;
   }
   else
   {
      if(pdl < entry && (entry - pdl) < minRoom) return false;
   }
   return true;
}

// Count our positions + pending orders on this symbol for a given direction.
int MyExposure(bool isLong)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(isLong && type == POSITION_TYPE_BUY)  count++;
      if(!isLong && type == POSITION_TYPE_SELL) count++;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(isLong && (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP))  count++;
      if(!isLong && (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)) count++;
   }
   return count;
}

// Delete our still-pending orders (called after the trade window closes).
void CancelMyPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      trade.OrderDelete(ticket);
   }
}
//+------------------------------------------------------------------+
