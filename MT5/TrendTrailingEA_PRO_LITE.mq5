//+------------------------------------------------------------------+
//|                                     TrendTrailingEA_PRO_LITE.mq5  |
//|                                                                  |
//|  All-in-one build tuned for: more frequency, fewer losses,       |
//|  better net profit. Core strategy unchanged (pivot-rejection     |
//|  entries in the trend direction, independent BUY/SELL cycles,    |
//|  grid, trailing, PKT session, news filter, dashboard) PLUS:      |
//|   - Trend robustness (deadband + confirm-bars + ADX gate)        |
//|   - Spread filter                                                 |
//|   - ATR dynamic TP/SL/trailing/grid                               |
//|   - Partial take-profit + runner                                  |
//|   - Basket stop, daily loss limit, daily profit target, cooldown  |
//|   - Rejection wick-quality filter + RSI confluence                |
//|   - Stall (time-based) exit                                       |
//|   - D1 pivot confluence -> larger size on A+ setups               |
//|   - Auto-GMT session timing                                       |
//|                                                                  |
//|  *** Grid averages into losers. Even with caps, test on demo. *** |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "7.00"
#property strict

#include <Trade/Trade.mqh>

enum ENUM_TARGET_MODE
  {
   MODE_MONEY_USD    = 0,  // Inputs are in account currency (USD) per trade
   MODE_PRICE_POINTS = 1   // Inputs are in raw price distance (e.g. 6.0 = 6.00)
  };

enum ENUM_PIVOT_METHOD
  {
   PIVOT_STANDARD  = 0,   // Classic / Floor pivots
   PIVOT_FIBONACCI = 1,   // Fibonacci pivots
   PIVOT_CAMARILLA = 2,   // Camarilla pivots
   PIVOT_WOODIE    = 3    // Woodie pivots
  };

//============================ INPUTS ================================//
input group "=== Trend Filter (higher timeframe) ==="
input ENUM_TIMEFRAMES    InpTrendTF        = PERIOD_M5;      // Higher timeframe for trend
input int                InpMAPeriod       = 50;             // Trend MA period
input ENUM_MA_METHOD     InpMAMethod       = MODE_EMA;       // Trend MA method
input ENUM_APPLIED_PRICE InpMAPrice        = PRICE_CLOSE;    // Trend MA applied price

input group "=== Trend Robustness (whipsaw filter) ==="
input bool               InpUseDeadband    = true;          // Require price to clear the MA by a buffer
input double             InpDeadbandUSD    = 0.5;            // Deadband buffer (USD/price) around the MA
input bool               InpUseConfirmBars = true;          // Require N consecutive HTF closes to flip trend
input int                InpConfirmBars    = 2;             // Consecutive HTF closes needed to change trend
input bool               InpUseADX         = true;          // Only trade when ADX shows momentum
input int                InpADXPeriod      = 14;            // ADX period (on the trend timeframe)
input double             InpADXThreshold   = 20.0;          // Minimum ADX to call it a trend

input group "=== Entry / Sizing ==="
input double             InpLots           = 0.01;          // Base lot (LITE: single min lot, no partial)
input long               InpMagic          = 990078;        // Magic number
input ENUM_TIMEFRAMES    InpSignalTF       = PERIOD_M1;     // Timeframe whose candles are checked for rejections
input double             InpRejectionBuffer = 0.0;          // Extra distance (USD/price) body must close beyond level

input group "=== Entry Quality Filters ==="
input bool               InpUseWickFilter  = true;          // Require a real rejection wick
input double             InpMinWickRatio   = 1.0;           // Min rejection-wick : body ratio
input bool               InpUseRSI         = true;          // RSI confluence at the level
input int                InpRSIPeriod      = 14;            // RSI period (signal TF)
input double             InpRSIOB          = 60.0;          // Sell rejections need RSI >= this
input double             InpRSIOS          = 40.0;          // Buy rejections need RSI <= this

input group "=== Spread Filter ==="
input bool               InpUseSpreadFilter = true;         // Block new trades when spread too wide
input int                InpMaxSpreadPts    = 50;           // Max spread (points) to allow trading

input group "=== Targets: fixed OR ATR ==="
input ENUM_TARGET_MODE   InpTargetMode     = MODE_MONEY_USD;// How the FIXED inputs below are read
input double             InpTakeProfit     = 6.0;           // Fixed take profit (USD or price)
input double             InpStopLoss       = 6.0;           // Fixed stop loss (USD or price)
input double             InpTrailStart     = 0.3;           // Fixed favourable move before trailing
input double             InpTrailDistance  = 0.3;           // Fixed trailing gap
input double             InpTrailStep      = 0.05;          // Min SL improvement before it moves
input bool               InpLockBreakeven  = true;          // Armed trail never closes in loss
input bool               InpUseATR         = true;          // Size targets from ATR (overrides the fixed ones)
input ENUM_TIMEFRAMES    InpATRTF          = PERIOD_M5;     // ATR timeframe
input int                InpATRPeriod      = 14;            // ATR period
input double             InpATR_TP         = 1.0;           // Take profit  = this * ATR
input double             InpATR_SL         = 1.2;           // Stop loss     = this * ATR
input double             InpATR_TrailStart = 0.5;           // Trail start   = this * ATR
input double             InpATR_TrailDist  = 0.5;           // Trail gap      = this * ATR
input double             InpATR_GridStep   = 0.8;           // Grid step      = this * ATR

input group "=== Partial Take-Profit + Runner ==="
input bool               InpUsePartialTP   = false;         // OFF in LITE (0.01 lot cannot be split)
input double             InpPartialPct      = 50.0;         // Percent of volume to close at TP1
input double             InpTP1Frac         = 0.5;          // TP1 distance = this * full TP distance

input group "=== Risk Caps ==="
input bool               InpUseBasketStop  = true;          // Flatten everything on max floating loss
input double             InpBasketStopUSD  = 40.0;          // Max total floating loss (USD) -> close all
input bool               InpUseDailyLoss   = true;          // Stop new trades after daily loss
input double             InpDailyLossUSD   = 60.0;          // Daily loss limit (USD)
input bool               InpUseDailyProfit = true;          // Stop new trades after daily profit
input double             InpDailyProfitUSD = 60.0;          // Daily profit target (USD)
input int                InpCooldownMin    = 30;            // Cooldown (min) after a basket stop (0=off)

input group "=== Stall Exit ==="
input bool               InpUseStallExit   = true;          // Close trades that stall
input int                InpMaxTradeMinutes = 120;          // Close a trade older than this (0=off)

input group "=== Grid (average into adverse moves) ==="
input bool               InpEnableGrid      = true;         // Add trades as price moves against the first
input double             InpGridStepUSD     = 4.0;          // Fixed grid step (used if ATR off)
input int                InpMaxGridTrades   = 3;            // Max total trades per side per cycle
input bool               InpGridRespectFilters = false;     // Grid adds also blocked by session/news

input group "=== Pivot Points + Confluence ==="
input bool               InpShowPivots      = true;         // Draw pivot S/R lines
input ENUM_PIVOT_METHOD  InpPivotMethod     = PIVOT_STANDARD;// Pivot calculation method
input ENUM_TIMEFRAMES    InpPivotTF         = PERIOD_M30;   // Primary pivot timeframe (rejections)
input bool               InpUseConfluence   = true;         // Bigger size when level aligns with a higher-TF pivot
input ENUM_TIMEFRAMES    InpPivot2TF        = PERIOD_D1;    // Confluence pivot timeframe
input double             InpConfluenceTolUSD = 1.0;         // Max distance (USD/price) to count as confluent
input double             InpConfluenceLots   = 0.02;        // Lot on a confluent (A+) rejection

input group "=== Session (Pakistan time, PKT = UTC+5) ==="
input bool               InpAutoGMT         = true;         // Derive PKT from true GMT (live); offset only in tester
input int                InpBrokerGMTOffset = 3;            // Broker server GMT offset (tester / AutoGMT off)
input int                InpStartHourPKT    = 12;           // Start hour PKT (12 = 12:00 PM)
input int                InpEndHourPKT      = 20;           // End hour PKT (20 = 8:00 PM)

input group "=== News Filter ==="
input bool               InpUseNewsFilter   = true;         // Enable news blackout
input int                InpNewsMinsBefore  = 15;           // Minutes BEFORE news to stop
input int                InpNewsMinsAfter   = 15;           // Minutes AFTER news to resume
input string             InpManualNewsPKT   = "";           // Manual news PKT: "2026.07.28 17:30,2026.07.29 12:30"
input bool               InpUseCalendarAuto = true;         // Also use MT5 economic calendar (live only)
input int                InpNewsImportance  = 3;            // Min importance: 1=Low 2=Moderate 3=High
input string             InpNewsCurrencies  = "USD";        // Currencies to watch (comma sep), "" = all

input group "=== Dashboard & Debug ==="
input bool               InpShowDashboard   = true;         // Show info panel on the chart
input bool               InpDebugLogs       = false;        // Print decisions to the journal

//============================ GLOBALS ==============================//
CTrade    trade;
int       maHandle = INVALID_HANDLE;
int       adxHandle = INVALID_HANDLE;
int       atrHandle = INVALID_HANDLE;
int       rsiHandle = INVALID_HANDLE;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;
double    g_minLot, g_lotStep;

datetime  g_newsTimes[];
datetime  g_lastPivotPeriod  = 0;
datetime  g_lastPivot2Period = 0;
datetime  g_lastSignalBar    = 0;

double    g_levels[7];       // primary pivots (rejection detection)
double    g_levels2[7];      // confluence pivots (higher TF)
int       g_numLevels = 7;
double    g_rejLevel = 0.0;  // level that produced the last rejection

int       g_trendState = 0;  // last confirmed trend direction (-1/0/+1)

bool      g_calBlackout   = false;
datetime  g_calLastCheck  = 0;
datetime  g_calNextTime   = 0;
string    g_calNextName   = "";

bool      g_pausedBuy  = false;
bool      g_pausedSell = false;

ulong     g_partialed[];     // tickets already partially closed
int       g_dayStamp = 0;
double    g_dayStartEquity = 0.0;
datetime  g_cooldownUntil = 0;

struct CycleInfo
  {
   int      count;
   long     baseType;
   ulong    baseTicket;
   double   basePrice;
   double   baseSL;
   double   baseTP;
   double   totalLots;
   double   floatPL;
   datetime baseTime;
  };

//========================= BASIC HELPERS ==========================//
double DistanceToPrice(double value)
  {
   if(InpTargetMode == MODE_PRICE_POINTS) return value;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0 || InpLots <= 0.0) return value;
   return value * ts / (tv * InpLots);
  }

double MoneyFromDistance(double dist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return 0.0;
   return dist / ts * tv * InpLots;
  }

double CurrentATR()
  {
   double a[];
   if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 1, 1, a) >= 1) return a[0];
   return 0.0;
  }

// --- target distances: ATR if enabled and valid, else the fixed inputs ---
double TPDist()        { double a=CurrentATR(); return (InpUseATR && a>0)? InpATR_TP*a        : DistanceToPrice(InpTakeProfit); }
double SLDist()        { double a=CurrentATR(); return (InpUseATR && a>0)? InpATR_SL*a        : DistanceToPrice(InpStopLoss); }
double TrailStartDist(){ double a=CurrentATR(); return (InpUseATR && a>0)? InpATR_TrailStart*a: DistanceToPrice(InpTrailStart); }
double TrailGapDist()  { double a=CurrentATR(); return (InpUseATR && a>0)? InpATR_TrailDist*a : DistanceToPrice(InpTrailDistance); }
double GridStepDist()  { double a=CurrentATR(); return (InpUseATR && a>0)? InpATR_GridStep*a  : DistanceToPrice(InpGridStepUSD); }

int SpreadPts() { return (int)MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/g_point); }
bool SpreadOK() { return (!InpUseSpreadFilter || SpreadPts() <= InpMaxSpreadPts); }

datetime ServerToPKT(datetime tServer)
  {
   long shift;
   if(InpAutoGMT && !MQLInfoInteger(MQL_TESTER))
     {
      long serverOffset = (long)TimeCurrent() - (long)TimeGMT();
      shift = 5 * 3600 - serverOffset;
     }
   else
      shift = (long)(5 - InpBrokerGMTOffset) * 3600;
   return (datetime)((long)tServer + shift);
  }
datetime PKTNow() { return ServerToPKT(TimeCurrent()); }

string TFName(ENUM_TIMEFRAMES tf)
  {
   if(tf == PERIOD_CURRENT) tf = (ENUM_TIMEFRAMES)_Period;
   return StringSubstr(EnumToString(tf), 7);
  }

void ParseNewsList()
  {
   ArrayFree(g_newsTimes);
   string parts[];
   int n = StringSplit(InpManualNewsPKT, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s == "") continue;
      datetime t = StringToTime(s);
      if(t > 0) { int sz = ArraySize(g_newsTimes); ArrayResize(g_newsTimes, sz+1); g_newsTimes[sz] = t; }
     }
  }

//========================= PARTIAL-TRACKING =======================//
bool IsPartialed(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_partialed); i++) if(g_partialed[i] == ticket) return true;
   return false;
  }
void MarkPartialed(ulong ticket)
  {
   int sz = ArraySize(g_partialed); ArrayResize(g_partialed, sz+1); g_partialed[sz] = ticket;
  }

//============================ INIT ================================//
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   maHandle = iMA(_Symbol, InpTrendTF, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
   if(maHandle == INVALID_HANDLE) { Print("Failed MA handle"); return(INIT_FAILED); }
   if(InpUseADX)
     {
      adxHandle = iADX(_Symbol, InpTrendTF, InpADXPeriod);
      if(adxHandle == INVALID_HANDLE) { Print("Failed ADX handle"); return(INIT_FAILED); }
     }
   if(InpUseATR)
     {
      atrHandle = iATR(_Symbol, InpATRTF, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE) { Print("Failed ATR handle"); return(INIT_FAILED); }
     }
   if(InpUseRSI)
     {
      rsiHandle = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE) { Print("Failed RSI handle"); return(INIT_FAILED); }
     }

   ArrayInitialize(g_levels, 0.0);
   ArrayInitialize(g_levels2, 0.0);
   ParseNewsList();

   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   g_dayStamp = t.year*10000 + t.mon*100 + t.day;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   EventSetTimer(1);

   if(InpUsePartialTP && InpLots < 2*g_minLot - 1e-9)
      Print("WARNING: Partial-TP needs lot >= 2x min lot (", DoubleToString(2*g_minLot,2), "). It will be skipped at current lot.");
   if(InpEnableGrid)
      Print("WARNING: Grid averages into losers. Basket stop and daily loss limit are the guardrails - keep them on.");
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Account is NETTING - simultaneous BUY & SELL cycles will not work. Use a HEDGING account.");

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(maHandle  != INVALID_HANDLE) IndicatorRelease(maHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
     {
      ObjectsDeleteAll(0, "PIV_");
      ObjectsDeleteAll(0, "DB_");
     }
  }

//============================ TREND ===============================//
int TrendDirection()
  {
   if(InpUseADX && adxHandle != INVALID_HANDLE)
     {
      double adx[];
      if(CopyBuffer(adxHandle, 0, 1, 1, adx) >= 1 && adx[0] < InpADXThreshold) return 0;
     }
   int need = InpUseConfirmBars ? (int)MathMax(1, InpConfirmBars) : 1;
   double ma[];
   if(CopyBuffer(maHandle, 0, 1, need, ma) < need) return g_trendState;
   double band = InpUseDeadband ? DistanceToPrice(InpDeadbandUSD) : 0.0;

   int cd = 0;
   for(int s = 1; s <= need; s++)
     {
      double c = iClose(_Symbol, InpTrendTF, s);
      if(c <= 0.0) { cd = 0; break; }
      double m = ma[s-1];
      int d = (c > m + band) ? 1 : (c < m - band) ? -1 : 0;
      if(s == 1) { if(d == 0) { cd = 0; break; } cd = d; }
      else if(d != cd) { cd = 0; break; }
     }
   if(cd != 0) g_trendState = cd;
   return g_trendState;
  }

//======================== SESSION / NEWS ==========================//
bool IsWithinSession()
  {
   MqlDateTime st; TimeToStruct(PKTNow(), st);
   return (st.hour >= InpStartHourPKT && st.hour < InpEndHourPKT);
  }

bool CalendarBlackout()
  {
   if(!InpUseCalendarAuto) return false;
   datetime now = TimeCurrent();
   if(now - g_calLastCheck < 60) return g_calBlackout;
   g_calLastCheck = now; g_calBlackout = false; g_calNextTime = 0; g_calNextName = "";

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, now - 12*3600, now + 12*3600, NULL, NULL);
   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt)) continue;
      if((int)evt.importance < InpNewsImportance) continue;
      if(InpNewsCurrencies != "")
        {
         MqlCalendarCountry c;
         if(!CalendarCountryById((long)evt.country_id, c)) continue;
         if(StringFind(InpNewsCurrencies, c.currency) < 0) continue;
        }
      datetime et = values[i].time;
      if(now >= et - InpNewsMinsBefore*60 && now <= et + InpNewsMinsAfter*60) g_calBlackout = true;
      if(et > now && (g_calNextTime == 0 || et < g_calNextTime)) { g_calNextTime = et; g_calNextName = evt.name; }
     }
   return g_calBlackout;
  }

bool IsNewsBlackout()
  {
   if(!InpUseNewsFilter) return false;
   datetime nowPKT = PKTNow();
   for(int i = 0; i < ArraySize(g_newsTimes); i++)
     {
      datetime et = g_newsTimes[i];
      if(nowPKT >= et - InpNewsMinsBefore*60 && nowPKT <= et + InpNewsMinsAfter*60) return true;
     }
   return CalendarBlackout();
  }

string NextNewsText()
  {
   datetime nowPKT = PKTNow(), bestPKT = 0;
   string label = "";
   for(int i = 0; i < ArraySize(g_newsTimes); i++)
      if(g_newsTimes[i] > nowPKT && (bestPKT == 0 || g_newsTimes[i] < bestPKT)) { bestPKT = g_newsTimes[i]; label = "manual"; }
   if(g_calNextTime > 0)
     {
      datetime calPKT = ServerToPKT(g_calNextTime);
      if(calPKT > nowPKT && (bestPKT == 0 || calPKT < bestPKT)) { bestPKT = calPKT; label = g_calNextName; }
     }
   if(bestPKT == 0) return "none in next 12h";
   long secs = (long)(bestPKT - nowPKT);
   string cd = (secs >= 3600) ? StringFormat("%dh%02dm",(int)(secs/3600),(int)((secs%3600)/60)) : StringFormat("%dm",(int)(secs/60));
   string txt = StringFormat("%s PKT (in %s)", TimeToString(bestPKT, TIME_MINUTES), cd);
   if(label != "" && label != "manual") txt += " " + label;
   return txt;
  }

//========================= RISK CAPS ==============================//
void DayRollover()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int stamp = t.year*10000 + t.mon*100 + t.day;
   if(stamp != g_dayStamp)
     {
      g_dayStamp = stamp;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      ArrayResize(g_partialed, 0);
     }
  }
double DailyPL() { return AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity; }
bool DailyHalt()
  {
   double pl = DailyPL();
   if(InpUseDailyLoss   && pl <= -InpDailyLossUSD)   return true;
   if(InpUseDailyProfit && pl >=  InpDailyProfitUSD) return true;
   return false;
  }
bool InCooldown() { return (g_cooldownUntil > 0 && TimeCurrent() < g_cooldownUntil); }

double TotalFloatPL()
  {
   double s = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)  continue;
      s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return s;
  }
void CloseAllEA()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)  continue;
      trade.PositionClose(tk);
     }
  }
void BasketStopCheck()
  {
   if(!InpUseBasketStop) return;
   if(TotalFloatPL() <= -InpBasketStopUSD)
     {
      if(InpDebugLogs) PrintFormat("BASKET STOP: floating %.2f <= -%.2f -> flatten", TotalFloatPL(), InpBasketStopUSD);
      CloseAllEA();
      if(InpCooldownMin > 0) g_cooldownUntil = TimeCurrent() + InpCooldownMin*60;
     }
  }

//======================= CYCLE COLLECTION =========================//
bool CollectCycleDir(const long wantType, CycleInfo &ci)
  {
   ci.count = 0; ci.totalLots = 0; ci.floatPL = 0;
   ci.baseTicket = 0; ci.basePrice = 0; ci.baseSL = 0; ci.baseTP = 0; ci.baseType = -1; ci.baseTime = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)   != wantType) continue;
      ci.count++;
      ci.totalLots += PositionGetDouble(POSITION_VOLUME);
      ci.floatPL   += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ci.baseTicket == 0 || ot < ci.baseTime)
        {
         ci.baseTime=ot; ci.baseTicket=ticket;
         ci.basePrice=PositionGetDouble(POSITION_PRICE_OPEN);
         ci.baseSL=PositionGetDouble(POSITION_SL);
         ci.baseTP=PositionGetDouble(POSITION_TP);
         ci.baseType=PositionGetInteger(POSITION_TYPE);
        }
     }
   return (ci.count > 0);
  }

//============================ ORDERS ==============================//
void OpenTrade(int dir, double lots)
  {
   double tpDist = TPDist();
   double slDist = SLDist();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(dir > 0)
     {
      double sl = NormalizeDouble(ask - slDist, g_digits);
      double tp = NormalizeDouble(ask + tpDist, g_digits);
      if(!trade.Buy(lots, _Symbol, ask, sl, tp, "PRO BUY"))
         PrintFormat("Buy failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else if(dir < 0)
     {
      double sl = NormalizeDouble(bid + slDist, g_digits);
      double tp = NormalizeDouble(bid - tpDist, g_digits);
      if(!trade.Sell(lots, _Symbol, bid, sl, tp, "PRO SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//============================ GRID ================================//
bool GridLevelFilled(const long posType, double levelPrice, double tol)
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)   != posType)  continue;
      if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - levelPrice) <= tol) return true;
     }
   return false;
  }

void ManageGridSide(const long posType, const int dir, const int trend)
  {
   CycleInfo ci;
   if(!CollectCycleDir(posType, ci)) return;
   if(ci.count >= InpMaxGridTrades) return;

   if(trend != dir)
     {
      if(dir > 0){ if(InpDebugLogs && !g_pausedBuy) Print("GRID BUY: adds paused (trend flipped)"); g_pausedBuy=true; }
      else       { if(InpDebugLogs && !g_pausedSell) Print("GRID SELL: adds paused (trend flipped)"); g_pausedSell=true; }
      return;
     }
   if(dir > 0) g_pausedBuy = false; else g_pausedSell = false;

   if(DailyHalt() || InCooldown()) return;
   if(InpUseSpreadFilter && !SpreadOK()) return;
   if(InpGridRespectFilters && (!IsWithinSession() || IsNewsBlackout())) return;

   double step = GridStepDist();
   if(step <= 0.0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double adverse = (posType == POSITION_TYPE_BUY) ? (ci.basePrice - bid) : (bid - ci.basePrice);
   if(adverse < step) return;

   int levelsReached = (int)MathFloor(adverse / step + 1e-9);
   int gridOpen = ci.count - 1;
   if(gridOpen >= levelsReached) return;

   double refPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(GridLevelFilled(posType, refPrice, step*0.5)) return;

   if(InpDebugLogs) PrintFormat("GRID: %s add #%d (adverse %.2f)", (dir>0?"BUY":"SELL"), gridOpen+1, adverse);
   OpenTrade(dir, InpLots);
  }
void ManageGrid()
  {
   int trend = TrendDirection();
   ManageGridSide(POSITION_TYPE_SELL, -1, trend);
   ManageGridSide(POSITION_TYPE_BUY,  +1, trend);
  }

//========================== TRAILING ==============================//
void ManageTrailing()
  {
   double startDist = TrailStartDist();
   double trailDist = TrailGapDist();
   double stepDist  = DistanceToPrice(InpTrailStep);
   double minStop   = g_stopsLevelPts * g_point;
   if(trailDist < minStop) trailDist = minStop;

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double beBuf = (ask - bid) + g_point;

      if(type == POSITION_TYPE_BUY)
        {
         if(bid - entry < startDist) continue;
         double newSL = bid - trailDist;
         if(InpLockBreakeven) { double f = entry + beBuf; if(newSL < f) newSL = f; }
         newSL = NormalizeDouble(newSL, g_digits);
         if(newSL <= curSL) continue;
         if(curSL > 0 && newSL - curSL < stepDist - g_point*0.5) continue;
         if(newSL >= bid) continue;
         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("TRAIL BUY #%I64u FAILED: %d %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else if(type == POSITION_TYPE_SELL)
        {
         if(entry - ask < startDist) continue;
         double newSL = ask + trailDist;
         if(InpLockBreakeven) { double c = entry - beBuf; if(newSL > c) newSL = c; }
         newSL = NormalizeDouble(newSL, g_digits);
         if(curSL > 0 && newSL >= curSL) continue;
         if(curSL > 0 && curSL - newSL < stepDist - g_point*0.5) continue;
         if(newSL <= ask) continue;
         if(!trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("TRAIL SELL #%I64u FAILED: %d %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
     }
  }

//===================== PARTIAL TP + RUNNER ========================//
void ManagePartials()
  {
   if(!InpUsePartialTP) return;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      if(IsPartialed(ticket)) continue;

      double vol   = PositionGetDouble(POSITION_VOLUME);
      if(vol < 2*g_minLot - 1e-9) continue;            // cannot split and keep a runner
      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posTP = PositionGetDouble(POSITION_TP);
      if(posTP <= 0.0) continue;

      double tp1 = entry + InpTP1Frac * (posTP - entry);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool hit = (type == POSITION_TYPE_BUY) ? (bid >= tp1) : (ask <= tp1);
      if(!hit) continue;

      double closeVol = MathFloor((vol * InpPartialPct/100.0)/g_lotStep)*g_lotStep;
      if(closeVol < g_minLot) closeVol = g_minLot;
      if(vol - closeVol < g_minLot) closeVol = vol - g_minLot;
      closeVol = NormalizeDouble(closeVol, 2);
      if(closeVol < g_minLot) continue;

      if(trade.PositionClosePartial(ticket, closeVol))
        {
         MarkPartialed(ticket);
         double be = (type == POSITION_TYPE_BUY) ? entry + (ask-bid) + g_point : entry - (ask-bid) - g_point;
         trade.PositionModify(ticket, NormalizeDouble(be, g_digits), posTP);
         if(InpDebugLogs) PrintFormat("PARTIAL: closed %.2f of #%I64u at TP1 %.2f, SL->BE", closeVol, ticket, tp1);
        }
     }
  }

//========================== STALL EXIT ============================//
void ManageStallExit()
  {
   if(!InpUseStallExit || InpMaxTradeMinutes <= 0) return;
   long maxSec = (long)InpMaxTradeMinutes * 60;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)   continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if((long)(TimeCurrent() - ot) >= maxSec)
        {
         if(InpDebugLogs) PrintFormat("STALL EXIT: closing #%I64u (age > %d min)", ticket, InpMaxTradeMinutes);
         trade.PositionClose(ticket);
        }
     }
  }

//============================ PIVOTS ==============================//
void ComputePivots(double H, double L, double C, double O,
                   double &P, double &R1, double &R2, double &R3, double &S1, double &S2, double &S3)
  {
   double range = H - L;
   switch(InpPivotMethod)
     {
      case PIVOT_FIBONACCI:
         P=(H+L+C)/3.0; R1=P+0.382*range; S1=P-0.382*range; R2=P+0.618*range; S2=P-0.618*range; R3=P+1.0*range; S3=P-1.0*range; break;
      case PIVOT_CAMARILLA:
         P=(H+L+C)/3.0; R1=C+range*1.1/12.0; S1=C-range*1.1/12.0; R2=C+range*1.1/6.0; S2=C-range*1.1/6.0; R3=C+range*1.1/4.0; S3=C-range*1.1/4.0; break;
      case PIVOT_WOODIE:
         P=(H+L+2.0*O)/4.0; R1=2*P-L; S1=2*P-H; R2=P+range; S2=P-range; R3=H+2*(P-L); S3=L-2*(H-P); break;
      default:
         P=(H+L+C)/3.0; R1=2*P-L; S1=2*P-H; R2=P+range; S2=P-range; R3=H+2*(P-L); S3=L-2*(H-P); break;
     }
  }

bool ComputePivotSet(ENUM_TIMEFRAMES tf, double &out[])
  {
   double H = iHigh(_Symbol, tf, 1), L = iLow(_Symbol, tf, 1), C = iClose(_Symbol, tf, 1), O = iOpen(_Symbol, tf, 0);
   if(H <= 0 || L <= 0 || C <= 0) return false;
   double P,R1,R2,R3,S1,S2,S3;
   ComputePivots(H,L,C,O,P,R1,R2,R3,S1,S2,S3);
   out[0]=P; out[1]=R1; out[2]=R2; out[3]=R3; out[4]=S1; out[5]=S2; out[6]=S3;
   return true;
  }

void DrawHLine(string name, double price, color clr, int style, int width, string label)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,label);
  }

void UpdatePivots()
  {
   datetime cp = iTime(_Symbol, InpPivotTF, 0);
   if(cp != 0 && cp != g_lastPivotPeriod)
     {
      if(ComputePivotSet(InpPivotTF, g_levels))
        {
         if(InpShowPivots)
           {
            DrawHLine("PIV_P",  g_levels[0], clrGold,       STYLE_SOLID, 2, "Pivot");
            DrawHLine("PIV_R1", g_levels[1], clrTomato,     STYLE_DOT,   1, "R1");
            DrawHLine("PIV_R2", g_levels[2], clrTomato,     STYLE_DOT,   1, "R2");
            DrawHLine("PIV_R3", g_levels[3], clrTomato,     STYLE_DASH,  1, "R3");
            DrawHLine("PIV_S1", g_levels[4], clrDodgerBlue, STYLE_DOT,   1, "S1");
            DrawHLine("PIV_S2", g_levels[5], clrDodgerBlue, STYLE_DOT,   1, "S2");
            DrawHLine("PIV_S3", g_levels[6], clrDodgerBlue, STYLE_DASH,  1, "S3");
            ChartRedraw();
           }
         g_lastPivotPeriod = cp;
        }
     }
   if(InpUseConfluence)
     {
      datetime cp2 = iTime(_Symbol, InpPivot2TF, 0);
      if(cp2 != 0 && cp2 != g_lastPivot2Period)
         if(ComputePivotSet(InpPivot2TF, g_levels2)) g_lastPivot2Period = cp2;
     }
  }

bool IsConfluent(double levelPrice)
  {
   if(!InpUseConfluence || levelPrice <= 0) return false;
   double tol = DistanceToPrice(InpConfluenceTolUSD);
   for(int i = 0; i < g_numLevels; i++)
      if(g_levels2[i] > 0 && MathAbs(levelPrice - g_levels2[i]) <= tol) return true;
   return false;
  }

//========================= REJECTION ==============================//
double GetRSI()
  {
   double r[];
   if(rsiHandle != INVALID_HANDLE && CopyBuffer(rsiHandle, 0, 1, 1, r) >= 1) return r[0];
   return 50.0;
  }

bool CheckRejection(int &dir)
  {
   dir = 0; g_rejLevel = 0.0;
   double buf = DistanceToPrice(InpRejectionBuffer);
   double O = iOpen(_Symbol, InpSignalTF, 1), H = iHigh(_Symbol, InpSignalTF, 1);
   double L = iLow(_Symbol, InpSignalTF, 1), C = iClose(_Symbol, InpSignalTF, 1);
   if(O <= 0 || H <= 0 || L <= 0 || C <= 0) return false;

   double body = MathAbs(C - O); if(body < g_point) body = g_point;
   double upWick = H - MathMax(O, C);
   double dnWick = MathMin(O, C) - L;

   int sellVotes = 0, buyVotes = 0; double sLvl = 0, bLvl = 0;
   for(int i = 0; i < g_numLevels; i++)
     {
      double lvl = g_levels[i];
      if(lvl <= 0) continue;
      if(H >= lvl && C <= lvl - buf && C < O)
         if(!InpUseWickFilter || upWick >= InpMinWickRatio*body)
           { sellVotes++; if(sLvl==0 || MathAbs(lvl-C) < MathAbs(sLvl-C)) sLvl = lvl; }
      if(L <= lvl && C >= lvl + buf && C > O)
         if(!InpUseWickFilter || dnWick >= InpMinWickRatio*body)
           { buyVotes++; if(bLvl==0 || MathAbs(lvl-C) < MathAbs(bLvl-C)) bLvl = lvl; }
     }
   if(sellVotes > 0 && buyVotes == 0) { dir = -1; g_rejLevel = sLvl; return true; }
   if(buyVotes  > 0 && sellVotes == 0) { dir =  1; g_rejLevel = bLvl; return true; }
   return false;
  }

bool IsNewSignalBar()
  {
   datetime t = iTime(_Symbol, InpSignalTF, 0);
   if(t == 0 || t == g_lastSignalBar) return false;
   g_lastSignalBar = t;
   return true;
  }

//============================ DASHBOARD ===========================//
void DashPanel()
  {
   string obj = "DB_bg";
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,6);
      ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,22);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,C'16,20,28');
      ObjectSetInteger(0,obj,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,obj,OBJPROP_COLOR,C'70,80,100');
      ObjectSetInteger(0,obj,OBJPROP_BACK,false);
      ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,300);
   ObjectSetInteger(0,obj,OBJPROP_YSIZE,430);
  }
void DashLabel(int row, string text, color clr)
  {
   string obj = StringFormat("DB_r%02d", row);
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,14);
      ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,30 + row*16);
      ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
     }
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
   ObjectSetString(0,obj,OBJPROP_TEXT,(text=="")?" ":text);
  }
int DashSide(int r, const string name, const long posType, const int dir, const int trend)
  {
   color cText=clrSilver, cGood=clrLimeGreen, cBad=clrTomato, cWarn=clrOrange;
   CycleInfo ci;
   if(!CollectCycleDir(posType, ci)) { DashLabel(r++, name+": no cycle", cText); return r; }
   DashLabel(r++, StringFormat("%s %d/%d base %.2f P/L %+.2f", name, ci.count, InpMaxGridTrades, ci.basePrice, ci.floatPL), (dir>0)?cGood:cBad);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double moved = (dir>0)?(bid-ci.basePrice):(ci.basePrice-ask);
   if(moved >= TrailStartDist())
      DashLabel(r++, StringFormat(" SL %.2f TP %.2f  Trail ON", ci.baseSL, ci.baseTP), cGood);
   else
      DashLabel(r++, StringFormat(" SL %.2f TP %.2f  arms +%.2f/%.2f", ci.baseSL, ci.baseTP, TrailStartDist(), moved), cWarn);
   return r;
  }
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   color cText=clrSilver, cGood=clrLimeGreen, cBad=clrTomato, cWarn=clrOrange, cHead=clrGold, cDim=C'90,100,120';
   DashPanel();
   int r = 0;
   DashLabel(r++, "TrendTrailing LITE v7.0 " + _Symbol, cHead);
   MqlDateTime pt; TimeToStruct(PKTNow(), pt);
   DashLabel(r++, StringFormat("PKT %02d:%02d:%02d (srv %s) GMT:%s", pt.hour, pt.min, pt.sec,
             TimeToString(TimeCurrent(),TIME_MINUTES), (InpAutoGMT && !MQLInfoInteger(MQL_TESTER))?"auto":"man"), cText);
   bool inSes = IsWithinSession();
   DashLabel(r++, StringFormat("Session: %s (%02d-%02d PKT)", inSes?"OPEN":"CLOSED", InpStartHourPKT, InpEndHourPKT), inSes?cGood:cBad);
   bool bo = IsNewsBlackout();
   DashLabel(r++, bo?"News: BLACKOUT":"News: clear", bo?cBad:cGood);
   DashLabel(r++, "Next: " + NextNewsText(), cText);

   int trend = TrendDirection();
   string ts = (trend>0)?"UP":(trend<0)?"DOWN":"FLAT";
   DashLabel(r++, StringFormat("Trend [%s MA%d]: %s", TFName(InpTrendTF), InpMAPeriod, ts), (trend>0)?cGood:(trend<0)?cBad:cText);
   if(InpUseADX && adxHandle != INVALID_HANDLE)
     {
      double av[]; double a=0; if(CopyBuffer(adxHandle,0,1,1,av)>=1) a=av[0];
      DashLabel(r++, StringFormat("ADX %.1f (min %.0f)%s", a, InpADXThreshold, (a<InpADXThreshold)?"  CHOP":""), (a<InpADXThreshold)?cWarn:cText);
     }
   if(InpUseRSI) DashLabel(r++, StringFormat("RSI %.1f  (OS %.0f / OB %.0f)", GetRSI(), InpRSIOS, InpRSIOB), cText);

   double atr = CurrentATR();
   DashLabel(r++, StringFormat("Targets: TP %.2f SL %.2f %s", TPDist(), SLDist(), (InpUseATR && atr>0)?StringFormat("(ATR %.2f)",atr):"(fixed)"), cText);
   DashLabel(r++, StringFormat("Pivots %s  P %.2f", TFName(InpPivotTF), g_levels[0]), cText);
   int sp = SpreadPts();
   DashLabel(r++, StringFormat("Spread %d pts (max %d)", sp, InpMaxSpreadPts), (InpUseSpreadFilter && sp>InpMaxSpreadPts)?cBad:cText);

   double dpl = DailyPL();
   string halt = DailyHalt()?"  HALT":(InCooldown()?"  COOLDOWN":"");
   DashLabel(r++, StringFormat("Day P/L %+.2f (-%.0f/+%.0f)%s", dpl, InpDailyLossUSD, InpDailyProfitUSD, halt), (dpl>=0)?cGood:cBad);
   DashLabel(r++, StringFormat("Basket %+.2f (stop -%.0f)", TotalFloatPL(), InpBasketStopUSD), cText);
   DashLabel(r++, "-------------------------------", cDim);
   r = DashSide(r, "BUY",  POSITION_TYPE_BUY,  +1, trend);
   r = DashSide(r, "SELL", POSITION_TYPE_SELL, -1, trend);
   DashLabel(r++, StringFormat("Bal %.2f Eq %.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)), cText);
   ChartRedraw();
  }

void OnTimer() { UpdatePivots(); UpdateDashboard(); }

//============================ TICK ================================//
void OnTick()
  {
   DayRollover();
   UpdatePivots();
   ManageTrailing();
   ManagePartials();
   ManageStallExit();
   BasketStopCheck();
   if(InpEnableGrid) ManageGrid();

   bool newBar = IsNewSignalBar();
   UpdateDashboard();

   // ---- new-cycle entries ----
   if(!IsWithinSession() || IsNewsBlackout()) return;
   if(DailyHalt() || InCooldown()) return;
   if(InpUseSpreadFilter && !SpreadOK()) return;
   if(!newBar) return;

   int trend = TrendDirection();
   if(trend == 0) return;

   CycleInfo ci;
   long wantType = (trend > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CollectCycleDir(wantType, ci)) return;      // this direction already has a cycle

   int rej;
   if(!CheckRejection(rej) || rej != trend) return;

   // RSI confluence: buy only when not overbought, sell only when not oversold
   if(InpUseRSI)
     {
      double rsi = GetRSI();
      if(rej > 0 && rsi > InpRSIOS) return;        // buy needs oversold
      if(rej < 0 && rsi < InpRSIOB) return;        // sell needs overbought
     }

   double lots = (InpUseConfluence && IsConfluent(g_rejLevel)) ? InpConfluenceLots : InpLots;
   if(InpDebugLogs)
      PrintFormat("ENTRY %s  rejLevel %.2f  conf=%s  lots=%.2f", (trend>0?"BUY":"SELL"), g_rejLevel,
                  (IsConfluent(g_rejLevel)?"yes":"no"), lots);
   OpenTrade(trend, lots);
  }
//+------------------------------------------------------------------+
