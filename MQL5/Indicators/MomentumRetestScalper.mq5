//+------------------------------------------------------------------+
//|                                    MomentumRetestScalper.mq5      |
//|            Momentum Retest Strategy (1-Min Scalping)              |
//|                                                                  |
//|  Faithful implementation of the "Momentum Retest Strategy"       |
//|  taught in the source video. The indicator detects break-and-    |
//|  retest (role reversal) setups confirmed by pin bar / engulfing  |
//|  candlestick patterns, then marks the entry, stop-loss and       |
//|  take-profit and raises an alert.                                 |
//|                                                                  |
//|  STRATEGY LOGIC (long example, mirror for shorts):               |
//|   1. Market structure -> most recent confirmed swing HIGH is the |
//|      active RESISTANCE (swing LOW is active SUPPORT).             |
//|   2. BREAKOUT: a candle closes above the resistance (impulsive   |
//|      move through the level).                                     |
//|   3. RETEST: price pulls back to the broken level. By role       |
//|      reversal, broken resistance now acts as support.            |
//|   4. CONFIRMATION at the level: bullish pin bar (hammer) or       |
//|      bullish engulfing candle.                                    |
//|   5. ENTRY at the close of the confirmation candle.               |
//|      SL below the retest low; TP = entry + RR * risk.             |
//|                                                                  |
//|  NOTE: This is an INDICATOR (signals + alerts), not an auto-      |
//|  trader. No indicator can guarantee profit. Always backtest,     |
//|  forward-test on demo, and use disciplined risk management.       |
//+------------------------------------------------------------------+
#property copyright "Momentum Retest Strategy"
#property version   "1.00"
#property description "Break-and-retest (role reversal) scalping signals with pin bar / engulfing confirmation. Educational tool - not financial advice."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0: Buy arrow (drawn below the entry bar)
#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

//--- Plot 1: Sell arrow (drawn above the entry bar)
#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//============================ INPUTS ================================//
input group "=== Market Structure ==="
input int    InpSwingLookback     = 5;     // Swing lookback (bars each side of a pivot)
input int    InpMaxHistoryBars    = 1500;  // Bars of history to scan

input group "=== Breakout & Retest ==="
input bool   InpUseATR            = true;  // Use ATR-adaptive buffers (recommended)
input int    InpATRPeriod         = 14;    // ATR period
input double InpBreakoutBufferATR = 0.05;  // Breakout buffer (x ATR) - close must clear the level by this
input double InpRetestToleranceATR= 0.20;  // Retest tolerance (x ATR) - how close the wick must revisit the level
input double InpSLBufferATR       = 0.10;  // Extra SL buffer beyond the retest swing (x ATR)
input int    InpBreakoutBufferPts = 20;    // Breakout buffer in points  (if ATR mode is OFF)
input int    InpRetestTolerancePts= 60;    // Retest tolerance in points (if ATR mode is OFF)
input int    InpSLBufferPts       = 30;    // SL buffer in points        (if ATR mode is OFF)
input int    InpMaxBarsForRetest  = 20;    // Max bars to wait for a valid retest after breakout

input group "=== Confirmation Patterns ==="
input bool   InpUsePinbar         = true;  // Use pin bar (hammer / shooting star)
input bool   InpUseEngulfing      = true;  // Use engulfing pattern
input double InpPinWickBodyRatio  = 2.0;   // Pin bar: dominant wick >= X * body
input double InpPinMaxOppWickPct  = 0.35;  // Pin bar: opposite wick <= X * range
input double InpPinBodyMaxPct     = 0.40;  // Pin bar: body <= X * range

input group "=== Trade Management ==="
input double InpRiskReward        = 2.0;   // Reward : Risk ratio for the TP
input bool   InpRequireImpulse    = false; // Require an impulsive breakout candle
input double InpMinBreakBodyATR   = 0.5;   // Min breakout candle body (x ATR) if impulse required

input group "=== Visuals ==="
input bool   InpShowSLTP          = true;  // Draw SL / TP / entry boxes
input bool   InpShowLevel         = true;  // Draw the broken (retest) level
input int    InpMaxSetupsDrawn    = 8;     // Max recent setups to draw SL/TP for
input color  InpBuyColor          = clrLime;   // Buy visuals color
input color  InpSellColor         = clrRed;    // Sell visuals color
input color  InpLevelColor        = clrGold;   // Retest level color

input group "=== Alerts ==="
input bool   InpAlertPopup        = true;  // Popup alert on new signal
input bool   InpAlertPush         = false; // Push notification on new signal
input bool   InpAlertEmail        = false; // Email on new signal

//============================ BUFFERS ==============================//
double BuyBuffer[];
double SellBuffer[];

//============================ GLOBALS ==============================//
int      g_atrHandle = INVALID_HANDLE;
string   g_prefix    = "MRS_";        // graphical object name prefix
datetime g_lastAlertBuy  = 0;         // de-dup alert per signal bar
datetime g_lastAlertSell = 0;

// Small container describing a detected setup (used for drawing).
struct Setup
{
   bool     isBuy;
   datetime entryTime;
   double   entry;
   double   sl;
   double   tp;
   double   level;      // broken level (retest price)
   datetime levelTime;  // where the level was broken
};

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);      // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);      // down arrow
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  12);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -12);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellColor);

   ArraySetAsSeries(BuyBuffer,  false);
   ArraySetAsSeries(SellBuffer, false);

   if(InpUseATR)
   {
      g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Print("MomentumRetestScalper: failed to create ATR handle");
         return(INIT_FAILED);
      }
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Momentum Retest Scalper");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization - clean up our objects                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//| Pattern helpers (operate on absolute, ascending bar indices)     |
//+------------------------------------------------------------------+
bool IsPivotHigh(const int i, const double &high[], const int N, const int total)
{
   if(i - N < 0 || i + N > total - 1)
      return(false);
   double v = high[i];
   for(int k = 1; k <= N; k++)
   {
      if(high[i - k] > v) return(false);   // strictly higher on the left rejects
      if(high[i + k] > v) return(false);   // strictly higher on the right rejects
   }
   return(true);
}

bool IsPivotLow(const int i, const double &low[], const int N, const int total)
{
   if(i - N < 0 || i + N > total - 1)
      return(false);
   double v = low[i];
   for(int k = 1; k <= N; k++)
   {
      if(low[i - k] < v) return(false);
      if(low[i + k] < v) return(false);
   }
   return(true);
}

// Bullish pin bar / hammer: small body, long lower wick, little/no upper wick.
bool IsBullishPin(const int i, const double &o[], const double &h[],
                  const double &l[], const double &c[])
{
   double range = h[i] - l[i];
   if(range <= 0) return(false);
   double body  = MathAbs(c[i] - o[i]);
   double upper = h[i] - MathMax(o[i], c[i]);
   double lower = MathMin(o[i], c[i]) - l[i];
   if(body <= 0) body = range * 0.0001;             // avoid div-by-zero on doji
   if(lower < InpPinWickBodyRatio * body) return(false);
   if(upper > InpPinMaxOppWickPct * range) return(false);
   if(body  > InpPinBodyMaxPct   * range) return(false);
   return(true);
}

// Bearish pin bar / shooting star: small body, long upper wick, little/no lower wick.
bool IsBearishPin(const int i, const double &o[], const double &h[],
                  const double &l[], const double &c[])
{
   double range = h[i] - l[i];
   if(range <= 0) return(false);
   double body  = MathAbs(c[i] - o[i]);
   double upper = h[i] - MathMax(o[i], c[i]);
   double lower = MathMin(o[i], c[i]) - l[i];
   if(body <= 0) body = range * 0.0001;
   if(upper < InpPinWickBodyRatio * body) return(false);
   if(lower > InpPinMaxOppWickPct * range) return(false);
   if(body  > InpPinBodyMaxPct   * range) return(false);
   return(true);
}

// Bullish engulfing: prior bearish body fully engulfed by current bullish body.
bool IsBullishEngulf(const int i, const double &o[], const double &c[])
{
   if(i < 1) return(false);
   bool prevBear = c[i-1] < o[i-1];
   bool currBull = c[i]   > o[i];
   if(!prevBear || !currBull) return(false);
   return(o[i] <= c[i-1] && c[i] >= o[i-1]);
}

// Bearish engulfing: prior bullish body fully engulfed by current bearish body.
bool IsBearishEngulf(const int i, const double &o[], const double &c[])
{
   if(i < 1) return(false);
   bool prevBull = c[i-1] > o[i-1];
   bool currBear = c[i]   < o[i];
   if(!prevBull || !currBear) return(false);
   return(o[i] >= c[i-1] && c[i] <= o[i-1]);
}

bool BullConfirm(const int i, const double &o[], const double &h[],
                 const double &l[], const double &c[])
{
   if(InpUsePinbar    && IsBullishPin(i,o,h,l,c))  return(true);
   if(InpUseEngulfing && IsBullishEngulf(i,o,c))   return(true);
   return(false);
}

bool BearConfirm(const int i, const double &o[], const double &h[],
                 const double &l[], const double &c[])
{
   if(InpUsePinbar    && IsBearishPin(i,o,h,l,c))  return(true);
   if(InpUseEngulfing && IsBearishEngulf(i,o,c))   return(true);
   return(false);
}

//+------------------------------------------------------------------+
//| Draw one setup's SL / TP / entry / level                         |
//+------------------------------------------------------------------+
void DrawSetup(const Setup &s)
{
   string tag = g_prefix + (s.isBuy ? "B_" : "S_") + (string)(long)s.entryTime;

   // right edge of the boxes: a few bars into the future for readability
   datetime rightEdge = s.entryTime + (datetime)(PeriodSeconds(_Period) * 10);
   color    col       = s.isBuy ? InpBuyColor : InpSellColor;

   if(InpShowSLTP)
   {
      // TP box (entry -> tp) : shaded green, drawn behind the candles
      string nTP = tag + "_TP";
      ObjectCreate(0, nTP, OBJ_RECTANGLE, 0, s.entryTime, s.entry, rightEdge, s.tp);
      ObjectSetInteger(0, nTP, OBJPROP_COLOR, clrSeaGreen);
      ObjectSetInteger(0, nTP, OBJPROP_FILL, true);
      ObjectSetInteger(0, nTP, OBJPROP_BACK, true);

      // SL box (entry -> sl) : shaded red, drawn behind the candles
      string nSL = tag + "_SL";
      ObjectCreate(0, nSL, OBJ_RECTANGLE, 0, s.entryTime, s.entry, rightEdge, s.sl);
      ObjectSetInteger(0, nSL, OBJPROP_COLOR, clrFireBrick);
      ObjectSetInteger(0, nSL, OBJPROP_FILL, true);
      ObjectSetInteger(0, nSL, OBJPROP_BACK, true);

      // Entry line
      string nE = tag + "_E";
      ObjectCreate(0, nE, OBJ_TREND, 0, s.entryTime, s.entry, rightEdge, s.entry);
      ObjectSetInteger(0, nE, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nE, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);

      // RR label
      string nL = tag + "_LBL";
      double risk = MathAbs(s.entry - s.sl);
      double rr   = (risk > 0) ? MathAbs(s.tp - s.entry) / risk : 0.0;
      ObjectCreate(0, nL, OBJ_TEXT, 0, rightEdge, s.tp);
      ObjectSetString(0, nL, OBJPROP_TEXT,
                      StringFormat("%s  RR %.2f", (s.isBuy ? "BUY" : "SELL"), rr));
      ObjectSetInteger(0, nL, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nL, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, nL, OBJPROP_ANCHOR, ANCHOR_LEFT);
   }

   if(InpShowLevel)
   {
      // The broken level that price retested (role reversal)
      string nLv = tag + "_LV";
      ObjectCreate(0, nLv, OBJ_TREND, 0, s.levelTime, s.level, rightEdge, s.level);
      ObjectSetInteger(0, nLv, OBJPROP_COLOR, InpLevelColor);
      ObjectSetInteger(0, nLv, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nLv, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nLv, OBJPROP_RAY_RIGHT, false);
   }
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
   int minBars = 2 * InpSwingLookback + InpMaxBarsForRetest + InpATRPeriod + 5;
   if(rates_total < minBars)
      return(rates_total);

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   // Only re-run the full scan when a new bar has closed (efficiency + no repaint).
   static datetime s_lastBarTime = 0;
   datetime lastClosedTime = time[rates_total - 2];   // rates_total-1 is the forming bar
   if(lastClosedTime == s_lastBarTime && prev_calculated > 0)
      return(rates_total);

   // Determine scan window [startIdx .. lastClosed].
   int lastClosed = rates_total - 2;                  // last fully closed bar
   int startIdx   = MathMax(InpSwingLookback + 1, rates_total - InpMaxHistoryBars);

   // ATR values (fetch before committing this bar so we can retry if not ready).
   double atr[];
   ArraySetAsSeries(atr, false);
   if(InpUseATR)
   {
      if(CopyBuffer(g_atrHandle, 0, 0, rates_total, atr) <= 0)
         return(prev_calculated);                     // ATR not ready yet; retry next tick
   }

   // Commit: produce a fresh scan for this newly closed bar.
   s_lastBarTime = lastClosedTime;
   ArrayInitialize(BuyBuffer,  0.0);
   ArrayInitialize(SellBuffer, 0.0);
   ObjectsDeleteAll(0, g_prefix);

   // ---- State machine (single active setup per direction) ----
   double resLevel = 0.0;  int resBar = -1;  bool haveRes = false;   // active resistance (swing high)
   double supLevel = 0.0;  int supBar = -1;  bool haveSup = false;   // active support (swing low)

   bool   brokeUp = false;  double brkUpLvl = 0.0;  int brkUpBar = -1;  int upDeadline = 0;  bool retestUp = false;  double minLowSinceUp = 0.0;
   bool   brokeDn = false;  double brkDnLvl = 0.0;  int brkDnBar = -1;  int dnDeadline = 0;  bool retestDn = false;  double maxHighSinceDn = 0.0;

   Setup drawn[];
   int   drawnCount = 0;

   datetime newestBuyTime  = 0;
   datetime newestSellTime = 0;
   double   newestBuyPrice  = 0.0;
   double   newestSellPrice = 0.0;

   for(int i = startIdx; i <= lastClosed; i++)
   {
      double atrV = InpUseATR ? atr[i] : 0.0;
      double breakBuf = InpUseATR ? InpBreakoutBufferATR  * atrV : InpBreakoutBufferPts  * _Point;
      double retestTol= InpUseATR ? InpRetestToleranceATR * atrV : InpRetestTolerancePts * _Point;
      double slBuf    = InpUseATR ? InpSLBufferATR        * atrV : InpSLBufferPts        * _Point;
      if(InpUseATR && atrV <= 0.0) continue;

      //--- 1) Update structure: newest confirmed pivot at m = i - InpSwingLookback
      int m = i - InpSwingLookback;
      if(m >= InpSwingLookback)
      {
         if(IsPivotHigh(m, high, InpSwingLookback, rates_total) && !brokeUp)
         { resLevel = high[m]; resBar = m; haveRes = true; }

         if(IsPivotLow(m, low, InpSwingLookback, rates_total) && !brokeDn)
         { supLevel = low[m]; supBar = m; haveSup = true; }
      }

      //================= LONG branch =================//
      if(!brokeUp && haveRes && i > resBar)
      {
         bool impulseOK = true;
         if(InpRequireImpulse)
         {
            double bodyC = MathAbs(close[i] - open[i]);
            impulseOK = (!InpUseATR) ? true : (bodyC >= InpMinBreakBodyATR * atrV);
         }
         if(close[i] > resLevel + breakBuf && impulseOK)
         {
            brokeUp = true; brkUpLvl = resLevel; brkUpBar = i;
            upDeadline = i + InpMaxBarsForRetest;
            retestUp = false; minLowSinceUp = low[i];
            haveRes = false;   // consume the level
         }
      }
      else if(brokeUp)
      {
         if(low[i] < minLowSinceUp) minLowSinceUp = low[i];

         if(i > upDeadline)
         {
            brokeUp = false;   // setup expired without a valid retest
         }
         else
         {
            // retest: price wicks back down to the broken level
            if(low[i] <= brkUpLvl + retestTol)
               retestUp = true;

            bool nearLevel = (MathMin(low[i], (i>0?low[i-1]:low[i])) <= brkUpLvl + retestTol);
            if(retestUp && nearLevel && close[i] > brkUpLvl &&
               BullConfirm(i, open, high, low, close))
            {
               double entry = close[i];
               double sl    = MathMin(minLowSinceUp, low[i]) - slBuf;
               double risk  = entry - sl;
               if(risk > 0)
               {
                  double tp = entry + InpRiskReward * risk;
                  BuyBuffer[i] = low[i] - slBuf;      // arrow just under the bar
                  newestBuyTime = time[i]; newestBuyPrice = entry;

                  ArrayResize(drawn, drawnCount + 1);
                  drawn[drawnCount].isBuy     = true;
                  drawn[drawnCount].entryTime = time[i];
                  drawn[drawnCount].entry     = entry;
                  drawn[drawnCount].sl        = sl;
                  drawn[drawnCount].tp        = tp;
                  drawn[drawnCount].level     = brkUpLvl;
                  drawn[drawnCount].levelTime = time[brkUpBar];
                  drawnCount++;
               }
               brokeUp = false;   // done with this setup
            }
         }
      }

      //================= SHORT branch =================//
      if(!brokeDn && haveSup && i > supBar)
      {
         bool impulseOK = true;
         if(InpRequireImpulse)
         {
            double bodyC = MathAbs(close[i] - open[i]);
            impulseOK = (!InpUseATR) ? true : (bodyC >= InpMinBreakBodyATR * atrV);
         }
         if(close[i] < supLevel - breakBuf && impulseOK)
         {
            brokeDn = true; brkDnLvl = supLevel; brkDnBar = i;
            dnDeadline = i + InpMaxBarsForRetest;
            retestDn = false; maxHighSinceDn = high[i];
            haveSup = false;
         }
      }
      else if(brokeDn)
      {
         if(high[i] > maxHighSinceDn) maxHighSinceDn = high[i];

         if(i > dnDeadline)
         {
            brokeDn = false;
         }
         else
         {
            if(high[i] >= brkDnLvl - retestTol)
               retestDn = true;

            bool nearLevel = (MathMax(high[i], (i>0?high[i-1]:high[i])) >= brkDnLvl - retestTol);
            if(retestDn && nearLevel && close[i] < brkDnLvl &&
               BearConfirm(i, open, high, low, close))
            {
               double entry = close[i];
               double sl    = MathMax(maxHighSinceDn, high[i]) + slBuf;
               double risk  = sl - entry;
               if(risk > 0)
               {
                  double tp = entry - InpRiskReward * risk;
                  SellBuffer[i] = high[i] + slBuf;
                  newestSellTime = time[i]; newestSellPrice = entry;

                  ArrayResize(drawn, drawnCount + 1);
                  drawn[drawnCount].isBuy     = false;
                  drawn[drawnCount].entryTime = time[i];
                  drawn[drawnCount].entry     = entry;
                  drawn[drawnCount].sl        = sl;
                  drawn[drawnCount].tp        = tp;
                  drawn[drawnCount].level     = brkDnLvl;
                  drawn[drawnCount].levelTime = time[brkDnBar];
                  drawnCount++;
               }
               brokeDn = false;
            }
         }
      }
   }

   //--- Draw the most recent N setups only (avoid clutter)
   int drawFrom = MathMax(0, drawnCount - InpMaxSetupsDrawn);
   for(int d = drawFrom; d < drawnCount; d++)
      DrawSetup(drawn[d]);

   //--- Alerts: only for a signal that formed on the just-closed bar
   if(newestBuyTime == lastClosedTime && g_lastAlertBuy != lastClosedTime)
   {
      g_lastAlertBuy = lastClosedTime;
      RaiseAlert(true, newestBuyPrice);
   }
   if(newestSellTime == lastClosedTime && g_lastAlertSell != lastClosedTime)
   {
      g_lastAlertSell = lastClosedTime;
      RaiseAlert(false, newestSellPrice);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Fire the configured alerts                                       |
//+------------------------------------------------------------------+
void RaiseAlert(const bool isBuy, const double price)
{
   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("Momentum Retest %s  %s  %s @ %s",
                             dir, _Symbol,
                             EnumToString((ENUM_TIMEFRAMES)_Period),
                             DoubleToString(price, _Digits));
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Momentum Retest Signal", msg);
}
//+------------------------------------------------------------------+
