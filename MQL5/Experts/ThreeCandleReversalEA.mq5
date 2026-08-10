//+------------------------------------------------------------------+
//|                                       ThreeCandleReversalEA.mq5   |
//|                          Three-Candle Reversal Pattern EA (XAUUSD)|
//|                                                                  |
//|  Strategy (evaluated on each newly closed bar):                  |
//|                                                                  |
//|  Bars used (index 0 = current forming bar, not used):            |
//|      First  candle = bar index 3 (oldest of the three)           |
//|      Middle candle = bar index 2                                 |
//|      Third  candle = bar index 1 (most recently closed)          |
//|                                                                  |
//|  BUY  : red(3) -> green(2) -> green(3rd)                         |
//|          middle LOW  (incl. wick) < first LOW  AND < third LOW   |
//|          third candle BODY top (close) engulfs first candle HIGH |
//|                                                                  |
//|  SELL : green(3) -> red(2) -> red(3rd)                           |
//|          middle HIGH (incl. wick) > first HIGH AND > third HIGH  |
//|          third candle BODY bottom (close) engulfs first candle LOW|
//|                                                                  |
//|  Fixed TP / SL, both manually adjustable. Built for M1 & M5,     |
//|  XAUUSD only.                                                     |
//+------------------------------------------------------------------+
#property copyright "Three-Candle Reversal EA"
#property version   "1.30"
#property strict
#property description "Three-candle reversal pattern EA for XAUUSD on M1/M5."
#property description "Hammer/shooting-star middle candle, solid outer candles,"
#property description "trend filter, fixed TP/SL, tight trailing, dashboard & alerts."

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_TPSL_MODE
  {
   TPSL_PRICE_USD = 0,   // Distance in USD of price movement (1.0 = $1 gold move)
   TPSL_MONEY_USD = 1    // Target profit/loss in account currency
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group    "=== Money Management ==="
input double         InpLotSize        = 0.01;            // Fixed lot size
input ENUM_TPSL_MODE InpTpSlMode       = TPSL_PRICE_USD;  // How TP/SL values are interpreted
input double         InpTakeProfit     = 1.0;             // Take Profit (USD)  <-- adjustable
input double         InpStopLoss       = 1.0;             // Stop Loss  (USD)   <-- adjustable

input group    "=== Trailing Stop (fixed USD, no ATR) ==="
input bool           InpUseTrailing    = true;            // Enable tight trailing stop
input double         InpTrailStartUSD  = 0.5;             // Start trailing after this profit (USD)
input double         InpTrailGapUSD    = 0.1;             // Trail distance behind price (USD, tight)
input double         InpTrailStepUSD   = 0.0;             // Min SL move before updating (USD, 0=each tick)

input group    "=== Trade Filters ==="
input bool           InpEnableBuy      = true;            // Allow BUY trades
input bool           InpEnableSell     = true;            // Allow SELL trades
input int            InpMaxPositions   = 1;               // Max simultaneous EA positions
input double         InpMaxSpreadUSD   = 0.0;             // Max allowed spread in USD (0 = off)

input group    "=== Trend / Reversal Filter (M5 recommended) ==="
input bool           InpUseTrendFilter = true;            // Only take reversals (skip mid-trend signals)
input int            InpSwingLookback  = 12;              // Local top/bottom lookback in bars (0=off)
input int            InpMAPeriod       = 50;              // Trend MA period (0=off)
input ENUM_MA_METHOD InpMAMethod       = MODE_EMA;        // Trend MA method
input int            InpMASlopeBars    = 5;               // Bars used to measure MA slope

input group    "=== Candle Shape Filter ==="
input bool           InpUseShapeFilter = true;            // Require hammer/star middle + solid 1st/3rd
input double         InpHammerWickPct  = 0.5;             // Dominant wick >= this fraction of range
input double         InpHammerHeadPct  = 0.15;            // Opposite wick <= this fraction of range
input double         InpHammerBodyPct  = 0.4;             // Hammer/star body <= this fraction of range
input double         InpSolidBodyPct   = 0.5;             // 1st/3rd body >= this fraction (not doji/hammer)

input group    "=== Instrument / Timeframe Guards ==="
input bool           InpRestrictSymbol    = true;         // Only run on XAUUSD-type symbol
input bool           InpRestrictTimeframe = true;         // Only run on M1 / M5

input group    "=== Execution ==="
input long           InpMagicNumber    = 20250804;        // Magic number
input int            InpDeviationPts   = 30;              // Max deviation/slippage (points)
input string         InpTradeComment   = "3CandleEA";     // Trade comment

input group    "=== Notifications ==="
input bool           InpEnableSound    = true;            // Play a sound when a trade opens
input string         InpBuySound       = "alert.wav";     // Sound file for BUY
input string         InpSellSound      = "alert2.wav";    // Sound file for SELL
input bool           InpEnableAlert    = false;           // Popup alert when a trade opens
input bool           InpEnablePush     = false;           // Push notification when a trade opens

input group    "=== Dashboard ==="
input bool           InpShowDashboard  = true;            // Show on-chart status dashboard
input int            InpDashX          = 12;              // Dashboard X offset (px)
input int            InpDashY          = 20;              // Dashboard Y offset (px)
input color          InpDashBgColor    = clrBlack;        // Dashboard background colour

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         trade;
datetime       g_lastBarTime = 0;      // used for new-bar detection
int            g_symDigits   = 2;
double         g_symPoint    = 0.01;
double         g_tickSize    = 0.01;
double         g_tickValue   = 1.0;
int            g_maHandle    = INVALID_HANDLE;   // trend MA indicator handle
string         g_lastSignal  = "None";           // last accepted signal (dashboard)
datetime       g_lastSignalTm= 0;                // time of last accepted signal
#define        DASH_PREFIX     "TCR_DASH_"

//+------------------------------------------------------------------+
//| Helper: is this a gold / XAUUSD-style symbol                     |
//+------------------------------------------------------------------+
bool IsGoldSymbol(const string sym)
  {
   string s = sym;
   StringToUpper(s);
   // Matches XAUUSD, XAUUSD.m, XAUUSDx, GOLD, etc.
   if(StringFind(s, "XAU") >= 0) return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Helper: allowed timeframe (M1 or M5 only)                        |
//+------------------------------------------------------------------+
bool IsAllowedTimeframe(const ENUM_TIMEFRAMES tf)
  {
   return (tf == PERIOD_M1 || tf == PERIOD_M5);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // --- Symbol guard ---------------------------------------------------
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol))
     {
      Print("ERROR: This EA is built for XAUUSD (gold). Current symbol: ", _Symbol,
            ". Attach it to gold or disable 'InpRestrictSymbol'.");
      return(INIT_FAILED);
     }

   // --- Timeframe guard ------------------------------------------------
   if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period))
     {
      Print("ERROR: This EA supports only M1 and M5. Current timeframe: ",
            EnumToString((ENUM_TIMEFRAMES)_Period),
            ". Switch to M1/M5 or disable 'InpRestrictTimeframe'.");
      return(INIT_FAILED);
     }

   // --- Input validation ----------------------------------------------
   if(InpLotSize <= 0.0)
     {
      Print("ERROR: InpLotSize must be > 0.");
      return(INIT_FAILED);
     }
   if(InpTakeProfit <= 0.0 || InpStopLoss <= 0.0)
     {
      Print("ERROR: TakeProfit and StopLoss must be > 0.");
      return(INIT_FAILED);
     }
   if(!InpEnableBuy && !InpEnableSell)
      Print("WARNING: Both BUY and SELL are disabled - EA will not trade.");

   // --- Cache symbol properties ---------------------------------------
   g_symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_symPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(g_tickSize <= 0.0) g_tickSize = g_symPoint;

   // --- Trend MA handle -----------------------------------------------
   if(InpUseTrendFilter && InpMAPeriod > 0)
     {
      g_maHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(g_maHandle == INVALID_HANDLE)
         Print("WARNING: failed to create MA handle - MA trend filter disabled.");
     }

   // --- Configure trade object ----------------------------------------
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   // Initialise new-bar detector so we don't fire on the first tick
   g_lastBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   PrintFormat("ThreeCandleReversalEA initialised on %s %s | digits=%d point=%.*f tickSize=%.*f tickValue=%.5f",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
               g_symDigits, g_symDigits, g_symPoint, g_symDigits, g_tickSize, g_tickValue);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
   PrintFormat("ThreeCandleReversalEA stopped. Reason=%d", reason);
  }

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == 0)
      return(false);
   if(curBarTime != g_lastBarTime)
     {
      g_lastBarTime = curBarTime;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Count open positions that belong to this EA (symbol + magic)     |
//+------------------------------------------------------------------+
int CountEaPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Spread filter (in USD of price)                                  |
//+------------------------------------------------------------------+
bool SpreadOK()
  {
   if(InpMaxSpreadUSD <= 0.0)
      return(true);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(spread > InpMaxSpreadUSD)
     {
      PrintFormat("Skip: spread %.*f > max %.*f", g_symDigits, spread, g_symDigits, InpMaxSpreadUSD);
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Convert TP/SL input into a price distance (in price units)       |
//+------------------------------------------------------------------+
double ResolveDistance(const double value)
  {
   if(InpTpSlMode == TPSL_PRICE_USD)
     {
      // For XAUUSD, 1 unit of price = $1 move, so distance == value.
      return(value);
     }
   else // TPSL_MONEY_USD -> convert money target to price distance
     {
      double perUnit = g_tickValue / g_tickSize;          // account money per 1.0 price move per 1 lot
      double denom   = perUnit * InpLotSize;
      if(denom <= 0.0)
        {
         Print("ERROR: cannot resolve money-based distance (tickValue/tickSize/lot invalid).");
         return(0.0);
        }
      return(value / denom);
     }
  }

//+------------------------------------------------------------------+
//| Clamp a stop distance to the broker minimum (stops level)        |
//+------------------------------------------------------------------+
double ClampToStopsLevel(double distance)
  {
   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (double)stopsLevelPts * g_symPoint;
   // add a small buffer of one point
   if(minDist > 0.0 && distance < minDist)
     {
      PrintFormat("WARNING: requested distance %.*f below broker min %.*f - adjusting.",
                  g_symDigits, distance, g_symDigits, minDist);
      distance = minDist + g_symPoint;
     }
   return(distance);
  }

//+------------------------------------------------------------------+
//| Candle helpers (shift-based)                                     |
//+------------------------------------------------------------------+
bool IsBull(const double o, const double c) { return(c > o); }   // green
bool IsBear(const double o, const double c) { return(c < o); }   // red

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
//| Timeframe -> short string (e.g. "M5")                            |
//+------------------------------------------------------------------+
string TfToStr(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

//+------------------------------------------------------------------+
//| Read the trend MA value at a given bar shift                     |
//+------------------------------------------------------------------+
double MaValue(const int shift)
  {
   if(g_maHandle == INVALID_HANDLE)
      return(EMPTY_VALUE);
   double buf[];
   if(CopyBuffer(g_maHandle, 0, shift, 1, buf) < 1)
      return(EMPTY_VALUE);
   return(buf[0]);
  }

//+------------------------------------------------------------------+
//| Trend / reversal context filter                                  |
//|   dir = +1 (buy)  requires a prior DOWN trend + local bottom     |
//|   dir = -1 (sell) requires a prior UP  trend + local top         |
//|   Pattern bars: third=1, middle=2, first=3                       |
//+------------------------------------------------------------------+
bool TrendFilterOK(const int dir)
  {
   if(!InpUseTrendFilter)
      return(true);

   // --- Local swing extreme: the middle candle must be the top/bottom ---
   if(InpSwingLookback > 0)
     {
      if(dir < 0) // SELL -> middle high must be the highest of the window
        {
         int hh = iHighest(_Symbol, _Period, MODE_HIGH, InpSwingLookback, 1);
         if(hh != 2)
            return(false);
        }
      else        // BUY -> middle low must be the lowest of the window
        {
         int ll = iLowest(_Symbol, _Period, MODE_LOW, InpSwingLookback, 1);
         if(ll != 2)
            return(false);
        }
     }

   // --- MA slope: prior trend must be OPPOSITE to the signal ---
   if(InpMAPeriod > 0 && g_maHandle != INVALID_HANDLE)
     {
      double maRecent = MaValue(1);
      double maOld    = MaValue(1 + InpMASlopeBars);
      if(maRecent != EMPTY_VALUE && maOld != EMPTY_VALUE)
        {
         if(dir < 0 && !(maRecent > maOld))   // sell needs a rising MA (up-trend into the top)
            return(false);
         if(dir > 0 && !(maRecent < maOld))   // buy needs a falling MA (down-trend into the bottom)
            return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Evaluate the three-candle pattern on closed bars 1,2,3           |
//|   returns:  1 = BUY signal, -1 = SELL signal, 0 = none           |
//+------------------------------------------------------------------+
int CheckPattern()
  {
   // Need at least 4 bars (0 forming + 1,2,3 closed)
   if(Bars(_Symbol, _Period) < 5)
      return(0);

   // First = shift 3, Middle = shift 2, Third = shift 1
   double o1 = iOpen (_Symbol, _Period, 3);  // first
   double c1 = iClose(_Symbol, _Period, 3);
   double h1 = iHigh (_Symbol, _Period, 3);
   double l1 = iLow  (_Symbol, _Period, 3);

   double o2 = iOpen (_Symbol, _Period, 2);  // middle
   double c2 = iClose(_Symbol, _Period, 2);
   double h2 = iHigh (_Symbol, _Period, 2);
   double l2 = iLow  (_Symbol, _Period, 2);

   double o3 = iOpen (_Symbol, _Period, 1);  // third
   double c3 = iClose(_Symbol, _Period, 1);
   double h3 = iHigh (_Symbol, _Period, 1);
   double l3 = iLow  (_Symbol, _Period, 1);

   // Guard against invalid data
   if(o1 == 0 || o2 == 0 || o3 == 0)
      return(0);

   //------------------------------------------------------------------
   // BUY pattern
   //   first red, middle green, third green
   //   middle low is lowest of the three (incl. wicks)
   //   third candle BODY top (close, since green) engulfs first HIGH
   //------------------------------------------------------------------
   if(InpEnableBuy)
     {
      bool colorsOK = IsBear(o1, c1) && IsBull(o2, c2) && IsBull(o3, c3);
      bool middleLowLowest = (l2 < l1) && (l2 < l3);
      bool bodyEngulfHigh   = (c3 > h1);  // green body top = close
      bool shapeOK = true;
      if(InpUseShapeFilter)
         shapeOK = IsHammerShape(o2, h2, l2, c2)   // middle = hammer
                && IsSolidCandle(o1, h1, l1, c1)    // first  = solid
                && IsSolidCandle(o3, h3, l3, c3);   // third  = solid
      if(colorsOK && middleLowLowest && bodyEngulfHigh && shapeOK)
        {
         if(TrendFilterOK(1))
           {
            PrintFormat("BUY pattern: first[red] o=%.*f c=%.*f h=%.*f | mid[green] l=%.*f | third[green] close=%.*f > firstHigh=%.*f",
                        g_symDigits,o1,g_symDigits,c1,g_symDigits,h1,g_symDigits,l2,g_symDigits,c3,g_symDigits,h1);
            return(1);
           }
         else
            Print("BUY pattern found but filtered out (not a bottom of a down-trend).");
        }
     }

   //------------------------------------------------------------------
   // SELL pattern
   //   first green, middle red, third red
   //   middle high is highest of the three (incl. wicks)
   //   third candle BODY bottom (close, since red) engulfs first LOW
   //------------------------------------------------------------------
   if(InpEnableSell)
     {
      bool colorsOK = IsBull(o1, c1) && IsBear(o2, c2) && IsBear(o3, c3);
      bool middleHighHighest = (h2 > h1) && (h2 > h3);
      bool bodyEngulfLow      = (c3 < l1);  // red body bottom = close
      bool shapeOK = true;
      if(InpUseShapeFilter)
         shapeOK = IsStarShape(o2, h2, l2, c2)     // middle = shooting star
                && IsSolidCandle(o1, h1, l1, c1)    // first  = solid
                && IsSolidCandle(o3, h3, l3, c3);   // third  = solid
      if(colorsOK && middleHighHighest && bodyEngulfLow && shapeOK)
        {
         if(TrendFilterOK(-1))
           {
            PrintFormat("SELL pattern: first[green] o=%.*f c=%.*f l=%.*f | mid[red] h=%.*f | third[red] close=%.*f < firstLow=%.*f",
                        g_symDigits,o1,g_symDigits,c1,g_symDigits,l1,g_symDigits,h2,g_symDigits,c3,g_symDigits,l1);
            return(-1);
           }
         else
            Print("SELL pattern found but filtered out (not a top of an up-trend).");
        }
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| Open a trade in the given direction                              |
//|   dir = +1 buy, -1 sell                                          |
//+------------------------------------------------------------------+
void OpenTrade(const int dir)
  {
   double tpDist = ResolveDistance(InpTakeProfit);
   double slDist = ResolveDistance(InpStopLoss);
   if(tpDist <= 0.0 || slDist <= 0.0)
     {
      Print("ERROR: invalid TP/SL distance - trade skipped.");
      return;
     }
   tpDist = ClampToStopsLevel(tpDist);
   slDist = ClampToStopsLevel(slDist);

   double price, sl, tp;
   bool ok = false;

   if(dir > 0) // BUY at Ask
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(price - slDist, g_symDigits);
      tp = NormalizeDouble(price + tpDist, g_symDigits);
      ok = trade.Buy(InpLotSize, _Symbol, price, sl, tp, InpTradeComment);
     }
   else        // SELL at Bid
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(price + slDist, g_symDigits);
      tp = NormalizeDouble(price - tpDist, g_symDigits);
      ok = trade.Sell(InpLotSize, _Symbol, price, sl, tp, InpTradeComment);
     }

   if(ok)
     {
      PrintFormat("%s opened: lots=%.2f price=%.*f SL=%.*f TP=%.*f retcode=%u deal=%I64u",
                  (dir > 0 ? "BUY" : "SELL"), InpLotSize,
                  g_symDigits, price, g_symDigits, sl, g_symDigits, tp,
                  trade.ResultRetcode(), trade.ResultDeal());
      NotifyEntry(dir, price);
     }
   else
     {
      PrintFormat("%s FAILED: retcode=%u (%s)",
                  (dir > 0 ? "BUY" : "SELL"),
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Trailing-stop manager (fixed USD distances, no ATR)              |
//|   - activates once a position is InpTrailStartUSD in profit      |
//|   - then keeps the SL InpTrailGapUSD behind price, tightening    |
//|     only in the trade's favour (never loosening).                |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(!InpUseTrailing)
      return;
   if(InpTrailGapUSD <= 0.0 || InpTrailStartUSD < 0.0)
      return;

   // Broker minimum stop distance (SL must sit at least this far from price)
   long   stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist       = (double)stopsLevelPts * g_symPoint;
   double step          = MathMax(InpTrailStepUSD, g_symPoint);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - openPrice) < InpTrailStartUSD)     // not enough profit yet
            continue;
         double gap   = MathMax(InpTrailGapUSD, minDist + g_symPoint);
         double newSL = NormalizeDouble(bid - gap, g_symDigits);
         // Only raise the stop, and only if it is a real improvement.
         if(newSL < bid && (curSL == 0.0 || newSL >= curSL + step))
           {
            if(trade.PositionModify(ticket, newSL, curTP))
               PrintFormat("Trail BUY #%I64u: SL -> %.*f (bid %.*f)",
                           ticket, g_symDigits, newSL, g_symDigits, bid);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((openPrice - ask) < InpTrailStartUSD)
            continue;
         double gap   = MathMax(InpTrailGapUSD, minDist + g_symPoint);
         double newSL = NormalizeDouble(ask + gap, g_symDigits);
         // Only lower the stop, and only if it is a real improvement.
         if(newSL > ask && (curSL == 0.0 || newSL <= curSL - step))
           {
            if(trade.PositionModify(ticket, newSL, curTP))
               PrintFormat("Trail SELL #%I64u: SL -> %.*f (ask %.*f)",
                           ticket, g_symDigits, newSL, g_symDigits, ask);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fire notifications when a trade is opened                         |
//+------------------------------------------------------------------+
void NotifyEntry(const int dir, const double price)
  {
   string d   = (dir > 0 ? "BUY" : "SELL");
   string msg = StringFormat("3-Candle EA %s %s @ %.*f", d, _Symbol, g_symDigits, price);
   if(InpEnableSound) PlaySound(dir > 0 ? InpBuySound : InpSellSound);
   if(InpEnableAlert) Alert(msg);
   if(InpEnablePush)  SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Current trend label from the MA slope                            |
//+------------------------------------------------------------------+
string TrendText()
  {
   if(!(InpMAPeriod > 0) || g_maHandle == INVALID_HANDLE)
      return("n/a");
   double r = MaValue(1);
   double o = MaValue(1 + InpMASlopeBars);
   if(r == EMPTY_VALUE || o == EMPTY_VALUE)
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
void DrawDashboard()
  {
   if(!InpShowDashboard)
      return;

   int x  = InpDashX;
   int y  = InpDashY;
   int lh = 16;      // line height
   int n  = 0;       // line counter

   DashPanel("BG", x - 6, y - 6, 250, 10 * lh + 14, InpDashBgColor);

   DashLabel("l0", "3-Candle Reversal EA", x, y + (n++) * lh, clrGold,  10);
   DashLabel("l1", "Pair/TF : " + _Symbol + " " + TfToStr((ENUM_TIMEFRAMES)_Period),
             x, y + (n++) * lh, clrWhite, 9);

   string trend = TrendText();
   color  tcol  = (trend == "UP" ? clrLime : (trend == "DOWN" ? clrTomato : clrSilver));
   DashLabel("l2", "Trend   : " + trend, x, y + (n++) * lh, tcol, 9);

   DashLabel("l3", "TrendFlt: " + (InpUseTrendFilter ? "ON" : "OFF"), x, y + (n++) * lh, clrWhite, 9);
   DashLabel("l4", "ShapeFlt: " + (InpUseShapeFilter ? "ON" : "OFF"), x, y + (n++) * lh, clrWhite, 9);

   color  scol   = (g_lastSignal == "BUY" ? clrLime : (g_lastSignal == "SELL" ? clrTomato : clrSilver));
   string sigtm  = (g_lastSignalTm > 0 ? TimeToString(g_lastSignalTm, TIME_MINUTES) : "-");
   DashLabel("l5", "Signal  : " + g_lastSignal + " " + sigtm, x, y + (n++) * lh, scol, 9);

   DashLabel("l6", "Open pos: " + IntegerToString(CountEaPositions()), x, y + (n++) * lh, clrWhite, 9);
   DashLabel("l7", "Trailing: " + (InpUseTrailing ? "ON" : "OFF"), x, y + (n++) * lh, clrWhite, 9);
   DashLabel("l8", "Sound   : " + (InpEnableSound ? "ON" : "OFF"),
             x, y + (n++) * lh, (InpEnableSound ? clrLime : clrSilver), 9);
   DashLabel("l9", "TP/SL   : " + DoubleToString(InpTakeProfit, 2) + "/" +
             DoubleToString(InpStopLoss, 2) + " USD", x, y + (n++) * lh, clrWhite, 9);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Runtime guards (in case of chart symbol/timeframe change)
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol))
      return;
   if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period))
      return;

   // Keep the dashboard fresh
   DrawDashboard();

   // Trailing stops are managed on EVERY tick (not just on a new bar)
   ManageTrailing();

   // --- Entry logic below runs only once per completed bar ---
   if(!IsNewBar())
      return;

   // Respect max simultaneous positions
   if(CountEaPositions() >= InpMaxPositions)
      return;

   // Ensure trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED)           ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)   ||
      !SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
      return;

   // Spread filter
   if(!SpreadOK())
      return;

   // Evaluate pattern
   int signal = CheckPattern();
   if(signal == 0)
      return;

   g_lastSignal   = (signal > 0 ? "BUY" : "SELL");
   g_lastSignalTm = TimeCurrent();

   OpenTrade(signal);
  }
//+------------------------------------------------------------------+
