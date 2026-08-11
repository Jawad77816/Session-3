//+------------------------------------------------------------------+
//|                                              PivotEMACross_EA.mq5 |
//|                                                                  |
//|  Strategy (M5):                                                  |
//|   - A STRONG bullish candle that crosses BOTH the Fibonacci      |
//|     Pivot (P) and the 9-EMA upward and closes  -> BUY.           |
//|   - A STRONG bearish candle that crosses BOTH the Pivot (P) and  |
//|     the 9-EMA downward and closes              -> SELL.          |
//|   - SL = that crossing candle's low (buy) / high (sell).         |
//|     TP = InpRewardRatio x risk (default 2.0 => 1:2).             |
//|   - One position at a time. No grid, no HTF trend filter, no     |
//|     trailing. Runs 24/5 except news blackout + weekend halt.     |
//|   - Dashboard, news halt (manual + MT5 calendar), weekend halt.  |
//|                                                                  |
//|  Reconstruction / judgment calls (all are inputs):              |
//|   - "Strong" = body >= InpStrongBodyRatio of the candle range.   |
//|   - "The pivot point" = the central Fibonacci Pivot (P).         |
//|   - Cross = candle opens on one side of a level and closes on    |
//|     the other. InpRequireCrossBoth toggles whether the EMA must  |
//|     be crossed too, or only closed beyond.                       |
//|   - Pivots "Auto" on an intraday chart = Daily (InpPivotTF).     |
//+------------------------------------------------------------------+
#property copyright "Session-3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- Pivot calculation method
enum ENUM_PIVOT_METHOD
  {
   PIVOT_STANDARD  = 0,   // Classic / Floor pivots
   PIVOT_FIBONACCI = 1,   // Fibonacci pivots
   PIVOT_CAMARILLA = 2,   // Camarilla pivots
   PIVOT_WOODIE    = 3    // Woodie pivots
  };

//============================ INPUTS ================================//
input group "=== Entry / Sizing ==="
input double             InpLots            = 0.01;          // Lot size
input long               InpMagic           = 990055;        // Magic number

input group "=== Signal (candle cross of Pivot + EMA) ==="
input ENUM_TIMEFRAMES    InpSignalTF        = PERIOD_CURRENT;// Signal timeframe (apply on M5)
input int                InpEMAPeriod       = 9;             // EMA length
input double             InpStrongBodyRatio = 0.6;           // "Strong" = body / candle range >= this
input bool               InpRequireCrossBoth = true;         // Candle must cross BOTH P and EMA (off = cross P, close beyond EMA)

input group "=== Targets (SL at candle extreme, TP = R:R) ==="
input double             InpRewardRatio     = 2.0;           // TP = this x risk (2.0 => 1:2). Manually adjustable.
input double             InpSLBufferUSD     = 0.0;           // Extra price beyond the candle high/low for the SL

input group "=== Pivot Points ==="
input bool               InpShowPivots      = true;          // Draw pivot lines
input ENUM_PIVOT_METHOD  InpPivotMethod     = PIVOT_FIBONACCI;// Pivot type
input ENUM_TIMEFRAMES    InpPivotTF         = PERIOD_D1;     // Pivot timeframe (Auto for intraday = Daily)
input int                InpPivotsBack      = 15;            // Number of past pivot periods to draw

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
int       emaHandle = INVALID_HANDLE;
double    g_point;
int       g_digits;
long      g_stopsLevelPts;

datetime  g_newsTimes[];
datetime  g_lastPivotPeriod = 0;
datetime  g_lastSignalBar   = 0;

double    g_levels[7];          // P, R1, R2, R3, S1, S2, S3 (current period, for the signal)
int       g_numLevels = 7;

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

//+------------------------------------------------------------------+
//| Parse the manual news list                                       |
//+------------------------------------------------------------------+
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

   emaHandle = iMA(_Symbol, InpSignalTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle");
      return(INIT_FAILED);
     }

   ArrayInitialize(g_levels, 0.0);
   ParseNewsList();
   EventSetTimer(1);

   PrintFormat("PivotEMACross | EMA%d on %s | Pivots %s x%d | RR 1:%.1f | News %d/%d min",
               InpEMAPeriod, TFName(InpSignalTF), TFName(InpPivotTF), InpPivotsBack,
               InpRewardRatio, InpNewsMinsBefore, InpNewsMinsAfter);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
     {
      ObjectsDeleteAll(0, "PIV_");
      ObjectsDeleteAll(0, "DB_");
     }
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

//+------------------------------------------------------------------+
//| Open a trade with an explicit SL price; TP = RR x risk           |
//+------------------------------------------------------------------+
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
      if(!trade.Buy(InpLots, _Symbol, entry, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "CrossEMA BUY"))
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
      if(!trade.Sell(InpLots, _Symbol, entry, NormalizeDouble(sl, g_digits), NormalizeDouble(tp, g_digits), "CrossEMA SELL"))
         PrintFormat("Sell failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else if(InpDebugLogs)
         PrintFormat("SELL entry=%.2f sl=%.2f tp=%.2f risk=%.2f", entry, sl, tp, risk);
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

void DrawSeg(string name, datetime t1, datetime t2, double price, color clr, int style, int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, name, 0, t1, price);
   ObjectMove(0, name, 1, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Recompute pivots on a new pivot period; draw N periods back      |
//+------------------------------------------------------------------+
void UpdatePivots()
  {
   datetime cur = iTime(_Symbol, InpPivotTF, 0);
   if(cur == 0 || cur == g_lastPivotPeriod) return;

   // current period's levels (from the previous completed period) drive the signal
   double H1 = iHigh(_Symbol, InpPivotTF, 1), L1 = iLow(_Symbol, InpPivotTF, 1);
   double C1 = iClose(_Symbol, InpPivotTF, 1), O1 = iOpen(_Symbol, InpPivotTF, 0);
   if(H1 > 0 && L1 > 0 && C1 > 0)
     {
      double P,R1,R2,R3,S1,S2,S3;
      ComputePivots(H1, L1, C1, O1, P, R1, R2, R3, S1, S2, S3);
      g_levels[0]=P; g_levels[1]=R1; g_levels[2]=R2; g_levels[3]=R3; g_levels[4]=S1; g_levels[5]=S2; g_levels[6]=S3;
     }

   if(InpShowPivots)
     {
      ObjectsDeleteAll(0, "PIV_");
      int n = (int)MathMax(1, InpPivotsBack);
      for(int i = 0; i < n; i++)
        {
         double H = iHigh(_Symbol, InpPivotTF, i + 1), L = iLow(_Symbol, InpPivotTF, i + 1);
         double C = iClose(_Symbol, InpPivotTF, i + 1), O = iOpen(_Symbol, InpPivotTF, i);
         if(H <= 0 || L <= 0 || C <= 0) continue;
         double P,R1,R2,R3,S1,S2,S3;
         ComputePivots(H, L, C, O, P, R1, R2, R3, S1, S2, S3);
         datetime t1 = iTime(_Symbol, InpPivotTF, i);
         datetime t2 = (i == 0) ? (cur + PeriodSeconds(InpPivotTF)) : iTime(_Symbol, InpPivotTF, i - 1);
         string pre = "PIV_" + (string)i + "_";
         DrawSeg(pre+"P",  t1, t2, P,  clrGold,       STYLE_SOLID, 2);
         DrawSeg(pre+"R1", t1, t2, R1, clrTomato,     STYLE_DOT,   1);
         DrawSeg(pre+"R2", t1, t2, R2, clrTomato,     STYLE_DOT,   1);
         DrawSeg(pre+"R3", t1, t2, R3, clrTomato,     STYLE_DASH,  1);
         DrawSeg(pre+"S1", t1, t2, S1, clrDodgerBlue, STYLE_DOT,   1);
         DrawSeg(pre+"S2", t1, t2, S2, clrDodgerBlue, STYLE_DOT,   1);
         DrawSeg(pre+"S3", t1, t2, S3, clrDodgerBlue, STYLE_DASH,  1);
        }
      ChartRedraw();
     }

   g_lastPivotPeriod = cur;
  }

//============================ SIGNAL ==============================//
double EMA(int shift)
  {
   double b[];
   if(CopyBuffer(emaHandle, 0, shift, 1, b) < 1) return 0.0;
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
   bool strong = (body / range) >= InpStrongBodyRatio;
   if(!strong) return false;

   double e = EMA(1);
   double P = g_levels[0];
   if(e <= 0 || P <= 0) return false;

   bool bull = (C > O), bear = (O > C);
   bool crossUpP   = (O < P && C > P);
   bool crossUpE   = (O < e && C > e);
   bool crossDnP   = (O > P && C < P);
   bool crossDnE   = (O > e && C < e);

   bool buy  = bull && crossUpP && (InpRequireCrossBoth ? crossUpE : (C > e));
   bool sell = bear && crossDnP && (InpRequireCrossBoth ? crossDnE : (C < e));

   if(buy)  { dir =  1; candleExtreme = L; g_lastSigTxt = "BUY cross " + TimeToString(iTime(_Symbol,InpSignalTF,1),TIME_MINUTES); return true; }
   if(sell) { dir = -1; candleExtreme = H; g_lastSigTxt = "SELL cross " + TimeToString(iTime(_Symbol,InpSignalTF,1),TIME_MINUTES); return true; }
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
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, 240);
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
   DashLabel(r++, "PivotEMACross v1.0  " + _Symbol, cHead);
   DashLabel(r++, StringFormat("Server %s  (%s)", TimeToString(TimeCurrent(), TIME_MINUTES), TFName(InpSignalTF)), cText);

   bool news = IsNewsBlackout();
   bool wknd = WeekendHalt();
   DashLabel(r++, news ? "News: BLACKOUT" : "News: clear", news ? cBad : cGood);
   DashLabel(r++, wknd ? "Weekend halt: ON" : "Weekend halt: off", wknd ? cWarn : cGood);

   double e = EMA(1);
   DashLabel(r++, StringFormat("EMA%d: %.2f   Pivot P: %.2f", InpEMAPeriod, e, g_levels[0]), cText);
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
      DashLabel(r++, "Position: flat (waiting for cross)", cText);

   DashLabel(r++, StringFormat("Bal %.2f  Eq %.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)), cText);
   ChartRedraw();
  }

void OnTimer() { UpdatePivots(); UpdateDashboard(); }

//============================ TICK ================================//
void OnTick()
  {
   UpdatePivots();
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
