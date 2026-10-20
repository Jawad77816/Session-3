//+------------------------------------------------------------------+
//|                                       MD5_Liquidity_Sweep.mq5     |
//|                   MD5 Liquidity Sweep + Fair Value Gap (ICT/SMC)  |
//|                                                                  |
//|  NON-REPAINTING MetaTrader 5 custom indicator.                   |
//|                                                                  |
//|  WHAT IT MARKS                                                   |
//|  --------------------------------------------------------------  |
//|  * Buy-side liquidity (BSL) sweep  -> price wicks ABOVE a prior   |
//|    swing HIGH (where buy stops rest) and CLOSES back BELOW it.    |
//|    Read as a bearish liquidity grab -> DOWN arrow above the bar.  |
//|  * Sell-side liquidity (SSL) sweep -> price wicks BELOW a prior   |
//|    swing LOW (where sell stops rest) and CLOSES back ABOVE it.    |
//|    Read as a bullish liquidity grab -> UP arrow below the bar.    |
//|  * The swept liquidity LEVEL is drawn as a line at the price the  |
//|    sweep occurred, from the swing to the sweep bar.               |
//|  * Fair Value Gaps (3-candle imbalance) classified REAL vs FAKE:  |
//|      REAL  = born from displacement (large, strong-bodied middle  |
//|              candle + meaningful gap; often right after a sweep)  |
//|      FAKE  = small gap formed in chop / weak momentum             |
//|                                                                  |
//|  WHY IT DOES NOT REPAINT                                         |
//|  --------------------------------------------------------------  |
//|  Every signal is evaluated ONLY on fully CLOSED bars and anchored |
//|  to a fixed bar time. The currently forming bar is never used to  |
//|  print a signal, so once an arrow / level / FVG box is drawn it   |
//|  never moves, changes colour, or disappears. Swing levels require |
//|  'InpPivotLength' closed bars on each side before they are even   |
//|  recognised -- that is confirmation LAG (inherent and honest),    |
//|  not repainting.                                                  |
//+------------------------------------------------------------------+
#property copyright "MD5 Liquidity Sweep + FVG"
#property link      ""
#property version   "1.00"
#property description "Non-repaint ICT Buy/Sell-side liquidity sweeps + Real/Fake Fair Value Gaps"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot 0 : Buy-side liquidity sweep (bearish) -> DOWN arrow above bar
#property indicator_label1  "BSL Sweep"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_width1  2
//--- plot 1 : Sell-side liquidity sweep (bullish) -> UP arrow below bar
#property indicator_label2  "SSL Sweep"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

//==================== INPUTS =======================================
input group "=== Liquidity / Sweep ==="
input int    InpPivotLength     = 10;             // Swing pivot strength (bars each side)
input int    InpMaxActiveLevels = 60;             // Max liquidity levels tracked at once
input bool   InpShowSweptLevel  = true;           // Draw the swept liquidity level line
input double InpArrowOffsetATR  = 0.5;            // Arrow distance from candle (x ATR)
input color  InpBSLColor        = clrTomato;      // Buy-side (high) level + arrow colour
input color  InpSSLColor        = clrDodgerBlue;  // Sell-side (low) level + arrow colour

input group "=== Fair Value Gaps (FVG) ==="
input bool   InpShowFVG         = true;           // Show Fair Value Gaps
input bool   InpShowFakeFVG     = true;           // Also show 'fake' (weak) FVGs
input int    InpATRPeriod       = 14;             // ATR period (displacement reference)
input double InpDispATR         = 1.2;            // REAL: middle candle range >= x * ATR
input double InpMinBodyRatio    = 0.50;           // REAL: middle candle body/range >= this
input double InpMinGapATR       = 0.10;           // REAL: gap size >= x * ATR
input int    InpSweepContextBars= 10;             // Tag FVG "+sweep" if sweep within N bars
input int    InpFVGExtendBars   = 30;             // Extend FVG box this many bars to the right
input color  InpRealBullColor   = clrForestGreen; // Real bullish FVG
input color  InpFakeBullColor   = clrPaleGreen;   // Fake bullish FVG
input color  InpRealBearColor   = clrFireBrick;   // Real bearish FVG
input color  InpFakeBearColor   = clrMistyRose;   // Fake bearish FVG

input group "=== Alerts (optional) ==="
input bool   InpAlertPopup      = false;          // Popup alert on confirmed sweep
input bool   InpAlertPush       = false;          // Push notification on confirmed sweep

input group "=== General ==="
input int    InpMaxBars         = 2500;           // Max history bars to process (0 = all)
input string InpPrefix          = "MD5LS_";       // Chart-object name prefix

//==================== GLOBALS ======================================
double  BufBSL[];                  // buy-side sweep arrows (bearish)
double  BufSSL[];                  // sell-side sweep arrows (bullish)
double  g_atr[];                   // ATR values, aligned so g_atr[i] <-> bar i (0 = oldest)
int     g_atrHandle = INVALID_HANDLE;

struct SLevel
  {
   double   price;                 // level price (the swing high / low)
   datetime time;                  // time of the pivot bar
   int      dir;                   // +1 = BSL (swing high), -1 = SSL (swing low)
   bool     swept;                 // already swept?
  };
SLevel  g_levels[];                // active + consumed liquidity levels

int      g_lastBSLsweepBar = -1000000;  // bar index of last buy-side sweep (for FVG context)
int      g_lastSSLsweepBar = -1000000;  // bar index of last sell-side sweep
datetime g_lastAlertTime   = 0;         // de-dupe alerts (one per bar)

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBSL, INDICATOR_DATA);
   SetIndexBuffer(1, BufSSL, INDICATOR_DATA);
   ArraySetAsSeries(BufBSL, false);
   ArraySetAsSeries(BufSSL, false);
   ArraySetAsSeries(g_atr , false);

   //--- 234 = Wingdings down arrow, 233 = Wingdings up arrow
   PlotIndexSetInteger(0, PLOT_ARROW, 234);
   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBSLColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSSLColor);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString (0, PLOT_LABEL, "BSL Sweep (bearish)");
   PlotIndexSetString (1, PLOT_LABEL, "SSL Sweep (bullish)");

   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("MD5LS: failed to create ATR handle");
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "MD5 Liquidity Sweep + FVG");
   ArrayResize(g_levels, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| De-initialisation                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, InpPrefix);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Pivot (fractal) detection -- strict local extreme over 2*len+1   |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], const int idx, const int len, const int total)
  {
   if(idx-len < 0 || idx+len > total-1) return(false);
   double v = h[idx];
   for(int k=idx-len; k<=idx+len; k++)
     {
      if(k==idx) continue;
      if(h[k] >= v) return(false);     // strict: ties disqualify
     }
   return(true);
  }
bool IsPivotLow(const double &l[], const int idx, const int len, const int total)
  {
   if(idx-len < 0 || idx+len > total-1) return(false);
   double v = l[idx];
   for(int k=idx-len; k<=idx+len; k++)
     {
      if(k==idx) continue;
      if(l[k] <= v) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Liquidity-level bookkeeping                                      |
//+------------------------------------------------------------------+
void TrimLevels()
  {
   int n = ArraySize(g_levels);
   if(n <= InpMaxActiveLevels) return;
   int remove = n - InpMaxActiveLevels;
   for(int i=0; i<n-remove; i++)
      g_levels[i] = g_levels[i+remove];     // drop the oldest 'remove' entries
   ArrayResize(g_levels, n-remove);
  }

void AddLevelUnique(const double price, const datetime t, const int dir)
  {
   int n = ArraySize(g_levels);
   for(int j=0; j<n; j++)
      if(g_levels[j].time==t && g_levels[j].dir==dir) return;   // already stored
   ArrayResize(g_levels, n+1);
   g_levels[n].price = price;
   g_levels[n].time  = t;
   g_levels[n].dir   = dir;
   g_levels[n].swept = false;
   TrimLevels();
  }

//+------------------------------------------------------------------+
//| Chart-object helpers                                             |
//+------------------------------------------------------------------+
void DrawSeg(const string name, datetime t1, double p1, datetime t2, double p2,
             color clr, int width, ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT ,false);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t1);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME ,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,p2);
  }

void DrawRect(const string name, datetime t1, double p1, datetime t2, double p2,
              color clr, bool fill, ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t1);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME ,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,p2);
  }

void DrawText(const string name, datetime t, double price, const string txt, color clr)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,price);
  }

//+------------------------------------------------------------------+
//| Alerts (only for the freshly-closed live bar, never on history)  |
//+------------------------------------------------------------------+
void FireAlert(const datetime t, const string msg)
  {
   if(!InpAlertPopup && !InpAlertPush) return;
   if(t == g_lastAlertTime) return;               // one alert per bar
   g_lastAlertTime = t;
   string full = _Symbol + " " + EnumToString(_Period) + ": " + msg;
   if(InpAlertPopup) Alert(full);
   if(InpAlertPush)  SendNotification(full);
  }

//+------------------------------------------------------------------+
//| Sweep detection on a single CLOSED bar i                         |
//+------------------------------------------------------------------+
void CheckSweeps(const int i, const int rates_total, const int prev_calculated,
                 const datetime &time[], const double &high[],
                 const double &low[], const double &close[])
  {
   double atr = g_atr[i];
   if(atr <= 0.0) atr = (high[i]-low[i]);         // fallback offset
   bool live = (prev_calculated>0 && i==rates_total-2);   // the just-closed real-time bar

   int cnt = ArraySize(g_levels);
   for(int j=0; j<cnt; j++)
     {
      if(g_levels[j].swept) continue;
      if(g_levels[j].time >= time[i]) continue;   // only levels formed BEFORE this bar

      if(g_levels[j].dir > 0)
        {
         //--- Buy-side liquidity: stops resting ABOVE a swing high
         double H = g_levels[j].price;
         if(high[i] > H && close[i] < H)          // wick above, close back below
           {
            g_levels[j].swept = true;
            BufBSL[i]         = high[i] + InpArrowOffsetATR*atr;
            g_lastBSLsweepBar = i;
            if(InpShowSweptLevel)
              {
               string nm = InpPrefix + "BSL_" + (string)(long)g_levels[j].time;
               DrawSeg (nm,       g_levels[j].time, H, time[i], H, InpBSLColor, 1, STYLE_SOLID);
               DrawText(nm+"_t",  g_levels[j].time, H, "BSL", InpBSLColor);
              }
            if(live) FireAlert(time[i], "Buy-side liquidity SWEEP (bearish) @ "+DoubleToString(H,_Digits));
           }
        }
      else
        {
         //--- Sell-side liquidity: stops resting BELOW a swing low
         double L = g_levels[j].price;
         if(low[i] < L && close[i] > L)           // wick below, close back above
           {
            g_levels[j].swept = true;
            BufSSL[i]         = low[i] - InpArrowOffsetATR*atr;
            g_lastSSLsweepBar = i;
            if(InpShowSweptLevel)
              {
               string nm = InpPrefix + "SSL_" + (string)(long)g_levels[j].time;
               DrawSeg (nm,       g_levels[j].time, L, time[i], L, InpSSLColor, 1, STYLE_SOLID);
               DrawText(nm+"_t",  g_levels[j].time, L, "SSL", InpSSLColor);
              }
            if(live) FireAlert(time[i], "Sell-side liquidity SWEEP (bullish) @ "+DoubleToString(L,_Digits));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fair Value Gap detection + Real/Fake classification at bar i     |
//| (3-candle pattern on bars i-2, i-1, i; confirmed at close of i)  |
//+------------------------------------------------------------------+
void CheckFVG(const int i, const datetime &time[], const double &o[],
              const double &high[], const double &low[], const double &close[])
  {
   if(!InpShowFVG) return;
   if(i < 2) return;
   double atr = g_atr[i];
   if(atr <= 0.0) return;

   bool bull = (low[i]  > high[i-2]);   // bullish imbalance: candle3 low above candle1 high
   bool bear = (high[i] < low[i-2]);    // bearish imbalance: candle3 high below candle1 low
   if(!bull && !bear) return;

   double gTop, gBot;
   int    dir;
   if(bull) { gTop = low[i];   gBot = high[i-2]; dir = +1; }   // gap between C1 high and C3 low
   else     { gTop = low[i-2]; gBot = high[i];   dir = -1; }   // gap between C3 high and C1 low

   double gap = gTop - gBot;
   if(gap <= 0.0) return;

   //--- displacement = the middle candle (i-1)
   double midRange = high[i-1] - low[i-1];
   double midBody  = MathAbs(close[i-1] - o[i-1]);
   double bodyRatio= (midRange > 0.0 ? midBody/midRange : 0.0);

   bool strong = (midRange >= InpDispATR*atr) && (bodyRatio >= InpMinBodyRatio);
   bool bigGap = (gap >= InpMinGapATR*atr);
   bool real   = (strong && bigGap);

   if(!real && !InpShowFakeFVG) return;

   //--- was there an aligned sweep just before this gap?
   bool postSweep = false;
   if(dir>0 && (i - g_lastSSLsweepBar) <= InpSweepContextBars) postSweep = true;
   if(dir<0 && (i - g_lastBSLsweepBar) <= InpSweepContextBars) postSweep = true;

   color col;
   if(dir>0) col = (real ? InpRealBullColor : InpFakeBullColor);
   else      col = (real ? InpRealBearColor : InpFakeBearColor);

   datetime t1 = time[i-2];
   datetime t2 = time[i] + (datetime)(InpFVGExtendBars * PeriodSeconds(_Period));

   string nm = InpPrefix + "FVG_" + (string)(long)time[i-2];
   DrawRect(nm, t1, gTop, t2, gBot, col, real, (real ? STYLE_SOLID : STYLE_DOT));

   string lbl = (real ? "FVG" : "fvg?");
   if(postSweep) lbl += "+sweep";
   DrawText(nm+"_t", time[i], (dir>0 ? gTop : gBot), lbl, col);
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
   int warmup = 2*InpPivotLength + 3;
   if(rates_total < warmup + 2) return(0);

   //--- make sure ATR is ready and aligned (g_atr[i] <-> bar i, 0 = oldest)
   if(BarsCalculated(g_atrHandle) < rates_total) return(prev_calculated);
   if(CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atr) < rates_total) return(prev_calculated);

   int start;
   if(prev_calculated == 0)
     {
      //--- full (re)build: wipe objects + state, rebuild deterministically
      ObjectsDeleteAll(0, InpPrefix);
      ArrayResize(g_levels, 0);
      g_lastBSLsweepBar = -1000000;
      g_lastSSLsweepBar = -1000000;
      start = warmup;
      if(InpMaxBars > 0 && rates_total - InpMaxBars > start)
         start = rates_total - InpMaxBars;
      for(int i=0; i<start; i++) { BufBSL[i]=EMPTY_VALUE; BufSSL[i]=EMPTY_VALUE; }
     }
   else
     {
      start = prev_calculated - 1;                 // recompute the previously-last bar
      if(start < warmup) start = warmup;
     }

   for(int i=start; i<rates_total; i++)
     {
      BufBSL[i] = EMPTY_VALUE;
      BufSSL[i] = EMPTY_VALUE;

      //--- NEVER finalise a signal on the still-forming last bar => non-repaint
      if(i >= rates_total-1) break;

      //--- 1) confirm the pivot that completed InpPivotLength bars ago
      int p = i - InpPivotLength;
      if(p >= InpPivotLength)
        {
         if(IsPivotHigh(high, p, InpPivotLength, rates_total))
            AddLevelUnique(high[p], time[p], +1);
         if(IsPivotLow(low, p, InpPivotLength, rates_total))
            AddLevelUnique(low[p], time[p], -1);
        }

      //--- 2) sweeps on this closed bar
      CheckSweeps(i, rates_total, prev_calculated, time, high, low, close);

      //--- 3) fair value gap on the triple ending at this closed bar
      CheckFVG(i, time, open, high, low, close);
     }

   ChartRedraw();
   return(rates_total);
  }
//+------------------------------------------------------------------+
