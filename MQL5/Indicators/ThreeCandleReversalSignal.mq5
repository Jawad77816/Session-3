//+------------------------------------------------------------------+
//|                                 ThreeCandleReversalSignal.mq5     |
//|                    Three-Candle Reversal Pattern Indicator (XAU) |
//|                                                                  |
//|  Detects the same three-candle pattern as the EA version, draws  |
//|  up/down arrows on the chart, and plays a notification sound     |
//|  (plus optional popup / push / email alerts). It does NOT trade. |
//|                                                                  |
//|  Bars used (index 0 = current forming bar, not signalled):       |
//|      First  candle = the signal bar minus 2                      |
//|      Middle candle = the signal bar minus 1                      |
//|      Third  candle = the signal (arrow) bar                      |
//|                                                                  |
//|  BUY  : red -> green -> green                                    |
//|          middle LOW  (incl. wick) < first LOW  AND < third LOW   |
//|          third candle BODY close engulfs the first candle HIGH   |
//|                                                                  |
//|  SELL : green -> red -> red                                      |
//|          middle HIGH (incl. wick) > first HIGH AND > third HIGH  |
//|          third candle BODY close engulfs the first candle LOW    |
//|                                                                  |
//|  Signals fire only on CLOSED bars (no repaint). Built for M1/M5, |
//|  XAUUSD.                                                          |
//+------------------------------------------------------------------+
#property copyright "Three-Candle Reversal Signal"
#property version   "1.40"
#property strict
#property description "Three-candle reversal pattern indicator for XAUUSD on M1/M5."
#property description "Draws arrows and plays a notification sound on each signal."

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Buy arrow
#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
//--- Sell arrow
#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group    "=== Signals ==="
input bool     InpEnableBuy   = true;          // Detect BUY signals
input bool     InpEnableSell  = true;          // Detect SELL signals
input double   InpArrowGapUSD = 0.10;          // Arrow gap from candle (USD)

input group    "=== Notifications ==="
input bool     InpEnableSound = true;          // Play notification sound
input string   InpBuySound    = "alert.wav";   // Sound file for BUY
input string   InpSellSound   = "alert2.wav";  // Sound file for SELL
input bool     InpEnableAlert = true;          // Popup alert
input bool     InpEnablePush  = false;         // Push notification to phone
input bool     InpEnableEmail = false;         // Email alert

input group    "=== Trend / Reversal Filter (M5 recommended) ==="
input bool           InpUseTrendFilter = true;      // Only show reversals (skip mid-trend signals)
input int            InpSwingLookback  = 12;        // Local top/bottom lookback in bars (0=off)
input int            InpMAPeriod       = 50;        // Trend MA period (0=off)
input ENUM_MA_METHOD InpMAMethod       = MODE_EMA;  // Trend MA method
input int            InpMASlopeBars    = 5;         // Bars used to measure MA slope

input group    "=== Candle Shape Filter ==="
input bool           InpUseShapeFilter = true;      // Require hammer/star middle + solid 1st/3rd
input double         InpHammerWickPct  = 0.5;       // Dominant wick >= this fraction of range
input double         InpHammerHeadPct  = 0.15;      // Opposite wick <= this fraction of range
input double         InpHammerBodyPct  = 0.4;       // Hammer/star body <= this fraction of range
input double         InpSolidBodyPct   = 0.5;       // 1st/3rd body >= this fraction (not doji/hammer)
input bool           InpMiddleInsideFirst = true;   // Middle body must sit inside the 1st candle's body

input group    "=== Dashboard ==="
input bool     InpShowDashboard = true;        // Show on-chart status dashboard
input int      InpDashX         = 12;          // Dashboard X offset (px)
input int      InpDashY         = 20;          // Dashboard Y offset (px)
input color    InpDashBgColor   = clrBlack;    // Dashboard background colour

input group    "=== Diagnostics ==="
input bool     InpLogRejections = true;        // Log why the last closed bar had no signal

input group    "=== Instrument / Timeframe Guards ==="
input bool     InpRestrictSymbol    = true;    // Only run on XAUUSD-type symbol
input bool     InpRestrictTimeframe = true;    // Only run on M1 / M5

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
double   BuyBuffer[];
double   SellBuffer[];
int      g_digits       = 2;
bool     g_active       = true;    // false if symbol/timeframe guard fails
bool     g_histInit     = false;   // suppress alerts for pre-existing history
datetime g_lastAlertBar = 0;       // time of the last evaluated closed bar
int      g_maHandle     = INVALID_HANDLE;  // trend MA indicator handle
double   g_maArr[];                // MA values aligned to the price series
bool     g_maReady      = false;   // MA buffer valid this calculation
string   g_lastSignal   = "None";  // last signal (dashboard)
datetime g_lastSignalTm = 0;       // time of last signal
string   g_lastCheck    = "-";     // why the last closed bar had no signal (diagnostics)
#define  DASH_PREFIX      "TCRIND_DASH_"

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsGoldSymbol(const string sym)
  {
   string s = sym;
   StringToUpper(s);
   if(StringFind(s, "XAU")  >= 0) return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   return false;
  }

bool IsAllowedTimeframe(const ENUM_TIMEFRAMES tf)
  {
   return (tf == PERIOD_M1 || tf == PERIOD_M5);
  }

string TfToStr(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);        // e.g. "PERIOD_M1"
   StringReplace(s, "PERIOD_", "");
   return s;
  }

bool IsBull(const double o, const double c) { return(c > o); }  // green
bool IsBear(const double o, const double c) { return(c < o); }  // red

//+------------------------------------------------------------------+
//| Candle-shape helpers                                             |
//|   Hammer        : long LOWER wick, small body, tiny upper wick   |
//|   Shooting star : long UPPER wick, small body, tiny lower wick   |
//|   Solid         : body-dominant candle (not doji/hammer/star)    |
//+------------------------------------------------------------------+
bool IsHammerShape(const double o, const double h, const double l, const double c)
  {
   double range = h - l;
   if(range <= 0.0) return(false);
   double body = MathAbs(c - o);
   double uw   = h - MathMax(o, c);
   double lw   = MathMin(o, c) - l;
   return(lw >= InpHammerWickPct * range &&
          uw <= InpHammerHeadPct * range &&
          body <= InpHammerBodyPct * range);
  }

bool IsStarShape(const double o, const double h, const double l, const double c)
  {
   double range = h - l;
   if(range <= 0.0) return(false);
   double body = MathAbs(c - o);
   double uw   = h - MathMax(o, c);
   double lw   = MathMin(o, c) - l;
   return(uw >= InpHammerWickPct * range &&
          lw <= InpHammerHeadPct * range &&
          body <= InpHammerBodyPct * range);
  }

bool IsSolidCandle(const double o, const double h, const double l, const double c)
  {
   double range = h - l;
   if(range <= 0.0) return(false);
   double body = MathAbs(c - o);
   return(body >= InpSolidBodyPct * range);
  }

//+------------------------------------------------------------------+
//| Middle body fully contained inside the first candle's body       |
//|   middle body top <= first body top  AND                         |
//|   middle body bottom >= first body bottom                        |
//+------------------------------------------------------------------+
bool MiddleBodyInsideFirst(const double oMid, const double cMid,
                           const double oFirst, const double cFirst)
  {
   double mTop = MathMax(oMid, cMid);
   double mBot = MathMin(oMid, cMid);
   double fTop = MathMax(oFirst, cFirst);
   double fBot = MathMin(oFirst, cFirst);
   return(mTop <= fTop && mBot >= fBot);
  }

//+------------------------------------------------------------------+
//| Fire the configured notifications                                |
//+------------------------------------------------------------------+
void FireAlerts(const bool isBuy, const double price, const datetime bt)
  {
   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("%s 3-Candle signal | %s %s | %s | close %.*f",
                             dir, _Symbol, TfToStr((ENUM_TIMEFRAMES)_Period),
                             TimeToString(bt, TIME_DATE | TIME_MINUTES),
                             g_digits, price);

   Print(msg);
   if(InpEnableAlert) Alert(msg);
   if(InpEnableSound) PlaySound(isBuy ? InpBuySound : InpSellSound);
   if(InpEnablePush)  SendNotification(msg);
   if(InpEnableEmail) SendMail("3-Candle " + dir + " signal", msg);
  }

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);   // down arrow
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArraySetAsSeries(BuyBuffer,  false);
   ArraySetAsSeries(SellBuffer, false);

   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   IndicatorSetString(INDICATOR_SHORTNAME, "3-Candle Reversal Signal");

   // --- Guards (soft: stays attached but idle, shows a chart note) ---
   g_active = true;
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol))
     {
      g_active = false;
      Comment("3-Candle Signal: this indicator is built for XAUUSD (gold).\n",
              "Current symbol: ", _Symbol,
              "  -> attach to gold or disable 'InpRestrictSymbol'.");
     }
   else if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period))
     {
      g_active = false;
      Comment("3-Candle Signal: supported timeframes are M1 and M5 only.\n",
              "Current timeframe: ", TfToStr((ENUM_TIMEFRAMES)_Period),
              "  -> switch to M1/M5 or disable 'InpRestrictTimeframe'.");
     }
   else
      Comment("");

   // --- Trend MA handle ---
   ArraySetAsSeries(g_maArr, false);
   if(InpUseTrendFilter && InpMAPeriod > 0)
     {
      g_maHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(g_maHandle == INVALID_HANDLE)
         Print("WARNING: failed to create MA handle - MA trend filter disabled.");
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   ObjectsDeleteAll(0, DASH_PREFIX);
   Comment("");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Trend label from the MA slope (for the dashboard)                |
//+------------------------------------------------------------------+
string IndTrendText(const int rates_total)
  {
   if(!(InpMAPeriod > 0) || !g_maReady)
      return("n/a");
   int i     = rates_total - 2;
   int older = i - InpMASlopeBars;
   if(i < 0 || older < 0)
      return("n/a");
   double r = g_maArr[i];
   double o = g_maArr[older];
   if(r == 0.0 || o == 0.0)
      return("n/a");
   if(r > o) return("UP");
   if(r < o) return("DOWN");
   return("FLAT");
  }

//+------------------------------------------------------------------+
//| Dashboard: background panel + text label helpers                 |
//+------------------------------------------------------------------+
void DashPanel(const string key, const int x, const int y, const int w, const int h, const color bg)
  {
   string name = DASH_PREFIX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
  }

void DashLabel(const string key, const string text, const int x, const int y, const color clr, const int fs)
  {
   string name = DASH_PREFIX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| Draw / refresh the on-chart dashboard                            |
//+------------------------------------------------------------------+
void DrawDashboard(const int rates_total)
  {
   if(!InpShowDashboard)
      return;

   int x  = InpDashX;
   int y  = InpDashY;
   int lh = 16;
   int n  = 0;

   DashPanel("BG", x - 6, y - 6, 330, 10 * lh + 14, InpDashBgColor);

   DashLabel("l0", "3-Candle Reversal Signal", x, y + (n++) * lh, clrGold, 10);
   DashLabel("l1", "Pair/TF : " + _Symbol + " " + TfToStr((ENUM_TIMEFRAMES)_Period),
             x, y + (n++) * lh, clrWhite, 9);

   string trend = IndTrendText(rates_total);
   color  tcol  = (trend == "UP" ? clrLime : (trend == "DOWN" ? clrTomato : clrSilver));
   DashLabel("l2", "Trend   : " + trend, x, y + (n++) * lh, tcol, 9);

   DashLabel("l3", "TrendFlt: " + (InpUseTrendFilter ? "ON" : "OFF"), x, y + (n++) * lh, clrWhite, 9);
   DashLabel("l4", "ShapeFlt: " + (InpUseShapeFilter ? "ON" : "OFF"), x, y + (n++) * lh, clrWhite, 9);

   color  scol  = (g_lastSignal == "BUY" ? clrLime : (g_lastSignal == "SELL" ? clrTomato : clrSilver));
   string sigtm = (g_lastSignalTm > 0 ? TimeToString(g_lastSignalTm, TIME_MINUTES) : "-");
   DashLabel("l5", "Signal  : " + g_lastSignal + " " + sigtm, x, y + (n++) * lh, scol, 9);

   bool soundOn = InpEnableSound;
   DashLabel("l6", "Sound   : " + (soundOn ? "ON" : "OFF"),
             x, y + (n++) * lh, (soundOn ? clrLime : clrSilver), 9);
   DashLabel("l7", "Alerts  : " + (InpEnableAlert ? "ON" : "OFF"),
             x, y + (n++) * lh, clrWhite, 9);
   DashLabel("l8", "Buys/Sells: " + (InpEnableBuy ? "Y" : "N") + "/" + (InpEnableSell ? "Y" : "N"),
             x, y + (n++) * lh, clrWhite, 9);

   bool  isSig = (StringFind(g_lastCheck, "signal") >= 0);
   color ccol  = (isSig ? clrLime : clrGoldenrod);
   DashLabel("l9", "Last bar: " + g_lastCheck, x, y + (n++) * lh, ccol, 9);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Trend / reversal context filter (array / non-series indexing)    |
//|   isBuy=true  -> requires prior DOWN trend + local bottom        |
//|   isBuy=false -> requires prior UP  trend + local top            |
//|   Pattern bars: first=i-2, middle=i-1, third(signal)=i           |
//+------------------------------------------------------------------+
bool TrendFilterOK(const bool isBuy, const int i, const int rates_total,
                   const double &high[], const double &low[], const bool maReady)
  {
   if(!InpUseTrendFilter)
      return(true);

   // --- Local swing extreme: the middle candle must be the top/bottom ---
   if(InpSwingLookback > 0)
     {
      // Window = the InpSwingLookback bars ending at the signal bar i.
      int wStart = i - InpSwingLookback + 1;
      if(wStart < 0) wStart = 0;
      int extIdx = i - 1;                       // middle candle
      if(isBuy)
        {
         double m = low[extIdx];
         for(int k = wStart; k <= i; k++)
            if(low[k] < m) return(false);       // a lower low exists -> not the bottom
        }
      else
        {
         double m = high[extIdx];
         for(int k = wStart; k <= i; k++)
            if(high[k] > m) return(false);       // a higher high exists -> not the top
        }
     }

   // --- MA slope: prior trend must be OPPOSITE to the signal ---
   if(InpMAPeriod > 0 && maReady)
     {
      int older = i - InpMASlopeBars;
      if(older >= 0)
        {
         double maRecent = g_maArr[i];
         double maOld    = g_maArr[older];
         if(maRecent != EMPTY_VALUE && maOld != EMPTY_VALUE && maRecent != 0.0 && maOld != 0.0)
           {
            if(!isBuy && !(maRecent > maOld)) return(false); // sell needs rising MA
            if(isBuy  && !(maRecent < maOld)) return(false); // buy  needs falling MA
           }
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Diagnose the last CLOSED bar: which rule stopped a signal?       |
//|   Returns a short human-readable reason for the dashboard/log.   |
//+------------------------------------------------------------------+
string DiagnoseBar(const int sig, const int rates_total, const bool maReady,
                   const double &open[], const double &high[],
                   const double &low[],  const double &close[])
  {
   if(sig < 2)
      return("warming up");

   int i1 = sig - 2, i2 = sig - 1, i3 = sig;   // first, middle, third
   double o1 = open[i1], c1 = close[i1], h1 = high[i1], l1 = low[i1];
   double o2 = open[i2], c2 = close[i2], h2 = high[i2], l2 = low[i2];
   double o3 = open[i3], c3 = close[i3], h3 = high[i3], l3 = low[i3];

   bool buySkel  = IsBear(o1, c1) && IsBull(o2, c2) && IsBull(o3, c3);
   bool sellSkel = IsBull(o1, c1) && IsBear(o2, c2) && IsBear(o3, c3);

   if(!buySkel && !sellSkel)
      return("no 3-candle colour pattern");

   if(buySkel && InpEnableBuy)
     {
      if(!((l2 < l1) && (l2 < l3)))                                 return("BUY blocked: middle not lowest low");
      if(!(c3 > h1))                                                return("BUY blocked: 3rd body doesn't engulf 1st high");
      if(InpUseShapeFilter && !IsHammerShape(o2, h2, l2, c2))       return("BUY blocked: middle not a hammer");
      if(InpUseShapeFilter && !IsSolidCandle(o1, h1, l1, c1))       return("BUY blocked: 1st candle not solid");
      if(InpUseShapeFilter && !IsSolidCandle(o3, h3, l3, c3))       return("BUY blocked: 3rd candle not solid");
      if(InpMiddleInsideFirst && !MiddleBodyInsideFirst(o2, c2, o1, c1)) return("BUY blocked: middle body not inside 1st");
      if(!TrendFilterOK(true, sig, rates_total, high, low, maReady))return("BUY blocked: trend/swing filter");
      return("BUY signal");
     }
   if(sellSkel && InpEnableSell)
     {
      if(!((h2 > h1) && (h2 > h3)))                                 return("SELL blocked: middle not highest high");
      if(!(c3 < l1))                                                return("SELL blocked: 3rd body doesn't engulf 1st low");
      if(InpUseShapeFilter && !IsStarShape(o2, h2, l2, c2))         return("SELL blocked: middle not a shooting star");
      if(InpUseShapeFilter && !IsSolidCandle(o1, h1, l1, c1))       return("SELL blocked: 1st candle not solid");
      if(InpUseShapeFilter && !IsSolidCandle(o3, h3, l3, c3))       return("SELL blocked: 3rd candle not solid");
      if(InpMiddleInsideFirst && !MiddleBodyInsideFirst(o2, c2, o1, c1)) return("SELL blocked: middle body not inside 1st");
      if(!TrendFilterOK(false, sig, rates_total, high, low, maReady))return("SELL blocked: trend/swing filter");
      return("SELL signal");
     }
   return("setup disabled (buy/sell off)");
  }

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int        rates_total,
                const int        prev_calculated,
                const datetime  &time[],
                const double    &open[],
                const double    &high[],
                const double    &low[],
                const double    &close[],
                const long      &tick_volume[],
                const long      &volume[],
                const int       &spread[])
  {
   if(!g_active)
      return(rates_total);

   if(rates_total < 4)
      return(rates_total);

   double gap = InpArrowGapUSD;
   if(gap < 0.0) gap = 0.0;

   // Refresh MA values aligned to the price series (non-series indexing).
   bool maReady = false;
   if(InpUseTrendFilter && InpMAPeriod > 0 && g_maHandle != INVALID_HANDLE)
     {
      if(CopyBuffer(g_maHandle, 0, 0, rates_total, g_maArr) == rates_total)
         maReady = true;
     }
   g_maReady = maReady;

   // Determine where to (re)start computing.
   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BuyBuffer,  EMPTY_VALUE);
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
      start = 2;
     }
   else
      start = prev_calculated - 1;   // recompute the last (now closed) bar
   if(start < 2) start = 2;

   for(int i = start; i <= rates_total - 1; i++)
     {
      BuyBuffer[i]  = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;

      // Only CLOSED bars can be a confirmed signal bar (no repaint).
      if(i > rates_total - 2)
         continue;

      // first = i-2, middle = i-1, third(signal) = i
      double o1 = open[i-2],  c1 = close[i-2], h1 = high[i-2], l1 = low[i-2]; // first
      double o2 = open[i-1],  c2 = close[i-1], h2 = high[i-1], l2 = low[i-1]; // middle
      double o3 = open[i],    c3 = close[i],   h3 = high[i],   l3 = low[i];   // third

      // --- BUY: red -> green -> green -------------------------------
      if(InpEnableBuy)
        {
         bool colorsOK        = IsBear(o1, c1) && IsBull(o2, c2) && IsBull(o3, c3);
         bool middleLowLowest = (l2 < l1) && (l2 < l3);
         bool bodyEngulfHigh  = (c3 > h1);   // green body top = close
         bool shapeOK = true;
         if(InpUseShapeFilter)
            shapeOK = IsHammerShape(o2, h2, l2, c2)   // middle = hammer
                   && IsSolidCandle(o1, h1, l1, c1)    // first  = solid
                   && IsSolidCandle(o3, h3, l3, c3);   // third  = solid
         // NEW: middle body must sit inside the first candle's body
         // (its lower wick still pokes below first low via middleLowLowest).
         bool insideOK = (!InpMiddleInsideFirst) || MiddleBodyInsideFirst(o2, c2, o1, c1);
         if(colorsOK && middleLowLowest && bodyEngulfHigh && shapeOK && insideOK &&
            TrendFilterOK(true, i, rates_total, high, low, maReady))
           {
            BuyBuffer[i] = l3 - gap;
            continue;
           }
        }

      // --- SELL: green -> red -> red --------------------------------
      if(InpEnableSell)
        {
         bool colorsOK          = IsBull(o1, c1) && IsBear(o2, c2) && IsBear(o3, c3);
         bool middleHighHighest = (h2 > h1) && (h2 > h3);
         bool bodyEngulfLow     = (c3 < l1);  // red body bottom = close
         bool shapeOK = true;
         if(InpUseShapeFilter)
            shapeOK = IsStarShape(o2, h2, l2, c2)     // middle = shooting star
                   && IsSolidCandle(o1, h1, l1, c1)    // first  = solid
                   && IsSolidCandle(o3, h3, l3, c3);   // third  = solid
         // NEW: middle body must sit inside the first candle's body
         // (its upper wick still pokes above first high via middleHighHighest).
         bool insideOK = (!InpMiddleInsideFirst) || MiddleBodyInsideFirst(o2, c2, o1, c1);
         if(colorsOK && middleHighHighest && bodyEngulfLow && shapeOK && insideOK &&
            TrendFilterOK(false, i, rates_total, high, low, maReady))
           {
            SellBuffer[i] = h3 + gap;
           }
        }
     }

   // --- Notifications: only for the most recently CLOSED bar, once ---
   int sig = rates_total - 2;

   // Diagnose the last closed bar every calculation (feeds the dashboard).
   g_lastCheck = DiagnoseBar(sig, rates_total, maReady, open, high, low, close);

   if(sig >= 2)
     {
      datetime bt = time[sig];
      if(!g_histInit)
        {
         // First run after (re)load: mark history as seen, don't alert it,
         // but populate the dashboard with the most recent past signal.
         int scanStart = MathMax(2, sig - 1000);
         for(int j = sig; j >= scanStart; j--)
           {
            if(BuyBuffer[j] != EMPTY_VALUE)  { g_lastSignal = "BUY";  g_lastSignalTm = time[j]; break; }
            if(SellBuffer[j] != EMPTY_VALUE) { g_lastSignal = "SELL"; g_lastSignalTm = time[j]; break; }
           }
         g_lastAlertBar = bt;
         g_histInit     = true;
        }
      else if(bt != g_lastAlertBar)
        {
         if(BuyBuffer[sig] != EMPTY_VALUE)
           {
            FireAlerts(true,  close[sig], bt);
            g_lastSignal = "BUY";  g_lastSignalTm = bt;
           }
         else if(SellBuffer[sig] != EMPTY_VALUE)
           {
            FireAlerts(false, close[sig], bt);
            g_lastSignal = "SELL"; g_lastSignalTm = bt;
           }
         else if(InpLogRejections)
           {
            // No signal on this new closed bar: log why, so M1/M5 behaviour
            // is transparent instead of looking "broken".
            PrintFormat("%s %s | %s | %s", _Symbol, TfToStr((ENUM_TIMEFRAMES)_Period),
                        TimeToString(bt, TIME_DATE | TIME_MINUTES), g_lastCheck);
           }
         g_lastAlertBar = bt;   // advance so we evaluate each closed bar once
        }
     }

   DrawDashboard(rates_total);

   return(rates_total);
  }
//+------------------------------------------------------------------+
