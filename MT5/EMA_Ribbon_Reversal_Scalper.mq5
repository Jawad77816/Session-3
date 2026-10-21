//+------------------------------------------------------------------+
//|                                EMA_Ribbon_Reversal_Scalper.mq5    |
//|   "The Only EMA Settings You'll Ever Need" (TRIPPATRADING style)  |
//|                                                                  |
//|   5-EMA reversal / pullback framework for scalping M1 / M5       |
//|   on Gold, Crypto, FX, Indices, etc.                             |
//|                                                                  |
//|   STRUCTURE                                                      |
//|     - White channel : EMA(5) High  +  EMA(5) Low                 |
//|                        -> short-term momentum / microstructure   |
//|     - Green channel : EMA(100) High +  EMA(100) Low              |
//|                        -> medium-term retracement / pullback zone|
//|     - Orange line   : EMA(200) Close                             |
//|                        -> structural trend filter (bias)         |
//|                                                                  |
//|   BUY  (reversal, mechanical)                                    |
//|     1. Price CLOSES ABOVE the 200 EMA        (bias flips up)     |
//|     2. Whole WHITE channel moves ABOVE 200 EMA (momentum align)  |
//|     3. Price PULLS BACK and TOUCHES the green channel            |
//|     4. A candle CLOSES ABOVE the white channel  -> BUY signal    |
//|        SL just below green channel, TP = R multiple.             |
//|   SELL = exact mirror of the above.                              |
//|                                                                  |
//|   Filters: no pullback = no trade (no chasing); avoid choppy     |
//|   markets where price keeps crossing the 200 EMA.                |
//+------------------------------------------------------------------+
#property copyright "Built for the TRIPPATRADING EMA Ribbon strategy"
#property link      "https://claude.ai/code"
#property version   "1.00"
#property description "5-EMA reversal/pullback scalping system: white channel (EMA5 H/L),"
#property description "green channel (EMA100 H/L) and the 200 EMA trend filter, with"
#property description "mechanical buy/sell signals, SL/TP levels and alerts."
#property strict

#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   9

//--- Plot 0 : White channel fill
#property indicator_label1  "White Channel"
#property indicator_type1   DRAW_FILLING
//--- Plot 1 : Green channel fill
#property indicator_label2  "Green Channel"
#property indicator_type2   DRAW_FILLING
//--- Plot 2 : EMA5 High (white upper)
#property indicator_label3  "EMA Fast High"
#property indicator_type3   DRAW_LINE
//--- Plot 3 : EMA5 Low (white lower)
#property indicator_label4  "EMA Fast Low"
#property indicator_type4   DRAW_LINE
//--- Plot 4 : EMA100 High (green upper)
#property indicator_label5  "EMA Mid High"
#property indicator_type5   DRAW_LINE
//--- Plot 5 : EMA100 Low (green lower)
#property indicator_label6  "EMA Mid Low"
#property indicator_type6   DRAW_LINE
//--- Plot 6 : EMA200 (orange trend)
#property indicator_label7  "EMA Trend 200"
#property indicator_type7   DRAW_LINE
//--- Plot 7 : Buy arrow
#property indicator_label8  "Buy Signal"
#property indicator_type8   DRAW_ARROW
//--- Plot 8 : Sell arrow
#property indicator_label9  "Sell Signal"
#property indicator_type9   DRAW_ARROW

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== EMA Structure (video defaults) ==="
input int                FastLength   = 5;            // Fast (white) channel EMA length
input int                MidLength    = 100;          // Mid (green) channel EMA length
input int                TrendLength  = 200;          // Trend filter EMA length
input ENUM_MA_METHOD     MaMethod     = MODE_EMA;     // MA method (video uses EMA)

input group "=== Colours & Style ==="
input color              FastLineColor  = clrWhite;      // White channel line colour
input color              MidLineColor   = clrLime;       // Green channel line colour
input color              TrendLineColor = clrOrange;     // 200 EMA line colour
input int                FastLineWidth  = 1;             // White channel line width
input int                MidLineWidth   = 2;             // Green channel line width
input int                TrendLineWidth = 3;             // 200 EMA line width
input bool               ShowFills      = true;          // Shade the channels
input color              FastFillColor  = clrWhiteSmoke; // White channel fill
input color              MidFillColor   = clrGreen;      // Green channel fill
input uchar              FillAlpha      = 230;           // Fill transparency (0=opaque,255=invisible)

input group "=== Signals ==="
input bool               ShowSignals        = true;      // Draw buy/sell arrows
input color              BuyArrowColor      = clrDodgerBlue; // Buy arrow colour
input color              SellArrowColor     = clrRed;        // Sell arrow colour
input int                ArrowWidth         = 2;         // Arrow size (1-5)
input double             ArrowOffsetATR     = 0.6;       // Arrow distance from candle (x ATR)
input bool               RequireFreshCross  = true;      // Require a recent 200-EMA cross (true reversal)
input int                CrossLookback      = 60;        // Max bars from 200-EMA cross to entry
input int                PullbackLookback   = 25;        // Max bars from green-channel touch to entry
input bool               AvoidChop          = true;      // Skip choppy markets
input int                MaxCrossesInWindow = 4;         // Max 200-EMA crosses allowed in CrossLookback

input group "=== Stop Loss / Take Profit ==="
input bool               ShowSLTP        = true;         // Draw SL / TP levels
input double             RiskReward      = 2.0;          // Take-profit as multiple of risk (R)
input double             SL_BufferATR    = 0.15;         // Extra SL buffer beyond green channel (x ATR)
input int                SLTP_Signals    = 3;            // How many recent signals to draw SL/TP for
input int                SLTP_RightBars  = 18;           // How far right to extend SL/TP lines (bars)

input group "=== Alerts ==="
input bool               AlertPopup      = true;         // Popup alert on new signal
input bool               AlertPush       = false;        // Push notification (mobile)
input bool               AlertEmail      = false;        // Email alert
input bool               AlertSound      = true;         // Play sound on new signal
input string             AlertSoundFile  = "alert.wav";  // Sound file

input group "=== Info Panel ==="
input bool               ShowPanel       = true;         // Show on-chart info panel
input int                PanelX          = 12;           // Panel X (px from left)
input int                PanelY          = 20;           // Panel Y (px from top)
input int                PanelFontSize   = 9;            // Panel font size

//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+
double WhiteFillTop[];   // 0
double WhiteFillBot[];   // 1
double GreenFillTop[];   // 2
double GreenFillBot[];   // 3
double FastHighBuf[];    // 4  EMA(FastLength) High  -> white upper
double FastLowBuf[];     // 5  EMA(FastLength) Low   -> white lower
double MidHighBuf[];     // 6  EMA(MidLength)  High  -> green upper
double MidLowBuf[];      // 7  EMA(MidLength)  Low   -> green lower
double TrendBuf[];       // 8  EMA(TrendLength) Close-> orange
double BuyBuf[];         // 9  buy arrow price
double SellBuf[];        // 10 sell arrow price

//--- indicator handles
int hFastHigh = INVALID_HANDLE;
int hFastLow  = INVALID_HANDLE;
int hMidHigh  = INVALID_HANDLE;
int hMidLow   = INVALID_HANDLE;
int hTrend    = INVALID_HANDLE;
int hATR      = INVALID_HANDLE;

double ATRBuf[];         // ATR values (working array, not plotted)

//--- object prefixes
const string SLTP_PREFIX  = "TTrib_SLTP_";
const string PANEL_PREFIX = "TTrib_Panel_";

//--- alert de-dup
datetime g_lastAlertTime  = 0;
datetime g_sltpBuiltFor   = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- map buffers to plots (ORDER MATTERS - matches plot order)
   SetIndexBuffer(0, WhiteFillTop, INDICATOR_DATA);
   SetIndexBuffer(1, WhiteFillBot, INDICATOR_DATA);
   SetIndexBuffer(2, GreenFillTop, INDICATOR_DATA);
   SetIndexBuffer(3, GreenFillBot, INDICATOR_DATA);
   SetIndexBuffer(4, FastHighBuf,  INDICATOR_DATA);
   SetIndexBuffer(5, FastLowBuf,   INDICATOR_DATA);
   SetIndexBuffer(6, MidHighBuf,   INDICATOR_DATA);
   SetIndexBuffer(7, MidLowBuf,    INDICATOR_DATA);
   SetIndexBuffer(8, TrendBuf,     INDICATOR_DATA);
   SetIndexBuffer(9, BuyBuf,       INDICATOR_DATA);
   SetIndexBuffer(10,SellBuf,      INDICATOR_DATA);

   //--- non-timeseries indexing (index 0 = oldest bar)
   ArraySetAsSeries(WhiteFillTop,false); ArraySetAsSeries(WhiteFillBot,false);
   ArraySetAsSeries(GreenFillTop,false); ArraySetAsSeries(GreenFillBot,false);
   ArraySetAsSeries(FastHighBuf,false);  ArraySetAsSeries(FastLowBuf,false);
   ArraySetAsSeries(MidHighBuf,false);   ArraySetAsSeries(MidLowBuf,false);
   ArraySetAsSeries(TrendBuf,false);
   ArraySetAsSeries(BuyBuf,false);       ArraySetAsSeries(SellBuf,false);
   ArraySetAsSeries(ATRBuf,false);

   //--- empty values so warm-up / non-signal bars draw nothing
   for(int p=0; p<9; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Plot 0 : white fill
   PlotIndexSetInteger(0, PLOT_SHOW_DATA, false);
   uint fastARGB = ShowFills ? ColorToARGB(FastFillColor,(uchar)(255-FillAlpha)) : ColorToARGB(FastFillColor,0);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, (long)fastARGB);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, (long)fastARGB);

   //--- Plot 1 : green fill
   PlotIndexSetInteger(1, PLOT_SHOW_DATA, false);
   uint midARGB = ShowFills ? ColorToARGB(MidFillColor,(uchar)(255-FillAlpha)) : ColorToARGB(MidFillColor,0);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, (long)midARGB);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, (long)midARGB);

   //--- Plot 2/3 : white channel lines
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, FastLineColor);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, FastLineWidth);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, FastLineColor);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, FastLineWidth);

   //--- Plot 4/5 : green channel lines
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, MidLineColor);
   PlotIndexSetInteger(4, PLOT_LINE_WIDTH, MidLineWidth);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, MidLineColor);
   PlotIndexSetInteger(5, PLOT_LINE_WIDTH, MidLineWidth);

   //--- Plot 6 : 200 EMA
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, TrendLineColor);
   PlotIndexSetInteger(6, PLOT_LINE_WIDTH, TrendLineWidth);

   //--- Plot 7 : buy arrow (up)
   PlotIndexSetInteger(7, PLOT_ARROW, 233);
   PlotIndexSetInteger(7, PLOT_LINE_COLOR, BuyArrowColor);
   PlotIndexSetInteger(7, PLOT_LINE_WIDTH, ArrowWidth);
   PlotIndexSetInteger(7, PLOT_SHOW_DATA, ShowSignals);

   //--- Plot 8 : sell arrow (down)
   PlotIndexSetInteger(8, PLOT_ARROW, 234);
   PlotIndexSetInteger(8, PLOT_LINE_COLOR, SellArrowColor);
   PlotIndexSetInteger(8, PLOT_LINE_WIDTH, ArrowWidth);
   PlotIndexSetInteger(8, PLOT_SHOW_DATA, ShowSignals);

   //--- start drawing after warm-up
   for(int p=2; p<=6; p++)
      PlotIndexSetInteger(p, PLOT_DRAW_BEGIN, TrendLength);

   //--- create indicator handles (source High / Low / Close as per the strategy)
   hFastHigh = iMA(_Symbol, _Period, FastLength,  0, MaMethod, PRICE_HIGH);
   hFastLow  = iMA(_Symbol, _Period, FastLength,  0, MaMethod, PRICE_LOW);
   hMidHigh  = iMA(_Symbol, _Period, MidLength,   0, MaMethod, PRICE_HIGH);
   hMidLow   = iMA(_Symbol, _Period, MidLength,   0, MaMethod, PRICE_LOW);
   hTrend    = iMA(_Symbol, _Period, TrendLength, 0, MaMethod, PRICE_CLOSE);
   hATR      = iATR(_Symbol, _Period, 14);

   if(hFastHigh==INVALID_HANDLE || hFastLow==INVALID_HANDLE ||
      hMidHigh==INVALID_HANDLE  || hMidLow==INVALID_HANDLE  ||
      hTrend==INVALID_HANDLE    || hATR==INVALID_HANDLE)
     {
      Print("EMA Ribbon Scalper: failed to create one or more indicator handles");
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "EMA Ribbon Scalper ("+
                      (string)FastLength+"/"+(string)MidLength+"/"+(string)TrendLength+")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, SLTP_PREFIX);
   ObjectsDeleteAll(0, PANEL_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Helper : is an EMA value usable (not warm-up / empty)            |
//+------------------------------------------------------------------+
bool Valid(const double v)
  {
   return(v!=0.0 && v!=EMPTY_VALUE && v<DBL_MAX);
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
   int minBars = TrendLength + 5;
   if(rates_total < minBars) return(0);

   //--- make sure the sub-indicators are fully calculated
   if(BarsCalculated(hTrend)   < rates_total) return(prev_calculated);
   if(BarsCalculated(hFastHigh)< rates_total) return(prev_calculated);
   if(BarsCalculated(hMidHigh) < rates_total) return(prev_calculated);
   if(BarsCalculated(hATR)     < rates_total) return(prev_calculated);

   //--- copy EMA / ATR values into the (persistent) buffers, chronological order
   if(CopyBuffer(hFastHigh, 0, 0, rates_total, FastHighBuf) <= 0) return(prev_calculated);
   if(CopyBuffer(hFastLow,  0, 0, rates_total, FastLowBuf ) <= 0) return(prev_calculated);
   if(CopyBuffer(hMidHigh,  0, 0, rates_total, MidHighBuf ) <= 0) return(prev_calculated);
   if(CopyBuffer(hMidLow,   0, 0, rates_total, MidLowBuf  ) <= 0) return(prev_calculated);
   if(CopyBuffer(hTrend,    0, 0, rates_total, TrendBuf   ) <= 0) return(prev_calculated);
   if(ArraySize(ATRBuf)!=rates_total) ArrayResize(ATRBuf, rates_total);
   if(CopyBuffer(hATR,      0, 0, rates_total, ATRBuf     ) <= 0) return(prev_calculated);

   //--- processing window
   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(WhiteFillTop, EMPTY_VALUE);
      ArrayInitialize(WhiteFillBot, EMPTY_VALUE);
      ArrayInitialize(GreenFillTop, EMPTY_VALUE);
      ArrayInitialize(GreenFillBot, EMPTY_VALUE);
      ArrayInitialize(BuyBuf,  EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      start = 0;
     }
   else
      start = prev_calculated - 1;        // recompute last (forming) bar too

   bool newSignal = false;
   datetime newSignalTime = 0;
   bool     newSignalIsBuy = false;
   double   newSignalPrice = 0.0;

   for(int i=start; i<rates_total; i++)
     {
      //--- channel fills mirror the line buffers
      if(ShowFills && Valid(FastHighBuf[i]) && Valid(FastLowBuf[i]))
        { WhiteFillTop[i]=FastHighBuf[i]; WhiteFillBot[i]=FastLowBuf[i]; }
      else
        { WhiteFillTop[i]=EMPTY_VALUE; WhiteFillBot[i]=EMPTY_VALUE; }

      if(ShowFills && Valid(MidHighBuf[i]) && Valid(MidLowBuf[i]))
        { GreenFillTop[i]=MidHighBuf[i]; GreenFillBot[i]=MidLowBuf[i]; }
      else
        { GreenFillTop[i]=EMPTY_VALUE; GreenFillBot[i]=EMPTY_VALUE; }

      //--- default: no arrow on this bar
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      //--- signals only on CLOSED bars with valid EMAs
      if(i < minBars || i >= rates_total-1) continue;
      if(!ShowSignals) continue;
      if(!Valid(TrendBuf[i]) || !Valid(FastHighBuf[i]) || !Valid(FastLowBuf[i]) ||
         !Valid(MidHighBuf[i]) || !Valid(MidLowBuf[i])) continue;
      if(!Valid(TrendBuf[i-1]) || !Valid(FastHighBuf[i-1]) || !Valid(FastLowBuf[i-1])) continue;

      double atr = (Valid(ATRBuf[i]) ? ATRBuf[i] : (high[i]-low[i]));
      if(atr<=0) atr = _Point*10;

      //================= BUY ========================================
      bool freshBreakUp = (close[i] >  FastHighBuf[i]) && (close[i-1] <= FastHighBuf[i-1]);
      bool whiteAbove   = (FastLowBuf[i] > TrendBuf[i]);   // whole white channel above 200
      bool priceAbove   = (close[i] > TrendBuf[i]);

      if(freshBreakUp && whiteAbove && priceAbove)
        {
         bool pulledBack = false;                         // touched green channel recently
         for(int j=i; j>=i-PullbackLookback && j>=1; j--)
            if(Valid(MidHighBuf[j]) && low[j] <= MidHighBuf[j]) { pulledBack=true; break; }

         bool freshCross = !RequireFreshCross;             // recent cross above 200 EMA
         if(RequireFreshCross)
            for(int k=i; k>=i-CrossLookback && k>=1; k--)
               if(Valid(TrendBuf[k]) && Valid(TrendBuf[k-1]) &&
                  close[k] > TrendBuf[k] && close[k-1] <= TrendBuf[k-1]) { freshCross=true; break; }

         bool notChoppy = (!AvoidChop) || (CountCrosses(close,i,CrossLookback) <= MaxCrossesInWindow);

         if(pulledBack && freshCross && notChoppy)
           {
            BuyBuf[i] = low[i] - atr*ArrowOffsetATR;
            if(i == rates_total-2) { newSignal=true; newSignalTime=time[i]; newSignalIsBuy=true;  newSignalPrice=close[i]; }
            continue;                                      // one direction per bar
           }
        }

      //================= SELL =======================================
      bool freshBreakDn = (close[i] <  FastLowBuf[i]) && (close[i-1] >= FastLowBuf[i-1]);
      bool whiteBelow   = (FastHighBuf[i] < TrendBuf[i]);  // whole white channel below 200
      bool priceBelow   = (close[i] < TrendBuf[i]);

      if(freshBreakDn && whiteBelow && priceBelow)
        {
         bool pulledUp = false;                            // retraced up to touch green channel
         for(int j=i; j>=i-PullbackLookback && j>=1; j--)
            if(Valid(MidLowBuf[j]) && high[j] >= MidLowBuf[j]) { pulledUp=true; break; }

         bool freshCrossDn = !RequireFreshCross;
         if(RequireFreshCross)
            for(int k=i; k>=i-CrossLookback && k>=1; k--)
               if(Valid(TrendBuf[k]) && Valid(TrendBuf[k-1]) &&
                  close[k] < TrendBuf[k] && close[k-1] >= TrendBuf[k-1]) { freshCrossDn=true; break; }

         bool notChoppy = (!AvoidChop) || (CountCrosses(close,i,CrossLookback) <= MaxCrossesInWindow);

         if(pulledUp && freshCrossDn && notChoppy)
           {
            SellBuf[i] = high[i] + atr*ArrowOffsetATR;
            if(i == rates_total-2) { newSignal=true; newSignalTime=time[i]; newSignalIsBuy=false; newSignalPrice=close[i]; }
           }
        }
     }

   //--- SL / TP drawing (rebuild only when the newest signal changes)
   if(ShowSLTP)
      DrawSLTP(rates_total, time, high, low, close);

   //--- alerts on a freshly closed-bar signal
   if(newSignal && prev_calculated>0 && newSignalTime>g_lastAlertTime)
     {
      g_lastAlertTime = newSignalTime;
      FireAlert(newSignalIsBuy, newSignalPrice);
     }

   //--- info panel
   if(ShowPanel)
      UpdatePanel(rates_total, time, close);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Count how many times close crossed the 200 EMA in a window       |
//+------------------------------------------------------------------+
int CountCrosses(const double &close[], const int i, const int window)
  {
   int cnt = 0;
   int from = i-window; if(from<1) from=1;
   for(int k=from; k<=i; k++)
     {
      if(!Valid(TrendBuf[k]) || !Valid(TrendBuf[k-1])) continue;
      bool nowAbove  = close[k]   > TrendBuf[k];
      bool prevAbove = close[k-1] > TrendBuf[k-1];
      if(nowAbove != prevAbove) cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| Draw SL / TP levels for the last N signals                       |
//+------------------------------------------------------------------+
void DrawSLTP(const int rates_total,
              const datetime &time[],
              const double &high[],
              const double &low[],
              const double &close[])
  {
   //--- find newest signal bar; skip rebuild if unchanged
   int newest = -1;
   for(int i=rates_total-2; i>=0; i--)
     {
      if((BuyBuf[i]!=EMPTY_VALUE && BuyBuf[i]!=0.0) ||
         (SellBuf[i]!=EMPTY_VALUE && SellBuf[i]!=0.0)) { newest=i; break; }
     }
   if(newest<0) { ObjectsDeleteAll(0, SLTP_PREFIX); g_sltpBuiltFor=0; return; }
   if(time[newest]==g_sltpBuiltFor) return;   // nothing new
   g_sltpBuiltFor = time[newest];

   ObjectsDeleteAll(0, SLTP_PREFIX);

   //--- collect the last SLTP_Signals signals (buy or sell), newest first
   int found = 0;
   for(int i=newest; i>=0 && found<SLTP_Signals; i--)
     {
      bool isBuy  = (BuyBuf[i]!=EMPTY_VALUE  && BuyBuf[i]!=0.0);
      bool isSell = (SellBuf[i]!=EMPTY_VALUE && SellBuf[i]!=0.0);
      if(!isBuy && !isSell) continue;
      found++;

      double entry = close[i];
      double sl, tp;
      double buffer = (Valid(ATRBuf[i])?ATRBuf[i]:(high[i]-low[i]))*SL_BufferATR;

      if(isBuy)
        {
         sl = MidLowBuf[i]  - buffer;              // just below green channel
         tp = entry + RiskReward*(entry - sl);
        }
      else
        {
         sl = MidHighBuf[i] + buffer;              // just above green channel
         tp = entry - RiskReward*(sl - entry);
        }

      datetime t1 = time[i];
      int ri = i + SLTP_RightBars;
      datetime t2 = (ri < rates_total)
                    ? time[ri]
                    : (datetime)((long)time[rates_total-1] + (long)PeriodSeconds()*(long)(ri-(rates_total-1)));

      string tag = SLTP_PREFIX + (isBuy?"B":"S") + (string)(long)t1 + "_";
      DrawLevel(tag+"SL", t1, sl, t2, clrRed,      STYLE_DASH, "SL "+DoubleToString(sl,_Digits));
      DrawLevel(tag+"TP", t1, tp, t2, clrLimeGreen,STYLE_DASH, "TP "+DoubleToString(tp,_Digits));
      DrawLevel(tag+"EN", t1, entry, t2, clrSilver,STYLE_DOT,  "Entry "+DoubleToString(entry,_Digits));
     }
  }

//+------------------------------------------------------------------+
//| Draw a single horizontal level segment + text                    |
//+------------------------------------------------------------------+
void DrawLevel(const string name, const datetime t1, const double price,
               const datetime t2, const color clr, const int style, const string txt)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     { ObjectMove(0,name,0,t1,price); ObjectMove(0,name,1,t2,price); }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   string lname = name+"_txt";
   if(ObjectFind(0,lname)<0)
      ObjectCreate(0, lname, OBJ_TEXT, 0, t2, price);
   else
      ObjectMove(0, lname, 0, t2, price);
   ObjectSetString(0, lname, OBJPROP_TEXT, " "+txt);
   ObjectSetInteger(0, lname, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lname, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, lname, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, lname, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lname, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Fire alert(s) on a new signal                                    |
//+------------------------------------------------------------------+
void FireAlert(const bool isBuy, const double price)
  {
   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("EMA Ribbon Scalper: %s signal  %s  %s  @ %s",
                             dir, _Symbol, TimeframeToStr(_Period),
                             DoubleToString(price,_Digits));
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("EMA Ribbon Scalper "+dir+" "+_Symbol, msg);
   if(AlertSound) PlaySound(AlertSoundFile);
  }

//+------------------------------------------------------------------+
//| Info panel                                                       |
//+------------------------------------------------------------------+
void UpdatePanel(const int rates_total, const datetime &time[], const double &close[])
  {
   int i = rates_total-1;                  // current (forming) bar for live context
   if(i<1 || !Valid(TrendBuf[i]) || !Valid(FastLowBuf[i]) || !Valid(FastHighBuf[i])) return;

   bool bull       = close[i] > TrendBuf[i];
   bool whiteUp    = FastLowBuf[i]  > TrendBuf[i];
   bool whiteDn    = FastHighBuf[i] < TrendBuf[i];
   string bias     = bull ? "BULLISH (above 200)" : "BEARISH (below 200)";
   string momentum = whiteUp ? "Aligned UP" : (whiteDn ? "Aligned DOWN" : "Mixed / no alignment");

   //--- find last signal
   string lastSig = "none yet";
   for(int k=rates_total-2; k>=0 && k>rates_total-500; k--)
     {
      if(BuyBuf[k]!=EMPTY_VALUE && BuyBuf[k]!=0.0)
        { lastSig = "BUY @ "+TimeToString(time[k],TIME_DATE|TIME_MINUTES); break; }
      if(SellBuf[k]!=EMPTY_VALUE && SellBuf[k]!=0.0)
        { lastSig = "SELL @ "+TimeToString(time[k],TIME_DATE|TIME_MINUTES); break; }
     }

   string nextStep;
   if(bull && whiteUp)      nextStep = "Long bias: wait pullback to GREEN, then close above WHITE";
   else if(!bull && whiteDn)nextStep = "Short bias: wait pullback to GREEN, then close below WHITE";
   else                     nextStep = "Wait for 200 EMA break + white-channel alignment";

   string lines[7];
   lines[0] = "EMA RIBBON SCALPER  "+_Symbol+"  "+TimeframeToStr(_Period);
   lines[1] = "Structure: EMA "+(string)FastLength+" (white) / "+(string)MidLength+" (green) / "+(string)TrendLength+" (orange)";
   lines[2] = "Bias:      "+bias;
   lines[3] = "Momentum:  "+momentum;
   lines[4] = "Setup:     "+nextStep;
   lines[5] = "Last sig:  "+lastSig;
   lines[6] = "R:R "+DoubleToString(RiskReward,1)+"   (reversal / pullback system)";

   color pcol = bull ? clrLime : clrOrangeRed;
   for(int n=0; n<7; n++)
     {
      string nm = PANEL_PREFIX+(string)n;
      if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,PanelX);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,PanelY + n*(PanelFontSize+7));
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,PanelFontSize);
      ObjectSetString (0,nm,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,nm,OBJPROP_COLOR, n==0 ? clrWhite : pcol);
      ObjectSetString (0,nm,OBJPROP_TEXT,lines[n]);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_BACK,false);
     }
  }

//+------------------------------------------------------------------+
//| Timeframe to text                                                |
//+------------------------------------------------------------------+
string TimeframeToStr(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return(s);
  }
//+------------------------------------------------------------------+
