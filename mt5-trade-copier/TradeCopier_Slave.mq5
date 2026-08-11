//+------------------------------------------------------------------+
//|                                           TradeCopier_Slave.mq5   |
//|   Free local trade copier - SLAVE side (runs on the REAL acct)    |
//|                                                                  |
//|   Reads the snapshot written by the Master EA and mirrors every  |
//|   position, multiplying the lot size (default x10, so a 0.01     |
//|   demo trade becomes 0.10 on the real account).                  |
//|                                                                  |
//|   - Opens positions the master has but the slave doesn't.        |
//|   - Closes positions the master has closed.                      |
//|   - Keeps SL/TP and volume in sync.                              |
//|                                                                  |
//|   100% free. No DLLs, no external services, no subscriptions.    |
//|                                                                  |
//|   IMPORTANT: use a HEDGING real account (each trade = its own    |
//|   position). Netting accounts merge same-symbol trades and this  |
//|   1:1 mapping will not work correctly.                           |
//+------------------------------------------------------------------+
#property copyright "Free Trade Copier"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- Inputs ---------------------------------------------------------
input string InpSignalFile     = "trade_copier_signals.csv"; // Shared file name (must match Master)
input double InpLotMultiplier  = 10.0;   // 0.01 x 10 = 0.10. Set your multiplier here
input double InpFixedLot       = 0.0;    // >0 = ignore multiplier, use this fixed lot for every copy
input string InpSymbolSuffix   = "";     // e.g. ".a" or ".pro" if the real broker adds a suffix (EURUSD.a)
input string InpSymbolPrefix   = "";     // e.g. "m" if the real broker uses a prefix (mEURUSD)
input long   InpSlaveMagic     = 990011; // Magic number stamped on copied trades (leave as-is)
input bool   InpCopySLTP       = true;   // Copy stop loss / take profit levels
input bool   InpEnableTrading  = true;   // Master OFF switch. false = read only, no trades
input int    InpMaxStaleSec    = 30;     // If the master file is older than this, stop OPENING new trades
input int    InpTimerMs        = 500;    // How often to read & reconcile (ms)
input int    InpDeviation      = 20;     // Max price slippage (points) for market orders
input bool   InpVerbose        = true;   // Print status to the Experts log

//--- Globals --------------------------------------------------------
CTrade   g_trade;

// Parsed master snapshot
ulong    m_ticket[];
string   m_symbol[];
int      m_type[];
double   m_volume[];
double   m_sl[];
double   m_tp[];
long     g_masterLogin  = 0;
long     g_masterTime   = 0;
int      g_masterCount  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpSlaveMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   EventSetMillisecondTimer((InpTimerMs < 100) ? 100 : InpTimerMs);
   if(InpVerbose)
      PrintFormat("[SLAVE] Started. Account #%I64d. Reading Common\\Files\\%s  Multiplier=%.2f",
                  AccountInfoInteger(ACCOUNT_LOGIN), InpSignalFile, InpLotMultiplier);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { EventKillTimer(); }

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!ReadSnapshot()) return;
   Reconcile();
}

//+------------------------------------------------------------------+
//| Map a master symbol to this broker's symbol name                 |
//+------------------------------------------------------------------+
string MapSymbol(const string masterSym)
{
   return InpSymbolPrefix + masterSym + InpSymbolSuffix;
}

//+------------------------------------------------------------------+
//| Read & parse the master snapshot file                            |
//+------------------------------------------------------------------+
bool ReadSnapshot()
{
   ArrayResize(m_ticket, 0);
   ArrayResize(m_symbol, 0);
   ArrayResize(m_type,   0);
   ArrayResize(m_volume, 0);
   ArrayResize(m_sl,     0);
   ArrayResize(m_tp,     0);
   g_masterCount = 0;

   int h = FileOpen(InpSignalFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      // File may briefly not exist during the master's atomic move; that's fine.
      return false;
   }

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) == 0) continue;

      string parts[];
      int n = StringSplit(line, ',', parts);
      if(n <= 0) continue;

      if(parts[0] == "HEARTBEAT" && n >= 3)
      {
         g_masterLogin = (long)StringToInteger(parts[1]);
         g_masterTime  = (long)StringToInteger(parts[2]);
      }
      else if(parts[0] == "POS" && n >= 8)
      {
         int idx = g_masterCount;
         ArrayResize(m_ticket, idx + 1);
         ArrayResize(m_symbol, idx + 1);
         ArrayResize(m_type,   idx + 1);
         ArrayResize(m_volume, idx + 1);
         ArrayResize(m_sl,     idx + 1);
         ArrayResize(m_tp,     idx + 1);

         m_ticket[idx] = (ulong)StringToInteger(parts[1]);
         m_symbol[idx] = parts[2];
         m_type[idx]   = (int)StringToInteger(parts[3]);
         m_volume[idx] = StringToDouble(parts[4]);
         m_sl[idx]     = StringToDouble(parts[6]);
         m_tp[idx]     = StringToDouble(parts[7]);
         g_masterCount++;
      }
   }
   FileClose(h);
   return true;
}

//+------------------------------------------------------------------+
//| Is the master snapshot fresh enough to open new trades?          |
//+------------------------------------------------------------------+
bool MasterIsFresh()
{
   long age = (long)TimeCurrent() - g_masterTime;
   return (age <= InpMaxStaleSec && age >= -InpMaxStaleSec);
}

//+------------------------------------------------------------------+
//| Find the master index for a given master ticket (-1 if gone)     |
//+------------------------------------------------------------------+
int FindMasterIndex(const ulong masterTicket)
{
   for(int i = 0; i < g_masterCount; i++)
      if(m_ticket[i] == masterTicket) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Parse the master ticket we stamped in a slave position's comment |
//| Comment format: "MC#<masterticket>"                              |
//+------------------------------------------------------------------+
ulong MasterTicketFromComment(const string comment)
{
   int p = StringFind(comment, "MC#");
   if(p < 0) return 0;
   string num = StringSubstr(comment, p + 3);
   return (ulong)StringToInteger(num);
}

//+------------------------------------------------------------------+
//| Normalize a desired volume to the symbol's min/max/step          |
//+------------------------------------------------------------------+
double NormalizeVolume(const string sym, double vol)
{
   double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP); // temp, reassigned below
   double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   vmax         = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   if(vstep <= 0) vstep = 0.01;
   vol = MathRound(vol / vstep) * vstep;
   if(vol < vmin) vol = vmin;
   if(vol > vmax) vol = vmax;
   // clean floating point noise
   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
//| Desired slave volume for a master volume                         |
//+------------------------------------------------------------------+
double DesiredVolume(const string slaveSym, double masterVol)
{
   double v = (InpFixedLot > 0.0) ? InpFixedLot : masterVol * InpLotMultiplier;
   return NormalizeVolume(slaveSym, v);
}

//+------------------------------------------------------------------+
//| Main reconcile loop                                              |
//+------------------------------------------------------------------+
void Reconcile()
{
   bool fresh = MasterIsFresh();

   //=== PASS 1: walk our own copied positions =======================
   // Close any whose master ticket is gone; sync SL/TP & volume for the rest.
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong sTicket = PositionGetTicket(i);
      if(sTicket == 0) continue;
      if(!PositionSelectByTicket(sTicket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic) continue;

      string sComment  = PositionGetString(POSITION_COMMENT);
      ulong  mTicket   = MasterTicketFromComment(sComment);
      if(mTicket == 0) continue; // not one of ours / no mapping

      int mIdx = FindMasterIndex(mTicket);

      if(mIdx < 0)
      {
         // Master closed it -> close the copy. (Closing is always allowed,
         // even if the feed is briefly stale, to protect the real account.)
         if(InpEnableTrading)
         {
            if(g_trade.PositionClose(sTicket))
               { if(InpVerbose) PrintFormat("[SLAVE] Closed copy #%I64u (master %I64u gone)", sTicket, mTicket); }
         }
         continue;
      }

      // Still open on master -> keep SL/TP and volume aligned.
      string slaveSym = PositionGetString(POSITION_SYMBOL);
      double sSL      = PositionGetDouble(POSITION_SL);
      double sTP      = PositionGetDouble(POSITION_TP);
      double sVol     = PositionGetDouble(POSITION_VOLUME);

      if(InpEnableTrading && InpCopySLTP)
      {
         double wantSL = m_sl[mIdx];
         double wantTP = m_tp[mIdx];
         if(MathAbs(sSL - wantSL) > _Point || MathAbs(sTP - wantTP) > _Point)
            g_trade.PositionModify(sTicket, wantSL, wantTP);
      }

      // Volume sync (handles master scaling out): only reduce here.
      if(InpEnableTrading)
      {
         double wantVol = DesiredVolume(slaveSym, m_volume[mIdx]);
         double vstep   = SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_STEP);
         if(vstep <= 0) vstep = 0.01;
         if(sVol - wantVol >= vstep - 1e-8 && wantVol >= SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_MIN))
         {
            double reduce = NormalizeVolume(slaveSym, sVol - wantVol);
            if(reduce > 0)
            {
               if(g_trade.PositionClosePartial(sTicket, reduce))
                  { if(InpVerbose) PrintFormat("[SLAVE] Reduced copy #%I64u by %.2f", sTicket, reduce); }
            }
         }
      }
   }

   //=== PASS 2: open master positions we don't have yet =============
   if(!InpEnableTrading || !fresh) return;

   for(int j = 0; j < g_masterCount; j++)
   {
      if(HaveCopyFor(m_ticket[j])) continue;

      string slaveSym = MapSymbol(m_symbol[j]);
      if(!SymbolSelect(slaveSym, true))
      {
         if(InpVerbose) PrintFormat("[SLAVE] Symbol '%s' not found on this broker - skipping master %I64u",
                                    slaveSym, m_ticket[j]);
         continue;
      }

      double vol = DesiredVolume(slaveSym, m_volume[j]);
      if(vol <= 0) continue;

      string comment = StringFormat("MC#%I64u", m_ticket[j]);
      double sl = InpCopySLTP ? m_sl[j] : 0.0;
      double tp = InpCopySLTP ? m_tp[j] : 0.0;

      g_trade.SetTypeFillingBySymbol(slaveSym);
      bool ok;
      if(m_type[j] == 0) // BUY
         ok = g_trade.Buy(vol, slaveSym, 0.0, sl, tp, comment);
      else               // SELL
         ok = g_trade.Sell(vol, slaveSym, 0.0, sl, tp, comment);

      if(InpVerbose)
      {
         if(ok) PrintFormat("[SLAVE] Opened %s %.2f %s copy of master %I64u",
                            (m_type[j]==0?"BUY":"SELL"), vol, slaveSym, m_ticket[j]);
         else   PrintFormat("[SLAVE] OPEN FAILED for master %I64u (%s): retcode=%d %s",
                            m_ticket[j], slaveSym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Do we already have a copy open for this master ticket?           |
//+------------------------------------------------------------------+
bool HaveCopyFor(const ulong masterTicket)
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic) continue;
      if(MasterTicketFromComment(PositionGetString(POSITION_COMMENT)) == masterTicket)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
