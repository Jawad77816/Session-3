//+------------------------------------------------------------------+
//|                                        MTF_Trend_Alignment.mq5    |
//|                     Multi-Timeframe Trend Alignment Signal        |
//|                                                                   |
//|  Strategy:                                                        |
//|   1. Check trend on H4, H1 and M15.                               |
//|   2. If all three are BULLISH, look at the entry chart (M1).      |
//|      - If M1 is also bullish -> BUY signal.                       |
//|   3. If all three are BEARISH, look at the entry chart (M1).      |
//|      - If M1 is also bearish -> SELL signal.                      |
//|                                                                   |
//|  For every signal the indicator draws the Entry, Stop-Loss (SL)   |
//|  and Take-Profit (TP) levels. TP distance = SL distance * Reward  |
//|  ratio (default 1:3, can be set to 1:4 or any value).             |
//+------------------------------------------------------------------+
#property copyright "MTF Trend Alignment"
#property version   "1.00"
#property description "Buy/Sell signals when H4 + H1 + M15 + M1 trends align. Draws Entry / SL / TP at a 1:3 (or 1:4) risk-reward ratio."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0 : BUY arrow
#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

//--- Plot 1 : SELL arrow
#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//+------------------------------------------------------------------+
//| Trend detection method                                           |
//+------------------------------------------------------------------+
enum ENUM_TREND_METHOD
  {
   TREND_EMA_CROSS = 0,  // Fast EMA vs Slow EMA (+ price filter)
   TREND_PRICE_EMA = 1   // Price vs a single EMA
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group             "=== Timeframes ==="
input ENUM_TIMEFRAMES   InpTF1        = PERIOD_H4;        // Higher TF 1
input ENUM_TIMEFRAMES   InpTF2        = PERIOD_H1;        // Higher TF 2
input ENUM_TIMEFRAMES   InpTF3        = PERIOD_M15;       // Higher TF 3
input ENUM_TIMEFRAMES   InpEntryTF    = PERIOD_M1;        // Entry timeframe (attach chart)

input group             "=== Trend Definition ==="
input ENUM_TREND_METHOD InpMethod     = TREND_EMA_CROSS;  // Trend method
input int               InpFastEMA    = 21;               // Fast EMA period
input int               InpSlowEMA    = 50;               // Slow EMA period
input ENUM_MA_PRICE     InpAppliedPr  = PRICE_CLOSE;      // Applied price

input group             "=== Risk / Reward ==="
input int               InpATRPeriod  = 14;               // ATR period (SL distance)
input double            InpATRMult    = 1.5;              // ATR multiplier for SL
input double            InpRewardRatio= 3.0;              // Reward ratio (3 = 1:3, 4 = 1:4)

input group             "=== Alerts & Display ==="
input bool              InpPopupAlert = true;             // Popup alert on signal
input bool              InpPushAlert  = false;            // Push notification on signal
input bool              InpDrawLevels = true;             // Draw Entry / SL / TP lines
input int               InpArrowGapPts= 10;               // Arrow gap from candle (points)

//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+
double BufBuy[];
double BufSell[];

//--- Indicator handles
int hFast1,hSlow1,hFast2,hSlow2,hFast3,hSlow3,hFastE,hSlowE;
int hATR;

//--- Object name prefix
const string OBJ_PREFIX = "MTF_TA_";

//--- Remember the last signal bar so alerts/levels fire only once per bar
datetime g_lastSignalBar = 0;

//+------------------------------------------------------------------+
//| Create the MA handles for one timeframe                          |
//+------------------------------------------------------------------+
bool CreateMAHandles(ENUM_TIMEFRAMES tf,int &hFast,int &hSlow)
  {
   hFast = iMA(_Symbol,tf,InpFastEMA,0,MODE_EMA,InpAppliedPr);
   hSlow = iMA(_Symbol,tf,InpSlowEMA,0,MODE_EMA,InpAppliedPr);
   return(hFast!=INVALID_HANDLE && hSlow!=INVALID_HANDLE);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,BufBuy,INDICATOR_DATA);
   SetIndexBuffer(1,BufSell,INDICATOR_DATA);

   PlotIndexSetInteger(0,PLOT_ARROW,233);      // up arrow
   PlotIndexSetInteger(1,PLOT_ARROW,234);      // down arrow
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   ArraySetAsSeries(BufBuy,true);
   ArraySetAsSeries(BufSell,true);

   if(InpFastEMA>=InpSlowEMA)
     {
      Print("Fast EMA period must be smaller than Slow EMA period.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRewardRatio<=0.0)
     {
      Print("Reward ratio must be greater than 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- create all handles
   if(!CreateMAHandles(InpTF1,hFast1,hSlow1)) return(INIT_FAILED);
   if(!CreateMAHandles(InpTF2,hFast2,hSlow2)) return(INIT_FAILED);
   if(!CreateMAHandles(InpTF3,hFast3,hSlow3)) return(INIT_FAILED);
   if(!CreateMAHandles(InpEntryTF,hFastE,hSlowE)) return(INIT_FAILED);

   hATR = iATR(_Symbol,InpEntryTF,InpATRPeriod);
   if(hATR==INVALID_HANDLE) return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME,"MTF Trend Alignment");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit - clean up drawn objects                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
//| Return the trend of a timeframe:  +1 bull, -1 bear, 0 flat       |
//+------------------------------------------------------------------+
int TrendOf(int hFast,int hSlow,ENUM_TIMEFRAMES tf)
  {
   double fast[2], slow[2], closeArr[2];
   if(CopyBuffer(hFast,0,0,2,fast)<2) return(0);
   if(CopyBuffer(hSlow,0,0,2,slow)<2) return(0);
   if(CopyClose(_Symbol,tf,0,2,closeArr)<2) return(0);

   double f = fast[1];      // last closed bar value
   double s = slow[1];
   double c = closeArr[1];

   if(InpMethod==TREND_EMA_CROSS)
     {
      if(f>s && c>f) return(+1);
      if(f<s && c<f) return(-1);
      return(0);
     }
   else // TREND_PRICE_EMA -> price vs fast EMA only
     {
      if(c>f) return(+1);
      if(c<f) return(-1);
      return(0);
     }
  }

//+------------------------------------------------------------------+
//| Draw / refresh the Entry, SL and TP levels for the last signal   |
//+------------------------------------------------------------------+
void DrawLevels(bool isBuy,datetime t,double entry,double sl,double tp)
  {
   if(!InpDrawLevels) return;

   ObjectsDeleteAll(0,OBJ_PREFIX);   // keep only the newest signal

   datetime t2 = t + PeriodSeconds(PERIOD_CURRENT)*40; // line length
   color cEntry = clrGold;
   color cSL    = clrRed;
   color cTP    = clrLime;

   string s1 = OBJ_PREFIX+"Entry";
   string s2 = OBJ_PREFIX+"SL";
   string s3 = OBJ_PREFIX+"TP";

   //--- Entry line
   ObjectCreate(0,s1,OBJ_TREND,0,t,entry,t2,entry);
   ObjectSetInteger(0,s1,OBJPROP_COLOR,cEntry);
   ObjectSetInteger(0,s1,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,s1,OBJPROP_RAY_RIGHT,false);

   //--- SL line
   ObjectCreate(0,s2,OBJ_TREND,0,t,sl,t2,sl);
   ObjectSetInteger(0,s2,OBJPROP_COLOR,cSL);
   ObjectSetInteger(0,s2,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,s2,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,s2,OBJPROP_RAY_RIGHT,false);

   //--- TP line
   ObjectCreate(0,s3,OBJ_TREND,0,t,tp,t2,tp);
   ObjectSetInteger(0,s3,OBJPROP_COLOR,cTP);
   ObjectSetInteger(0,s3,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,s3,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,s3,OBJPROP_RAY_RIGHT,false);

   //--- Text labels
   string dir = isBuy ? "BUY" : "SELL";
   double rr  = InpRewardRatio;
   LabelAt(OBJ_PREFIX+"L_Entry",t2,entry,StringFormat("%s Entry: %s",dir,DoubleToString(entry,_Digits)),cEntry);
   LabelAt(OBJ_PREFIX+"L_SL",   t2,sl,   StringFormat("SL: %s",DoubleToString(sl,_Digits)),cSL);
   LabelAt(OBJ_PREFIX+"L_TP",   t2,tp,   StringFormat("TP (1:%s): %s",DoubleToString(rr,1),DoubleToString(tp,_Digits)),cTP);
  }

//+------------------------------------------------------------------+
//| Helper - place a text label anchored at a price/time             |
//+------------------------------------------------------------------+
void LabelAt(string name,datetime t,double price,string txt,color clr)
  {
   ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
  }

//+------------------------------------------------------------------+
//| Fire alerts once per signal bar                                  |
//+------------------------------------------------------------------+
void FireAlerts(bool isBuy,double entry,double sl,double tp)
  {
   string dir = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("%s %s  MTF aligned (H4+H1+M15+%s). Entry %s | SL %s | TP %s (1:%s)",
                             _Symbol, dir, EnumToString(InpEntryTF),
                             DoubleToString(entry,_Digits),
                             DoubleToString(sl,_Digits),
                             DoubleToString(tp,_Digits),
                             DoubleToString(InpRewardRatio,1));
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   int limit = rates_total - prev_calculated;
   if(prev_calculated>0) limit++;                 // recompute the last bar
   if(limit>rates_total-2) limit=rates_total-2;   // keep room for [i+1]

   //--- clear the visible range on a full recalculation
   if(prev_calculated==0)
     {
      ArrayInitialize(BufBuy,EMPTY_VALUE);
      ArrayInitialize(BufSell,EMPTY_VALUE);
     }

   //--- Higher-timeframe trend is evaluated on the last CLOSED HTF bar,
   //--- so it is the same for all forming entry bars. Compute once.
   int t1 = TrendOf(hFast1,hSlow1,InpTF1);
   int t2 = TrendOf(hFast2,hSlow2,InpTF2);
   int t3 = TrendOf(hFast3,hSlow3,InpTF3);

   bool htfBull = (t1>0 && t2>0 && t3>0);
   bool htfBear = (t1<0 && t2<0 && t3<0);

   //--- Entry TF EMAs (as series)
   double feBuf[], seBuf[];
   ArraySetAsSeries(feBuf,true);
   ArraySetAsSeries(seBuf,true);
   int need = limit+3;
   if(CopyBuffer(hFastE,0,0,need,feBuf)<need) return(prev_calculated);
   if(CopyBuffer(hSlowE,0,0,need,seBuf)<need) return(prev_calculated);

   double atr[];
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(hATR,0,0,limit+3,atr)<limit+3) return(prev_calculated);

   //--- loop over closed entry bars (index 1 = last closed bar)
   for(int i=limit; i>=1; i--)
     {
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;

      //--- entry TF trend on bar i
      double f  = feBuf[i];
      double s  = seBuf[i];
      double c  = close[i];
      double fp = feBuf[i+1];      // previous bar fast EMA
      double cp = close[i+1];

      int eTrend;
      if(InpMethod==TREND_EMA_CROSS)
         eTrend = (f>s && c>f) ? 1 : ((f<s && c<f) ? -1 : 0);
      else
         eTrend = (c>f) ? 1 : ((c<f) ? -1 : 0);

      //--- require a fresh entry (crossed into alignment on THIS bar)
      bool freshBull = (c>f && cp<=fp);
      bool freshBear = (c<f && cp>=fp);

      double slDist = atr[i]*InpATRMult;
      if(slDist<=0) continue;

      double pts = InpArrowGapPts*_Point;

      if(htfBull && eTrend>0 && freshBull)
        {
         double entry = close[i];
         double sl    = entry - slDist;
         double tp    = entry + slDist*InpRewardRatio;
         BufBuy[i]    = low[i]-pts;

         if(i==1 && time[i]!=g_lastSignalBar)   // act once on the just-closed signal bar
           {
            g_lastSignalBar = time[i];
            DrawLevels(true,time[i],entry,sl,tp);
            FireAlerts(true,entry,sl,tp);
           }
        }
      else if(htfBear && eTrend<0 && freshBear)
        {
         double entry = close[i];
         double sl    = entry + slDist;
         double tp    = entry - slDist*InpRewardRatio;
         BufSell[i]   = high[i]+pts;

         if(i==1 && time[i]!=g_lastSignalBar)
           {
            g_lastSignalBar = time[i];
            DrawLevels(false,time[i],entry,sl,tp);
            FireAlerts(false,entry,sl,tp);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
