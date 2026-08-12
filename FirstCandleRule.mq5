//+------------------------------------------------------------------+
//|                                            FirstCandleRule.mq5    |
//|      "First Candle Rule" opening-range scalping indicator (MT5)   |
//|      Rebuilt from the TradersNotes / Jason video lesson.          |
//|                                                                  |
//|  Rules taught in the video:                                      |
//|    1. At the session open (9:30 EST) take the FIRST 5-minute      |
//|       candle (9:30-9:35). Mark its HIGH and LOW = the day's       |
//|       only key levels (the "First Candle Range", FCR).           |
//|    2. Drop to the 1-minute chart for the entry.                   |
//|    3. Price must BREAK a level and leave a GAP between candle     |
//|       wicks (a displacement / fair-value-gap) = "real force",     |
//|       not just a wick poke or a close.                            |
//|    4. Wait for a RETEST of that level.                            |
//|    5. On the retest, a candle ENGULFING in the break direction    |
//|       triggers the entry.                                         |
//|    6. Target a FIXED risk-to-reward.                              |
//|          - the video uses 3:1;  this indicator DEFAULTS to 1:2    |
//|            (InpRR), and it is manually adjustable.                 |
//|                                                                  |
//|  Break ABOVE the high -> BUY.   Break BELOW the low -> SELL.      |
//|  Apply on the M1 chart of a stock / index / your instrument.      |
//|                                                                  |
//|  NOTE ON TIME: MT5 uses BROKER SERVER time, not EST. Set          |
//|  InpSessionHour / InpSessionMin to whatever 9:30 EST is on YOUR   |
//|  broker's clock (check the time in the Market Watch).             |
//+------------------------------------------------------------------+
#property copyright "First Candle Rule"
#property version   "1.00"
#property description "Opening-range (First Candle Rule) breakout: gap displacement + retest + engulfing entry, fixed R:R. Popup/sound/push alerts. Default R:R 1:2, adjustable."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0 : Buy arrow
#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
//--- Plot 1 : Sell arrow
#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- inputs : session / first candle ------------------------------------------
input group                "=== Session (broker server time!) ==="
input int    InpSessionHour   = 9;      // Session open hour (server time)
input int    InpSessionMin    = 30;     // Session open minute (server time)
input int    InpFirstCandleMin= 5;      // First candle length (minutes)
input int    InpEntryWindowMin= 90;     // Only look for entries for N min after open

//--- inputs : entry logic -----------------------------------------------------
input group                "=== Entry logic ==="
input bool   InpRequireGap    = true;   // Require a wick gap (FVG) on the break
input bool   InpAllowLong      = true;  // Take BUY (break above the high)
input bool   InpAllowShort     = true;  // Take SELL (break below the low)
input int    InpMaxPerDay      = 1;     // Max signals per direction per day

//--- inputs : risk / reward ---------------------------------------------------
input group                "=== Risk / Reward ==="
input double InpRR            = 2.0;    // Risk : Reward  (1 : x)   [video used 3.0]
input int    InpSLBufPts      = 0;      // Extra stop buffer (points)
input bool   InpDrawSLTP      = true;   // Draw Entry/SL/TP lines for latest signal
input int    InpZoneBars      = 20;     // SL/TP line length (bars)

//--- inputs : levels drawing --------------------------------------------------
input group                "=== First-candle levels ==="
input bool   InpDrawLevels    = true;   // Draw the FCR high/low lines
input color  InpLevelColor    = clrDodgerBlue;

//--- inputs : alerts ----------------------------------------------------------
input group                "=== Alerts / Notifications ==="
input bool   InpAlertPopup    = true;   // Popup alert
input bool   InpAlertSound    = true;   // Play a sound
input string InpBuySound       = "alert.wav";   // Buy  sound
input string InpSellSound      = "alert2.wav";  // Sell sound
input bool   InpPush           = false; // Push notification (mobile)
input bool   InpEmail          = false; // E-mail alert

//--- buffers ------------------------------------------------------------------
double BuyBuffer[];
double SellBuffer[];

//--- persistent state ---------------------------------------------------------
int      g_curDay      = -1;            // yyyymmdd of the day being tracked
double   g_fcHigh      = -DBL_MAX;      // first-candle high
double   g_fcLow       =  DBL_MAX;      // first-candle low
bool     g_levelsReady = false;
int      g_longPhase   = 0;             // 0 idle, 1 displaced/broke, 2+ done
int      g_shortPhase  = 0;
int      g_longCount   = 0;             // signals fired today (long)
int      g_shortCount  = 0;
datetime g_lastProcessed = 0;           // time of last CLOSED bar processed
datetime g_lastAlertBar  = 0;
bool     g_liveMode      = false;
string   g_prefix        = "FCR_";

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);   // up arrow (buy)
   PlotIndexSetInteger(1, PLOT_ARROW, 234);   // down arrow (sell)
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME, "First Candle Rule");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
  }

//+------------------------------------------------------------------+
//| Candle helpers                                                   |
//+------------------------------------------------------------------+
bool BullEngulf(const double &o[], const double &c[], const int i)
  {
   return(c[i] > o[i] && c[i-1] < o[i-1] && o[i] <= c[i-1] && c[i] >= o[i-1]);
  }
bool BearEngulf(const double &o[], const double &c[], const int i)
  {
   return(c[i] < o[i] && c[i-1] > o[i-1] && o[i] >= c[i-1] && c[i] <= o[i-1]);
  }
string TFToStr(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   if(StringFind(s, "PERIOD_") == 0) s = StringSubstr(s, 7);
   return(s);
  }
void ResetDay()
  {
   g_fcHigh = -DBL_MAX;
   g_fcLow  =  DBL_MAX;
   g_levelsReady = false;
   g_longPhase = 0;  g_shortPhase = 0;
   g_longCount = 0;  g_shortCount = 0;
  }

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 5)
      return(0);

   int lastClosed = rates_total - 2;      // last fully-closed bar
   if(lastClosed < 2)
      return(0);

   // keep the forming bar clean
   BuyBuffer[rates_total-1]  = 0.0;
   SellBuffer[rates_total-1] = 0.0;

   if(prev_calculated == 0)
     {
      ArrayInitialize(BuyBuffer,  0.0);
      ArrayInitialize(SellBuffer, 0.0);
      ObjectsDeleteAll(0, g_prefix);
      g_curDay = -1;  ResetDay();
      g_liveMode = false;
      for(int i = 2; i <= lastClosed; i++)
        {
         BuyBuffer[i] = 0.0;  SellBuffer[i] = 0.0;
         ProcessBar(i, time, open, high, low, close, false);
        }
      g_lastProcessed = time[lastClosed];
      g_lastAlertBar  = time[lastClosed];   // prime: no alert for historical signals
      g_liveMode      = true;
      return(rates_total);
     }

   // incremental: process only newly-closed bars
   int i0 = MathMax(2, prev_calculated - 2);
   for(int i = i0; i <= lastClosed; i++)
     {
      if(time[i] <= g_lastProcessed)
         continue;
      BuyBuffer[i] = 0.0;  SellBuffer[i] = 0.0;
      bool live = (i == lastClosed);
      ProcessBar(i, time, open, high, low, close, live);
      g_lastProcessed = time[i];
     }
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| State machine for one closed bar i                               |
//+------------------------------------------------------------------+
void ProcessBar(const int i,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const bool live)
  {
   MqlDateTime st;
   TimeToStruct(time[i], st);
   int dayid = st.year*10000 + st.mon*100 + st.day;
   int mod   = st.hour*60 + st.min;                 // minutes into the day

   if(dayid != g_curDay)
     {
      g_curDay = dayid;
      ResetDay();
     }

   int startMin = InpSessionHour*60 + InpSessionMin;
   int endMin   = startMin + InpFirstCandleMin;

   // ---- build the first-candle range ----
   if(mod >= startMin && mod < endMin)
     {
      g_fcHigh = MathMax(g_fcHigh, high[i]);
      g_fcLow  = MathMin(g_fcLow,  low[i]);
      return;
     }

   if(!g_levelsReady)
     {
      if(mod >= endMin && g_fcHigh > -DBL_MAX && g_fcLow < DBL_MAX)
        {
         g_levelsReady = true;
         if(InpDrawLevels)
           {
            datetime midnight = (datetime)(time[i] - mod*60);
            datetime s1 = midnight + startMin*60;
            datetime s2 = midnight + (endMin + InpEntryWindowMin)*60;
            DrawLevel(g_prefix+"H", s1, g_fcHigh, s2, "FCR High");
            DrawLevel(g_prefix+"L", s1, g_fcLow,  s2, "FCR Low");
           }
        }
      else
         return;
     }

   // ---- only hunt for entries inside the entry window ----
   if(mod > startMin + InpEntryWindowMin)
      return;

   double buf = InpSLBufPts * _Point;
   double off = MathMax(high[i]-low[i], _Point) * 0.5;

   // =============================== LONG (break above the high) =====
   if(InpAllowLong && g_longCount < InpMaxPerDay)
     {
      if(g_longPhase == 0)
        {
         bool gapUp = (!InpRequireGap) || (low[i] > high[i-2]);   // wick gap up
         bool broke = (close[i] > g_fcHigh && high[i] > g_fcHigh);
         if(gapUp && broke)
            g_longPhase = 1;
        }
      else if(g_longPhase == 1)
        {
         // wicked back to the level but closed back above it (level held) + engulfing
         bool retest = (low[i] <= g_fcHigh && close[i] > g_fcHigh);
         if(retest && BullEngulf(open, close, i))
           {
            double entry = close[i];
            double sl    = MathMin(low[i], low[i-1]) - buf;
            double risk  = entry - sl;
            if(risk > 0)
              {
               double tp = entry + InpRR * risk;
               BuyBuffer[i] = low[i] - off;
               g_longPhase = 2;  g_longCount++;
               EmitSignal(true, time[i], entry, sl, tp, live);
              }
           }
        }
     }

   // =============================== SHORT (break below the low) =====
   if(InpAllowShort && g_shortCount < InpMaxPerDay)
     {
      if(g_shortPhase == 0)
        {
         bool gapDn = (!InpRequireGap) || (high[i] < low[i-2]);   // wick gap down
         bool broke = (close[i] < g_fcLow && low[i] < g_fcLow);
         if(gapDn && broke)
            g_shortPhase = 1;
        }
      else if(g_shortPhase == 1)
        {
         // wicked back to the level but closed back below it (level held) + engulfing
         bool retest = (high[i] >= g_fcLow && close[i] < g_fcLow);
         if(retest && BearEngulf(open, close, i))
           {
            double entry = close[i];
            double sl    = MathMax(high[i], high[i-1]) + buf;
            double risk  = sl - entry;
            if(risk > 0)
              {
               double tp = entry - InpRR * risk;
               SellBuffer[i] = high[i] + off;
               g_shortPhase = 2;  g_shortCount++;
               EmitSignal(false, time[i], entry, sl, tp, live);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fire notifications + draw the trade zone                         |
//+------------------------------------------------------------------+
void EmitSignal(const bool isBuy, const datetime t,
                const double entry, const double sl, const double tp,
                const bool live)
  {
   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("%s  %s  %s  (First Candle Rule)  |  Entry %s  SL %s  TP %s  (1:%s)",
                             dir, _Symbol, TFToStr((ENUM_TIMEFRAMES)_Period),
                             DoubleToString(entry, _Digits),
                             DoubleToString(sl,    _Digits),
                             DoubleToString(tp,    _Digits),
                             DoubleToString(InpRR, 1));
   Print(msg);

   if(live && t != g_lastAlertBar)
     {
      g_lastAlertBar = t;
      if(InpAlertPopup) Alert(msg);
      if(InpAlertSound) PlaySound(isBuy ? InpBuySound : InpSellSound);
      if(InpPush)       SendNotification(msg);
      if(InpEmail)      SendMail("First Candle Rule: " + dir + " " + _Symbol, msg);
     }

   if(InpDrawSLTP)
      DrawZone(t, entry, sl, tp);
  }

//+------------------------------------------------------------------+
//| Chart objects                                                    |
//+------------------------------------------------------------------+
void CreateSeg(const string name, datetime t1, double p1, datetime t2, double p2,
               color col, ENUM_LINE_STYLE stl = STYLE_SOLID, int wid = 2)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, stl);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, wid);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }
void CreateTxt(const string name, datetime t, double p, const string text, color col)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }
void DrawLevel(const string name, datetime t1, double price, datetime t2, const string text)
  {
   CreateSeg(name, t1, price, t2, price, InpLevelColor, STYLE_DASH, 1);
   CreateTxt(name+"t", t2, price, " "+text, InpLevelColor);
  }
void DrawZone(datetime t1, double entry, double sl, double tp)
  {
   ObjectsDeleteAll(0, g_prefix+"Z");
   datetime t2 = t1 + (datetime)(PeriodSeconds() * InpZoneBars);
   CreateSeg(g_prefix+"ZEN", t1, entry, t2, entry, clrSilver,    STYLE_DOT, 1);
   CreateSeg(g_prefix+"ZSL", t1, sl,    t2, sl,    clrRed,       STYLE_SOLID, 2);
   CreateSeg(g_prefix+"ZTP", t1, tp,    t2, tp,    clrLimeGreen, STYLE_SOLID, 2);
   CreateTxt(g_prefix+"ZtEN", t2, entry, " Entry", clrSilver);
   CreateTxt(g_prefix+"ZtSL", t2, sl,    " SL",    clrRed);
   CreateTxt(g_prefix+"ZtTP", t2, tp,    " TP (1:"+DoubleToString(InpRR,1)+")", clrLimeGreen);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
