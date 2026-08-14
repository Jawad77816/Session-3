//+------------------------------------------------------------------+
//|                                       ThreeCandleReversalEA.mq5   |
//|            Self-contained Three-Candle Reversal EA (XAUUSD M1/M5) |
//|                                                                  |
//|  Everything the indicator does, built directly into one EA - no  |
//|  iCustom, no external dependency. Trades live AND backtests in    |
//|  the Strategy Tester.                                            |
//|                                                                  |
//|  BUY  : red -> green -> green, middle is a hammer/pin with the    |
//|         lowest low, its body inside candle 1's body, 3rd body     |
//|         closes above candle 1's high. Optional confirmation,      |
//|         trend filter and RSI-momentum filter.                    |
//|  SELL : mirror image.                                            |
//|                                                                  |
//|  Auto SL/TP: SL at the middle candle's extreme, TP = ratio x risk|
//+------------------------------------------------------------------+
#property copyright "Three-Candle Reversal EA"
#property version   "2.40"
#property strict
#property description "Self-contained three-candle reversal EA for XAUUSD M1/M5 with trend,"
#property description "RSI and ADX-regime filters, auto SL/RR TP, risk sizing and loss lockout."

#include <Trade/Trade.mqh>

enum ENUM_RSI_MODE
  {
   RSI_DIVERGENCE = 0,   // Momentum divergence (best quality filter)
   RSI_THRESHOLD  = 1    // Overbought/oversold threshold
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group    "=== Trading ==="
input double   InpLotSize        = 0.01;        // Fixed lot size
input int      InpMaxPositions   = 1;           // Max simultaneous positions
input double   InpMaxSpreadUSD   = 0.0;         // Max spread in USD (0 = off)
input long     InpMagicNumber    = 20250811;    // Magic number
input int      InpDeviationPts   = 30;          // Max deviation (points)

input group    "=== Auto SL/TP (candle-based) ==="
input bool     InpAutoSLTP       = true;        // Auto SL from middle candle, TP = ratio x risk
input double   InpRewardRatio    = 3.0;         // Reward:risk ratio (3 for 1:3, 4 for 1:4)
input double   InpSLBufferUSD    = 0.0;         // Extra buffer beyond the middle candle wick (USD)
input double   InpTakeProfit     = 1.0;         // Fixed TP (USD) - used only when AutoSLTP = false
input double   InpStopLoss       = 1.0;         // Fixed SL (USD) - used only when AutoSLTP = false

input group    "=== Risk Management ==="
input bool     InpUseRiskSizing  = true;        // Size lot by % risk (else fixed InpLotSize)
input double   InpRiskPercent    = 1.0;         // Risk this % of balance per trade
input double   InpMaxSLUSD       = 10.0;        // Skip signals whose SL is wider than this (USD, 0=off)
input bool     InpCapLotToMargin = true;        // If lot too big for margin, use max affordable (never "no money")

input group    "=== Anti-Trend Lockout ==="
input bool     InpUseLossLockout = true;        // Pause after consecutive losses (stop fighting a trend)
input int      InpMaxConsecLosses = 3;          // Lock out after this many losses in a row
input int      InpLockoutBars    = 12;          // Pause for this many bars after lockout

input group    "=== Trailing Stop (fixed USD) ==="
input bool     InpUseTrailing    = false;       // Tight trailing (off: let R:R TP run)
input double   InpTrailStartUSD  = 0.5;         // Start trailing after this profit (USD)
input double   InpTrailGapUSD    = 0.1;         // Trail distance behind price (USD)
input double   InpTrailStepUSD   = 0.0;         // Min SL move before updating (USD)

input group    "=== Signals ==="
input bool     InpEnableBuy      = true;        // Allow BUY trades
input bool     InpEnableSell     = true;        // Allow SELL trades
input bool     InpReverseSignals = false;       // Flip buy<->sell (test continuation vs reversal)

input group    "=== Trend / Reversal Filter ==="
input bool           InpUseTrendFilter = true;  // Only take reversals (skip mid-trend)
input int            InpSwingLookback  = 12;    // Local top/bottom lookback (bars, 0=off)
input int            InpMAPeriod       = 50;    // Trend MA period (0=off)
input ENUM_MA_METHOD InpMAMethod       = MODE_EMA; // Trend MA method
input int            InpMASlopeBars    = 5;     // Bars used to measure MA slope

input group    "=== Regime Filter (ADX) ==="
input bool           InpUseADXFilter   = true;  // Only fade RANGING markets (skip strong trends)
input int            InpADXPeriod      = 14;    // ADX period
input double         InpADXMax         = 30.0;  // Skip when ADX above this (market trending)

input group    "=== Candle Shape Filter ==="
input bool     InpRequireSolidOuter = true;     // 1st & 3rd must be solid (not doji/hammer)
input bool     InpMiddleInsideFirst = true;     // Middle body inside 1st candle's body
input bool     InpUseShapeFilter    = false;    // ALSO require strict hammer/star wick ratios
input double   InpHammerWickPct   = 0.5;        // Dominant wick >= this fraction of range
input double   InpHammerHeadPct   = 0.15;       // Opposite wick <= this fraction of range
input double   InpHammerBodyPct   = 0.4;        // Hammer/star body <= this fraction of range
input double   InpSolidBodyPct    = 0.5;        // 1st/3rd body >= this fraction

input group    "=== Confirmation ==="
input bool     InpConfirmCandle  = false;       // Require next candle to confirm

input group    "=== Momentum / RSI Quality Filter ==="
input bool           InpUseRSIFilter = true;    // Filter by RSI momentum
input ENUM_RSI_MODE  InpRSIMode      = RSI_DIVERGENCE; // Divergence or Threshold
input int            InpRSIPeriod    = 14;      // RSI period
input double         InpRSIOverbought = 70.0;   // Threshold: sell needs RSI >= this
input double         InpRSIOversold   = 30.0;   // Threshold: buy needs RSI <= this

input group    "=== Notifications ==="
input bool     InpEnableSound    = true;        // Play a sound on entry
input string   InpBuySound       = "alert.wav"; // Sound for BUY
input string   InpSellSound      = "alert2.wav";// Sound for SELL
input bool     InpEnableAlert    = false;       // Popup alert on entry
input bool     InpEnablePush     = false;       // Push notification on entry

input group    "=== Dashboard ==="
input bool     InpShowDashboard  = true;        // Show on-chart dashboard
input int      InpDashX          = 12;          // Dashboard X (px)
input int      InpDashY          = 20;          // Dashboard Y (px)
input color    InpDashBgColor    = clrBlack;    // Dashboard background

input group    "=== Instrument / Timeframe Guards ==="
input bool     InpRestrictSymbol    = true;     // Only run on XAUUSD-type symbol
input bool     InpRestrictTimeframe = true;     // Only run on M1 / M5

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade   trade;
datetime g_lastBarTime = 0;
int      g_symDigits   = 2;
double   g_symPoint    = 0.01;
int      g_maHandle    = INVALID_HANDLE;
int      g_rsiHandle   = INVALID_HANDLE;
int      g_adxHandle   = INVALID_HANDLE;
int      g_consecLosses = 0;                    // consecutive losing trades
datetime g_lockoutUntil = 0;                    // trading paused until this time
string   g_lastSignal  = "None";
datetime g_lastSignalTm = 0;
string   g_lastCheck   = "-";
#define  DASH_PREFIX     "TCREA_DASH_"

//+------------------------------------------------------------------+
//| Basic helpers                                                    |
//+------------------------------------------------------------------+
bool IsGoldSymbol(const string sym)
  {
   string s = sym; StringToUpper(s);
   return(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0);
  }
bool IsAllowedTimeframe(const ENUM_TIMEFRAMES tf) { return(tf == PERIOD_M1 || tf == PERIOD_M5); }
string TfToStr(const ENUM_TIMEFRAMES tf) { string s = EnumToString(tf); StringReplace(s, "PERIOD_", ""); return s; }
bool IsBull(const double o, const double c) { return(c > o); }
bool IsBear(const double o, const double c) { return(c < o); }

bool IsHammerShape(const double o, const double h, const double l, const double c)
  {
   double range = h - l; if(range <= 0.0) return false;
   double body = MathAbs(c - o), uw = h - MathMax(o, c), lw = MathMin(o, c) - l;
   return(lw >= InpHammerWickPct * range && uw <= InpHammerHeadPct * range && body <= InpHammerBodyPct * range);
  }
bool IsStarShape(const double o, const double h, const double l, const double c)
  {
   double range = h - l; if(range <= 0.0) return false;
   double body = MathAbs(c - o), uw = h - MathMax(o, c), lw = MathMin(o, c) - l;
   return(uw >= InpHammerWickPct * range && lw <= InpHammerHeadPct * range && body <= InpHammerBodyPct * range);
  }
bool IsSolidCandle(const double o, const double h, const double l, const double c)
  {
   double range = h - l; if(range <= 0.0) return false;
   return(MathAbs(c - o) >= InpSolidBodyPct * range);
  }
bool MiddleBodyInsideFirst(const double om, const double cm, const double of, const double cf)
  {
   return(MathMax(om, cm) <= MathMax(of, cf) && MathMin(om, cm) >= MathMin(of, cf));
  }

double MaAt(const int shift)
  {
   if(g_maHandle == INVALID_HANDLE) return(EMPTY_VALUE);
   double b[]; if(CopyBuffer(g_maHandle, 0, shift, 1, b) < 1) return(EMPTY_VALUE);
   return(b[0]);
  }
double RsiAt(const int shift)
  {
   if(g_rsiHandle == INVALID_HANDLE) return(EMPTY_VALUE);
   double b[]; if(CopyBuffer(g_rsiHandle, 0, shift, 1, b) < 1) return(EMPTY_VALUE);
   return(b[0]);
  }
double AdxAt(const int shift)
  {
   if(g_adxHandle == INVALID_HANDLE) return(EMPTY_VALUE);
   double b[]; if(CopyBuffer(g_adxHandle, 0, shift, 1, b) < 1) return(EMPTY_VALUE);  // buffer 0 = MAIN ADX
   return(b[0]);
  }

//+------------------------------------------------------------------+
//| Regime filter: only fade ranging markets (ADX <= max)            |
//+------------------------------------------------------------------+
bool AdxOK()
  {
   if(!InpUseADXFilter || g_adxHandle == INVALID_HANDLE) return(true);
   double adx = AdxAt(1);
   if(adx == EMPTY_VALUE || adx <= 0.0) return(true);   // not ready -> don't block
   return(adx <= InpADXMax);
  }

//+------------------------------------------------------------------+
//| RSI momentum quality filter (dir=+1 buy, -1 sell)                |
//+------------------------------------------------------------------+
bool RsiOK(const int dir, const int off)
  {
   if(!InpUseRSIFilter || g_rsiHandle == INVALID_HANDLE) return(true);
   int midShift = 2 + off;
   double rMid = RsiAt(midShift);
   if(rMid == EMPTY_VALUE || rMid <= 0.0) return(true);

   if(InpRSIMode == RSI_THRESHOLD)
      return(dir > 0 ? (rMid <= InpRSIOversold) : (rMid >= InpRSIOverbought));

   // Divergence: middle candle is the price extreme; keep only if RSI is NOT.
   int look = (InpSwingLookback > 0 ? InpSwingLookback : 12);
   double buf[];
   if(CopyBuffer(g_rsiHandle, 0, 1 + off, look, buf) < look) return(true);
   double maxR = -1.0, minR = 1e9;
   for(int k = 0; k < look; k++)
     {
      double v = buf[k]; if(v <= 0.0) continue;
      if(v > maxR) maxR = v;
      if(v < minR) minR = v;
     }
   if(dir > 0) return(rMid > minR + 0.001);   // bullish divergence
   return(rMid < maxR - 0.001);               // bearish divergence
  }

//+------------------------------------------------------------------+
//| Trend / reversal context filter                                  |
//+------------------------------------------------------------------+
bool TrendFilterOK(const int dir, const int off)
  {
   if(!InpUseTrendFilter) return(true);
   if(InpSwingLookback > 0)
     {
      if(dir < 0)
        { if(iHighest(_Symbol, _Period, MODE_HIGH, InpSwingLookback, 1 + off) != 2 + off) return(false); }
      else
        { if(iLowest(_Symbol, _Period, MODE_LOW, InpSwingLookback, 1 + off) != 2 + off) return(false); }
     }
   if(InpMAPeriod > 0 && g_maHandle != INVALID_HANDLE)
     {
      double r = MaAt(1 + off), o = MaAt(1 + off + InpMASlopeBars);
      if(r != EMPTY_VALUE && o != EMPTY_VALUE)
        {
         if(dir < 0 && !(r > o)) return(false);   // sell needs rising MA
         if(dir > 0 && !(r < o)) return(false);   // buy needs falling MA
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Evaluate the pattern; sets g_lastCheck; returns +1/-1/0          |
//+------------------------------------------------------------------+
int CheckPattern()
  {
   int off = InpConfirmCandle ? 1 : 0;
   if(Bars(_Symbol, _Period) < 6 + off) { g_lastCheck = "warming up"; return(0); }

   int fs = 3 + off, ms = 2 + off, ts = 1 + off;   // first, middle, third shifts
   double o1 = iOpen(_Symbol,_Period,fs), c1 = iClose(_Symbol,_Period,fs), h1 = iHigh(_Symbol,_Period,fs), l1 = iLow(_Symbol,_Period,fs);
   double o2 = iOpen(_Symbol,_Period,ms), c2 = iClose(_Symbol,_Period,ms), h2 = iHigh(_Symbol,_Period,ms), l2 = iLow(_Symbol,_Period,ms);
   double o3 = iOpen(_Symbol,_Period,ts), c3 = iClose(_Symbol,_Period,ts), h3 = iHigh(_Symbol,_Period,ts), l3 = iLow(_Symbol,_Period,ts);
   double oc = iOpen(_Symbol,_Period,1),  cc = iClose(_Symbol,_Period,1);   // confirmation candle (shift 1)

   if(o1 == 0 || o2 == 0 || o3 == 0) { g_lastCheck = "no data"; return(0); }

   bool buySkel  = IsBear(o1,c1) && IsBull(o2,c2) && IsBull(o3,c3);
   bool sellSkel = IsBull(o1,c1) && IsBear(o2,c2) && IsBear(o3,c3);
   if(!buySkel && !sellSkel) { g_lastCheck = "no 3-candle colour pattern"; return(0); }

   if(buySkel && InpEnableBuy)
     {
      if(!((l2 < l1) && (l2 < l3)))                              { g_lastCheck = "BUY blocked: middle not lowest low"; return(0); }
      if(!(c3 > h1))                                             { g_lastCheck = "BUY blocked: 3rd doesn't engulf 1st high"; return(0); }
      if(InpUseShapeFilter && !IsHammerShape(o2,h2,l2,c2))       { g_lastCheck = "BUY blocked: middle not a hammer"; return(0); }
      if(InpRequireSolidOuter && !(IsSolidCandle(o1,h1,l1,c1) && IsSolidCandle(o3,h3,l3,c3))) { g_lastCheck = "BUY blocked: outer candle not solid"; return(0); }
      if(InpMiddleInsideFirst && !MiddleBodyInsideFirst(o2,c2,o1,c1)) { g_lastCheck = "BUY blocked: middle body not inside 1st"; return(0); }
      if(off == 1 && !(cc > oc))                                 { g_lastCheck = "BUY blocked: confirmation not bullish"; return(0); }
      if(!RsiOK(1, off))                                         { g_lastCheck = "BUY blocked: no bullish RSI momentum"; return(0); }
      if(!AdxOK())                                               { g_lastCheck = "BUY blocked: market trending (ADX)"; return(0); }
      if(!TrendFilterOK(1, off))                                 { g_lastCheck = "BUY blocked: trend/swing filter"; return(0); }
      g_lastCheck = "BUY signal"; return(1);
     }
   if(sellSkel && InpEnableSell)
     {
      if(!((h2 > h1) && (h2 > h3)))                              { g_lastCheck = "SELL blocked: middle not highest high"; return(0); }
      if(!(c3 < l1))                                             { g_lastCheck = "SELL blocked: 3rd doesn't engulf 1st low"; return(0); }
      if(InpUseShapeFilter && !IsStarShape(o2,h2,l2,c2))         { g_lastCheck = "SELL blocked: middle not a shooting star"; return(0); }
      if(InpRequireSolidOuter && !(IsSolidCandle(o1,h1,l1,c1) && IsSolidCandle(o3,h3,l3,c3))) { g_lastCheck = "SELL blocked: outer candle not solid"; return(0); }
      if(InpMiddleInsideFirst && !MiddleBodyInsideFirst(o2,c2,o1,c1)) { g_lastCheck = "SELL blocked: middle body not inside 1st"; return(0); }
      if(off == 1 && !(cc < oc))                                 { g_lastCheck = "SELL blocked: confirmation not bearish"; return(0); }
      if(!RsiOK(-1, off))                                        { g_lastCheck = "SELL blocked: no bearish RSI momentum"; return(0); }
      if(!AdxOK())                                               { g_lastCheck = "SELL blocked: market trending (ADX)"; return(0); }
      if(!TrendFilterOK(-1, off))                                { g_lastCheck = "SELL blocked: trend/swing filter"; return(0); }
      g_lastCheck = "SELL signal"; return(-1);
     }
   g_lastCheck = "setup disabled"; return(0);
  }

//+------------------------------------------------------------------+
//| Trading utilities                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(t == 0) return(false);
   if(t != g_lastBarTime) { g_lastBarTime = t; return(true); }
   return(false);
  }
int CountEaPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      c++;
     }
   return(c);
  }
bool SpreadOK()
  {
   if(InpMaxSpreadUSD <= 0.0) return(true);
   return((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) <= InpMaxSpreadUSD);
  }
double ClampStop(double d)
  {
   double minD = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_symPoint;
   if(minD > 0.0 && d < minD) d = minD + g_symPoint;
   return(d);
  }

//+------------------------------------------------------------------+
//| Resolve SL/TP distances for a trade                              |
//+------------------------------------------------------------------+
bool ResolveSLTP(const int dir, const double price, double &slDist, double &tpDist)
  {
   if(InpAutoSLTP)
     {
      int off = InpConfirmCandle ? 1 : 0;
      int midShift = 2 + off;
      double midLow = iLow(_Symbol, _Period, midShift), midHigh = iHigh(_Symbol, _Period, midShift);
      if(midLow <= 0.0 || midHigh <= 0.0) return(false);
      slDist = (dir > 0 ? price - (midLow - InpSLBufferUSD) : (midHigh + InpSLBufferUSD) - price);
      if(slDist <= 0.0) { Print("AutoSLTP: invalid risk distance - trade skipped."); return(false); }
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

void NotifyEntry(const int dir, const double price)
  {
   string msg = StringFormat("3-Candle EA %s %s @ %.*f", (dir > 0 ? "BUY" : "SELL"), _Symbol, g_symDigits, price);
   if(InpEnableSound) PlaySound(dir > 0 ? InpBuySound : InpSellSound);
   if(InpEnableAlert) Alert(msg);
   if(InpEnablePush)  SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Normalise a lot to the broker's min/max/step                     |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return(lot);
  }

//+------------------------------------------------------------------+
//| Lot size for a trade: risk % of balance over the SL distance     |
//+------------------------------------------------------------------+
double CalcLot(const double slDist)
  {
   if(!InpUseRiskSizing) return(NormalizeLot(InpLotSize));
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickVal <= 0.0 || slDist <= 0.0) return(NormalizeLot(InpLotSize));
   double riskAmt     = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot  = slDist / tickSize * tickVal;      // money lost per 1.0 lot if SL hit
   if(lossPerLot <= 0.0) return(NormalizeLot(InpLotSize));
   return(NormalizeLot(riskAmt / lossPerLot));
  }

//+------------------------------------------------------------------+
//| Largest lot the current free margin can open (0 = none)          |
//+------------------------------------------------------------------+
double MaxAffordableLot(const int dir, const double price)
  {
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginPerLot = 0.0;
   ENUM_ORDER_TYPE ot = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcMargin(ot, _Symbol, 1.0, price, marginPerLot) || marginPerLot <= 0.0)
      return(0.0);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   // Use 95% of free margin as a safety buffer, round DOWN to a step.
   double lot = MathFloor((freeMargin * 0.95 / marginPerLot) / step) * step;
   if(lot < minLot) return(0.0);   // cannot afford even the minimum lot
   return(lot);
  }

void OpenTrade(const int dir)
  {
   double price = (dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double slDist, tpDist;
   if(!ResolveSLTP(dir, price, slDist, tpDist)) return;

   // Max-SL cap: refuse trades whose candle-based stop is too wide (the
   // blow-up trades in Jan 2026 had SL distances of $30-$82).
   if(InpMaxSLUSD > 0.0 && slDist > InpMaxSLUSD)
     {
      PrintFormat("Skip %s: SL %.2f USD exceeds max %.2f", (dir > 0 ? "BUY" : "SELL"), slDist, InpMaxSLUSD);
      return;
     }

   double lot = CalcLot(slDist);
   if(lot <= 0.0) { Print("Skip: computed lot <= 0"); return; }

   // Margin cap: if the requested lot needs more margin than we have, use the
   // largest affordable lot instead of failing with "not enough money".
   if(InpCapLotToMargin)
     {
      double affordable = MaxAffordableLot(dir, price);
      if(affordable <= 0.0)
        {
         PrintFormat("Skip %s: balance too small for even the minimum lot.", (dir > 0 ? "BUY" : "SELL"));
         return;
        }
      if(lot > affordable)
        {
         PrintFormat("Lot %.2f needs more margin than available - capping to %.2f", lot, affordable);
         lot = affordable;
        }
     }

   double slp, tpp; bool ok;
   if(dir > 0)
     {
      slp = NormalizeDouble(price - slDist, g_symDigits);
      tpp = NormalizeDouble(price + tpDist, g_symDigits);
      ok = trade.Buy(lot, _Symbol, price, slp, tpp, "3CandleEA");
     }
   else
     {
      slp = NormalizeDouble(price + slDist, g_symDigits);
      tpp = NormalizeDouble(price - tpDist, g_symDigits);
      ok = trade.Sell(lot, _Symbol, price, slp, tpp, "3CandleEA");
     }
   if(ok)
     {
      PrintFormat("%s %.2f lot @ %.*f SL=%.*f TP=%.*f risk=%.*f", (dir > 0 ? "BUY" : "SELL"), lot,
                  g_symDigits, price, g_symDigits, slp, g_symDigits, tpp, g_symDigits, slDist);
      NotifyEntry(dir, price);
     }
   else
      PrintFormat("%s failed: %u (%s)", (dir > 0 ? "BUY" : "SELL"), trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

void ManageTrailing()
  {
   if(!InpUseTrailing || InpTrailGapUSD <= 0.0) return;
   double minD = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_symPoint;
   double step = MathMax(InpTrailStepUSD, g_symPoint);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i); if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double op = PositionGetDouble(POSITION_PRICE_OPEN), csl = PositionGetDouble(POSITION_SL), ctp = PositionGetDouble(POSITION_TP);
      double gap = MathMax(InpTrailGapUSD, minD + g_symPoint);
      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - op) < InpTrailStartUSD) continue;
         double nsl = NormalizeDouble(bid - gap, g_symDigits);
         if(nsl < bid && (csl == 0.0 || nsl >= csl + step)) trade.PositionModify(tk, nsl, ctp);
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((op - ask) < InpTrailStartUSD) continue;
         double nsl = NormalizeDouble(ask + gap, g_symDigits);
         if(nsl > ask && (csl == 0.0 || nsl <= csl - step)) trade.PositionModify(tk, nsl, ctp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
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
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);     ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
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
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs); ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }
string TrendText()
  {
   if(!(InpMAPeriod > 0) || g_maHandle == INVALID_HANDLE) return("n/a");
   double r = MaAt(1), o = MaAt(1 + InpMASlopeBars);
   if(r == EMPTY_VALUE || o == EMPTY_VALUE) return("n/a");
   return(r > o ? "UP" : (r < o ? "DOWN" : "FLAT"));
  }
void DrawDashboard()
  {
   if(!InpShowDashboard) return;
   int x = InpDashX, y = InpDashY, lh = 16, n = 0;
   DashPanel("BG", x - 6, y - 6, 330, 9 * lh + 14, InpDashBgColor);
   DashLabel("l0", "3-Candle Reversal EA", x, y + (n++) * lh, clrGold, 10);
   DashLabel("l1", "Pair/TF : " + _Symbol + " " + TfToStr((ENUM_TIMEFRAMES)_Period), x, y + (n++) * lh, clrWhite, 9);
   string tr = TrendText();
   DashLabel("l2", "Trend   : " + tr, x, y + (n++) * lh, (tr=="UP"?clrLime:(tr=="DOWN"?clrTomato:clrSilver)), 9);
   string rsiStr = (!InpUseRSIFilter ? "N" : (InpRSIMode == RSI_DIVERGENCE ? "Div" : "Thr"));
   double adxNow = (InpUseADXFilter ? AdxAt(1) : 0.0);
   string adxStr = (!InpUseADXFilter ? "off" : (adxNow == EMPTY_VALUE ? "n/a" : DoubleToString(adxNow,0)
                    + (adxNow > InpADXMax ? " TREND" : " range")));
   DashLabel("l3", "Filters : Trend=" + (InpUseTrendFilter?"Y":"N") + " RSI=" + rsiStr
                 + " Cnf=" + (InpConfirmCandle?"Y":"N") + "  ADX " + adxStr, x, y + (n++) * lh,
             (InpUseADXFilter && adxNow != EMPTY_VALUE && adxNow > InpADXMax ? clrOrange : clrWhite), 9);
   DashLabel("l4", "SL/TP   : " + (InpAutoSLTP ? "Auto 1:" + DoubleToString(InpRewardRatio,1)
                 : "Fixed " + DoubleToString(InpTakeProfit,2) + "/" + DoubleToString(InpStopLoss,2))
                 + (InpUseRiskSizing ? "  Risk " + DoubleToString(InpRiskPercent,1) + "%" : "  Lot " + DoubleToString(InpLotSize,2))
                 + (InpMaxSLUSD > 0.0 ? "  maxSL " + DoubleToString(InpMaxSLUSD,0) : ""),
             x, y + (n++) * lh, clrWhite, 9);
   color sc = (g_lastSignal=="BUY"?clrLime:(g_lastSignal=="SELL"?clrTomato:clrSilver));
   DashLabel("l5", "Signal  : " + g_lastSignal + " " + (g_lastSignalTm>0?TimeToString(g_lastSignalTm,TIME_MINUTES):"-"), x, y + (n++) * lh, sc, 9);
   bool locked = (g_lockoutUntil > 0 && TimeCurrent() < g_lockoutUntil);
   DashLabel("l6", "Open pos: " + IntegerToString(CountEaPositions())
                 + "  Losses: " + IntegerToString(g_consecLosses)
                 + (locked ? "  [LOCKED]" : ""),
             x, y + (n++) * lh, (locked ? clrOrange : clrWhite), 9);
   DashLabel("l7", "Trailing: " + (InpUseTrailing?"ON":"OFF"), x, y + (n++) * lh, clrWhite, 9);
   bool isSig = (StringFind(g_lastCheck, "signal") >= 0);
   DashLabel("l8", "Last bar: " + g_lastCheck, x, y + (n++) * lh, (isSig?clrLime:clrGoldenrod), 9);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol))
     { Print("ERROR: run on XAUUSD (gold). Current: ", _Symbol); return(INIT_FAILED); }
   if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period))
     { Print("ERROR: supports only M1 and M5."); return(INIT_FAILED); }
   if(InpLotSize <= 0.0) { Print("ERROR: lot must be > 0."); return(INIT_FAILED); }

   g_symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_symPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(InpUseTrendFilter && InpMAPeriod > 0)
      g_maHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   if(InpUseRSIFilter && InpRSIPeriod > 0)
      g_rsiHandle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(InpUseADXFilter && InpADXPeriod > 0)
      g_adxHandle = iADX(_Symbol, _Period, InpADXPeriod);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_lastBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   Print("ThreeCandleReversalEA v2.00 started on ", _Symbol, " ", TfToStr((ENUM_TIMEFRAMES)_Period));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_maHandle != INVALID_HANDLE) IndicatorRelease(g_maHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(InpRestrictSymbol && !IsGoldSymbol(_Symbol)) return;
   if(InpRestrictTimeframe && !IsAllowedTimeframe((ENUM_TIMEFRAMES)_Period)) return;

   ManageTrailing();
   DrawDashboard();

   if(!IsNewBar()) return;

   if(CountEaPositions() >= InpMaxPositions) return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return;
   if(!SpreadOK()) return;

   // Anti-trend lockout: after N consecutive losses, stand aside for a while.
   if(InpUseLossLockout && g_lockoutUntil > 0 && TimeCurrent() < g_lockoutUntil)
     {
      g_lastCheck = "locked out (" + IntegerToString(g_consecLosses) + " losses)";
      return;
     }

   int signal = CheckPattern();
   if(signal == 0) return;

   if(InpReverseSignals) signal = -signal;   // continuation test: fade the fade

   g_lastSignal = (signal > 0 ? "BUY" : "SELL");
   g_lastSignalTm = TimeCurrent();
   OpenTrade(signal);
  }

//+------------------------------------------------------------------+
//| Track closed trades: count consecutive losses -> set lockout     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpUseLossLockout) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;  // closing deal only

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   if(profit < 0.0)
     {
      g_consecLosses++;
      if(g_consecLosses >= InpMaxConsecLosses)
        {
         g_lockoutUntil = TimeCurrent() + (long)InpLockoutBars * PeriodSeconds();
         PrintFormat("Lockout: %d losses in a row -> pausing %d bars.", g_consecLosses, InpLockoutBars);
        }
     }
   else
     {
      g_consecLosses = 0;   // a win resets the streak
     }
  }
//+------------------------------------------------------------------+
