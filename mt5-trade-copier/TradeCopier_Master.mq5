//+------------------------------------------------------------------+
//|                                          TradeCopier_Master.mq5   |
//|   Free local trade copier - MASTER side (runs on the DEMO acct)   |
//|                                                                  |
//|   Writes a snapshot of all open positions to a shared file in    |
//|   the MT5 "Common\Files" folder. The Slave EA (on the real       |
//|   account) reads that file and mirrors the trades.               |
//|                                                                  |
//|   100% free. No DLLs, no external services, no subscriptions.    |
//+------------------------------------------------------------------+
#property copyright "Free Trade Copier"
#property version   "1.00"
#property strict

//--- Inputs ---------------------------------------------------------
input string  InpSignalFile   = "trade_copier_signals.csv"; // Shared file name (must match Slave)
input int     InpTimerMs      = 400;    // How often to write the snapshot (ms)
input long    InpMagicFilter  = 0;      // 0 = copy ALL trades. Otherwise only this magic number
input bool    InpVerbose      = true;   // Print status to the Experts log

//--- Globals --------------------------------------------------------
string g_tmpFile;

//+------------------------------------------------------------------+
int OnInit()
{
   g_tmpFile = InpSignalFile + ".tmp";
   EventSetMillisecondTimer((InpTimerMs < 100) ? 100 : InpTimerMs);
   if(InpVerbose)
      PrintFormat("[MASTER] Started. Account #%I64d. Writing to Common\\Files\\%s",
                  AccountInfoInteger(ACCOUNT_LOGIN), InpSignalFile);
   WriteSnapshot(); // write immediately so the slave sees us right away
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   WriteSnapshot();
}

//+------------------------------------------------------------------+
//| Build the snapshot text and write it atomically                  |
//+------------------------------------------------------------------+
void WriteSnapshot()
{
   //--- Line 1 is metadata: HEARTBEAT,<login>,<server-time-epoch>
   string text = StringFormat("HEARTBEAT,%I64d,%I64d\n",
                              AccountInfoInteger(ACCOUNT_LOGIN),
                              (long)TimeCurrent());

   //--- One line per open position:
   //    POS,<ticket>,<symbol>,<type 0=buy/1=sell>,<volume>,<openprice>,<sl>,<tp>
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(InpMagicFilter != 0 && magic != InpMagicFilter) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      long   type  = PositionGetInteger(POSITION_TYPE); // 0=BUY, 1=SELL
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      text += StringFormat("POS,%I64u,%s,%d,%.2f,%.5f,%.5f,%.5f\n",
                           ticket, sym, (int)type, vol, price, sl, tp);
   }

   //--- Write to a temp file first, then move over the real file so
   //    the slave never reads a half-written file.
   int h = FileOpen(g_tmpFile,
                    FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      if(InpVerbose) PrintFormat("[MASTER] FileOpen failed: %d", GetLastError());
      return;
   }
   FileWriteString(h, text);
   FileClose(h);

   if(!FileMove(g_tmpFile, FILE_COMMON, InpSignalFile, FILE_COMMON | FILE_REWRITE))
   {
      if(InpVerbose) PrintFormat("[MASTER] FileMove failed: %d", GetLastError());
   }
}
//+------------------------------------------------------------------+
