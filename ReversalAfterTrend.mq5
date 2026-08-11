//+------------------------------------------------------------------+
//|                                        ReversalAfterTrend.mq5     |
//|      Reversal-After-Trend  —  signal indicator for MetaTrader 5   |
//|      Rebuilt from a price-action video lesson (e.g. XAUUSD, M5)   |
//|                                                                  |
//|  Logic:                                                          |
//|    * A run of N same-colour candles = "the trend".               |
//|    * The first opposite-colour candle = the reversal = signal.   |
//|        - down-run of red candles, then a GREEN candle  -> BUY     |
//|        - up-run   of green candles, then a RED  candle -> SELL    |
//|    * Stop-loss at the reversal / swing extreme.                  |
//|    * Targets at a fixed Risk:Reward (default 1:2 and 1:3).       |
//|                                                                  |
//|  It DRAWS buy/sell arrows and, on every new signal, fires a      |
//|  popup + sound + (optional) push / e-mail alert.                 |
//+------------------------------------------------------------------+
#property copyright "Reversal After Trend"
#property version   "1.00"
#property description "Buy/Sell arrows when a reversal candle appears after a run of same-colour candles. Popup + sound + push alerts. Entry/SL/TP shown."
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

//--- enums --------------------------------------------------------------------
enum ENUM_COLOURMODE
  {
   COLOUR_BODY = 0,   // Body (close vs open)
   COLOUR_PREV = 1    // Close vs previous close
  };
enum ENUM_SLMODE
  {
   SL_REVERSAL = 0,   // Reversal candle
   SL_SWING    = 1    // Swing of the whole move
  };

//--- inputs : signal ----------------------------------------------------------
input group                "=== Signal ==="
input int             InpTrendLen = 5;              // Consecutive trend candles before reversal
input ENUM_COLOURMODE InpColour   = COLOUR_BODY;    // How to define candle colour
input bool            InpBarClose = true;           // Signal only on closed bars (no repaint)

//--- inputs : filters ---------------------------------------------------------
input group                "=== Filters (optional) ==="
input bool  InpUseVolume = false;                   // Require reversal volume > average
input int   InpVolLen    = 20;                      // Volume average length

//--- inputs : risk / reward (used in the alert text + drawn lines) ------------
input group                "=== Risk / Reward ==="
input ENUM_SLMODE InpSLMode   = SL_REVERSAL;        // Stop-loss anchor
input int         InpSLBufPts = 0;                  // Extra stop buffer (points)
input double      InpRR1      = 2.0;                // Primary target R:R  (1 : x)
input double      InpRR2      = 3.0;                // Second  target R:R  (1 : x)
input bool        InpDrawSLTP = true;               // Draw Entry/SL/TP lines for latest signal
input int         InpZoneBars = 12;                 // Line length (bars)

//--- inputs : alerts / notifications ------------------------------------------
input group                "=== Alerts / Notifications ==="
input bool   InpAlertPopup = true;                  // Popup alert
input bool   InpAlertSound = true;                  // Play a sound
input string InpBuySound   = "alert.wav";           // Buy  sound file
input string InpSellSound  = "alert2.wav";          // Sell sound file
input bool   InpPush       = false;                 // Push notification (mobile)
input bool   InpEmail      = false;                 // E-mail alert

//--- buffers & state ----------------------------------------------------------
double   BuyBuffer[];
double   SellBuffer[];
datetime g_lastAlertBar = 0;
string   g_prefix       = "RAT_";

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);          // up arrow (buy)
   PlotIndexSetInteger(1, PLOT_ARROW, 234);          // down arrow (sell)
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME, "Reversal After Trend (" + (string)InpTrendLen + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
  }

//+------------------------------------------------------------------+
//| Candle colour helpers                                            |
//+------------------------------------------------------------------+
bool IsBull(const double &o[], const double &c[], const int i)
  {
   if(InpColour == COLOUR_BODY)
      return(c[i] > o[i]);
   return(i > 0 && c[i] > c[i - 1]);
  }
bool IsBear(const double &o[], const double &c[], const int i)
  {
   if(InpColour == COLOUR_BODY)
      return(c[i] < o[i]);
   return(i > 0 && c[i] < c[i - 1]);
  }
double LowestLow(const double &lo[], const int i, const int n)
  {
   double m = lo[i];
   for(int k = 1; k <= n; k++)
      m = MathMin(m, lo[i - k]);
   return(m);
  }
double HighestHigh(const double &hi[], const int i, const int n)
  {
   double m = hi[i];
   for(int k = 1; k <= n; k++)
      m = MathMax(m, hi[i - k]);
   return(m);
  }
string TFToStr(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);        // e.g. "PERIOD_M5"
   if(StringFind(s, "PERIOD_") == 0)
      s = StringSubstr(s, 7);
   return(s);
  }

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < InpTrendLen + 2)
      return(0);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BuyBuffer,  0.0);
      ArrayInitialize(SellBuffer, 0.0);
      // prime to the last closed bar so we do NOT alert on already-formed
      // (historical) signals when the indicator is first attached / recompiled
      if(rates_total >= 2)
         g_lastAlertBar = time[rates_total - 2];
     }

   int start = (prev_calculated > 1) ? prev_calculated - 1 : InpTrendLen + 1;

   for(int i = start; i < rates_total; i++)
     {
      BuyBuffer[i]  = 0.0;
      SellBuffer[i] = 0.0;

      if(i < InpTrendLen + 1)
         continue;

      //--- optional volume filter (spike on the reversal candle)
      bool volOk = true;
      if(InpUseVolume)
        {
         double sum = 0.0; int cnt = 0;
         for(int k = 0; k < InpVolLen && (i - k) >= 0; k++)
           { sum += (double)tick_volume[i - k]; cnt++; }
         double avg = (cnt > 0) ? sum / cnt : 0.0;
         volOk = ((double)tick_volume[i] > avg);
        }

      //--- run of same-colour candles just BEFORE bar i
      bool downRun = true, upRun = true;
      for(int k = 1; k <= InpTrendLen; k++)
        {
         if(!IsBear(open, close, i - k)) downRun = false;
         if(!IsBull(open, close, i - k)) upRun   = false;
        }

      bool buy  = downRun && IsBull(open, close, i) && volOk;
      bool sell = upRun   && IsBear(open, close, i) && volOk;

      double off = MathMax(high[i] - low[i], _Point) * 0.5;
      if(buy)  BuyBuffer[i]  = low[i]  - off;
      if(sell) SellBuffer[i] = high[i] + off;
     }

   //--- fire alert / draw levels on the most recent qualifying bar
   int sig = InpBarClose ? rates_total - 2 : rates_total - 1;
   if(sig >= InpTrendLen + 1)
     {
      bool isBuy  = (BuyBuffer[sig]  != 0.0);
      bool isSell = (SellBuffer[sig] != 0.0);

      if((isBuy || isSell) && time[sig] != g_lastAlertBar) // a genuinely new signal bar
        {
         g_lastAlertBar = time[sig];
         HandleSignal(isBuy, sig, time, high, low, close);
        }
     }
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Build the message, fire notifications, draw the zone             |
//+------------------------------------------------------------------+
void HandleSignal(const bool isBuy, const int i,
                  const datetime &time[], const double &high[],
                  const double &low[], const double &close[])
  {
   double entry = close[i];
   double buf   = InpSLBufPts * _Point;
   double sl, tp1, tp2, risk;

   if(isBuy)
     {
      double base = (InpSLMode == SL_REVERSAL) ? low[i] : LowestLow(low, i, InpTrendLen);
      sl   = base - buf;
      risk = entry - sl;
      tp1  = entry + InpRR1 * risk;
      tp2  = entry + InpRR2 * risk;
     }
   else
     {
      double base = (InpSLMode == SL_REVERSAL) ? high[i] : HighestHigh(high, i, InpTrendLen);
      sl   = base + buf;
      risk = sl - entry;
      tp1  = entry - InpRR1 * risk;
      tp2  = entry - InpRR2 * risk;
     }

   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("%s  %s  %s   |   Entry %s   SL %s   TP1 %s   TP2 %s",
                             dir, _Symbol, TFToStr((ENUM_TIMEFRAMES)_Period),
                             DoubleToString(entry, _Digits),
                             DoubleToString(sl,   _Digits),
                             DoubleToString(tp1,  _Digits),
                             DoubleToString(tp2,  _Digits));

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(isBuy ? InpBuySound : InpSellSound);
   if(InpPush)       SendNotification(msg);
   if(InpEmail)      SendMail("Reversal signal: " + dir + " " + _Symbol, msg);
   Print(msg);

   if(InpDrawSLTP)
      DrawZone(time[i], entry, sl, tp1, tp2);
  }

//+------------------------------------------------------------------+
//| Chart-object helpers                                             |
//+------------------------------------------------------------------+
void CreateSeg(const string name, datetime t1, double p1, datetime t2, double p2,
               color col, ENUM_LINE_STYLE st = STYLE_SOLID)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
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
void DrawZone(datetime t1, double entry, double sl, double tp1, double tp2)
  {
   ObjectsDeleteAll(0, g_prefix);
   datetime t2 = t1 + (datetime)(PeriodSeconds() * InpZoneBars);

   CreateSeg(g_prefix + "EN",  t1, entry, t2, entry, clrSilver, STYLE_DOT);
   CreateSeg(g_prefix + "SL",  t1, sl,    t2, sl,    clrRed);
   CreateSeg(g_prefix + "TP1", t1, tp1,   t2, tp1,   clrLimeGreen);
   CreateSeg(g_prefix + "TP2", t1, tp2,   t2, tp2,   clrGreen);

   CreateTxt(g_prefix + "tEN", t2, entry, " Entry", clrSilver);
   CreateTxt(g_prefix + "tSL", t2, sl,    " SL",    clrRed);
   CreateTxt(g_prefix + "tT1", t2, tp1,   " TP1 (1:" + DoubleToString(InpRR1, 1) + ")", clrLimeGreen);
   CreateTxt(g_prefix + "tT2", t2, tp2,   " TP2 (1:" + DoubleToString(InpRR2, 1) + ")", clrGreen);

   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
