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
#property version   "1.10"
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
   Comment("");
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
         if(colorsOK && middleLowLowest && bodyEngulfHigh &&
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
         if(colorsOK && middleHighHighest && bodyEngulfLow &&
            TrendFilterOK(false, i, rates_total, high, low, maReady))
           {
            SellBuffer[i] = h3 + gap;
           }
        }
     }

   // --- Notifications: only for the most recently CLOSED bar, once ---
   int sig = rates_total - 2;
   if(sig >= 2)
     {
      datetime bt = time[sig];
      if(!g_histInit)
        {
         // First run after (re)load: mark history as seen, don't alert it.
         g_lastAlertBar = bt;
         g_histInit     = true;
        }
      else if(bt != g_lastAlertBar)
        {
         if(BuyBuffer[sig] != EMPTY_VALUE)
            FireAlerts(true,  close[sig], bt);
         else if(SellBuffer[sig] != EMPTY_VALUE)
            FireAlerts(false, close[sig], bt);
         g_lastAlertBar = bt;   // advance so we evaluate each closed bar once
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
