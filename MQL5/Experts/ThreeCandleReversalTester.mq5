//+------------------------------------------------------------------+
//|                                   ThreeCandleReversalTester.mq5   |
//|            Backtest wrapper for ThreeCandleReversalSignal (XAU)   |
//|                                                                  |
//|  MT5's Strategy Tester runs EAs, not indicators. This EA loads   |
//|  the ThreeCandleReversalSignal indicator via iCustom, reads its  |
//|  Buy/Sell arrow buffers, and opens trades with fixed TP/SL and   |
//|  an optional tight trailing stop - so you can backtest the EXACT |
//|  indicator logic and see win-rate, profit and drawdown.          |
//|                                                                  |
//|  Requirements:                                                   |
//|   - ThreeCandleReversalSignal.ex5 compiled and located in        |
//|     MQL5/Indicators/ (or set InpIndicatorName to its subpath).   |
//|   - Run the tester on XAUUSD, M1 or M5.                          |
//+------------------------------------------------------------------+
#property copyright "Three-Candle Reversal Tester"
#property version   "1.10"
#property strict
#property description "Backtests/trades the ThreeCandleReversalSignal indicator's arrows"
#property description "with candle-based auto SL and reward:risk TP."

#include <Trade/Trade.mqh>

//--- must match the indicator's enum order/values
enum ENUM_RSI_MODE
  {
   RSI_DIVERGENCE = 0,   // Momentum divergence
   RSI_THRESHOLD  = 1    // Overbought/oversold threshold
  };

//+------------------------------------------------------------------+
//| Inputs - Trading                                                 |
//+------------------------------------------------------------------+
input group    "=== Trading ==="
input double   InpLotSize        = 0.01;        // Fixed lot size
input int      InpMaxPositions   = 1;           // Max simultaneous positions
input double   InpMaxSpreadUSD   = 0.0;         // Max spread in USD (0 = off)
input long     InpMagicNumber    = 20250811;    // Magic number
input int      InpDeviationPts   = 30;          // Max deviation (points)

input group    "=== Auto SL/TP (candle-based) ==="
input bool     InpAutoSLTP       = true;        // Auto SL from middle candle, TP = ratio x risk
input double   InpRewardRatio    = 3.0;         // Reward:risk ratio (e.g. 3 for 1:3, 4 for 1:4)
input double   InpSLBufferUSD    = 0.0;         // Extra buffer beyond the middle candle wick (USD)
input double   InpTakeProfit     = 1.0;         // Fixed TP (USD) - used only when AutoSLTP = false
input double   InpStopLoss       = 1.0;         // Fixed SL (USD) - used only when AutoSLTP = false

input group    "=== Trailing Stop (fixed USD) ==="
input bool     InpUseTrailing    = false;       // Tight trailing (off: let R:R TP run)
input double   InpTrailStartUSD   = 0.5;        // Start trailing after this profit (USD)
input double   InpTrailGapUSD      = 0.1;       // Trail distance behind price (USD)
input double   InpTrailStepUSD     = 0.0;       // Min SL move before updating (USD)

input group    "=== Indicator ==="
input string   InpIndicatorName  = "ThreeCandleReversalSignal"; // Indicator name/subpath

//--- Strategy inputs passed through to the indicator (match its inputs)
input group    "=== Signals ==="
input bool           InpEnableBuy      = true;
input bool           InpEnableSell     = true;

input group    "=== Trend / Reversal Filter ==="
input bool           InpUseTrendFilter = true;
input int            InpSwingLookback  = 12;
input int            InpMAPeriod       = 50;
input ENUM_MA_METHOD InpMAMethod       = MODE_EMA;
input int            InpMASlopeBars    = 5;

input group    "=== Candle Shape Filter ==="
input bool           InpRequireSolidOuter = true;
input bool           InpMiddleInsideFirst = true;
input bool           InpUseShapeFilter    = false;
input double         InpHammerWickPct  = 0.5;
input double         InpHammerHeadPct  = 0.15;
input double         InpHammerBodyPct  = 0.4;
input double         InpSolidBodyPct   = 0.5;

input group    "=== Confirmation ==="
input bool           InpConfirmCandle  = false;

input group    "=== Momentum / RSI Quality Filter ==="
input bool           InpUseRSIFilter   = true;
input ENUM_RSI_MODE  InpRSIMode        = RSI_DIVERGENCE;
input int            InpRSIPeriod      = 14;
input double         InpRSIOverbought  = 70.0;
input double         InpRSIOversold    = 30.0;

input group    "=== Instrument / Timeframe Guards ==="
input bool           InpRestrictSymbol    = true;
input bool           InpRestrictTimeframe = true;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade   trade;
int      g_handle      = INVALID_HANDLE;
datetime g_lastBarTime = 0;
int      g_symDigits   = 2;
double   g_symPoint    = 0.01;

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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol))
     {
      Print("ERROR: run this on XAUUSD (gold). Current: ", _Symbol);
      return(INIT_FAILED);
     }
   if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period))
     {
      Print("ERROR: this strategy supports only M1 and M5.");
      return(INIT_FAILED);
     }
   if(InpLotSize <= 0.0 || InpTakeProfit <= 0.0 || InpStopLoss <= 0.0)
     {
      Print("ERROR: lot / TP / SL must be > 0.");
      return(INIT_FAILED);
     }

   g_symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_symPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Load the indicator via iCustom. The parameters MUST be listed in the
   // exact order the indicator declares them.
   g_handle = iCustom(_Symbol, _Period, InpIndicatorName,
                      InpEnableBuy,          // 1  InpEnableBuy
                      InpEnableSell,         // 2  InpEnableSell
                      0.10,                  // 3  InpArrowGapUSD (cosmetic)
                      false,                 // 4  InpEnableSound
                      "alert.wav",           // 5  InpBuySound
                      "alert2.wav",          // 6  InpSellSound
                      false,                 // 7  InpEnableAlert
                      false,                 // 8  InpEnablePush
                      false,                 // 9  InpEnableEmail
                      InpUseTrendFilter,     // 10 InpUseTrendFilter
                      InpSwingLookback,      // 11 InpSwingLookback
                      InpMAPeriod,           // 12 InpMAPeriod
                      InpMAMethod,           // 13 InpMAMethod
                      InpMASlopeBars,        // 14 InpMASlopeBars
                      InpRequireSolidOuter,  // 15 InpRequireSolidOuter
                      InpMiddleInsideFirst,  // 16 InpMiddleInsideFirst
                      InpUseShapeFilter,     // 17 InpUseShapeFilter
                      InpHammerWickPct,      // 18 InpHammerWickPct
                      InpHammerHeadPct,      // 19 InpHammerHeadPct
                      InpHammerBodyPct,      // 20 InpHammerBodyPct
                      InpSolidBodyPct,       // 21 InpSolidBodyPct
                      InpConfirmCandle,      // 22 InpConfirmCandle
                      InpUseRSIFilter,       // 23 InpUseRSIFilter
                      InpRSIMode,            // 24 InpRSIMode
                      InpRSIPeriod,          // 25 InpRSIPeriod
                      InpRSIOverbought,      // 26 InpRSIOverbought
                      InpRSIOversold,        // 27 InpRSIOversold
                      true,                  // 28 InpShowDashboard (nice in visual mode)
                      12,                    // 29 InpDashX
                      20,                    // 30 InpDashY
                      clrBlack,              // 31 InpDashBgColor
                      false,                 // 32 InpLogRejections
                      InpRestrictSymbol,     // 33 InpRestrictSymbol
                      InpRestrictTimeframe); // 34 InpRestrictTimeframe

   if(g_handle == INVALID_HANDLE)
     {
      Print("ERROR: could not load indicator '", InpIndicatorName,
            "'. Make sure it is compiled in MQL5/Indicators/.");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_lastBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   PrintFormat("Tester initialised on %s %s (indicator '%s' handle=%d)",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), InpIndicatorName, g_handle);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handle != INVALID_HANDLE)
      IndicatorRelease(g_handle);
  }

//+------------------------------------------------------------------+
//| New-bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(t == 0) return(false);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Count this EA's open positions                                   |
//+------------------------------------------------------------------+
int CountEaPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      c++;
     }
   return(c);
  }

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
  {
   if(InpMaxSpreadUSD <= 0.0) return(true);
   double sp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return(sp <= InpMaxSpreadUSD);
  }

//+------------------------------------------------------------------+
//| Clamp a stop distance to the broker minimum                      |
//+------------------------------------------------------------------+
double ClampStop(double d)
  {
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minD = (double)lvl * g_symPoint;
   if(minD > 0.0 && d < minD) d = minD + g_symPoint;
   return(d);
  }

//+------------------------------------------------------------------+
//| Resolve SL/TP distances (price units) for a trade                |
//|   Auto mode: SL = middle-candle low (buy) / high (sell),          |
//|              TP = InpRewardRatio x that risk distance.           |
//|   Fixed mode: InpStopLoss / InpTakeProfit in USD.               |
//|   Returns false if the geometry is invalid (skip the trade).    |
//+------------------------------------------------------------------+
bool ResolveSLTP(const int dir, const double price, double &slDist, double &tpDist)
  {
   if(InpAutoSLTP)
     {
      // The arrow sits on the last closed bar (shift 1). The middle candle
      // is 2 bars before it, or 3 bars when confirmation shifts it back.
      int midShift = (InpConfirmCandle ? 3 : 2);
      double midLow  = iLow (_Symbol, _Period, midShift);
      double midHigh = iHigh(_Symbol, _Period, midShift);
      if(midLow <= 0.0 || midHigh <= 0.0)
         return(false);

      if(dir > 0)  // BUY: SL below the middle candle low
        {
         double slPrice = midLow - InpSLBufferUSD;
         slDist = price - slPrice;
        }
      else         // SELL: SL above the middle candle high
        {
         double slPrice = midHigh + InpSLBufferUSD;
         slDist = slPrice - price;
        }

      if(slDist <= 0.0)
        {
         PrintFormat("AutoSLTP: invalid risk distance (%.*f) - trade skipped.", g_symDigits, slDist);
         return(false);
        }
      slDist = ClampStop(slDist);
      tpDist = slDist * InpRewardRatio;
     }
   else
     {
      slDist = ClampStop(InpStopLoss);
      tpDist = ClampStop(InpTakeProfit);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Open a trade (+1 buy, -1 sell)                                   |
//+------------------------------------------------------------------+
void OpenTrade(const int dir)
  {
   double price = (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double slDist, tpDist;
   if(!ResolveSLTP(dir, price, slDist, tpDist))
      return;

   double slp, tpp;
   if(dir > 0)
     {
      slp = NormalizeDouble(price - slDist, g_symDigits);
      tpp = NormalizeDouble(price + tpDist, g_symDigits);
      trade.Buy(InpLotSize, _Symbol, price, slp, tpp, "3CandleTest");
     }
   else
     {
      slp = NormalizeDouble(price + slDist, g_symDigits);
      tpp = NormalizeDouble(price - tpDist, g_symDigits);
      trade.Sell(InpLotSize, _Symbol, price, slp, tpp, "3CandleTest");
     }
   PrintFormat("%s @ %.*f  SL=%.*f  TP=%.*f  (risk=%.*f R:R=1:%.1f)",
               (dir > 0 ? "BUY" : "SELL"), g_symDigits, price,
               g_symDigits, slp, g_symDigits, tpp,
               g_symDigits, slDist, (InpAutoSLTP ? InpRewardRatio : tpDist / MathMax(slDist, _Point)));
  }

//+------------------------------------------------------------------+
//| Trailing-stop manager (fixed USD)                                |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(!InpUseTrailing || InpTrailGapUSD <= 0.0) return;
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minD = (double)lvl * g_symPoint;
   double step = MathMax(InpTrailStepUSD, g_symPoint);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double op   = PositionGetDouble(POSITION_PRICE_OPEN);
      double csl  = PositionGetDouble(POSITION_SL);
      double ctp  = PositionGetDouble(POSITION_TP);
      double gap  = MathMax(InpTrailGapUSD, minD + g_symPoint);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - op) < InpTrailStartUSD) continue;
         double nsl = NormalizeDouble(bid - gap, g_symDigits);
         if(nsl < bid && (csl == 0.0 || nsl >= csl + step))
            trade.PositionModify(tk, nsl, ctp);
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((op - ask) < InpTrailStartUSD) continue;
         double nsl = NormalizeDouble(ask + gap, g_symDigits);
         if(nsl > ask && (csl == 0.0 || nsl <= csl - step))
            trade.PositionModify(tk, nsl, ctp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Is a buffer value a real signal (not empty)?                     |
//+------------------------------------------------------------------+
bool HasSignal(const int bufferIndex)
  {
   double b[];
   if(CopyBuffer(g_handle, bufferIndex, 1, 1, b) < 1)   // shift 1 = last closed bar
      return(false);
   double v = b[0];
   return(v != EMPTY_VALUE && v != 0.0 && MathIsValidNumber(v) && v < DBL_MAX / 2.0);
  }

//+------------------------------------------------------------------+
//| Tick handler                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailing();

   if(!IsNewBar())
      return;

   if(CountEaPositions() >= InpMaxPositions)
      return;
   if(!SpreadOK())
      return;

   // Buffer 0 = Buy arrow, buffer 1 = Sell arrow (indicator plot order).
   bool buy  = InpEnableBuy  && HasSignal(0);
   bool sell = InpEnableSell && HasSignal(1);

   if(buy)
      OpenTrade(+1);
   else if(sell)
      OpenTrade(-1);
  }
//+------------------------------------------------------------------+
