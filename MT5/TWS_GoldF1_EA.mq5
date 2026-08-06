//+------------------------------------------------------------------+
//|                                                TWS_GoldF1_EA.mq5  |
//|                                                                  |
//|  Reconstruction of the "TWS GOLD F1" trend-following pullback     |
//|  system, rebuilt from its published input list (the original      |
//|  .ex5 is closed source, so entry mechanics are reconstructed      |
//|  from the documented parameters).                                 |
//|                                                                  |
//|  Rules:                                                          |
//|   - Direction: longs only above the 200 EMA, shorts only below    |
//|     (RequireTrendFilter).                                         |
//|   - Setup: 20 EMA / 50 EMA stacked in trend order; price pulls    |
//|     back into the 20/50 zone (wick reaches the 20 EMA) and the    |
//|     candle closes back beyond the 20 EMA in the trend direction.  |
//|   - Stop: beyond the 15-bar swing low/high. Target: RewardRatio   |
//|     x risk (3:1). ConsistencyMode banks 50% at +2R.               |
//|   - Sizing: RiskPercent of equity per trade (5% as shipped -      |
//|     aggressive; consider 0.5-1%).                                 |
//|   - Defer window / Friday controls / spread filter as configured. |
//|                                                                  |
//|  Reconstruction assumptions (cannot be read from the binary):     |
//|   - Defer window blocks new entries from DeferStartH until        |
//|     DeferReleaseH (server time). DeferEndH kept for parity only.  |
//|   - One position at a time ("single, directional position").      |
//|   - Banking does NOT move SL to breakeven unless                  |
//|     TWS_MoveSLToBEOnBank is enabled.                              |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//---TWS-INPUTS-BEGIN---
input group "=== TWS: Risk ==="
input double TWS_RiskPercent        = 5.0;    // Risk % of equity per trade (5 = aggressive!)
input double TWS_MaxLotCap          = 200.0;  // Hard cap on lot size
input double TWS_MaxTotalDrawdownPc = 100.0;  // Kill-switch: stop entries at this % drawdown from peak (100 = off)
input int    TWS_MaxTradesPerDay    = 5;      // Max TWS entries per day

input group "=== TWS: Strategy ==="
input ENUM_TIMEFRAMES TWS_TF        = PERIOD_H1; // Timeframe of the EMA/pullback logic
input int    TWS_EMA_Trend          = 200;    // Master trend EMA
input int    TWS_EMA_Fast           = 20;     // Fast momentum EMA
input int    TWS_EMA_Slow           = 50;     // Slow momentum EMA
input int    TWS_SwingLookback      = 15;     // Bars for the swing high/low stop
input double TWS_RewardRatio        = 3.0;    // TP = this x risk
input bool   TWS_RequireTrendFilter = true;   // Never trade against the 200 EMA
input bool   TWS_UseTrendSlope      = false;  // Also require the trend EMA to slope
input int    TWS_TrendSlopeBars     = 3;      // Slope measured over N bars
input double TWS_MinSlopeUSD        = 0.0;    // Min slope (price) over those bars

input group "=== TWS: Consistency Mode ==="
input bool   TWS_ConsistencyMode    = true;   // Bank part of the position at +BankAtRR
input double TWS_BankAtRR           = 2.0;    // Bank when trade reaches this R multiple
input double TWS_BankPercent        = 50.0;   // Percent of volume to bank
input bool   TWS_MoveSLToBEOnBank   = false;  // Also move SL to breakeven when banking

input group "=== TWS: Trailing ==="
input int    TWS_TrailMode          = 0;      // 0 = off, 1 = ATR trail
input double TWS_TrailActivateRR    = 2.0;    // Trail activates at this R multiple
input int    TWS_TrailATRPeriod     = 14;     // ATR period
input double TWS_TrailATRMult       = 2.5;    // Trail distance = this x ATR

input group "=== TWS: Time (server hours) ==="
input int    TWS_BrokerGMTOffset    = 3;      // Info only: broker server GMT offset
input int    TWS_DeferStartH        = 13;     // No new entries from this server hour...
input int    TWS_DeferEndH          = 12;     // (kept for parity with the original set; release hour governs)
input int    TWS_DeferReleaseH      = 14;     // ...until this server hour
input int    TWS_FridayReduceHourSrv = 20;    // Friday hour to reduce exposure
input double TWS_WeekendReducePct   = 0.0;    // Percent of position to close then (0 = off)
input int    TWS_FridayNoEntryHourSrv = 23;   // No new entries after this hour on Friday

input group "=== TWS: Execution ==="
input double TWS_MaxChaseUSD        = 5.0;    // Skip entry if price ran further than this from the signal close
input double TWS_MaxSpreadPoints    = 350.0;  // Skip entries when spread (points) exceeds this
input int    TWS_DeviationPoints    = 50;     // Max slippage on execution
input long   TWS_Magic              = 50502;  // TWS magic number
input bool   TWS_EnableAlerts       = false;  // Pop-up alerts on entry/bank
input bool   TWS_ShowDashboard      = true;   // On-chart panel (standalone build)
input bool   TWS_DebugLogs          = false;  // Journal log of TWS decisions
//---TWS-INPUTS-END---

//---TWS-GLOBALS-BEGIN---
CTrade    twsTrade;
int       twsEmaTrendH = INVALID_HANDLE;
int       twsEmaFastH  = INVALID_HANDLE;
int       twsEmaSlowH  = INVALID_HANDLE;
int       twsAtrH      = INVALID_HANDLE;
datetime  g_twsLastBar     = 0;
int       g_twsDayStamp    = 0;
int       g_twsTradesToday = 0;
double    g_twsPeakEquity  = 0.0;
ulong     g_twsBanked[];    // tickets already banked by Consistency Mode
ulong     g_twsReduced[];   // tickets already Friday-reduced
//---TWS-GLOBALS-END---

// standalone core globals (the combined build gets these from its base EA)
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

//+------------------------------------------------------------------+
//| Short name of a timeframe ("H1", "M15", ...)                     |
//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf)
  {
   if(tf == PERIOD_CURRENT)
      tf = (ENUM_TIMEFRAMES)_Period;
   return StringSubstr(EnumToString(tf), 7);
  }

//---TWS-FUNCS-BEGIN---
//==================== TWS GOLD F1 MODULE ==========================//
bool TwsTicketIn(ulong &arr[], ulong t)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == t) return true;
   return false;
  }

void TwsMark(ulong &arr[], ulong t)
  {
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = t;
  }

double TwsInd(int handle, int shift)
  {
   if(handle == INVALID_HANDLE) return 0.0;
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return 0.0;
   return b[0];
  }

//+------------------------------------------------------------------+
//| TWS init / deinit (indicator handles, state)                     |
//+------------------------------------------------------------------+
bool TwsInit()
  {
   twsTrade.SetExpertMagicNumber(TWS_Magic);
   twsTrade.SetTypeFillingBySymbol(_Symbol);
   twsTrade.SetDeviationInPoints(TWS_DeviationPoints);

   twsEmaTrendH = iMA(_Symbol, TWS_TF, TWS_EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   twsEmaFastH  = iMA(_Symbol, TWS_TF, TWS_EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   twsEmaSlowH  = iMA(_Symbol, TWS_TF, TWS_EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   if(twsEmaTrendH == INVALID_HANDLE || twsEmaFastH == INVALID_HANDLE || twsEmaSlowH == INVALID_HANDLE)
     {
      Print("TWS: failed to create EMA handles");
      return false;
     }
   if(TWS_TrailMode > 0)
     {
      twsAtrH = iATR(_Symbol, TWS_TF, TWS_TrailATRPeriod);
      if(twsAtrH == INVALID_HANDLE)
        {
         Print("TWS: failed to create ATR handle");
         return false;
        }
     }

   g_twsPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   g_twsDayStamp = t.year * 10000 + t.mon * 100 + t.day;

   if(TWS_RiskPercent >= 2.0)
      PrintFormat("TWS WARNING: RiskPercent = %.1f%% per trade is aggressive. The original's equity "
                  "curve leans on this compounding; consider 0.5-1%% to see the raw edge.", TWS_RiskPercent);
   return true;
  }

void TwsDeinit()
  {
   if(twsEmaTrendH != INVALID_HANDLE) IndicatorRelease(twsEmaTrendH);
   if(twsEmaFastH  != INVALID_HANDLE) IndicatorRelease(twsEmaFastH);
   if(twsEmaSlowH  != INVALID_HANDLE) IndicatorRelease(twsEmaSlowH);
   if(twsAtrH      != INVALID_HANDLE) IndicatorRelease(twsAtrH);
  }

//+------------------------------------------------------------------+
//| Day rollover + peak-equity tracking                              |
//+------------------------------------------------------------------+
void TwsDayTick()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int stamp = t.year * 10000 + t.mon * 100 + t.day;
   if(stamp != g_twsDayStamp)
     {
      g_twsDayStamp = stamp;
      g_twsTradesToday = 0;
      ArrayResize(g_twsBanked, 0);
      ArrayResize(g_twsReduced, 0);
     }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_twsPeakEquity) g_twsPeakEquity = eq;
  }

//+------------------------------------------------------------------+
//| Entry-defer window (server hours), wrap-capable                  |
//+------------------------------------------------------------------+
bool TwsInDefer(int hour)
  {
   int s = TWS_DeferStartH, r = TWS_DeferReleaseH;
   if(s == r) return false;
   if(s < r)  return (hour >= s && hour < r);
   return (hour >= s || hour < r);
  }

//+------------------------------------------------------------------+
//| Count / fetch the open TWS position                              |
//+------------------------------------------------------------------+
int TwsCountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)    continue;
      if(PositionGetInteger(POSITION_MAGIC)  != TWS_Magic) continue;
      c++;
     }
   return c;
  }

bool TwsGetPosition(ulong &ticket, long &ptype, double &vol, double &entry, double &rr, bool &banked)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)    continue;
      if(PositionGetInteger(POSITION_MAGIC)  != TWS_Magic) continue;

      ticket = tk;
      ptype  = PositionGetInteger(POSITION_TYPE);
      vol    = PositionGetDouble(POSITION_VOLUME);
      entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp = PositionGetDouble(POSITION_TP);
      double riskDist = (ptype == POSITION_TYPE_BUY) ? (tp - entry) : (entry - tp);
      if(TWS_RewardRatio > 0) riskDist /= TWS_RewardRatio;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double prof = (ptype == POSITION_TYPE_BUY) ? (bid - entry) : (entry - ask);
      rr = (riskDist > 0) ? prof / riskDist : 0.0;
      banked = TwsTicketIn(g_twsBanked, tk);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Signal: pullback into the 20/50 zone + resumption, with trend    |
//|  +1 long, -1 short, 0 none                                       |
//+------------------------------------------------------------------+
int TwsSignal()
  {
   double eT = TwsInd(twsEmaTrendH, 1);
   double eF = TwsInd(twsEmaFastH, 1);
   double eS = TwsInd(twsEmaSlowH, 1);
   double o1 = iOpen(_Symbol,  TWS_TF, 1);
   double h1 = iHigh(_Symbol,  TWS_TF, 1);
   double l1 = iLow(_Symbol,   TWS_TF, 1);
   double c1 = iClose(_Symbol, TWS_TF, 1);
   if(eT <= 0 || eF <= 0 || eS <= 0 || o1 <= 0 || c1 <= 0) return 0;

   double slope = 0.0;
   if(TWS_UseTrendSlope)
     {
      double eTn = TwsInd(twsEmaTrendH, 1 + (int)MathMax(1, TWS_TrendSlopeBars));
      if(eTn <= 0) return 0;
      slope = eT - eTn;
     }

   // LONG: above 200 EMA, 20>50, wick pulled back to the 20 EMA, bullish close back above it
   if((!TWS_RequireTrendFilter || c1 > eT) && eF > eS &&
      l1 <= eF && c1 > eF && c1 > o1 &&
      (!TWS_UseTrendSlope || slope >= TWS_MinSlopeUSD))
      return 1;

   // SHORT: mirror
   if((!TWS_RequireTrendFilter || c1 < eT) && eF < eS &&
      h1 >= eF && c1 < eF && c1 < o1 &&
      (!TWS_UseTrendSlope || slope <= -TWS_MinSlopeUSD))
      return -1;

   return 0;
  }

//+------------------------------------------------------------------+
//| Risk-percent position sizing                                     |
//+------------------------------------------------------------------+
double TwsCalcLots(double riskDist)
  {
   double tickV = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickS = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickV <= 0 || tickS <= 0 || riskDist <= 0) return 0;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * TWS_RiskPercent / 100.0;
   double perLot    = riskDist / tickS * tickV;      // money risked per 1.0 lot
   if(perLot <= 0) return 0;

   double lots  = riskMoney / perLot;
   double lstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lstep <= 0) lstep = 0.01;

   lots = MathFloor(lots / lstep) * lstep;
   if(lots > TWS_MaxLotCap) lots = TWS_MaxLotCap;
   if(lmax > 0 && lots > lmax) lots = lmax;
   if(lots < lmin)
     {
      if(TWS_DebugLogs) Print("TWS: computed lot below broker minimum - using min lot (risk exceeds target)");
      lots = lmin;
     }
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Try to open a TWS trade (called once per closed TWS_TF bar)      |
//+------------------------------------------------------------------+
void TwsTryEnter()
  {
   if(TwsCountPositions() > 0) return;                 // one position at a time
   if(g_twsTradesToday >= TWS_MaxTradesPerDay) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(TWS_MaxTotalDrawdownPc < 100.0 && g_twsPeakEquity > 0)
     {
      double ddPc = (g_twsPeakEquity - eq) / g_twsPeakEquity * 100.0;
      if(ddPc >= TWS_MaxTotalDrawdownPc)
        {
         if(TWS_DebugLogs) Print("TWS: drawdown kill-switch active - no new entries");
         return;
        }
     }

   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   if(TwsInDefer(st.hour)) return;
   if(st.day_of_week == 5 && st.hour >= TWS_FridayNoEntryHourSrv) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) / g_point > TWS_MaxSpreadPoints) return;

   int dir = TwsSignal();
   if(dir == 0) return;

   double c1 = iClose(_Symbol, TWS_TF, 1);
   double px = (dir > 0) ? ask : bid;
   if(MathAbs(px - c1) > TWS_MaxChaseUSD)
     {
      if(TWS_DebugLogs) PrintFormat("TWS: not chasing (%.2f from signal close)", MathAbs(px - c1));
      return;
     }

   double buf = (ask - bid) + 2 * g_point;             // place the stop just beyond the swing
   double sl, riskDist;
   if(dir > 0)
     {
      int idx = iLowest(_Symbol, TWS_TF, MODE_LOW, TWS_SwingLookback, 1);
      if(idx < 0) return;
      sl = iLow(_Symbol, TWS_TF, idx) - buf;
      riskDist = px - sl;
     }
   else
     {
      int idx = iHighest(_Symbol, TWS_TF, MODE_HIGH, TWS_SwingLookback, 1);
      if(idx < 0) return;
      sl = iHigh(_Symbol, TWS_TF, idx) + buf;
      riskDist = sl - px;
     }
   double minStop = g_stopsLevelPts * g_point;
   if(riskDist <= MathMax(minStop, 10 * g_point))
     {
      if(TWS_DebugLogs) Print("TWS: swing stop invalid/too tight - skip");
      return;
     }

   double tp   = (dir > 0) ? px + TWS_RewardRatio * riskDist : px - TWS_RewardRatio * riskDist;
   double lots = TwsCalcLots(riskDist);
   if(lots <= 0) return;

   bool ok = (dir > 0)
             ? twsTrade.Buy(lots, _Symbol, px, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "TWS BUY")
             : twsTrade.Sell(lots, _Symbol, px, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "TWS SELL");
   if(ok)
     {
      g_twsTradesToday++;
      if(TWS_EnableAlerts)
         Alert(StringFormat("TWS %s %s %.2f lots (risk %.2f)", _Symbol, dir > 0 ? "BUY" : "SELL", lots, riskDist));
      if(TWS_DebugLogs)
         PrintFormat("TWS ENTRY %s lots=%.2f sl=%.2f tp=%.2f risk=%.2f",
                     dir > 0 ? "BUY" : "SELL", lots, sl, tp, riskDist);
     }
   else
      PrintFormat("TWS %s failed: %d %s", dir > 0 ? "Buy" : "Sell",
                  twsTrade.ResultRetcode(), twsTrade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Manage the open TWS position: banking, ATR trail, Friday reduce  |
//+------------------------------------------------------------------+
void TwsManage()
  {
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lstep <= 0) lstep = 0.01;

   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)    continue;
      if(PositionGetInteger(POSITION_MAGIC)  != TWS_Magic) continue;

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      // Original risk derived from the 3:1 target so trailing can't distort it
      double riskDist = (ptype == POSITION_TYPE_BUY) ? (curTP - entry) : (entry - curTP);
      if(TWS_RewardRatio > 0) riskDist /= TWS_RewardRatio;
      double prof = (ptype == POSITION_TYPE_BUY) ? (bid - entry) : (entry - ask);
      double rr   = (riskDist > 0) ? prof / riskDist : 0.0;

      // --- Consistency Mode: bank part of the position at +BankAtRR ---
      if(TWS_ConsistencyMode && riskDist > 0 && rr >= TWS_BankAtRR && !TwsTicketIn(g_twsBanked, ticket))
        {
         double closeVol = MathFloor(vol * TWS_BankPercent / 100.0 / lstep) * lstep;
         if(closeVol >= lmin && vol - closeVol >= lmin)
           {
            if(twsTrade.PositionClosePartial(ticket, NormalizeDouble(closeVol, 2)))
              {
               TwsMark(g_twsBanked, ticket);
               if(TWS_MoveSLToBEOnBank)
                 {
                  double be = (ptype == POSITION_TYPE_BUY) ? entry + (ask - bid) + g_point
                                                           : entry - (ask - bid) - g_point;
                  twsTrade.PositionModify(ticket, NormalizeDouble(be, g_digits), curTP);
                 }
               if(TWS_EnableAlerts)
                  Alert(StringFormat("TWS banked %.0f%% at +%.1fR", TWS_BankPercent, TWS_BankAtRR));
               if(TWS_DebugLogs)
                  PrintFormat("TWS BANK #%I64u: closed %.2f at rr %.2f", ticket, closeVol, rr);
              }
           }
         else
            TwsMark(g_twsBanked, ticket);   // cannot split further - stop retrying
        }

      // --- ATR trailing (TrailMode 1) ---
      if(TWS_TrailMode > 0 && twsAtrH != INVALID_HANDLE && riskDist > 0 && rr >= TWS_TrailActivateRR)
        {
         double a[];
         if(CopyBuffer(twsAtrH, 0, 1, 1, a) >= 1 && a[0] > 0)
           {
            if(ptype == POSITION_TYPE_BUY)
              {
               double newSL = NormalizeDouble(bid - TWS_TrailATRMult * a[0], g_digits);
               if(newSL > curSL && newSL < bid)
                  if(!twsTrade.PositionModify(ticket, newSL, curTP))
                     PrintFormat("TWS trail modify failed: %d %s",
                                 twsTrade.ResultRetcode(), twsTrade.ResultRetcodeDescription());
              }
            else
              {
               double newSL = NormalizeDouble(ask + TWS_TrailATRMult * a[0], g_digits);
               if((curSL <= 0 || newSL < curSL) && newSL > ask)
                  if(!twsTrade.PositionModify(ticket, newSL, curTP))
                     PrintFormat("TWS trail modify failed: %d %s",
                                 twsTrade.ResultRetcode(), twsTrade.ResultRetcodeDescription());
              }
           }
        }

      // --- Friday weekend risk reduction ---
      if(TWS_WeekendReducePct > 0 && st.day_of_week == 5 && st.hour >= TWS_FridayReduceHourSrv &&
         !TwsTicketIn(g_twsReduced, ticket))
        {
         double closeVol = MathFloor(vol * TWS_WeekendReducePct / 100.0 / lstep) * lstep;
         if(closeVol >= lmin && vol - closeVol >= lmin)
           {
            if(twsTrade.PositionClosePartial(ticket, NormalizeDouble(closeVol, 2)))
               TwsMark(g_twsReduced, ticket);
           }
         else
            TwsMark(g_twsReduced, ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| TWS engine tick driver                                           |
//+------------------------------------------------------------------+
void TwsOnTick()
  {
   TwsDayTick();
   TwsManage();

   datetime bt = iTime(_Symbol, TWS_TF, 0);
   if(bt == 0 || bt == g_twsLastBar) return;
   g_twsLastBar = bt;
   TwsTryEnter();
  }

//+------------------------------------------------------------------+
//| Two dashboard rows summarising the TWS engine                    |
//+------------------------------------------------------------------+
int TwsDashRows(int r)
  {
   color cText = clrSilver, cGood = clrLimeGreen, cBad = clrTomato;

   double eT = TwsInd(twsEmaTrendH, 1);
   double eF = TwsInd(twsEmaFastH, 1);
   double eS = TwsInd(twsEmaSlowH, 1);
   double c1 = iClose(_Symbol, TWS_TF, 1);
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);

   string trendTxt = (eT <= 0 || c1 <= 0) ? "..." : (c1 > eT ? "above200" : "below200");
   string stackTxt = (eF > eS) ? "20>50" : "20<50";
   string state    = TwsInDefer(st.hour) ? "  DEFER" : "";
   DashLabel(r++, StringFormat("TWS[%s] %s %s%s", TFName(TWS_TF), trendTxt, stackTxt, state),
             (eT > 0 && c1 > eT) ? cGood : cBad);

   ulong tk; long ptype; double vol, entry, rr; bool banked;
   if(TwsGetPosition(tk, ptype, vol, entry, rr, banked))
      DashLabel(r++, StringFormat("TWS %s %.2f @%.2f RR %+.1f%s",
                ptype == POSITION_TYPE_BUY ? "BUY" : "SELL", vol, entry, rr,
                banked ? " bkd" : ""), cText);
   else
      DashLabel(r++, StringFormat("TWS flat  today %d/%d", g_twsTradesToday, TWS_MaxTradesPerDay), cText);
   return r;
  }
//---TWS-FUNCS-END---

//====================== STANDALONE DASHBOARD ======================//
void DashPanel()
  {
   string obj = "DB_bg";
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 22);
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'16,20,28');
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, C'70,80,100');
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, 140);
  }

void DashLabel(int row, string text, color clr)
  {
   string obj = StringFormat("DB_r%02d", row);
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 14);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 30 + row * 16);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0,  obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0,  obj, OBJPROP_TEXT, (text == "") ? " " : text);
  }

void UpdateDash()
  {
   if(!TWS_ShowDashboard) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   color cText = clrSilver, cBad = clrTomato, cHead = clrGold;
   DashPanel();
   int r = 0;

   DashLabel(r++, "TWS Gold F1 (recon)  " + _Symbol, cHead);

   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   string defer = TwsInDefer(st.hour) ? "  DEFER" : "";
   DashLabel(r++, StringFormat("Server %s%s", TimeToString(TimeCurrent(), TIME_MINUTES), defer), cText);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int sp = (int)MathRound((ask - bid) / g_point);
   DashLabel(r++, StringFormat("Spread %d pts (max %.0f)  Risk %.1f%%", sp, TWS_MaxSpreadPoints, TWS_RiskPercent),
             (sp > TWS_MaxSpreadPoints) ? cBad : cText);

   r = TwsDashRows(r);

   DashLabel(r++, StringFormat("Bal %.2f  Eq %.2f  Peak %.2f",
             AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), g_twsPeakEquity), cText);

   ChartRedraw();
  }

//============================ EVENTS ==============================//
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   if(!TwsInit())
      return(INIT_FAILED);

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   TwsDeinit();
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
      ObjectsDeleteAll(0, "DB_");
  }

void OnTimer()
  {
   UpdateDash();
  }

void OnTick()
  {
   TwsOnTick();
   UpdateDash();
  }
//+------------------------------------------------------------------+
