//+------------------------------------------------------------------+
//|                                                        MSB_OB.mq5 |
//|                    Market Structure Break + Order Block (MSB-OB)  |
//|                                                                  |
//|  MetaTrader 5 recreation of the "MSB-OB" TradingView indicator   |
//|  shown in the strategy video:                                    |
//|    * A ZigZag (pivot) engine finds swing highs / swing lows.     |
//|    * A Market Structure Break (MSB) is flagged when price closes |
//|      beyond the last confirmed swing (bullish = above swing high,|
//|      bearish = below swing low). A Fib factor of the impulse leg |
//|      is used as a breakout-confirmation buffer to filter noise.  |
//|    * The last opposite candle before the break is drawn as an    |
//|      Order Block (OB) zone: green = bullish (demand),            |
//|      red = bearish (supply). That zone is the trade entry area.  |
//|                                                                  |
//|  Designed for the 5-minute timeframe but works on any chart.     |
//+------------------------------------------------------------------+
#property copyright "MSB-OB strategy recreation"
#property version   "1.00"
#property description "Market Structure Break + Order Block (MSB-OB). Swing structure via ZigZag, breakout confirmation via Fib factor, and bullish/bearish order-block zones."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

//--- Plot 1: Bullish MSB signal (up arrow at the break bar)
#property indicator_label1  "Bullish MSB"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
//--- Plot 2: Bearish MSB signal (down arrow at the break bar)
#property indicator_label2  "Bearish MSB"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
//--- Plot 3: ZigZag structure line (optional, uses 2 buffers)
#property indicator_label3  "ZigZag"
#property indicator_type3   DRAW_ZIGZAG
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- Inputs (mirroring the video's indicator settings) --------------
input int    InpZigZagLength = 9;       // ZigZag Length (pivot lookback each side)
input bool   InpShowZigzag   = false;   // Show Zigzag
input double InpFibFactor    = 0.273;   // Fib Factor for breakout confirmation
input int    InpMaxSetups    = 50;      // Max recent OB/MSB drawings to keep
input int    InpOBExtendBars = 30;      // Extend OB box this many bars to the right
input color  InpBullColor    = clrLime; // Bullish OB / MSB colour
input color  InpBearColor    = clrRed;  // Bearish OB / MSB colour
input bool   InpFillOB       = true;    // Fill OB rectangles

//--- Indicator buffers
double BullArrow[];
double BearArrow[];
double ZZUp[];
double ZZDn[];

//--- Object prefix so we can clean up only our own objects
const string OBJ_PREFIX = "MSBOB_";

//--- Persistent structure state (kept between OnCalculate calls)
double   g_lastPHprice = 0.0;   datetime g_lastPHtime = 0;   int g_lastPHidx = -1;
double   g_lastPLprice = 0.0;   datetime g_lastPLtime = 0;   int g_lastPLidx = -1;
datetime g_brokenHighTime = 0;  // last swing-high time already broken
datetime g_brokenLowTime  = 0;  // last swing-low  time already broken
int      g_setupCount = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BullArrow, INDICATOR_DATA);
   SetIndexBuffer(1, BearArrow, INDICATOR_DATA);
   SetIndexBuffer(2, ZZUp,      INDICATOR_DATA);
   SetIndexBuffer(3, ZZDn,      INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);          // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);          // down arrow
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (2, PLOT_EMPTY_VALUE, 0.0);

   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpShowZigzag ? clrSilver : clrNONE);

   IndicatorSetString(INDICATOR_SHORTNAME, "MSB-OB");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, OBJ_PREFIX);
  }
//+------------------------------------------------------------------+
//| Is bar p a pivot high (highest high over +/- L bars)?            |
//| Arrays are NON-series here (index 0 = oldest).                    |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &high[], int p, int L, int rates_total)
  {
   if(p - L < 0 || p + L >= rates_total) return(false);
   double v = high[p];
   for(int k = 1; k <= L; k++)
     {
      if(high[p-k] > v) return(false);   // a bar to the left is higher
      if(high[p+k] > v) return(false);   // a bar to the right is higher
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool IsPivotLow(const double &low[], int p, int L, int rates_total)
  {
   if(p - L < 0 || p + L >= rates_total) return(false);
   double v = low[p];
   for(int k = 1; k <= L; k++)
     {
      if(low[p-k] < v) return(false);
      if(low[p+k] < v) return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Average candle range over the last n bars ending at i            |
//+------------------------------------------------------------------+
double AvgRange(const double &high[], const double &low[], int i, int n)
  {
   double sum = 0.0; int cnt = 0;
   for(int k = i; k > i - n && k >= 0; k--) { sum += (high[k] - low[k]); cnt++; }
   if(cnt == 0) return(0.0);
   return(sum / cnt);
  }
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
   int L = InpZigZagLength;
   if(L < 1) L = 1;
   if(rates_total < 2*L + 5) return(0);

   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BullArrow, EMPTY_VALUE);
      ArrayInitialize(BearArrow, EMPTY_VALUE);
      ArrayInitialize(ZZUp, 0.0);
      ArrayInitialize(ZZDn, 0.0);
      // reset structure state + drawings on a full recalculation
      g_lastPHprice=0; g_lastPHtime=0; g_lastPHidx=-1;
      g_lastPLprice=0; g_lastPLtime=0; g_lastPLidx=-1;
      g_brokenHighTime=0; g_brokenLowTime=0; g_setupCount=0;
      ObjectsDeleteAll(0, OBJ_PREFIX);
      start = L;
     }
   else
      start = prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
     {
      BullArrow[i] = EMPTY_VALUE;
      BearArrow[i] = EMPTY_VALUE;
      ZZUp[i] = 0.0;
      ZZDn[i] = 0.0;

      // Confirm the pivot that sits L bars behind the current bar i.
      int p = i - L;
      if(p >= L)
        {
         if(IsPivotHigh(high, p, L, rates_total))
           {
            g_lastPHprice = high[p]; g_lastPHtime = time[p]; g_lastPHidx = p;
            if(InpShowZigzag) ZZUp[p] = high[p];
           }
         if(IsPivotLow(low, p, L, rates_total))
           {
            g_lastPLprice = low[p]; g_lastPLtime = time[p]; g_lastPLidx = p;
            if(InpShowZigzag) ZZDn[p] = low[p];
           }
        }

      // Breakout-confirmation buffer = FibFactor x recent average candle
      // range (ATR-like). This scales sensibly across instruments so the
      // break must clear the swing by a fraction of a typical candle.
      double avgRange = AvgRange(high, low, i, 14);
      double buffer   = InpFibFactor * avgRange;

      //--- Bullish MSB: close above the last confirmed swing high ---
      if(g_lastPHidx >= 0 && g_lastPHtime != g_brokenHighTime &&
         close[i] > g_lastPHprice + buffer)
        {
         BullArrow[i] = low[i] - 0.5 * avgRange;
         DrawMSBLine(true, g_lastPHtime, time[i], g_lastPHprice);
         DrawOrderBlock(true, open, high, low, close, time, g_lastPHidx, i);
         g_brokenHighTime = g_lastPHtime;
        }

      //--- Bearish MSB: close below the last confirmed swing low ----
      if(g_lastPLidx >= 0 && g_lastPLtime != g_brokenLowTime &&
         close[i] < g_lastPLprice - buffer)
        {
         BearArrow[i] = high[i] + 0.5 * avgRange;
         DrawMSBLine(false, g_lastPLtime, time[i], g_lastPLprice);
         DrawOrderBlock(false, open, high, low, close, time, g_lastPLidx, i);
         g_brokenLowTime = g_lastPLtime;
        }
     }

   ChartRedraw(0);   // force the freshly-created objects to render
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Draw the horizontal MSB line + label                             |
//+------------------------------------------------------------------+
void DrawMSBLine(bool bullish, datetime t1, datetime t2, double price)
  {
   string name = OBJ_PREFIX + "MSB_" + (string)(long)t1;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, bullish ? InpBullColor : InpBearColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);

      string tname = OBJ_PREFIX + "MSBTXT_" + (string)(long)t1;
      ObjectCreate(0, tname, OBJ_TEXT, 0, t2, price);
      ObjectSetString (0, tname, OBJPROP_TEXT, "MSB");
      ObjectSetInteger(0, tname, OBJPROP_COLOR, bullish ? InpBullColor : InpBearColor);
      ObjectSetInteger(0, tname, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tname, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);

      PruneOldSetups();
     }
  }
//+------------------------------------------------------------------+
//| Draw the order-block rectangle (last opposite candle before break)|
//+------------------------------------------------------------------+
void DrawOrderBlock(bool bullish,
                    const double &open[], const double &high[],
                    const double &low[],  const double &close[],
                    const datetime &time[], int fromIdx, int breakIdx)
  {
   int obIdx = -1;
   // Bullish OB = last BEARISH candle before the up-move that broke structure.
   // Bearish OB = last BULLISH candle before the down-move that broke structure.
   for(int k = breakIdx; k > fromIdx && k > 0; k--)
     {
      bool bearCandle = (close[k] < open[k]);
      bool bullCandle = (close[k] > open[k]);
      if(bullish && bearCandle) { obIdx = k; break; }
      if(!bullish && bullCandle){ obIdx = k; break; }
     }
   if(obIdx < 0) obIdx = fromIdx;

   double obTop = high[obIdx];
   double obBot = low[obIdx];
   datetime tStart = time[obIdx];
   datetime tEnd   = time[breakIdx] + (datetime)(InpOBExtendBars * PeriodSeconds());

   string name = OBJ_PREFIX + "OB_" + (string)(long)tStart;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, obTop, tEnd, obBot);
      color c = bullish ? InpBullColor : InpBearColor;
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_FILL, InpFillOB);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      g_setupCount++;
      PruneOldSetups();
     }
  }
//+------------------------------------------------------------------+
//| Keep only the most recent InpMaxSetups drawings                  |
//+------------------------------------------------------------------+
void PruneOldSetups()
  {
   int total = ObjectsTotal(0);
   if(total <= InpMaxSetups * 3) return;
   // Collect our OB objects (oldest first) and delete the excess set.
   // Simple bounded cleanup: remove objects whose creation time is oldest.
   datetime oldest = 0; string oldestName = "";
   int obCount = 0;
   for(int i = 0; i < total; i++)
     {
      string nm = ObjectName(0, i);
      if(StringFind(nm, OBJ_PREFIX + "OB_") == 0)
        {
         obCount++;
         datetime t = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME);
         if(oldest == 0 || t < oldest) { oldest = t; oldestName = nm; }
        }
     }
   if(obCount > InpMaxSetups && oldestName != "")
     {
      long key = (long)oldest;
      ObjectDelete(0, oldestName);
      ObjectDelete(0, OBJ_PREFIX + "MSB_" + (string)key);
      ObjectDelete(0, OBJ_PREFIX + "MSBTXT_" + (string)key);
     }
  }
//+------------------------------------------------------------------+
