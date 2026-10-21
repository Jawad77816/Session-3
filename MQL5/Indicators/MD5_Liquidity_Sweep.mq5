//+------------------------------------------------------------------+
//|                                       MD5_Liquidity_Sweep.mq5     |
//|            MD5 Multi-Timeframe Liquidity Sweep + Fair Value Gap   |
//|                                                                  |
//|  NON-REPAINTING MetaTrader 5 custom indicator.                   |
//|                                                                  |
//|  MULTI-TIMEFRAME LIQUIDITY SWEEPS                                |
//|  --------------------------------------------------------------  |
//|  Attach it to ONE chart (e.g. M1) and it detects and labels the  |
//|  liquidity sweeps of every enabled timeframe at once:            |
//|  M1, M5, M15, M30, H1, H4, D1 (W1 optional).                     |
//|                                                                  |
//|  * Buy-side (BSL) sweep  -> price wicks ABOVE a prior swing HIGH  |
//|    (buy stops) and CLOSES back BELOW it   -> bearish grab,        |
//|    DOWN arrow above the bar, label "<TF> BSL".                    |
//|  * Sell-side (SSL) sweep -> price wicks BELOW a prior swing LOW   |
//|    (sell stops) and CLOSES back ABOVE it  -> bullish grab,        |
//|    UP arrow below the bar, label "<TF> SSL".                      |
//|  * The swept LEVEL is drawn as a line from the swing to the       |
//|    sweep bar. Higher timeframes draw bigger / bolder markers.     |
//|                                                                  |
//|  FAIR VALUE GAPS (chart timeframe)                               |
//|  --------------------------------------------------------------  |
//|  3-candle imbalance classified REAL vs FAKE from displacement    |
//|  (middle-candle range vs ATR), body dominance and gap size;       |
//|  tagged "+sweep" when it forms right after a sweep.               |
//|                                                                  |
//|  WHY IT DOES NOT REPAINT                                         |
//|  --------------------------------------------------------------  |
//|  Each timeframe is read using its CLOSED bars only (series index  |
//|  >= 1); the forming bar of any timeframe is never used. A sweep   |
//|  is decided at the candle's close and anchored to a fixed bar     |
//|  time, so once printed it never moves or disappears. A higher-TF  |
//|  sweep therefore appears when that TF's candle closes             |
//|  (confirmation lag) -- that is honest lag, not repainting.        |
//+------------------------------------------------------------------+
#property copyright "MD5 Liquidity Sweep + FVG"
#property link      ""
#property version   "2.00"
#property description "Non-repaint MULTI-TIMEFRAME ICT liquidity sweeps + Real/Fake Fair Value Gaps"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//==================== INPUTS =======================================
input group "=== Timeframes to scan for sweeps ==="
input bool   InpTF_M1  = true;   // Scan M1 liquidity sweeps
input bool   InpTF_M5  = true;   // Scan M5 liquidity sweeps
input bool   InpTF_M15 = true;   // Scan M15 liquidity sweeps
input bool   InpTF_M30 = true;   // Scan M30 liquidity sweeps
input bool   InpTF_H1  = true;   // Scan H1 liquidity sweeps
input bool   InpTF_H4  = true;   // Scan H4 liquidity sweeps
input bool   InpTF_D1  = true;   // Scan D1 liquidity sweeps
input bool   InpTF_W1  = false;  // Scan W1 liquidity sweeps

input group "=== Liquidity / Sweep ==="
input int    InpPivotLength     = 10;             // Swing pivot strength (bars each side, per TF)
input int    InpBarsPerTF       = 500;            // History bars scanned per timeframe
input bool   InpShowSweptLevel  = true;           // Draw the swept liquidity level line
input double InpArrowOffsetFrac = 0.5;            // Arrow distance from candle (x candle range)
input bool   InpScaleByTF       = true;           // Bigger markers/labels for higher timeframes
input int    InpLabelFontSize   = 8;              // Base label font size
input color  InpBSLColor        = clrTomato;      // Buy-side (high) sweep colour
input color  InpSSLColor        = clrDodgerBlue;  // Sell-side (low) sweep colour

input group "=== Buy / Sell signals (from the strategy) ==="
input bool   InpShowSignals     = true;           // Show prominent BUY/SELL signals
input bool   InpShowSweeps      = true;           // Show the raw sweep markers + levels
input bool   InpSignalStrongClose = true;         // Require sweep to close in the reversal half
input color  InpBuyColor        = clrAqua;        // BUY signal colour ("lime blue" - edit to taste)
input color  InpSellColor       = clrRed;         // SELL signal colour
input int    InpSignalWidth     = 4;              // BUY/SELL arrow size (prominence)
input int    InpSignalFontSize  = 12;             // BUY/SELL label font size
input double InpSignalExtraOffsetFrac = 0.9;      // Extra distance beyond the sweep marker

input group "=== Fair Value Gaps (chart timeframe) ==="
input bool   InpShowFVG         = true;           // Show Fair Value Gaps
input bool   InpShowFakeFVG     = true;           // Also show 'fake' (weak) FVGs
input int    InpATRPeriod       = 14;             // ATR period (displacement reference)
input double InpDispATR         = 1.2;            // REAL: middle candle range >= x * ATR
input double InpMinBodyRatio    = 0.50;           // REAL: middle candle body/range >= this
input double InpMinGapATR       = 0.10;           // REAL: gap size >= x * ATR
input int    InpSweepContextBars= 10;             // Tag FVG "+sweep" if sweep within N bars
input int    InpFVGExtendBars   = 30;             // Extend FVG box this many bars to the right
input int    InpMaxBars         = 2500;           // Max chart bars for FVG (0 = all)
input color  InpRealBullColor   = clrForestGreen; // Real bullish FVG
input color  InpFakeBullColor   = clrPaleGreen;   // Fake bullish FVG
input color  InpRealBearColor   = clrFireBrick;   // Real bearish FVG
input color  InpFakeBearColor   = clrMistyRose;   // Fake bearish FVG

input group "=== Alerts (optional) ==="
input bool   InpAlertPopup      = false;          // Popup alert on a fresh sweep (any TF)
input bool   InpAlertPush       = false;          // Push notification on a fresh sweep (any TF)

input group "=== General ==="
input string InpPrefix          = "MD5LS_";       // Chart-object name prefix

//==================== GLOBALS ======================================
double  g_atr[];                     // ATR of the chart timeframe (FVG displacement reference)
int     g_atrHandle = INVALID_HANDLE;

ENUM_TIMEFRAMES g_tfs[];             // enabled timeframes
string          g_tfNames[];         // their short names ("M1".."W1")
int             g_tfCount = 0;

datetime g_lastBar[];                // last seen bar-0 time per TF (new-bar detection)
datetime g_lastAlertBSL[];           // last alerted BSL sweep time per TF (de-dupe)
datetime g_lastAlertSSL[];           // last alerted SSL sweep time per TF

datetime g_curBSL[];                 // chart-TF BSL sweep times (ascending) -> FVG context
datetime g_curSSL[];                 // chart-TF SSL sweep times (ascending)

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string TFName(const ENUM_TIMEFRAMES tf)
  {
   return(StringSubstr(EnumToString(tf), 7));      // "PERIOD_H4" -> "H4"
  }

int TFRank(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return(0);
      case PERIOD_M5:  return(1);
      case PERIOD_M15: return(2);
      case PERIOD_M30: return(3);
      case PERIOD_H1:  return(4);
      case PERIOD_H4:  return(5);
      case PERIOD_D1:  return(6);
      case PERIOD_W1:  return(7);
      default:         return(0);
     }
  }

int TFWidth(const ENUM_TIMEFRAMES tf)
  {
   return(1 + TFRank(tf)/2);                        // 1..4
  }

void AddTF(const ENUM_TIMEFRAMES tf, const bool on)
  {
   if(!on) return;
   int s = g_tfCount;
   ArrayResize(g_tfs,        s+1);
   ArrayResize(g_tfNames,    s+1);
   ArrayResize(g_lastBar,    s+1);
   ArrayResize(g_lastAlertBSL,s+1);
   ArrayResize(g_lastAlertSSL,s+1);
   g_tfs[s]         = tf;
   g_tfNames[s]     = TFName(tf);
   g_lastBar[s]     = 0;
   g_lastAlertBSL[s]= 0;
   g_lastAlertSSL[s]= 0;
   g_tfCount        = s+1;
  }

void PushTime(datetime &arr[], const datetime t)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n+1);
   arr[n] = t;
  }

// arr is ascending; is there a sweep at/just-before tb within 'withinSec'?
bool RecentSweep(const datetime &arr[], const datetime tb, const int withinSec)
  {
   for(int i=ArraySize(arr)-1; i>=0; i--)
     {
      datetime s = arr[i];
      if(s > tb) continue;                          // sweep is after this bar -> skip
      return((tb - s) <= withinSec);                // nearest prior sweep decides
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Chart-object helpers                                             |
//+------------------------------------------------------------------+
void DrawArrowObj(const string name, datetime t, double price, int code,
                  color clr, int width, int anchor)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,price);
  }

void DrawTextObj(const string name, datetime t, double price, const string txt,
                 color clr, int fontsize, ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontsize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,price);
  }

void DrawSegObj(const string name, datetime t1, double p1, datetime t2, double p2,
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

void DrawRectObj(const string name, datetime t1, double p1, datetime t2, double p2,
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

//+------------------------------------------------------------------+
//| Did the sweep candle close in the reversal half of its range?    |
//+------------------------------------------------------------------+
bool FavorableClose(const bool isBuy, const double h, const double l, const double c)
  {
   double mid = (h + l) * 0.5;
   return(isBuy ? (c >= mid) : (c <= mid));
  }

//+------------------------------------------------------------------+
//| Bold text (used for the prominent BUY/SELL labels)               |
//+------------------------------------------------------------------+
void DrawBigText(const string name, datetime t, double price, const string txt,
                 color clr, int fontsize, ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial Black");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontsize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIME ,0,t);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,price);
  }

//+------------------------------------------------------------------+
//| Alert for a fresh signal / sweep (de-duped per TF + side)        |
//+------------------------------------------------------------------+
void FireAlert(const int ti, const string tn, const int dir,
               const double level, const datetime tSweep, const bool isSignal)
  {
   if(!InpAlertPopup && !InpAlertPush) return;
   if(dir > 0)
     {
      if(tSweep <= g_lastAlertBSL[ti]) return;
      g_lastAlertBSL[ti] = tSweep;
     }
   else
     {
      if(tSweep <= g_lastAlertSSL[ti]) return;
      g_lastAlertSSL[ti] = tSweep;
     }
   bool   isBuy = (dir < 0);
   string what  = isSignal ? (isBuy ? "BUY signal"  : "SELL signal")
                           : (isBuy ? "sell-side liquidity sweep" : "buy-side liquidity sweep");
   string msg   = _Symbol + " " + tn + ": " + what + " @ " + DoubleToString(level,_Digits);
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Draw the raw sweep marker (arrow + TF label + swept level)       |
//+------------------------------------------------------------------+
void DrawSweepMark(const string tn, const ENUM_TIMEFRAMES tf, const int dir,
                   const datetime tSweep, const double level, const datetime tPivot,
                   const double hj, const double lj)
  {
   double rng = hj - lj;
   if(rng <= 0.0) rng = MathMax(level*0.0005, _Point*10);
   double off  = rng * InpArrowOffsetFrac;
   int    w    = (InpScaleByTF ? TFWidth(tf) : 1);
   int    fs   = InpLabelFontSize + (InpScaleByTF ? MathMin(TFRank(tf),5) : 0);
   color  col  = (dir>0 ? InpBSLColor : InpSSLColor);
   string side = (dir>0 ? "BSL" : "SSL");
   string base = InpPrefix + tn + "_" + side + "_" + (string)(long)tSweep;

   double ap = (dir>0 ? hj+off : lj-off);
   int    aAnchor = (dir>0 ? ANCHOR_BOTTOM : ANCHOR_TOP);
   DrawArrowObj(base, tSweep, ap, (dir>0 ? 234 : 233), col, w, aAnchor);

   double lp = (dir>0 ? ap + off*0.6 : ap - off*0.6);
   ENUM_ANCHOR_POINT tAnchor = (dir>0 ? ANCHOR_LOWER : ANCHOR_UPPER);
   DrawTextObj(base+"_x", tSweep, lp, tn+" "+side, col, fs, tAnchor);

   if(InpShowSweptLevel)
      DrawSegObj(base+"_lvl", tPivot, level, tSweep, level, col, w, STYLE_SOLID);
  }

//+------------------------------------------------------------------+
//| Draw the prominent BUY/SELL signal (the strategy trigger)        |
//|   BUY  = sell-side liquidity swept & reclaimed  (bullish)        |
//|   SELL = buy-side  liquidity swept & reclaimed  (bearish)        |
//+------------------------------------------------------------------+
void DrawSignal(const string tn, const ENUM_TIMEFRAMES tf, const bool isBuy,
                const datetime tSweep, const double hj, const double lj)
  {
   double rng = hj - lj;
   if(rng <= 0.0) rng = MathMax(MathAbs(hj)*0.0005, _Point*10);
   double off = rng * (InpArrowOffsetFrac + InpSignalExtraOffsetFrac);
   color  col = (isBuy ? InpBuyColor : InpSellColor);
   int    w   = InpSignalWidth    + (InpScaleByTF ? TFRank(tf)/2 : 0);
   int    fs  = InpSignalFontSize + (InpScaleByTF ? MathMin(TFRank(tf),6) : 0);

   double ap      = (isBuy ? lj-off : hj+off);
   int    code    = (isBuy ? 233 : 234);               // up arrow / down arrow
   int    aAnchor = (isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   string base    = InpPrefix + tn + "_SIG_" + (isBuy ? "BUY" : "SELL") + "_" + (string)(long)tSweep;
   DrawArrowObj(base, tSweep, ap, code, col, w, aAnchor);

   double lp = (isBuy ? ap-off*0.5 : ap+off*0.5);
   ENUM_ANCHOR_POINT tAnchor = (isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
   DrawBigText(base+"_t", tSweep, lp, tn+" "+(isBuy ? "BUY" : "SELL"), col, fs, tAnchor);
  }

//+------------------------------------------------------------------+
//| Handle a confirmed sweep: context + marker + signal + alert      |
//+------------------------------------------------------------------+
void OnSweepHit(const int ti, const string tn, const ENUM_TIMEFRAMES tf, const int dir,
                const datetime tSweep, const double level, const datetime tPivot,
                const double hj, const double lj, const double cj,
                const bool isCur, const bool live)
  {
   if(isCur)
     {
      if(dir > 0) PushTime(g_curBSL, tSweep);
      else        PushTime(g_curSSL, tSweep);
     }

   if(InpShowSweeps)
      DrawSweepMark(tn, tf, dir, tSweep, level, tPivot, hj, lj);

   bool isBuy = (dir < 0);                              // sell-side sweep reclaimed -> BUY
   bool pass  = (!InpSignalStrongClose || FavorableClose(isBuy, hj, lj, cj));
   if(InpShowSignals && pass)
      DrawSignal(tn, tf, isBuy, tSweep, hj, lj);

   if(live)
      FireAlert(ti, tn, dir, level, tSweep, (InpShowSignals && pass));
  }

//+------------------------------------------------------------------+
//| Scan ONE timeframe for pivots + sweeps (closed bars only)        |
//+------------------------------------------------------------------+
void ScanTF(const int ti)
  {
   ENUM_TIMEFRAMES tf = g_tfs[ti];
   string          tn = g_tfNames[ti];
   bool firstScan = (g_lastBar[ti] == 0);            // first time we see this TF -> no alerts
   int  len  = InpPivotLength;
   int  need = 2*len + 3;
   int  avail = Bars(_Symbol, tf);
   if(avail < need+2) return;
   int  cnt = MathMin(InpBarsPerTF, avail);
   if(cnt < need+2) return;

   double   H[], L[], C[];
   datetime T[];
   ArraySetAsSeries(H,true);
   ArraySetAsSeries(L,true);
   ArraySetAsSeries(C,true);
   ArraySetAsSeries(T,true);
   if(CopyHigh (_Symbol,tf,0,cnt,H) <= 0) return;
   if(CopyLow  (_Symbol,tf,0,cnt,L) <= 0) return;
   if(CopyClose(_Symbol,tf,0,cnt,C) <= 0) return;
   if(CopyTime (_Symbol,tf,0,cnt,T) <= 0) return;
   int n = ArraySize(H);
   if(n < need+2) return;

   //--- bounded redraw: clear this TF's objects, then rebuild from the window
   ObjectsDeleteAll(0, InpPrefix + tn + "_");

   bool isCur = (tf == _Period);
   if(isCur) { ArrayResize(g_curBSL,0); ArrayResize(g_curSSL,0); }

   //--- 1) collect confirmed pivots (series idx: 0 = forming, 1 = last closed)
   double   pPrice[];
   datetime pTime[];
   int      pIdx[];
   int      pDir[];
   bool     pSwept[];
   for(int k=len+1; k<=n-1-len; k++)
     {
      bool ph=true, pl=true;
      double hv=H[k], lv=L[k];
      for(int m=k-len; m<=k+len; m++)
        {
         if(m==k) continue;
         if(H[m] >= hv) ph=false;
         if(L[m] <= lv) pl=false;
         if(!ph && !pl) break;
        }
      if(ph)
        {
         int s=ArraySize(pPrice);
         ArrayResize(pPrice,s+1); ArrayResize(pTime,s+1); ArrayResize(pIdx,s+1);
         ArrayResize(pDir,s+1);   ArrayResize(pSwept,s+1);
         pPrice[s]=hv; pTime[s]=T[k]; pIdx[s]=k; pDir[s]=+1; pSwept[s]=false;
        }
      if(pl)
        {
         int s=ArraySize(pPrice);
         ArrayResize(pPrice,s+1); ArrayResize(pTime,s+1); ArrayResize(pIdx,s+1);
         ArrayResize(pDir,s+1);   ArrayResize(pSwept,s+1);
         pPrice[s]=lv; pTime[s]=T[k]; pIdx[s]=k; pDir[s]=-1; pSwept[s]=false;
        }
     }
   int np = ArraySize(pPrice);
   if(np == 0) return;

   //--- 2) sweeps, chronologically oldest -> newest (first touch consumes a level)
   for(int j=n-2; j>=1; j--)
     {
      double hj=H[j], lj=L[j], cj=C[j];
      bool live = (j==1 && !firstScan);
      for(int q=0; q<np; q++)
        {
         if(pSwept[q]) continue;
         if(pIdx[q] <= j) continue;                 // level must be OLDER than the sweep bar
         double P = pPrice[q];
         if(pDir[q] > 0)
           {
            if(hj > P && cj < P)                     // wick above a high, close back below -> SELL
              {
               pSwept[q]=true;
               OnSweepHit(ti, tn, tf, +1, T[j], P, pTime[q], hj, lj, cj, isCur, live);
              }
           }
         else
           {
            if(lj < P && cj > P)                     // wick below a low, close back above -> BUY
              {
               pSwept[q]=true;
               OnSweepHit(ti, tn, tf, -1, T[j], P, pTime[q], hj, lj, cj, isCur, live);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fair Value Gap + Real/Fake classification at chart bar i         |
//+------------------------------------------------------------------+
void CheckFVG(const int i, const datetime &time[], const double &o[],
              const double &high[], const double &low[], const double &close[])
  {
   if(!InpShowFVG) return;
   if(i < 2) return;
   double atr = g_atr[i];
   if(atr <= 0.0) return;

   bool bull = (low[i]  > high[i-2]);
   bool bear = (high[i] < low[i-2]);
   if(!bull && !bear) return;

   double gTop, gBot;
   int    dir;
   if(bull) { gTop = low[i];   gBot = high[i-2]; dir = +1; }   // gap: C1 high -> C3 low
   else     { gTop = low[i-2]; gBot = high[i];   dir = -1; }   // gap: C3 high -> C1 low

   double gap = gTop - gBot;
   if(gap <= 0.0) return;

   double midRange = high[i-1] - low[i-1];
   double midBody  = MathAbs(close[i-1] - o[i-1]);
   double bodyRatio= (midRange > 0.0 ? midBody/midRange : 0.0);

   bool strong = (midRange >= InpDispATR*atr) && (bodyRatio >= InpMinBodyRatio);
   bool bigGap = (gap >= InpMinGapATR*atr);
   bool real   = (strong && bigGap);
   if(!real && !InpShowFakeFVG) return;

   int  withinSec = InpSweepContextBars * PeriodSeconds(_Period);
   bool postSweep = (dir>0 ? RecentSweep(g_curSSL, time[i], withinSec)
                           : RecentSweep(g_curBSL, time[i], withinSec));

   color col;
   if(dir>0) col = (real ? InpRealBullColor : InpFakeBullColor);
   else      col = (real ? InpRealBearColor : InpFakeBearColor);

   datetime t1 = time[i-2];
   datetime t2 = time[i] + (datetime)(InpFVGExtendBars * PeriodSeconds(_Period));
   string   nm = InpPrefix + "FVG_" + (string)(long)time[i-2];
   DrawRectObj(nm, t1, gTop, t2, gBot, col, real, (real ? STYLE_SOLID : STYLE_DOT));

   string lbl = (real ? "FVG" : "fvg?");
   if(postSweep) lbl += "+sweep";
   DrawTextObj(nm+"_t", time[i], (dir>0 ? gTop : gBot), lbl, col, InpLabelFontSize, ANCHOR_LEFT);
  }

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tfCount = 0;
   ArrayResize(g_tfs,0); ArrayResize(g_tfNames,0); ArrayResize(g_lastBar,0);
   ArrayResize(g_lastAlertBSL,0); ArrayResize(g_lastAlertSSL,0);
   AddTF(PERIOD_M1 , InpTF_M1);
   AddTF(PERIOD_M5 , InpTF_M5);
   AddTF(PERIOD_M15, InpTF_M15);
   AddTF(PERIOD_M30, InpTF_M30);
   AddTF(PERIOD_H1 , InpTF_H1);
   AddTF(PERIOD_H4 , InpTF_H4);
   AddTF(PERIOD_D1 , InpTF_D1);
   AddTF(PERIOD_W1 , InpTF_W1);

   ArraySetAsSeries(g_atr, false);
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("MD5LS: failed to create ATR handle");
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "MD5 MTF Liquidity Sweep + FVG");
   ArrayResize(g_curBSL,0);
   ArrayResize(g_curSSL,0);
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

   //--- ATR of the chart timeframe (for FVG), aligned g_atr[i] <-> bar i
   if(BarsCalculated(g_atrHandle) < rates_total) return(prev_calculated);
   if(CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atr) < rates_total) return(prev_calculated);

   bool fullBuild = (prev_calculated == 0);
   if(fullBuild)
     {
      ObjectsDeleteAll(0, InpPrefix);
      for(int t=0; t<g_tfCount; t++)
        { g_lastBar[t]=0; g_lastAlertBSL[t]=0; g_lastAlertSSL[t]=0; }
      ArrayResize(g_curBSL,0);
      ArrayResize(g_curSSL,0);
     }

   //--- Multi-timeframe sweep scan (each TF re-scanned only when it prints a new bar)
   for(int t=0; t<g_tfCount; t++)
     {
      datetime bt = iTime(_Symbol, g_tfs[t], 0);
      if(bt <= 0) continue;                           // that TF not ready yet
      if(fullBuild || bt != g_lastBar[t])
        {
         ScanTF(t);
         g_lastBar[t] = bt;
        }
     }

   //--- Fair Value Gaps on the chart timeframe (closed bars only)
   int startF;
   if(fullBuild)
     {
      startF = warmup;
      if(InpMaxBars > 0 && rates_total - InpMaxBars > startF)
         startF = rates_total - InpMaxBars;
     }
   else
     {
      startF = prev_calculated - 1;
      if(startF < warmup) startF = warmup;
     }
   for(int i=startF; i<rates_total; i++)
     {
      if(i >= rates_total-1) break;                   // never use the forming bar
      CheckFVG(i, time, open, high, low, close);
     }

   ChartRedraw();
   return(rates_total);
  }
//+------------------------------------------------------------------+
