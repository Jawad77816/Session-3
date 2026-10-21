//+------------------------------------------------------------------+
//|                                  Liquidity_Sweeper_Scalper.mq5    |
//|                 Liquidity Sweeper Scalper (MTF sweeps + signals)  |
//|                                                                  |
//|  NON-REPAINTING MetaTrader 5 custom indicator.                   |
//|                                                                  |
//|  CLEAN CHART BY DEFAULT                                          |
//|  --------------------------------------------------------------  |
//|  On the chart you see only two things:                           |
//|   1. A small CIRCLE on every liquidity sweep, on every enabled    |
//|      timeframe (M1..D1) - at the TOP of the candle for a buy-side |
//|      (high) sweep, at the BOTTOM for a sell-side (low) sweep.     |
//|   2. Prominent BUY / SELL signals (the confirmed, tradeable       |
//|      sweeps) - BUY in aqua below the bar, SELL in red above it.   |
//|                                                                  |
//|  Everything else still runs in the backend but is HIDDEN by       |
//|  default and can be switched back on:                            |
//|   - the verbose BSL/SSL arrows + labels + swept-level lines       |
//|     (InpShowSweeps)                                              |
//|   - Fair Value Gaps, real vs fake (InpShowFVG)                   |
//|                                                                  |
//|  LIQUIDITY SWEEPS (the engine)                                  |
//|  --------------------------------------------------------------  |
//|  * Buy-side (BSL) sweep  -> price wicks ABOVE a prior swing HIGH  |
//|    (buy stops) and CLOSES back BELOW it  -> bearish grab -> SELL. |
//|  * Sell-side (SSL) sweep -> price wicks BELOW a prior swing LOW   |
//|    (sell stops) and CLOSES back ABOVE it -> bullish grab -> BUY.  |
//|  A BUY/SELL only prints once the quality filters pass (close in   |
//|  the reversal half + a follow-through candle breaks the sweep's   |
//|  extreme), so weak counter-trend sweeps are dropped.             |
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
#property copyright "Liquidity Sweeper Scalper"
#property link      ""
#property version   "3.00"
#property description "Non-repaint MTF liquidity sweeps: sweep circles + confirmed BUY/SELL signals"
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

input group "=== Liquidity sweep circles ==="
input bool   InpShowSweepCircle = true;           // Mark every sweep with a circle (top/bottom of candle)
input color  InpSweepCircleColor= clrGold;        // Sweep circle colour
input int    InpSweepCircleCode = 159;            // Circle symbol (Wingdings: 159 dot, 108 big circle)
input int    InpSweepCircleSize = 2;              // Circle size (base width)

input group "=== Buy / Sell signals (from the strategy) ==="
input bool   InpShowSignals     = true;           // Show prominent BUY/SELL signals
input bool   InpShowSweeps      = false;          // Show the verbose sweep arrows+labels+levels (off: use circles)
input bool   InpSignalStrongClose = true;         // Require sweep to close in the reversal half
input color  InpBuyColor        = clrAqua;        // BUY signal colour ("lime blue" - edit to taste)
input color  InpSellColor       = clrRed;         // SELL signal colour
input int    InpSignalWidth     = 4;              // BUY/SELL arrow size (prominence)
input int    InpSignalFontSize  = 12;             // BUY/SELL label font size
input double InpSignalExtraOffsetFrac = 0.9;      // Extra distance beyond the sweep marker

input group "=== Signal quality filters ==="
input bool   InpUseConfirm      = true;           // Require follow-through: next candle breaks the sweep extreme
input bool   InpUseTrendFilter  = false;          // Only signal with the timeframe's EMA trend
input int    InpTrendEMAPeriod  = 50;             // EMA period for the trend filter

input group "=== Fair Value Gaps (chart timeframe, hidden by default) ==="
input bool   InpShowFVG         = false;          // Show Fair Value Gaps (off by default)
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
input string InpPrefix          = "LSS_";         // Chart-object name prefix

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
//| Draw a small circle marking a liquidity sweep                    |
//|   high (buy-side) sweep -> circle at the TOP of the candle        |
//|   low  (sell-side) sweep -> circle at the BOTTOM of the candle    |
//+------------------------------------------------------------------+
void DrawCircle(const string tn, const ENUM_TIMEFRAMES tf, const int dir,
                const datetime tSweep, const double hj, const double lj)
  {
   double rng = hj - lj;
   if(rng <= 0.0) rng = MathMax(MathAbs(hj)*0.0003, _Point*10);
   double off  = rng * 0.25;
   bool   high = (dir > 0);                              // buy-side (high) sweep -> top
   double ap   = (high ? hj+off : lj-off);
   int    w    = InpSweepCircleSize + (InpScaleByTF ? TFRank(tf)/2 : 0);
   int    anc  = (high ? ANCHOR_BOTTOM : ANCHOR_TOP);
   string base = InpPrefix + tn + "_CIR_" + (high ? "H" : "L") + "_" + (string)(long)tSweep;
   DrawArrowObj(base, tSweep, ap, InpSweepCircleCode, InpSweepCircleColor, w, anc);
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

   //--- optional EMA for the trend filter (manual, closed bars only)
   double maArr[];
   if(InpUseTrendFilter)
     {
      ArrayResize(maArr, n);
      double kk = 2.0/(InpTrendEMAPeriod + 1.0);
      maArr[n-1] = C[n-1];
      for(int i=n-2; i>=0; i--)
         maArr[i] = C[i]*kk + maArr[i+1]*(1.0-kk);
     }

   //--- 2) sweeps, chronologically oldest -> newest (first touch consumes a level)
   for(int j=n-2; j>=1; j--)
     {
      double hj=H[j], lj=L[j], cj=C[j];
      for(int q=0; q<np; q++)
        {
         if(pSwept[q]) continue;
         if(pIdx[q] <= j) continue;                 // level must be OLDER than the sweep bar
         double P = pPrice[q];
         int sdir = 0;
         if(pDir[q] > 0 && hj > P && cj < P) sdir = +1;   // buy-side swept  -> SELL
         if(pDir[q] < 0 && lj < P && cj > P) sdir = -1;   // sell-side swept -> BUY
         if(sdir == 0) continue;
         pSwept[q] = true;

         //--- current-TF context for the FVG "+sweep" tag
         if(isCur) { if(sdir>0) PushTime(g_curBSL, T[j]); else PushTime(g_curSSL, T[j]); }

         //--- circle highlight on every sweep (the clean default view)
         if(InpShowSweepCircle)
            DrawCircle(tn, tf, sdir, T[j], hj, lj);

         //--- verbose sweep marker (arrows + labels + level lines), hidden by default
         if(InpShowSweeps)
            DrawSweepMark(tn, tf, sdir, T[j], P, pTime[q], hj, lj);

         //--- signal quality filters --------------------------------------
         bool isBuy = (sdir < 0);
         bool ok    = true;
         // (a) the sweep must close in the reversal half of its own range
         if(InpSignalStrongClose && !FavorableClose(isBuy, hj, lj, cj)) ok = false;
         // (b) follow-through: the NEXT closed candle must break the sweep's extreme
         if(ok && InpUseConfirm)
           {
            if(j < 2) ok = false;                               // next bar not closed yet -> wait
            else if(isBuy ? !(C[j-1] > hj) : !(C[j-1] < lj)) ok = false;
           }
         // (c) optional EMA trend alignment on this timeframe
         if(ok && InpUseTrendFilter)
           {
            double ema = maArr[j];
            if(isBuy ? !(cj > ema) : !(cj < ema)) ok = false;
           }

         if(InpShowSignals && ok)
            DrawSignal(tn, tf, isBuy, T[j], hj, lj);

         //--- alert when the deciding bar is the newest closed bar
         bool sigLive = (InpUseConfirm ? (j==2) : (j==1)) && !firstScan;
         if(InpShowSignals)
           { if(ok && sigLive) FireAlert(ti, tn, sdir, P, T[j], true); }
         else
           { if(j==1 && !firstScan) FireAlert(ti, tn, sdir, P, T[j], false); }
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

   IndicatorSetString(INDICATOR_SHORTNAME, "Liquidity Sweeper Scalper");
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
