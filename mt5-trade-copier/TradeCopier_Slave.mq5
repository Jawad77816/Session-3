//+------------------------------------------------------------------+
//|                                           TradeCopier_Slave.mq5   |
//|   Free local trade copier - SLAVE side (runs on the REAL acct)    |
//|                                                                  |
//|   Reads the snapshot written by the Master EA and mirrors every  |
//|   position.                                                      |
//|                                                                  |
//|   STOPS/TARGETS:                                                 |
//|     * Stop Loss  -> copied 1:1 (same as master).                 |
//|     * Take Profit-> HALF of the master's target distance by      |
//|       default (InpTpFraction = 0.5). Anchored to the master's    |
//|       own entry->TP distance, so it is broker-price independent. |
//|                                                                  |
//|   You control the copy lot in TWO ways:                          |
//|                                                                  |
//|     * MANUAL FIXED lot  -> every copy uses a lot you set, and    |
//|       you can change it LIVE with on-chart + / - buttons.        |
//|       (0.01 demo trade -> 0.10, or 0.20, or whatever you pick.)  |
//|                                                                  |
//|     * MULTIPLIER        -> copy lot = demo lot x multiplier.     |
//|                                                                  |
//|   The chosen lot is saved and survives an EA/terminal restart.   |
//|                                                                  |
//|   100% free. No DLLs, no external services, no subscriptions.    |
//|                                                                  |
//|   IMPORTANT: use a HEDGING real account (each trade = its own    |
//|   position). Netting accounts merge same-symbol trades and this  |
//|   1:1 mapping will not work correctly.                           |
//+------------------------------------------------------------------+
#property copyright "Free Trade Copier"
#property version   "1.20"
#property strict

#include <Trade/Trade.mqh>

//--- Lot sizing mode ------------------------------------------------
enum ENUM_LOT_MODE
{
   LOT_MANUAL_FIXED = 0,  // Manual fixed lot (adjust live with the buttons)
   LOT_MULTIPLIER   = 1   // Demo lot x multiplier
};

//--- Inputs ---------------------------------------------------------
input string        InpSignalFile    = "trade_copier_signals.csv"; // Shared file name (must match Master)
input ENUM_LOT_MODE InpLotMode       = LOT_MANUAL_FIXED; // Lot mode
input double        InpManualLot     = 0.10;   // MANUAL mode: starting lot (change live with buttons)
input double        InpLotStepSmall  = 0.01;   // Small +/- button step
input double        InpLotStepBig    = 0.10;   // Big +/- button step
input double        InpMultiplier    = 10.0;   // MULTIPLIER mode: demo lot x this (0.01 x 10 = 0.10)
input string        InpSymbolSuffix  = "";     // Broker suffix, e.g. ".a" (EURUSD.a)
input string        InpSymbolPrefix  = "";     // Broker prefix, e.g. "m"  (mEURUSD)
input long          InpSlaveMagic    = 990011; // Magic number stamped on copied trades
input bool          InpCopySLTP      = true;   // Copy stop loss / take profit levels
input double        InpTpFraction    = 0.5;    // TP distance vs master (0.5 = half). SL is always copied 1:1
input bool          InpEnableTrading = true;   // Master OFF switch. false = read only, no trades
input int           InpMaxStaleSec   = 30;     // If master file older than this, stop OPENING new trades
input int           InpTimerMs       = 500;    // How often to read & reconcile (ms)
input int           InpDeviation     = 20;     // Max price slippage (points) for market orders
input bool          InpShowPanel     = true;   // Show the on-chart lot control panel
input bool          InpVerbose       = true;   // Print status to the Experts log

//--- Globals --------------------------------------------------------
CTrade   g_trade;
double   g_manualLot = 0.10;   // live-adjustable lot (MANUAL mode)
string   g_gvName;             // GlobalVariable name to persist the lot

// Parsed master snapshot
ulong    m_ticket[];
string   m_symbol[];
int      m_type[];
double   m_volume[];
double   m_open[];
double   m_sl[];
double   m_tp[];
long     g_masterLogin  = 0;
long     g_masterTime   = 0;
int      g_masterCount  = 0;

//--- Panel object names ---------------------------------------------
#define PNL   "TCpanel_"
string   BTN_MM, BTN_M, BTN_P, BTN_PP, LBL_VAL, LBL_TTL;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpSlaveMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   //--- restore the last-used manual lot (survives restarts)
   g_gvName = "TC_LOT_" + IntegerToString(InpSlaveMagic);
   if(GlobalVariableCheck(g_gvName))
      g_manualLot = GlobalVariableGet(g_gvName);
   else
      g_manualLot = InpManualLot;
   g_manualLot = CleanLot(g_manualLot);

   if(InpShowPanel && InpLotMode == LOT_MANUAL_FIXED)
      CreatePanel();

   EventSetMillisecondTimer((InpTimerMs < 100) ? 100 : InpTimerMs);

   if(InpVerbose)
      PrintFormat("[SLAVE] Started. Account #%I64d. Mode=%s  Lot=%.2f  Reading Common\\Files\\%s",
                  AccountInfoInteger(ACCOUNT_LOGIN),
                  (InpLotMode==LOT_MANUAL_FIXED ? "MANUAL" : "MULTIPLIER"),
                  (InpLotMode==LOT_MANUAL_FIXED ? g_manualLot : InpMultiplier),
                  InpSignalFile);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PNL);
   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!ReadSnapshot()) return;
   Reconcile();
}

//+------------------------------------------------------------------+
//| On-chart button clicks -> change the live manual lot             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == BTN_MM)      g_manualLot -= InpLotStepBig;
   else if(sparam == BTN_M)  g_manualLot -= InpLotStepSmall;
   else if(sparam == BTN_P)  g_manualLot += InpLotStepSmall;
   else if(sparam == BTN_PP) g_manualLot += InpLotStepBig;
   else return;

   g_manualLot = CleanLot(g_manualLot);
   GlobalVariableSet(g_gvName, g_manualLot);   // persist
   UpdatePanelValue();

   // un-press the button
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();

   if(InpVerbose) PrintFormat("[SLAVE] Copy lot set to %.2f (applies to NEW copies)", g_manualLot);
}

//+------------------------------------------------------------------+
//| Keep a lot sane: >= 0.01, rounded to 2 dp                        |
//+------------------------------------------------------------------+
double CleanLot(double v)
{
   if(v < 0.01) v = 0.01;
   return NormalizeDouble(v, 2);
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
   ArrayResize(m_open,   0);
   ArrayResize(m_sl,     0);
   ArrayResize(m_tp,     0);
   g_masterCount = 0;

   int h = FileOpen(InpSignalFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return false; // file may briefly not exist during the master's atomic move

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
         ArrayResize(m_open,   idx + 1);
         ArrayResize(m_sl,     idx + 1);
         ArrayResize(m_tp,     idx + 1);

         m_ticket[idx] = (ulong)StringToInteger(parts[1]);
         m_symbol[idx] = parts[2];
         m_type[idx]   = (int)StringToInteger(parts[3]);
         m_volume[idx] = StringToDouble(parts[4]);
         m_open[idx]   = StringToDouble(parts[5]);
         m_sl[idx]     = StringToDouble(parts[6]);
         m_tp[idx]     = StringToDouble(parts[7]);
         g_masterCount++;
      }
   }
   FileClose(h);
   return true;
}

//+------------------------------------------------------------------+
bool MasterIsFresh()
{
   long age = (long)TimeCurrent() - g_masterTime;
   return (age <= InpMaxStaleSec && age >= -InpMaxStaleSec);
}

//+------------------------------------------------------------------+
int FindMasterIndex(const ulong masterTicket)
{
   for(int i = 0; i < g_masterCount; i++)
      if(m_ticket[i] == masterTicket) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Master ticket we stamped in a copy's comment ("MC#<ticket>")     |
//+------------------------------------------------------------------+
ulong MasterTicketFromComment(const string comment)
{
   int p = StringFind(comment, "MC#");
   if(p < 0) return 0;
   return (ulong)StringToInteger(StringSubstr(comment, p + 3));
}

//+------------------------------------------------------------------+
//| Normalize a desired volume to the symbol's min/max/step          |
//+------------------------------------------------------------------+
double NormalizeVolume(const string sym, double vol)
{
   double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;
   vol = MathRound(vol / vstep) * vstep;
   if(vol < vmin) vol = vmin;
   if(vol > vmax) vol = vmax;
   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
//| Slave take-profit = a fraction of the master's TP distance.      |
//| Anchored to the master's own entry -> TP, so it does not depend  |
//| on the real broker's price. Returns 0 (no TP) if master has none.|
//+------------------------------------------------------------------+
double ComputeSlaveTP(const string sym, double masterOpen, double masterTP)
{
   if(masterTP <= 0.0 || masterOpen <= 0.0) return 0.0; // master has no TP
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double tp = masterOpen + (masterTP - masterOpen) * InpTpFraction;
   return NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Desired slave volume for a given master volume                   |
//+------------------------------------------------------------------+
double DesiredVolume(const string slaveSym, double masterVol)
{
   double v = (InpLotMode == LOT_MANUAL_FIXED) ? g_manualLot
                                               : masterVol * InpMultiplier;
   return NormalizeVolume(slaveSym, v);
}

//+------------------------------------------------------------------+
//| Main reconcile loop                                              |
//+------------------------------------------------------------------+
void Reconcile()
{
   bool fresh = MasterIsFresh();

   //=== PASS 1: our own copies -> close if master gone, sync others =
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong sTicket = PositionGetTicket(i);
      if(sTicket == 0) continue;
      if(!PositionSelectByTicket(sTicket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpSlaveMagic) continue;

      ulong mTicket = MasterTicketFromComment(PositionGetString(POSITION_COMMENT));
      if(mTicket == 0) continue;

      int mIdx = FindMasterIndex(mTicket);

      if(mIdx < 0)
      {
         // Master closed it -> close the copy (always allowed, even if stale).
         if(InpEnableTrading && g_trade.PositionClose(sTicket) && InpVerbose)
            PrintFormat("[SLAVE] Closed copy #%I64u (master %I64u gone)", sTicket, mTicket);
         continue;
      }

      string slaveSym = PositionGetString(POSITION_SYMBOL);

      if(InpEnableTrading && InpCopySLTP)
      {
         double wantSL = m_sl[mIdx];                                        // SL copied 1:1
         double wantTP = ComputeSlaveTP(slaveSym, m_open[mIdx], m_tp[mIdx]); // TP = fraction of master
         if(MathAbs(PositionGetDouble(POSITION_SL) - wantSL) > _Point ||
            MathAbs(PositionGetDouble(POSITION_TP) - wantTP) > _Point)
            g_trade.PositionModify(sTicket, wantSL, wantTP);
      }

      // Volume sync only makes sense in MULTIPLIER mode (master scaling out).
      // In MANUAL mode the copy lot is a fixed number you chose, so we leave it.
      if(InpEnableTrading && InpLotMode == LOT_MULTIPLIER)
      {
         double sVol    = PositionGetDouble(POSITION_VOLUME);
         double wantVol = DesiredVolume(slaveSym, m_volume[mIdx]);
         double vstep   = SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_STEP);
         if(vstep <= 0) vstep = 0.01;
         if(sVol - wantVol >= vstep - 1e-8 &&
            wantVol >= SymbolInfoDouble(slaveSym, SYMBOL_VOLUME_MIN))
         {
            double reduce = NormalizeVolume(slaveSym, sVol - wantVol);
            if(reduce > 0 && g_trade.PositionClosePartial(sTicket, reduce) && InpVerbose)
               PrintFormat("[SLAVE] Reduced copy #%I64u by %.2f", sTicket, reduce);
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
         if(InpVerbose) PrintFormat("[SLAVE] Symbol '%s' not found - skipping master %I64u",
                                    slaveSym, m_ticket[j]);
         continue;
      }

      double vol = DesiredVolume(slaveSym, m_volume[j]);
      if(vol <= 0) continue;

      string comment = StringFormat("MC#%I64u", m_ticket[j]);
      double sl = InpCopySLTP ? m_sl[j] : 0.0;                                 // SL copied 1:1
      double tp = InpCopySLTP ? ComputeSlaveTP(slaveSym, m_open[j], m_tp[j])   // TP = fraction of master
                              : 0.0;

      g_trade.SetTypeFillingBySymbol(slaveSym);
      bool ok = (m_type[j] == 0) ? g_trade.Buy(vol, slaveSym, 0.0, sl, tp, comment)
                                 : g_trade.Sell(vol, slaveSym, 0.0, sl, tp, comment);

      if(InpVerbose)
      {
         if(ok) PrintFormat("[SLAVE] Opened %s %.2f %s copy of master %I64u",
                            (m_type[j]==0?"BUY":"SELL"), vol, slaveSym, m_ticket[j]);
         else   PrintFormat("[SLAVE] OPEN FAILED master %I64u (%s): retcode=%d %s",
                            m_ticket[j], slaveSym, g_trade.ResultRetcode(),
                            g_trade.ResultRetcodeDescription());
      }
   }
}

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
//| On-chart lot control panel                                       |
//+------------------------------------------------------------------+
void CreatePanel()
{
   BTN_MM  = PNL + "mm";
   BTN_M   = PNL + "m";
   BTN_P   = PNL + "p";
   BTN_PP  = PNL + "pp";
   LBL_VAL = PNL + "val";
   LBL_TTL = PNL + "ttl";

   int x = 10, y = 24, h = 26, gap = 4;

   MakeLabel(LBL_TTL, x, y - 18, "COPY LOT (real account)", clrGainsboro, 9);

   MakeButton(BTN_MM, x,               y, 46, h, "-"+DoubleToString(InpLotStepBig,2),   clrFireBrick);
   MakeButton(BTN_M,  x+46+gap,        y, 40, h, "-"+DoubleToString(InpLotStepSmall,2), clrIndianRed);
   MakeLabel (LBL_VAL,x+46+gap+40+gap+6, y+4, DoubleToString(g_manualLot,2), clrWhite, 14);
   MakeButton(BTN_P,  x+46+gap+40+gap+70,        y, 40, h, "+"+DoubleToString(InpLotStepSmall,2), clrForestGreen);
   MakeButton(BTN_PP, x+46+gap+40+gap+70+40+gap, y, 46, h, "+"+DoubleToString(InpLotStepBig,2),   clrGreen);

   ChartRedraw();
}

//+------------------------------------------------------------------+
void UpdatePanelValue()
{
   if(ObjectFind(0, LBL_VAL) >= 0)
      ObjectSetString(0, LBL_VAL, OBJPROP_TEXT, DoubleToString(g_manualLot, 2));
}

//+------------------------------------------------------------------+
void MakeButton(string name, int x, int y, int w, int h, string text, color bg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void MakeLabel(string name, int x, int y, string text, color clr, int size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetString (0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+
