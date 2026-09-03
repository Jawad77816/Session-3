//+------------------------------------------------------------------+
//|                                             FourEmaRibbonEA.mq5   |
//|      4-EMA Ribbon trend EA (MetaTrader 5)                         |
//|      Rebuilt from a two-part TradingView video lesson.            |
//|                                                                  |
//|  Setup taught in the video (parts 1 & 2):                        |
//|    Four EMAs on the chart:                                        |
//|        EMA 8  (blue)   EMA 13 (green)   EMA 21 (yellow)   EMA 55 (red)
//|    (all Fibonacci; the legend briefly showed "9" for the fast one,|
//|     so InpEma1 is an input - set it to 9 if you prefer.)          |
//|                                                                  |
//|  Signal (the green circle in the video = the ribbon flip):        |
//|    LONG  : EMA8 crosses ABOVE EMA13 while the ribbon is bullish   |
//|            (EMA13 > EMA21 > EMA55).                                |
//|    SHORT : EMA8 crosses BELOW EMA13 while the ribbon is bearish   |
//|            (EMA13 < EMA21 < EMA55).                                |
//|    (InpRequireStack relaxes this to a simple EMA21/EMA55 trend    |
//|     filter if you turn it off.)                                   |
//|                                                                  |
//|  Exit: fixed Stop-Loss (swing or ATR) and a fixed Take-Profit at  |
//|        a manually adjustable Risk:Reward - DEFAULT 1:3 (InpRR).    |
//|                                                                  |
//|  This is an EXPERT ADVISOR - it opens/closes trades. Test on a    |
//|  DEMO account first. Signals are evaluated on CLOSED bars.        |
//+------------------------------------------------------------------+
#property copyright "Four EMA Ribbon EA"
#property version   "1.30"
#property description "4-EMA (8/13/21/55) ribbon crossover trend EA. Fixed R:R TP (default 1:3). Progressive lots, daily profit target + loss limit, optional ADX filter, equity kill-switch, and optional exit management (breakeven / trailing / partial TP). Closed-bar signals."

#include <Trade/Trade.mqh>
CTrade  trade;

//--- enums
enum ENUM_SLMODE
  {
   SL_SWING = 0,   // Swing high/low (lookback)
   SL_ATR   = 1    // ATR multiple
  };

//--- inputs : EMAs ------------------------------------------------------------
input group                "=== EMAs (Fibonacci ribbon) ==="
input int              InpEma1     = 8;            // Fast EMA   (blue)
input int              InpEma2     = 13;           // EMA 2      (green)
input int              InpEma3     = 21;           // EMA 3      (yellow)
input int              InpEma4     = 55;           // Slow EMA   (red)
input ENUM_MA_METHOD   InpMaMethod = MODE_EMA;     // MA method
input ENUM_APPLIED_PRICE InpMaPrice= PRICE_CLOSE;  // Applied price

//--- inputs : entry -----------------------------------------------------------
input group                "=== Entry ==="
input bool   InpTradeLong      = true;   // Allow long trades
input bool   InpTradeShort     = true;   // Allow short trades
input bool   InpRequireStack   = true;   // Require full 8>13>21>55 alignment
input bool   InpPriceFilter    = false;  // Also require close beyond the slow EMA
input bool   InpCloseOnOpposite= true;   // Close a trade on an opposite signal
input bool   InpOneTradeAtATime= true;   // Only one position (this symbol+magic)

//--- inputs : ADX trend-strength filter (optional) ---------------------------
// Only allow entries when ADX >= threshold (skips weak/choppy markets). ADX
// measures trend STRENGTH (not direction), so it is not redundant with the EMAs.
input group                "=== ADX filter (optional) ==="
input bool   InpUseADX     = false;  // Require ADX >= threshold to enter
input int    InpADXPeriod  = 14;     // ADX period
input double InpADXMin      = 20.0;  // Minimum ADX to allow entries

//--- inputs : risk / reward ---------------------------------------------------
input group                "=== Risk / Reward ==="
input double InpRR             = 3.0;    // Take-Profit R:R  (1 : x)   << default 1:3
input ENUM_SLMODE InpSLMode    = SL_SWING;// Stop-loss method
input int    InpSwingLookback  = 10;     // Swing lookback (bars)  [SL_SWING]
input double InpATRmult        = 1.5;    // ATR multiple           [SL_ATR]
input int    InpATRperiod      = 14;     // ATR period             [SL_ATR]
input int    InpSLBufferPts    = 10;     // Extra stop buffer (points)

//--- inputs : money management ------------------------------------------------
input group                "=== Money management ==="
input bool   InpUseRiskPct     = false;  // Size by % risk (else fixed lots)
input double InpRiskPct        = 1.0;    // Risk per trade (% of balance)
input double InpFixedLots      = 0.10;   // Fixed lot size

//--- inputs : progressive lot sizing -----------------------------------------
// Grows the lot as the balance grows. Example: base 0.05 at $500, then +0.01
// for every +$1000 of balance -> 0.06 at $1500, 0.07 at $2500, ...
// When enabled this OVERRIDES fixed lots and risk-% sizing.
input group                "=== Progressive lot sizing ==="
input bool   InpUseProgLots     = true;  // Grow lot with balance (overrides fixed/risk%)
input double InpProgBaseBalance = 500;   // Base balance for the base lot
input double InpProgBaseLot      = 0.05; // Base lot at/below the base balance
input double InpProgStepBalance  = 1000; // Add a step for every this much balance gained
input double InpProgLotStep      = 0.01; // Lot added per step

//--- inputs : daily profit target / loss limit -------------------------------
// Both measured on the day's REALISED profit (account currency). 0 = disabled.
//  * Profit target: once reached, no new trades until the next day.
//  * Loss limit:   once the day's loss reaches it, stop for the day (and, if
//    InpFlattenOnStop, close the open trade).
input group                "=== Daily profit target / loss limit ==="
input double InpDailyProfitTarget = 0.0; // Daily profit target (0 = no limit)
input double InpDailyLossLimit    = 0.0; // Daily loss limit    (0 = no limit)

//--- inputs : equity kill-switch (optional) ----------------------------------
// Hard account protector. If equity falls this % below its running peak, close
// everything and STOP trading until the EA is reloaded. 0 = disabled.
input group                "=== Equity kill-switch (optional) ==="
input double InpEquityDDStop  = 0.0;   // Max equity drawdown from peak (%, 0 = off)
input bool   InpFlattenOnStop = true;  // Close open trades when a limit/kill trips

//--- inputs : exit management (optional) -------------------------------------
// All measured in "R" = the trade's own initial risk (derived from its TP:
// R = |TP - entry| / InpRR). All default OFF, so the base strategy is unchanged.
input group                "=== Exit management (optional) ==="
input bool   InpUseBreakeven    = false; // Move SL to breakeven after +N R
input double InpBreakevenR       = 1.0;  // Profit in R to trigger breakeven
input int    InpBreakevenLockPts = 0;    // Lock this many points beyond entry at BE
input bool   InpUseTrail         = false;// Trailing stop (in R units)
input double InpTrailStartR       = 1.0; // Start trailing after +this many R
input double InpTrailDistR         = 1.0;// Trail distance behind price (in R)
input int    InpTrailStepPts       = 10; // Min SL improvement to modify (points)
input bool   InpUsePartial         = false; // Take partial profit
input double InpPartialAtR           = 1.0; // Close part at +this many R
input int    InpPartialPct            = 50;  // % of the position to close

//--- inputs : misc ------------------------------------------------------------
input group                "=== Misc ==="
input long   InpMagic          = 990088; // Magic number
input int    InpMaxSpreadPts   = 50;     // Max spread to enter (points, 0=off)
input int    InpSlippagePts    = 20;     // Max slippage (points)
input string InpComment        = "FourEMA";

//--- handles / state ----------------------------------------------------------
int      hEma1, hEma2, hEma3, hEma4, hATR, hADX;
datetime g_lastBar = 0;
int      g_dayKey          = -1;    // current day (yyyymmdd) for the daily target
double   g_dayStartBalance = 0.0;   // balance recorded at the start of the day
double   g_peakEquity      = 0.0;   // running peak equity (for the kill-switch)
bool     g_killed          = false; // equity kill-switch tripped -> stop trading
ulong    g_partialDone[];           // tickets already partially closed

//+------------------------------------------------------------------+
int OnInit()
  {
   hEma1 = iMA(_Symbol, _Period, InpEma1, 0, InpMaMethod, InpMaPrice);
   hEma2 = iMA(_Symbol, _Period, InpEma2, 0, InpMaMethod, InpMaPrice);
   hEma3 = iMA(_Symbol, _Period, InpEma3, 0, InpMaMethod, InpMaPrice);
   hEma4 = iMA(_Symbol, _Period, InpEma4, 0, InpMaMethod, InpMaPrice);
   hATR  = iATR(_Symbol, _Period, InpATRperiod);
   hADX  = iADX(_Symbol, _Period, InpADXPeriod);

   if(hEma1==INVALID_HANDLE || hEma2==INVALID_HANDLE || hEma3==INVALID_HANDLE ||
      hEma4==INVALID_HANDLE || hATR==INVALID_HANDLE  || hADX==INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);

   // pick a filling mode the symbol supports
   long fill = (long)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fill & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEma1); IndicatorRelease(hEma2);
   IndicatorRelease(hEma3); IndicatorRelease(hEma4);
   IndicatorRelease(hATR);  IndicatorRelease(hADX);
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == g_lastBar) return(false);
   g_lastBar = t;
   return(true);
  }
// read one buffer value at a given shift
bool EmaVal(const int handle, const int shift, double &out)
  {
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return(false);
   out = b[0];
   return(true);
  }
int CountMyPositions(const int dir)   // dir: +1 long, -1 short, 0 any
  {
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type != POSITION_TYPE_BUY)  continue;
      if(dir < 0 && type != POSITION_TYPE_SELL) continue;
      n++;
     }
   return(n);
  }
void CloseMyPositions(const int dir)
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type != POSITION_TYPE_BUY)  continue;
      if(dir < 0 && type != POSITION_TYPE_SELL) continue;
      trade.PositionClose(tk);
     }
  }
double NormalizeLots(double lots)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots/step) * step;
   if(lots < minL) lots = minL;
   if(lots > maxL) lots = maxL;
   return(lots);
  }
// progressive lot: base lot + one step per full "step balance" gained
double ProgressiveLots()
  {
   double gain  = AccountInfoDouble(ACCOUNT_BALANCE) - InpProgBaseBalance;
   int    steps = 0;
   if(InpProgStepBalance > 0.0 && gain > 0.0)
      steps = (int)MathFloor(gain / InpProgStepBalance);
   if(steps < 0) steps = 0;
   return(NormalizeLots(InpProgBaseLot + steps * InpProgLotStep));
  }
double CalcLots(const double slDistPrice)
  {
   if(InpUseProgLots) return(ProgressiveLots());     // balance-driven sizing (overrides the rest)
   if(!InpUseRiskPct) return(NormalizeLots(InpFixedLots));
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0 || slDistPrice <= 0)
      return(NormalizeLots(InpFixedLots));
   double riskMoney   = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   double lossPerLot  = (slDistPrice / tickSize) * tickVal;
   if(lossPerLot <= 0) return(NormalizeLots(InpFixedLots));
   return(NormalizeLots(riskMoney / lossPerLot));
  }
// swing low / high over N closed bars (starting at shift 1)
double SwingLow(const int lookback)
  {
   double lo[];
   ArraySetAsSeries(lo, true);
   if(CopyLow(_Symbol, _Period, 1, lookback, lo) < lookback) return(0);
   int mi = ArrayMinimum(lo, 0, lookback);
   return(lo[mi]);
  }
double SwingHigh(const int lookback)
  {
   double hi[];
   ArraySetAsSeries(hi, true);
   if(CopyHigh(_Symbol, _Period, 1, lookback, hi) < lookback) return(0);
   int mx = ArrayMaximum(hi, 0, lookback);
   return(hi[mx]);
  }

//+------------------------------------------------------------------+
//| Exit management: breakeven, trailing stop, partial take-profit   |
//+------------------------------------------------------------------+
bool PartialDone(const ulong tk)
  {
   for(int i = 0; i < ArraySize(g_partialDone); i++)
      if(g_partialDone[i] == tk) return(true);
   return(false);
  }
void MarkPartial(const ulong tk)
  {
   int n = ArraySize(g_partialDone);
   ArrayResize(g_partialDone, n+1);
   g_partialDone[n] = tk;
  }
void PrunePartial()                   // drop tickets that are no longer open
  {
   ulong keep[]; int k = 0;
   for(int i = 0; i < ArraySize(g_partialDone); i++)
      if(PositionSelectByTicket(g_partialDone[i]))
        { ArrayResize(keep, k+1); keep[k] = g_partialDone[i]; k++; }
   ArrayResize(g_partialDone, k);
   for(int i = 0; i < k; i++) g_partialDone[i] = keep[i];
  }
double NormalizePartialVol(double v)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   v = MathFloor(v/step) * step;
   return(v);
  }
void ManageOpenTrades()
  {
   if(!InpUseBreakeven && !InpUseTrail && !InpUsePartial) return;
   PrunePartial();

   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double minVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      if(tp <= 0.0) continue;                       // need TP to derive R
      double risk  = MathAbs(tp - entry) / InpRR;   // R in price terms
      if(risk <= 0.0) continue;

      bool   isLong = (type == POSITION_TYPE_BUY);
      double cur    = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profit = isLong ? (cur - entry) : (entry - cur);

      // --- partial take-profit (once per position) ---
      if(InpUsePartial && !PartialDone(tk) && profit >= InpPartialAtR * risk)
        {
         double closeVol = NormalizePartialVol(vol * InpPartialPct / 100.0);
         if(closeVol >= minVol && (vol - closeVol) >= minVol)
           {
            if(trade.PositionClosePartial(tk, closeVol))
              {
               MarkPartial(tk);
               vol = PositionGetDouble(POSITION_VOLUME);   // refresh remaining volume
              }
           }
         else
            MarkPartial(tk);   // can't split (too small) -> don't retry every tick
        }

      // --- breakeven + trailing collapsed into one target SL, applied once ---
      double target = sl;
      if(InpUseBreakeven && profit >= InpBreakevenR * risk)
        {
         double be = isLong ? entry + InpBreakevenLockPts*point
                            : entry - InpBreakevenLockPts*point;
         target = isLong ? MathMax(target, be) : MathMin(target, be);
        }
      if(InpUseTrail && profit >= InpTrailStartR * risk)
        {
         double nsl = isLong ? cur - InpTrailDistR*risk : cur + InpTrailDistR*risk;
         target = isLong ? MathMax(target, nsl) : MathMin(target, nsl);
        }

      bool improve = isLong ? (target > sl) : (target < sl);
      bool okDist  = isLong ? (cur - target >= stopLevel) : (target - cur >= stopLevel);
      if(improve && okDist && MathAbs(target - sl) >= InpTrailStepPts*point)
         trade.PositionModify(tk, NormalizeDouble(target, _Digits), tp);
     }
  }

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // --- equity kill-switch: runs every tick for fast protection ---
   if(g_killed)
      return;                                   // already stopped for good
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;      // trail the equity peak
   if(InpEquityDDStop > 0.0 && g_peakEquity > 0.0)
     {
      double ddpct = (g_peakEquity - eq) / g_peakEquity * 100.0;
      if(ddpct >= InpEquityDDStop)
        {
         if(InpFlattenOnStop) CloseMyPositions(0);
         g_killed = true;
         PrintFormat("EQUITY KILL-SWITCH: drawdown %.2f%% >= %.2f%% -> closed all, trading stopped.",
                     ddpct, InpEquityDDStop);
         return;
        }
     }

   // --- manage open trades (breakeven / trailing / partial) every tick ---
   ManageOpenTrades();

   if(!IsNewBar())
      return;

   // --- daily profit target: record the balance at the start of each new day ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int today = dt.year*10000 + dt.mon*100 + dt.day;
   if(today != g_dayKey)
     {
      g_dayKey = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }

   // --- daily loss limit: stop (and optionally flatten) for the rest of the day ---
   if(InpDailyLossLimit > 0.0 &&
      (AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance) <= -InpDailyLossLimit)
     {
      if(InpFlattenOnStop && CountMyPositions(0) > 0) CloseMyPositions(0);
      return;                                   // no more trading today
     }

   // --- pull EMA values on the two most recent CLOSED bars (shift 1 & 2) ---
   double e1_1,e1_2, e2_1,e2_2, e3_1, e4_1;
   if(!EmaVal(hEma1,1,e1_1) || !EmaVal(hEma1,2,e1_2)) return;
   if(!EmaVal(hEma2,1,e2_1) || !EmaVal(hEma2,2,e2_2)) return;
   if(!EmaVal(hEma3,1,e3_1)) return;
   if(!EmaVal(hEma4,1,e4_1)) return;

   bool crossUp   = (e1_1 > e2_1 && e1_2 <= e2_2);   // EMA8 crosses above EMA13
   bool crossDown = (e1_1 < e2_1 && e1_2 >= e2_2);   // EMA8 crosses below EMA13

   bool bullTrend = InpRequireStack ? (e2_1 > e3_1 && e3_1 > e4_1) : (e3_1 > e4_1);
   bool bearTrend = InpRequireStack ? (e2_1 < e3_1 && e3_1 < e4_1) : (e3_1 < e4_1);

   double close1 = iClose(_Symbol, _Period, 1);
   bool priceOkLong  = (!InpPriceFilter) || (close1 > e4_1);
   bool priceOkShort = (!InpPriceFilter) || (close1 < e4_1);

   bool longSig  = InpTradeLong  && crossUp   && bullTrend && priceOkLong;
   bool shortSig = InpTradeShort && crossDown && bearTrend && priceOkShort;

   // --- manage existing positions: close on opposite signal ---
   if(InpCloseOnOpposite)
     {
      if(shortSig && CountMyPositions(+1) > 0) CloseMyPositions(+1);
      if(longSig  && CountMyPositions(-1) > 0) CloseMyPositions(-1);
     }

   // --- entries ---
   // daily profit target reached -> no new trades until the next day (0 = off)
   if(InpDailyProfitTarget > 0.0 &&
      (AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance) >= InpDailyProfitTarget)
      return;

   if(InpOneTradeAtATime && CountMyPositions(0) > 0)
      return;

   // spread filter
   if(InpMaxSpreadPts > 0)
     {
      long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spr > InpMaxSpreadPts) return;
     }

   // ADX trend-strength filter (only gates NEW entries, not trade management)
   if(InpUseADX && (longSig || shortSig))
     {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return;   // ADX main line, last closed bar
      if(adx[0] < InpADXMin) return;                    // trend too weak -> skip
     }

   if(longSig)  OpenTrade(true);
   else if(shortSig) OpenTrade(false);
  }

//+------------------------------------------------------------------+
//| Open a trade with SL (swing/ATR) and fixed-R:R TP                |
//+------------------------------------------------------------------+
void OpenTrade(const bool isBuy)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buf   = InpSLBufferPts * point;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;

   // stop-loss level
   double sl = 0.0;
   if(InpSLMode == SL_SWING)
     {
      double sw = isBuy ? SwingLow(InpSwingLookback) : SwingHigh(InpSwingLookback);
      if(sw <= 0) return;
      sl = isBuy ? sw - buf : sw + buf;
     }
   else // ATR
     {
      double a[]; ArraySetAsSeries(a, true);
      if(CopyBuffer(hATR, 0, 1, 1, a) < 1) return;
      double dist = a[0] * InpATRmult + buf;
      sl = isBuy ? entry - dist : entry + dist;
     }

   double risk = isBuy ? (entry - sl) : (sl - entry);
   if(risk <= 0) return;

   // respect the broker's minimum stop distance
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(risk < stopLevel)
     {
      risk = stopLevel;
      sl   = isBuy ? entry - risk : entry + risk;
     }

   double tp = isBuy ? entry + InpRR * risk : entry - InpRR * risk;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalcLots(risk);
   if(lots <= 0) return;

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment)
                   : trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);

   if(!ok)
      PrintFormat("Order failed (%s): retcode=%d  %s",
                  isBuy?"BUY":"SELL", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else
      PrintFormat("%s %s  lots=%.2f  entry~%.5f  SL=%.5f  TP=%.5f  (1:%.1f)",
                  isBuy?"BUY":"SELL", _Symbol, lots, entry, sl, tp, InpRR);
  }
//+------------------------------------------------------------------+
