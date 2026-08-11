//+------------------------------------------------------------------+
//|                                             TripleEMACross_EA.mq5 |
//|                                                                  |
//|  Strategy (any timeframe):                                       |
//|   - EMAs 9 / 15 / 21. When stacked bullishly (9 > 15 > 21) and    |
//|     the closed candle is a STRONG bullish candle -> BUY.          |
//|   - When stacked bearishly (9 < 15 < 21) and a STRONG bearish     |
//|     candle -> SELL.                                               |
//|   - SL = that candle's low (buy) / high (sell).                   |
//|     TP = InpRewardRatio x risk (default 2.0 => 1:2).             |
//|   - One position at a time. No pivots, no grid, no trailing.      |
//|     Runs on any TF, 24/5 except news blackout + weekend halt.     |
//|   - Dashboard, news halt (manual + MT5 calendar), weekend halt.   |
//|                                                                  |
//|  Notes (inputs):                                                |
//|   - "Strong" = body >= InpStrongBodyRatio of the candle range.   |
//|   - InpRequireFreshStack: on = trade only the bar the ribbon      |
//|     first lines up; off = trade any strong candle while aligned.  |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//============================ INPUTS ================================//
input group "=== Entry / Sizing ==="
input double             InpLots            = 0.01;          // Lot size
input long               InpMagic           = 990066;        // Magic number

input group "=== EMA Ribbon (9 / 15 / 21) ==="
input ENUM_TIMEFRAMES    InpSignalTF        = PERIOD_CURRENT;// Signal timeframe (works on any TF)
input int                InpEMAFast         = 9;             // Fast EMA
input int                InpEMAMid          = 15;            // Middle EMA
input int                InpEMASlow         = 21;            // Slow EMA
input double             InpStrongBodyRatio = 0.6;           // "Strong" = body / candle range >= this
input bool               InpRequireFreshStack = false;       // true = only on the bar the ribbon lines up

input group "=== Targets (SL at candle extreme, TP = R:R) ==="
input double             InpRewardRatio     = 2.0;           // TP = this x risk (2.0 => 1:2). Manually adjustable.
input double             InpSLBufferUSD     = 0.0;           // Extra price beyond the candle high/low for the SL

input group "=== News Filter ==="
input bool               InpUseNewsFilter   = true;          // Enable news blackout
input int                InpNewsMinsBefore  = 30;            // Stop trading this many minutes BEFORE news
input int                InpNewsMinsAfter   = 30;            // Resume this many minutes AFTER news
input string             InpManualNewsPKT   = "";            // Manual news times PKT, comma sep: "2026.07.28 17:30,..."
input bool               InpUseCalendarAuto = true;          // Also use MT5 economic calendar (live only)
input int                InpNewsImportance  = 3;             // Min importance: 1=Low 2=Moderate 3=High
input string             InpNewsCurrencies  = "USD";         // Currencies to watch (comma sep), "" = all
input int                InpBrokerGMTOffset = 0;             // Broker server GMT offset (to read manual news PKT times)

input group "=== Weekend Halt (server time) ==="
input bool               InpUseWeekendHalt  = true;          // Block new entries over the weekend
input int                InpFridayEndHourSrv = 21;           // No new entries from this server hour on Friday

input group "=== Dashboard & Debug ==="
input bool               InpShowDashboard   = true;          // Show info panel
input bool               InpDebugLogs       = false;         // Print decisions to the journal

//============================ GLOBALS ==============================//
CTrade    trade;
int       emaFastH = INVALID_HANDLE;
int       emaMidH  = INVALID_HANDLE;
int       emaSlowH = INVALID_HANDLE;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

datetime  g_newsTimes[];
datetime  g_lastSignalBar = 0;

bool      g_calBlackout   = false;
datetime  g_calLastCheck  = 0;
string    g_lastSigTxt    = "-";

//+------------------------------------------------------------------+
//| Server time -> PKT wall-clock (UTC+5) for manual news times      |
//+------------------------------------------------------------------+
datetime PKTNow()
  {
   int shiftSec = (5 - InpBrokerGMTOffset) * 3600;
   return (datetime)((long)TimeCurrent() + shiftSec);
  }

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
      if(t > 0) { int sz = ArraySize(g_newsTimes); ArrayResize(g_newsTimes, sz + 1); g_newsTimes[sz] = t; }
     }
  }

//============================ INIT ================================//
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   emaFastH = iMA(_Symbol, InpSignalTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   emaMidH  = iMA(_Symbol, InpSignalTF, InpEMAMid,  0, MODE_EMA, PRICE_CLOSE);
   emaSlowH = iMA(_Symbol, InpSignalTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   if(emaFastH == INVALID_HANDLE || emaMidH == INVALID_HANDLE || emaSlowH == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle(s)");
      return(INIT_FAILED);
     }

   ParseNewsList();
   EventSetTimer(1);

   PrintFormat("TripleEMACross | EMA %d/%d/%d on %s | RR 1:%.1f | News %d/%d min",
               InpEMAFast, InpEMAMid, InpEMASlow, TFName(InpSignalTF), InpRewardRatio,
               InpNewsMinsBefore, InpNewsMinsAfter);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(emaFastH != INVALID_HANDLE) IndicatorRelease(emaFastH);
   if(emaMidH  != INVALID_HANDLE) IndicatorRelease(emaMidH);
   if(emaSlowH != INVALID_HANDLE) IndicatorRelease(emaSlowH);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
      ObjectsDeleteAll(0, "DB_");
  }

//======================== NEWS / TIME HALTS =======================//
bool CalendarBlackout()
  {
   if(!InpUseCalendarAuto) return false;
   datetime now = TimeCurrent();
   if(now - g_calLastCheck < 60) return g_calBlackout;
   g_calLastCheck = now; g_calBlackout = false;

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
      if(now >= et - InpNewsMinsBefore*60 && now <= et + InpNewsMinsAfter*60) { g_calBlackout = true; break; }
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

bool WeekendHalt()
  {
   if(!InpUseWeekendHalt) return false;
   MqlDateTime st; TimeToStruct(TimeCurrent(), st);
   if(st.day_of_week == 0) return true;                                  // Sunday
   if(st.day_of_week == 6) return true;                                  // Saturday
   if(st.day_of_week == 5 && st.hour >= InpFridayEndHourSrv) return true; // Friday wind-down
   return false;
  }

//========================== POSITIONS =============================//
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) c++;
     }
   return c;
  }

void OpenTrade(int dir, double candleExtreme)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStop = g_stopsLevelPts * g_point;

   if(dir > 0)
     {
      double entry = ask;
      double sl = candleExtreme - InpSLBufferUSD;
      double risk = entry - sl;
      if(risk < minStop || risk <= 0)
        { if(InpDebugLogs) PrintFormat("BUY skipped: risk %.5f below min stop %.5f", risk, minStop); return; }
      double tp = entry + InpRewardRatio * risk;
      if(!trade.Buy(InpLots, _Symbol, entry, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "TripleEMA BUY"))
         PrintFormat("Buy failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else if(InpDebugLogs)
         PrintFormat("BUY entry=%.2f sl=%.2f tp=%.2f risk=%.2f", entry, sl, tp, risk);
     }
   else if(dir < 0)
     {
      double entry = bid;
      double sl = candleExtreme + InpSLBufferUSD;
      double risk = sl - entry;
      if(risk < minStop || risk <= 0)
        { if(InpDebugLogs) PrintFormat("SELL skipped: risk %.5f below min stop %.5f", risk, minStop); return; }
      double tp = entry - InpRewardRatio * risk;
      if(!trade.Sell(InpLots, _Symbol, entry, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "TripleEMA SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else if(InpDebugLogs)
         PrintFormat("SELL entry=%.2f sl=%.2f tp=%.2f risk=%.2f", entry, sl, tp, risk);
     }
  }

//============================ SIGNAL ==============================//
double EMAv(int handle, int shift)
  {
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return 0.0;
   return b[0];
  }

//+------------------------------------------------------------------+
//| Signal on the last closed candle. dir=+1 buy/-1 sell/0 none.     |
//| candleExtreme = that candle's low (buy) / high (sell) for the SL.|
//+------------------------------------------------------------------+
bool CheckSignal(int &dir, double &candleExtreme)
  {
   dir = 0;
   double O = iOpen(_Symbol,  InpSignalTF, 1);
   double H = iHigh(_Symbol,  InpSignalTF, 1);
   double L = iLow(_Symbol,   InpSignalTF, 1);
   double C = iClose(_Symbol, InpSignalTF, 1);
   if(O <= 0 || H <= 0 || L <= 0 || C <= 0) return false;

   double range = H - L;
   if(range <= 0) return false;
   double body = MathAbs(C - O);
   bool strongBull = (C > O) && (body / range) >= InpStrongBodyRatio;
   bool strongBear = (O > C) && (body / range) >= InpStrongBodyRatio;
   if(!strongBull && !strongBear) return false;

   double e9  = EMAv(emaFastH, 1);
   double e15 = EMAv(emaMidH,  1);
   double e21 = EMAv(emaSlowH, 1);
   if(e9 <= 0 || e15 <= 0 || e21 <= 0) return false;

   bool bullStack = (e9 > e15 && e15 > e21);   // 9 top, 15 middle, 21 bottom
   bool bearStack = (e9 < e15 && e15 < e21);   // 9 bottom, 15 middle, 21 top

   // Optional: only fire on the bar the ribbon first lines up
   if(InpRequireFreshStack)
     {
      double p9 = EMAv(emaFastH, 2), p15 = EMAv(emaMidH, 2), p21 = EMAv(emaSlowH, 2);
      bool bullPrev = (p9 > p15 && p15 > p21);
      bool bearPrev = (p9 < p15 && p15 < p21);
      if(bullStack && bullPrev) bullStack = false;   // not fresh
      if(bearStack && bearPrev) bearStack = false;
     }

   if(bullStack && strongBull) { dir =  1; candleExtreme = L; g_lastSigTxt = "BUY "  + TimeToString(iTime(_Symbol,InpSignalTF,1),TIME_MINUTES); return true; }
   if(bearStack && strongBear) { dir = -1; candleExtreme = H; g_lastSigTxt = "SELL " + TimeToString(iTime(_Symbol,InpSignalTF,1),TIME_MINUTES); return true; }
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
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, 236);
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
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   color cText = clrSilver, cGood = clrLimeGreen, cBad = clrTomato, cWarn = clrOrange, cHead = clrGold, cDim = C'90,100,120';
   DashPanel();
   int r = 0;
   DashLabel(r++, "TripleEMACross v1.0  " + _Symbol, cHead);
   DashLabel(r++, StringFormat("Server %s  (%s)", TimeToString(TimeCurrent(), TIME_MINUTES), TFName(InpSignalTF)), cText);

   bool news = IsNewsBlackout();
   bool wknd = WeekendHalt();
   DashLabel(r++, news ? "News: BLACKOUT" : "News: clear", news ? cBad : cGood);
   DashLabel(r++, wknd ? "Weekend halt: ON" : "Weekend halt: off", wknd ? cWarn : cGood);

   double e9 = EMAv(emaFastH, 1), e15 = EMAv(emaMidH, 1), e21 = EMAv(emaSlowH, 1);
   string stack = (e9 > e15 && e15 > e21) ? "BULL (9>15>21)" :
                  (e9 < e15 && e15 < e21) ? "BEAR (9<15<21)" : "mixed";
   DashLabel(r++, "Ribbon: " + stack, (e9 > e15 && e15 > e21) ? cGood : (e9 < e15 && e15 < e21) ? cBad : cText);
   DashLabel(r++, StringFormat("EMA %.2f / %.2f / %.2f", e9, e15, e21), cText);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DashLabel(r++, StringFormat("Spread: %d pts   RR 1:%.1f", (int)MathRound((ask - bid)/g_point), InpRewardRatio), cText);
   DashLabel(r++, "Last signal: " + g_lastSigTxt, cText);
   DashLabel(r++, "-------------------------------", cDim);

   if(CountPositions() > 0)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         long ty = PositionGetInteger(POSITION_TYPE);
         DashLabel(r++, StringFormat("%s %.2f @ %.2f  SL %.2f TP %.2f  P/L %+.2f",
                   ty == POSITION_TYPE_BUY ? "BUY" : "SELL", PositionGetDouble(POSITION_VOLUME),
                   PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL),
                   PositionGetDouble(POSITION_TP), PositionGetDouble(POSITION_PROFIT)),
                   ty == POSITION_TYPE_BUY ? cGood : cBad);
         break;
        }
     }
   else
      DashLabel(r++, "Position: flat (waiting for ribbon)", cText);

   DashLabel(r++, StringFormat("Bal %.2f  Eq %.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)), cText);
   ChartRedraw();
  }

void OnTimer() { UpdateDashboard(); }

//============================ TICK ================================//
void OnTick()
  {
   bool newBar = IsNewSignalBar();
   UpdateDashboard();

   if(IsNewsBlackout() || WeekendHalt()) return;   // 24/5 minus news minus weekend
   if(CountPositions() > 0) return;                 // one position at a time
   if(!newBar) return;                              // act on candle close only

   int dir; double ext;
   if(CheckSignal(dir, ext))
      OpenTrade(dir, ext);
  }
//+------------------------------------------------------------------+
