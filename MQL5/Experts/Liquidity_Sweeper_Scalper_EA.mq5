//+------------------------------------------------------------------+
//|                                 Liquidity_Sweeper_Scalper_EA.mq5  |
//|            Expert Advisor version of the Liquidity Sweeper Scalper|
//|                                                                  |
//|  Trades the SAME confirmed BUY/SELL signals as the indicator,    |
//|  on a timeframe YOU pick in the inputs (M5 / M15 / M30 / H1 ...).|
//|                                                                  |
//|  Signal (identical logic to the indicator):                     |
//|   BUY  = sell-side liquidity sweep (wick below a swing low,       |
//|          close back above) + quality filters.                    |
//|   SELL = buy-side liquidity sweep (wick above a swing high,       |
//|          close back below) + quality filters.                    |
//|  Filters: close in the reversal half, and a follow-through candle |
//|  that breaks the sweep's extreme (non-repaint; confirmed on the   |
//|  closed bar). Entry is at the OPEN of the next bar after          |
//|  confirmation - no look-ahead.                                   |
//|                                                                  |
//|  Risk: SL just beyond the sweep wick, TP = InpRR x risk.          |
//|  "1:3" -> set InpRR = 3.0 (take-profit is 3x the stop distance).  |
//|                                                                  |
//|  NOTE: back-test with the tester timeframe set to M1 and modeling |
//|  "Every tick" or "1 minute OHLC" for realistic SL/TP fills; the   |
//|  EA itself always takes signals from InpSignalTF regardless of    |
//|  the chart/tester timeframe.                                      |
//+------------------------------------------------------------------+
#property copyright "Liquidity Sweeper Scalper EA"
#property link      ""
#property version   "1.00"
#property description "EA: trades confirmed liquidity-sweep BUY/SELL from a chosen timeframe, RR configurable (1:3 default)"

#include <Trade/Trade.mqh>
CTrade trade;

//==================== INPUTS =======================================
input group "=== Signal source ==="
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M15; // Timeframe to take BUY/SELL from (M5/M15/M30/H1)
input bool   InpTradeBuys      = true;          // Take BUY signals
input bool   InpTradeSells     = true;          // Take SELL signals

input group "=== Sweep detection (same as the indicator) ==="
input int    InpPivotLength    = 10;            // Swing pivot strength (bars each side)
input int    InpBarsScan       = 300;           // Signal-TF history bars scanned per new bar
input bool   InpSignalStrongClose = true;       // Sweep must close in the reversal half
input bool   InpUseConfirm     = true;          // Require follow-through candle (breaks sweep extreme)
input bool   InpUseTrendFilter = false;         // Only trade with the signal-TF EMA trend
input int    InpTrendEMAPeriod = 50;            // EMA period for the trend filter

input group "=== Risk / money management ==="
input double InpRR             = 3.0;           // Reward:Risk (TP = RR x SL). 1:3 -> 3.0
input double InpSLBufferPoints = 30;            // Extra SL distance beyond the sweep wick (points)
input int    InpLotMode        = 1;             // 0 = fixed lot, 1 = % risk of balance
input double InpFixedLot       = 0.01;          // Fixed lot (LotMode = 0)
input double InpRiskPercent    = 1.0;           // Risk % per trade (LotMode = 1)
input int    InpMaxOpenTrades  = 1;             // Max simultaneous positions from this EA
input bool   InpMoveToBE       = false;         // Move SL to break-even at +1R
input int    InpSlippagePoints = 20;            // Max slippage (points)
input long   InpMagic          = 775311;        // Magic number

input group "=== Filters (optional) ==="
input bool   InpUseSession     = false;         // Restrict trading hours (server time)
input int    InpStartHour      = 7;             // Session start hour (0-23)
input int    InpEndHour        = 20;            // Session end hour (0-23)
input long   InpMaxSpreadPoints= 0;             // Skip entry if spread above this (0 = ignore)

//==================== GLOBALS ======================================
datetime g_lastBar = 0;

struct Signal
  {
   bool   has;
   bool   isBuy;
   double swHigh;   // sweep candle high
   double swLow;    // sweep candle low
  };

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_lastBar = iTime(_Symbol, InpSignalTF, 0);   // don't act on a stale signal at attach
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
//| Sweep closed in the reversal half of its range?                  |
//+------------------------------------------------------------------+
bool FavorableClose(const bool isBuy, const double h, const double l, const double c)
  {
   double mid = (h + l) * 0.5;
   return(isBuy ? (c >= mid) : (c <= mid));
  }

//+------------------------------------------------------------------+
//| Detect a signal that just CONFIRMED on the last closed bar       |
//| (sweep on bar index 2, follow-through on bar index 1)            |
//+------------------------------------------------------------------+
Signal DetectSignal()
  {
   Signal sig;
   sig.has=false; sig.isBuy=false; sig.swHigh=0.0; sig.swLow=0.0;

   int len  = InpPivotLength;
   int need = 2*len + 3;
   int avail= Bars(_Symbol, InpSignalTF);
   int cnt  = (int)MathMin(InpBarsScan, avail);
   if(cnt < need + 3) return(sig);

   double   H[], L[], C[];
   datetime T[];
   ArraySetAsSeries(H,true); ArraySetAsSeries(L,true);
   ArraySetAsSeries(C,true); ArraySetAsSeries(T,true);
   if(CopyHigh (_Symbol,InpSignalTF,0,cnt,H) <= 0) return(sig);
   if(CopyLow  (_Symbol,InpSignalTF,0,cnt,L) <= 0) return(sig);
   if(CopyClose(_Symbol,InpSignalTF,0,cnt,C) <= 0) return(sig);
   if(CopyTime (_Symbol,InpSignalTF,0,cnt,T) <= 0) return(sig);
   int n = ArraySize(H);
   if(n < need + 3) return(sig);

   //--- pivots (confirmed swing highs/lows)
   double pPrice[]; int pIdx[]; int pDir[]; bool pSwept[];
   for(int k=len+1; k<=n-1-len; k++)
     {
      bool ph=true, pl=true;
      double hv=H[k], lv=L[k];
      for(int m=k-len; m<=k+len; m++)
        {
         if(m==k) continue;
         if(H[m] >= hv) ph=false;
         if(L[m] <= lv) pl=false;
         if(!ph && !pl) break;
        }
      if(ph)
        {
         int s=ArraySize(pPrice);
         ArrayResize(pPrice,s+1); ArrayResize(pIdx,s+1); ArrayResize(pDir,s+1); ArrayResize(pSwept,s+1);
         pPrice[s]=hv; pIdx[s]=k; pDir[s]=+1; pSwept[s]=false;
        }
      if(pl)
        {
         int s=ArraySize(pPrice);
         ArrayResize(pPrice,s+1); ArrayResize(pIdx,s+1); ArrayResize(pDir,s+1); ArrayResize(pSwept,s+1);
         pPrice[s]=lv; pIdx[s]=k; pDir[s]=-1; pSwept[s]=false;
        }
     }
   int np = ArraySize(pPrice);
   if(np == 0) return(sig);

   //--- optional EMA for the trend filter
   double ema[];
   if(InpUseTrendFilter)
     {
      ArrayResize(ema,n);
      double kk = 2.0/(InpTrendEMAPeriod + 1.0);
      ema[n-1] = C[n-1];
      for(int i=n-2; i>=0; i--) ema[i] = C[i]*kk + ema[i+1]*(1.0-kk);
     }

   //--- sweeps oldest -> newest (consume levels); emit only when the sweep is on
   //    bar index 2 and the confirmation bar is the just-closed bar index 1
   for(int j=n-2; j>=1; j--)
     {
      double hj=H[j], lj=L[j], cj=C[j];
      for(int q=0; q<np; q++)
        {
         if(pSwept[q]) continue;
         if(pIdx[q] <= j) continue;
         double P = pPrice[q];
         int sdir = 0;
         if(pDir[q] > 0 && hj > P && cj < P) sdir = +1;   // buy-side swept -> SELL
         if(pDir[q] < 0 && lj < P && cj > P) sdir = -1;   // sell-side swept -> BUY
         if(sdir == 0) continue;
         pSwept[q] = true;                                 // consume the level

         if(j != 2) continue;                              // only the freshly-confirmed sweep

         bool isBuy = (sdir < 0);
         if(InpSignalStrongClose && !FavorableClose(isBuy, hj, lj, cj)) continue;
         if(InpUseConfirm && (isBuy ? !(C[1] > hj) : !(C[1] < lj))) continue;
         if(InpUseTrendFilter && (isBuy ? !(cj > ema[2]) : !(cj < ema[2]))) continue;
         if(isBuy  && !InpTradeBuys ) continue;
         if(!isBuy && !InpTradeSells) continue;

         sig.has=true; sig.isBuy=isBuy; sig.swHigh=hj; sig.swLow=lj;
         return(sig);
        }
     }
   return(sig);
  }

//+------------------------------------------------------------------+
//| Count this EA's open positions on this symbol                    |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int c=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      c++;
     }
   return(c);
  }

//+------------------------------------------------------------------+
//| Normalise a lot size to the symbol's limits/step                 |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0) vstep = 0.01;
   lot = MathFloor(lot/vstep)*vstep;
   if(lot < vmin) lot = vmin;
   if(lot > vmax) lot = vmax;
   return(lot);
  }

//+------------------------------------------------------------------+
//| Lot from the risk model                                          |
//+------------------------------------------------------------------+
double CalcLot(const double riskPrice)
  {
   if(InpLotMode == 0) return(NormalizeLot(InpFixedLot));
   double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney= bal * InpRiskPercent/100.0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0.0 || tickSize<=0.0 || riskPrice<=0.0) return(NormalizeLot(InpFixedLot));
   double lossPerLot = riskPrice/tickSize * tickVal;     // money lost per 1.0 lot at SL
   if(lossPerLot <= 0.0) return(0.0);
   return(NormalizeLot(riskMoney/lossPerLot));
  }

//+------------------------------------------------------------------+
//| Inside the allowed session?                                      |
//+------------------------------------------------------------------+
bool InSession()
  {
   if(!InpUseSession) return(true);
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int h = t.hour;
   if(InpStartHour <= InpEndHour) return(h >= InpStartHour && h < InpEndHour);
   return(h >= InpStartHour || h < InpEndHour);          // overnight window
  }

//+------------------------------------------------------------------+
//| Open a trade from a confirmed signal                             |
//+------------------------------------------------------------------+
void TryEnter(const Signal &sig)
  {
   if(CountMyPositions() >= InpMaxOpenTrades) return;
   if(!InSession()) return;
   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) > InpMaxSpreadPoints) return;

   double point = _Point;
   double buffer= InpSLBufferPoints * point;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double spread= ask - bid;

   if(sig.isBuy)
     {
      double entry = ask;
      double sl    = sig.swLow - buffer;
      double minRisk = stops + spread;
      if(entry - sl < minRisk) sl = entry - minRisk;      // respect broker min stop
      double risk = entry - sl;
      if(risk <= 0.0) return;
      double tp = entry + InpRR*risk;
      double lot= CalcLot(risk);
      if(lot <= 0.0) return;
      trade.Buy(lot, _Symbol, 0.0,
                NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "LSS buy");
     }
   else
     {
      double entry = bid;
      double sl    = sig.swHigh + buffer;
      double minRisk = stops + spread;
      if(sl - entry < minRisk) sl = entry + minRisk;
      double risk = sl - entry;
      if(risk <= 0.0) return;
      double tp = entry - InpRR*risk;
      double lot= CalcLot(risk);
      if(lot <= 0.0) return;
      trade.Sell(lot, _Symbol, 0.0,
                 NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "LSS sell");
     }
  }

//+------------------------------------------------------------------+
//| Move SL to break-even at +1R (optional)                          |
//+------------------------------------------------------------------+
void ManageBreakEven()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if(tp==0.0) continue;
      double riskR = MathAbs(tp-open)/InpRR;              // 1R in price
      if(riskR<=0.0) continue;

      if(type==POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid-open >= riskR && sl < open)
            trade.PositionModify(tk, NormalizeDouble(open,_Digits), tp);
        }
      else if(type==POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open-ask >= riskR && (sl > open || sl==0.0))
            trade.PositionModify(tk, NormalizeDouble(open,_Digits), tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(InpMoveToBE) ManageBreakEven();

   datetime bt = iTime(_Symbol, InpSignalTF, 0);
   if(bt <= 0 || bt == g_lastBar) return;                // act once per new signal-TF bar
   g_lastBar = bt;

   Signal sig = DetectSignal();
   if(sig.has) TryEnter(sig);
  }
//+------------------------------------------------------------------+
