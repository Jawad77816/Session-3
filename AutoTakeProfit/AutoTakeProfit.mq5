//+------------------------------------------------------------------+
//|                                              AutoTakeProfit.mq5   |
//|      Automatically sets a Take Profit (and optional Stop Loss)    |
//|      on EVERY position you open manually, a fixed number of pips  |
//|      away from your entry price.                                  |
//|                                                                   |
//|      Example (default settings on Gold / XAUUSD):                 |
//|         You Buy  at 4000.00  ->  TP is set to 4001.00  (+10 pips) |
//|         You Sell at 4000.00  ->  TP is set to 3999.00  (-10 pips) |
//+------------------------------------------------------------------+
#property copyright "AutoTakeProfit"
#property link      ""
#property version   "1.00"
#property description "Auto-applies a Take Profit (and optional Stop Loss) to manual trades, a fixed number of pips from the entry price."

#include <Trade\Trade.mqh>

//--- Take Profit / Stop Loss ---------------------------------------
input group "=== Take Profit / Stop Loss ==="
input double InpTakeProfitPips = 10.0;   // Take Profit in pips (0 = do NOT set a TP)
input double InpStopLossPips   = 0.0;    // Stop Loss in pips   (0 = do NOT set a SL)
input int    InpPointsPerPip   = 0;      // Points per pip (0 = auto-detect; see notes below)

//--- Which trades to manage ----------------------------------------
input group "=== Which trades to manage ==="
input bool   InpApplyToBuy     = true;   // Manage Buy positions
input bool   InpApplyToSell    = true;   // Manage Sell positions
input long   InpMagicFilter    = -1;     // Only manage this magic number (-1 = all, includes manual trades)
input int    InpSymbolScope    = 0;      // Symbols: 0 = current chart only, 1 = ALL open symbols
input bool   InpOnlyIfNoTP     = true;   // Only add a TP when the position has none (recommended)

//--- Misc ----------------------------------------------------------
input group "=== Misc ==="
input bool   InpVerbose        = true;   // Print actions to the Experts / Journal log

//--- globals -------------------------------------------------------
CTrade   trade;
ulong    g_failed[];   // tickets we already failed on (avoids log spam)

//+------------------------------------------------------------------+
//| Return the price value of one "pip" for a given symbol.          |
//|                                                                  |
//|  - If InpPointsPerPip > 0, one pip = InpPointsPerPip * point.    |
//|  - Otherwise auto-detect:                                        |
//|      * Metals (XAU/XAG/Gold/Silver): pip = 0.10 in price, so     |
//|        10 pips = 1.00  ->  Buy 4000 gives TP 4001.               |
//|      * 3- or 5-digit FX pairs: pip = 10 points (a normal pip).   |
//|      * everything else:        pip = 1 point.                    |
//+------------------------------------------------------------------+
double PipSize(const string sym)
{
   const int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   const double point  = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(InpPointsPerPip > 0)
      return InpPointsPerPip * point;

   string u = sym;
   StringToUpper(u);
   const bool metal = (StringFind(u, "XAU")    >= 0 || StringFind(u, "GOLD")   >= 0 ||
                       StringFind(u, "XAG")    >= 0 || StringFind(u, "SILVER") >= 0);

   if(metal)
   {
      // Target: one pip = 0.10 in price for gold-style quotes.
      // 2-digit quote (4000.00): 10 * 0.01  = 0.10
      // 3-digit quote (4000.000): 100 * 0.001 = 0.10
      return (digits >= 3) ? 100 * point : 10 * point;
   }

   if(digits == 3 || digits == 5)
      return 10 * point;

   return point;
}

//+------------------------------------------------------------------+
//| Small helper: has this ticket already failed once?               |
//+------------------------------------------------------------------+
bool AlreadyFailed(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_failed); i++)
      if(g_failed[i] == ticket)
         return true;
   return false;
}

void MarkFailed(const ulong ticket)
{
   const int n = ArraySize(g_failed);
   ArrayResize(g_failed, n + 1);
   g_failed[n] = ticket;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   EventSetTimer(1);   // safety-net sweep once per second

   if(InpTakeProfitPips <= 0 && InpStopLossPips <= 0)
      Print("AutoTakeProfit: WARNING - both Take Profit and Stop Loss are 0, nothing will be set.");

   // Show a concrete example on the current symbol so you can verify the pip maths.
   const int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double pip    = PipSize(_Symbol);
   const double tpDist = InpTakeProfitPips * pip;

   PrintFormat("AutoTakeProfit started on %s | 1 pip = %s | TP = %.1f pips = %s in price",
               _Symbol,
               DoubleToString(pip, digits),
               InpTakeProfitPips,
               DoubleToString(tpDist, digits));

   if(InpTakeProfitPips > 0)
      PrintFormat("Example: a BUY at %s would get TP at %s (a SELL would get TP at %s)",
                  DoubleToString(4000.0, digits),
                  DoubleToString(4000.0 + tpDist, digits),
                  DoubleToString(4000.0 - tpDist, digits));

   // Run once immediately in case positions are already open.
   ManageAllPositions();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Triggers - react fast to new trades, plus safety-net sweeps      |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageAllPositions();
}

void OnTimer()
{
   ManageAllPositions();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   // A new deal was added (e.g. your manual trade just filled) -> act now.
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      ManageAllPositions();
}

//+------------------------------------------------------------------+
//| Core: loop every open position and set TP/SL where needed        |
//+------------------------------------------------------------------+
void ManageAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      const string sym = PositionGetString(POSITION_SYMBOL);

      // Symbol scope
      if(InpSymbolScope == 0 && sym != _Symbol)
         continue;

      // Magic filter (manual trades have magic == 0; -1 means "all")
      const long magic = PositionGetInteger(POSITION_MAGIC);
      if(InpMagicFilter >= 0 && magic != InpMagicFilter)
         continue;

      const long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY  && !InpApplyToBuy)   continue;
      if(type == POSITION_TYPE_SELL && !InpApplyToSell)  continue;

      const double curTP = PositionGetDouble(POSITION_TP);
      const double curSL = PositionGetDouble(POSITION_SL);

      // If it already has a TP and we only fill in missing ones, skip.
      if(InpOnlyIfNoTP && curTP != 0.0)
         continue;

      if(AlreadyFailed(ticket))
         continue;

      ApplyTpSl(ticket, sym, type, curSL, curTP);
   }
}

//+------------------------------------------------------------------+
//| Compute and apply the desired TP/SL for one position             |
//+------------------------------------------------------------------+
void ApplyTpSl(const ulong  ticket,
               const string sym,
               const long   type,
               const double curSL,
               const double curTP)
{
   const int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   const double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   const double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   const double pip    = PipSize(sym);

   // Start from what is already there so we never wipe an existing SL/TP.
   double newTP = curTP;
   double newSL = curSL;

   if(InpTakeProfitPips > 0)
   {
      const double dist = InpTakeProfitPips * pip;
      newTP = (type == POSITION_TYPE_BUY) ? open + dist : open - dist;
      newTP = NormalizeDouble(newTP, digits);
   }

   if(InpStopLossPips > 0)
   {
      const double dist = InpStopLossPips * pip;
      newSL = (type == POSITION_TYPE_BUY) ? open - dist : open + dist;
      newSL = NormalizeDouble(newSL, digits);
   }

   // Anything actually changing?
   const double tol = point / 2.0;
   const bool tpChanged = (InpTakeProfitPips > 0 && MathAbs(newTP - curTP) > tol);
   const bool slChanged = (InpStopLossPips   > 0 && MathAbs(newSL - curSL) > tol);
   if(!tpChanged && !slChanged)
      return;

   // Respect the broker's minimum stop distance from the CURRENT price.
   const double stopsLvl = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   const double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   const double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   if(InpTakeProfitPips > 0)
   {
      const bool tpTooClose =
         (type == POSITION_TYPE_BUY  && newTP <= bid + stopsLvl) ||
         (type == POSITION_TYPE_SELL && newTP >= ask - stopsLvl);
      if(tpTooClose)
      {
         if(InpVerbose)
            PrintFormat("AutoTakeProfit: skip #%I64u (%s) - TP %s too close to price (min stop %s). Set it manually.",
                        ticket, sym, DoubleToString(newTP, digits), DoubleToString(stopsLvl, digits));
         MarkFailed(ticket);
         return;
      }
   }

   if(InpStopLossPips > 0)
   {
      const bool slTooClose =
         (type == POSITION_TYPE_BUY  && newSL >= bid - stopsLvl) ||
         (type == POSITION_TYPE_SELL && newSL <= ask + stopsLvl);
      if(slTooClose)
      {
         if(InpVerbose)
            PrintFormat("AutoTakeProfit: skip #%I64u (%s) - SL %s too close to price (min stop %s).",
                        ticket, sym, DoubleToString(newSL, digits), DoubleToString(stopsLvl, digits));
         MarkFailed(ticket);
         return;
      }
   }

   if(trade.PositionModify(ticket, newSL, newTP))
   {
      if(InpVerbose)
         PrintFormat("AutoTakeProfit: #%I64u (%s) %s @ %s  ->  SL %s / TP %s",
                     ticket, sym, (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     DoubleToString(open, digits),
                     DoubleToString(newSL, digits),
                     DoubleToString(newTP, digits));
   }
   else
   {
      PrintFormat("AutoTakeProfit: FAILED to modify #%I64u (%s). retcode=%u (%s)",
                  ticket, sym, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      MarkFailed(ticket);   // don't hammer the same failing ticket every tick
   }
}
//+------------------------------------------------------------------+
