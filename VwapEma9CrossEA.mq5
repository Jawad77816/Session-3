//+------------------------------------------------------------------+
//|                                            VwapEma9CrossEA.mq5    |
//|      VWAP + EMA9 "crisscross" scalping EA (MetaTrader 5)          |
//|      Rebuilt from a price-action video lesson.                   |
//|                                                                  |
//|  Rules taught in the video (written on-screen):                  |
//|    * Indicators: EMA 9  +  session VWAP.                          |
//|    * SIGNAL on the 3-minute timeframe:                            |
//|         - EMA9 crosses ABOVE VWAP  -> bullish (calls / BUY)       |
//|         - EMA9 crosses UNDER VWAP  -> bearish (puts  / SELL)      |
//|    * ENTRY: switch to the 1-minute timeframe and take the candle  |
//|      that WICKS the EMA9 or the VWAP (a rejection wick in the      |
//|      bias direction).                                             |
//|    * Stop loss in the video is -25% of the option premium; for a  |
//|      price instrument this EA uses a price stop (wick / ATR /      |
//|      fixed), and a fixed take-profit at an adjustable R:R.        |
//|         >>> Take-profit defaults to 1:3 (InpRR = 3.0). <<<        |
//|                                                                  |
//|  MT5 has no built-in VWAP, so it is computed here (session        |
//|  anchored, typical price * tick volume).                          |
//|                                                                  |
//|  This is an EXPERT ADVISOR - it opens/closes real trades.        |
//|  Attach it to the ENTRY-timeframe chart (M1). Test on DEMO first. |
//+------------------------------------------------------------------+
#property copyright "VWAP + EMA9 Cross EA"
#property version   "1.00"
#property description "VWAP + EMA9 crisscross scalper. 3M cross sets bias, 1M wick-rejection enters. Fixed R:R TP, default 1:3 (adjustable)."

#include <Trade/Trade.mqh>
CTrade trade;

//--- enums
enum ENUM_SLMODE
  {
   SL_WICK  = 0,   // Entry-candle wick
   SL_ATR   = 1,   // ATR multiple
   SL_FIXED = 2    // Fixed points
  };

//--- inputs : timeframes / indicators -----------------------------------------
input group                "=== Timeframes & indicators ==="
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M3;      // Signal timeframe (the cross)
input ENUM_TIMEFRAMES InpEntryTF  = PERIOD_M1;      // Entry timeframe (the wick)
input int             InpEmaPeriod= 9;              // EMA period
input ENUM_APPLIED_PRICE InpMaPrice = PRICE_CLOSE;  // EMA applied price
input int             InpVWAPHour = 0;              // VWAP session anchor hour (server time)
input int             InpVWAPMin  = 0;              // VWAP session anchor minute

//--- inputs : entry -----------------------------------------------------------
input group                "=== Entry ==="
input bool   InpTradeLong        = true;   // Allow long (calls)
input bool   InpTradeShort       = true;   // Allow short (puts)
input int    InpMaxBarsSinceCross= 10;     // Enter only within N signal-bars of the cross (0=off)
input int    InpWickTolPts       = 20;     // Wick tolerance to the level (points)
input bool   InpRequireClose     = true;   // Require close back beyond the wicked level (rejection)
input bool   InpCloseOnOpposite  = true;   // Close a trade when the bias flips
input bool   InpOneTradeAtATime  = true;   // Only one position (this symbol+magic)

//--- inputs : risk / reward ---------------------------------------------------
input group                "=== Risk / Reward ==="
input double InpRR          = 3.0;    // Take-Profit R:R  (1 : x)   << default 1:3
input ENUM_SLMODE InpSLMode = SL_WICK;// Stop-loss method
input double InpATRmult     = 1.5;    // ATR multiple            [SL_ATR]
input int    InpATRperiod   = 14;     // ATR period              [SL_ATR]
input int    InpFixedSLPts  = 150;    // Fixed stop (points)     [SL_FIXED]
input int    InpSLBufferPts = 10;     // Extra stop buffer (points)

//--- inputs : money management ------------------------------------------------
input group                "=== Money management ==="
input bool   InpUseRiskPct  = false;  // Size by % risk (else fixed lots)
input double InpRiskPct      = 1.0;   // Risk per trade (% of balance)
input double InpFixedLots    = 0.10;  // Fixed lot size

//--- inputs : misc ------------------------------------------------------------
input group                "=== Misc ==="
input long   InpMagic        = 770077; // Magic number
input int    InpMaxSpreadPts = 60;     // Max spread to enter (points, 0=off)
input int    InpSlippagePts  = 20;     // Max slippage (points)
input string InpComment      = "VWAP-EMA9";

//--- handles / state ----------------------------------------------------------
int      hEmaSig, hEmaEnt, hATR;
datetime g_lastEntryBar = 0;
datetime g_lastSigBar   = 0;
int      g_crossDir     = 0;      // +1 bull, -1 bear, 0 none
datetime g_crossTime    = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   hEmaSig = iMA(_Symbol, InpSignalTF, InpEmaPeriod, 0, MODE_EMA, InpMaPrice);
   hEmaEnt = iMA(_Symbol, InpEntryTF,  InpEmaPeriod, 0, MODE_EMA, InpMaPrice);
   hATR    = iATR(_Symbol, InpEntryTF, InpATRperiod);
   if(hEmaSig==INVALID_HANDLE || hEmaEnt==INVALID_HANDLE || hATR==INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   long fill = (long)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fill & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEmaSig);
   IndicatorRelease(hEmaEnt);
   IndicatorRelease(hATR);
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool EmaVal(const int handle, const int shift, double &out)
  {
   double b[]; ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return(false);
   out = b[0];
   return(true);
  }
// session anchor time for a given bar time (most recent anchor <= t)
datetime AnchorFor(const datetime t)
  {
   MqlDateTime s; TimeToStruct(t, s);
   int barSec   = s.hour*3600 + s.min*60 + s.sec;
   datetime midnight = t - barSec;
   datetime anchor   = midnight + (InpVWAPHour*60 + InpVWAPMin)*60;
   if(t < anchor) anchor -= 86400;   // belongs to the previous session
   return(anchor);
  }
// session-anchored VWAP on timeframe tf at the given bar shift
double VWAP(const ENUM_TIMEFRAMES tf, const int shift)
  {
   datetime anchor = AnchorFor(iTime(_Symbol, tf, shift));
   int maxScan = 5000, count = 0;
   for(int j = shift; j < shift + maxScan; j++)
     {
      datetime tj = iTime(_Symbol, tf, j);
      if(tj == 0 || tj < anchor) break;
      count++;
     }
   if(count <= 0) return(iClose(_Symbol, tf, shift));

   double H[], L[], C[]; long V[];
   ArraySetAsSeries(H, true); ArraySetAsSeries(L, true);
   ArraySetAsSeries(C, true); ArraySetAsSeries(V, true);
   if(CopyHigh(_Symbol, tf, shift, count, H)       < count) return(iClose(_Symbol, tf, shift));
   if(CopyLow(_Symbol, tf, shift, count, L)        < count) return(iClose(_Symbol, tf, shift));
   if(CopyClose(_Symbol, tf, shift, count, C)      < count) return(iClose(_Symbol, tf, shift));
   if(CopyTickVolume(_Symbol, tf, shift, count, V) < count) return(iClose(_Symbol, tf, shift));

   double pv = 0.0, vv = 0.0;
   for(int k = 0; k < count; k++)
     {
      double tp = (H[k] + L[k] + C[k]) / 3.0;
      double vol = (double)V[k];
      pv += tp * vol;
      vv += vol;
     }
   return(vv > 0.0 ? pv/vv : iClose(_Symbol, tf, shift));
  }
int CountMyPositions(const int dir)
  {
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
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
double CalcLots(const double slDistPrice)
  {
   if(!InpUseRiskPct) return(NormalizeLots(InpFixedLots));
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0 || slDistPrice <= 0) return(NormalizeLots(InpFixedLots));
   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   double lossPerLot = (slDistPrice / tickSize) * tickVal;
   if(lossPerLot <= 0) return(NormalizeLots(InpFixedLots));
   return(NormalizeLots(riskMoney / lossPerLot));
  }
// current tradable bias from the signal TF (respecting recency & side)
int BiasDir()
  {
   if(g_crossDir == 0) return(0);
   double e1;
   if(!EmaVal(hEmaSig, 1, e1)) return(0);
   double v1 = VWAP(InpSignalTF, 1);
   if(g_crossDir > 0 && !(e1 > v1)) return(0);   // no longer above
   if(g_crossDir < 0 && !(e1 < v1)) return(0);   // no longer below
   if(InpMaxBarsSinceCross > 0)
     {
      int sigSec = PeriodSeconds(InpSignalTF);
      if(sigSec > 0)
        {
         int bars = (int)((iTime(_Symbol, InpSignalTF, 0) - g_crossTime) / sigSec);
         if(bars > InpMaxBarsSinceCross) return(0);
        }
     }
   return(g_crossDir);
  }

//+------------------------------------------------------------------+
//| Update the 3M cross bias on each new signal-TF bar               |
//+------------------------------------------------------------------+
void UpdateSignalCross()
  {
   datetime st = iTime(_Symbol, InpSignalTF, 0);
   if(st == g_lastSigBar) return;
   g_lastSigBar = st;

   double e1, e2;
   if(!EmaVal(hEmaSig, 1, e1) || !EmaVal(hEmaSig, 2, e2)) return;
   double v1 = VWAP(InpSignalTF, 1);
   double v2 = VWAP(InpSignalTF, 2);
   if(e1 > v1 && e2 <= v2)      { g_crossDir = +1; g_crossTime = st; }
   else if(e1 < v1 && e2 >= v2) { g_crossDir = -1; g_crossTime = st; }
  }

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateSignalCross();

   // act once per entry-TF bar
   datetime et = iTime(_Symbol, InpEntryTF, 0);
   if(et == g_lastEntryBar) return;
   g_lastEntryBar = et;

   int bias = BiasDir();

   // manage: close on bias flip
   if(InpCloseOnOpposite)
     {
      if(bias < 0 && CountMyPositions(+1) > 0) CloseMyPositions(+1);
      if(bias > 0 && CountMyPositions(-1) > 0) CloseMyPositions(-1);
     }

   if(bias == 0) return;
   if(InpOneTradeAtATime && CountMyPositions(0) > 0) return;

   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return;

   // entry-TF EMA9 + VWAP on the just-closed bar (shift 1)
   double eE1;
   if(!EmaVal(hEmaEnt, 1, eE1)) return;
   double vE1 = VWAP(InpEntryTF, 1);

   double o1 = iOpen(_Symbol,  InpEntryTF, 1);
   double h1 = iHigh(_Symbol,  InpEntryTF, 1);
   double l1 = iLow(_Symbol,   InpEntryTF, 1);
   double c1 = iClose(_Symbol, InpEntryTF, 1);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpWickTolPts * point;

   if(InpTradeLong && bias > 0)
     {
      // bullish rejection: wick down into EMA9 or VWAP, close back above it
      bool wickEma  = (l1 <= eE1 + tol) && (!InpRequireClose || c1 > eE1);
      bool wickVwap = (l1 <= vE1 + tol) && (!InpRequireClose || c1 > vE1);
      if((wickEma || wickVwap) && c1 >= o1)
         OpenTrade(true, l1);
      return;
     }
   if(InpTradeShort && bias < 0)
     {
      // bearish rejection: wick up into EMA9 or VWAP, close back below it
      bool wickEma  = (h1 >= eE1 - tol) && (!InpRequireClose || c1 < eE1);
      bool wickVwap = (h1 >= vE1 - tol) && (!InpRequireClose || c1 < vE1);
      if((wickEma || wickVwap) && c1 <= o1)
         OpenTrade(false, h1);
     }
  }

//+------------------------------------------------------------------+
//| Open a trade with SL and fixed-R:R TP                            |
//+------------------------------------------------------------------+
void OpenTrade(const bool isBuy, const double wickExtreme)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buf   = InpSLBufferPts * point;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;

   double sl = 0.0;
   if(InpSLMode == SL_WICK)
      sl = isBuy ? wickExtreme - buf : wickExtreme + buf;
   else if(InpSLMode == SL_ATR)
     {
      double a[]; ArraySetAsSeries(a, true);
      if(CopyBuffer(hATR, 0, 1, 1, a) < 1) return;
      double dist = a[0]*InpATRmult + buf;
      sl = isBuy ? entry - dist : entry + dist;
     }
   else // SL_FIXED
     {
      double dist = InpFixedSLPts*point + buf;
      sl = isBuy ? entry - dist : entry + dist;
     }

   double risk = isBuy ? (entry - sl) : (sl - entry);
   if(risk <= 0) return;

   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(risk < stopLevel)
     {
      risk = stopLevel;
      sl   = isBuy ? entry - risk : entry + risk;
     }

   double tp = isBuy ? entry + InpRR*risk : entry - InpRR*risk;
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalcLots(risk);
   if(lots <= 0) return;

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment)
                   : trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);
   if(!ok)
      PrintFormat("Order failed (%s): retcode=%d %s",
                  isBuy?"BUY":"SELL", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else
      PrintFormat("%s %s lots=%.2f entry~%.5f SL=%.5f TP=%.5f (1:%.1f)",
                  isBuy?"BUY":"SELL", _Symbol, lots, entry, sl, tp, InpRR);
  }
//+------------------------------------------------------------------+
