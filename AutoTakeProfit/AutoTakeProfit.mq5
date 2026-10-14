//+------------------------------------------------------------------+
//|                                              AutoTakeProfit.mq5   |
//|                                                                   |
//|   A manual-trading assistant for MT5 (built for Exness / XAUUSD): |
//|                                                                   |
//|   1) AUTO TAKE PROFIT - the moment you open a trade by hand, a    |
//|      Take Profit is placed a fixed number of pips from your entry |
//|      (default 10 pips -> Buy 4000 gets TP 4001).                  |
//|                                                                   |
//|   2) DAILY LIMITS - set a daily profit target and/or daily loss   |
//|      limit (in account currency). When either is reached the EA   |
//|      stops you taking new trades for the rest of the day.         |
//|      Both = 0  ->  no limit that day.                             |
//|                                                                   |
//|   3) HIGH-IMPACT NEWS BLOCK - no new trades 30 min before and     |
//|      30 min after high-impact news (NFP, CPI, FOMC, PCE, GDP...). |
//|      Trades already open BEFORE the window are left running.      |
//|      News comes from the MT5 economic calendar or Forex Factory.  |
//|                                                                   |
//|   4) DASHBOARD - a clean on-chart panel showing balance, equity,  |
//|      floating P/L, daily P/L vs limits, trading status and the    |
//|      next high-impact news.                                       |
//|                                                                   |
//|   NOTE: An EA cannot stop MT5's manual order window from firing.  |
//|   It "blocks" a trade by CLOSING it instantly after it opens      |
//|   inside a blocked window, and alerts you.                        |
//+------------------------------------------------------------------+
#property copyright "AutoTakeProfit"
#property version   "2.00"
#property description "Auto 10-pip Take Profit on manual trades, plus daily profit/loss limits, high-impact news blocking (MT5 calendar or Forex Factory) and an on-chart dashboard."

#include <Trade\Trade.mqh>

//--- news source selector
enum ENUM_NEWS_SOURCE
{
   NEWS_MT5_CALENDAR = 0,   // MT5 built-in economic calendar (recommended, no setup)
   NEWS_FOREX_FACTORY = 1   // Forex Factory feed (needs WebRequest whitelist)
};

//==================================================================
input group "========== TAKE PROFIT / STOP LOSS =========="
input double InpTakeProfitPips = 10.0;   // Take Profit in pips (0 = do NOT set a TP)
input double InpStopLossPips   = 0.0;    // Stop Loss in pips   (0 = do NOT set a SL)
input int    InpPointsPerPip   = 0;      // Points per pip (0 = auto; see README)
input bool   InpApplyToBuy     = true;   // Manage Buy positions
input bool   InpApplyToSell    = true;   // Manage Sell positions
input bool   InpOnlyIfNoTP     = true;   // Only add a TP when the position has none

input group "========== DAILY LIMITS (account currency; 0 & 0 = no limit) =========="
input double InpDailyProfitTarget = 0.0;   // Daily profit target - stop trading after +this (0 = off)
input double InpDailyLossLimit    = 0.0;   // Daily loss limit - stop trading after -this (0 = off)
input bool   InpCloseAllOnLimit   = false; // Also CLOSE all open trades when a daily limit is hit

input group "========== HIGH-IMPACT NEWS BLOCK =========="
input bool            InpBlockNews     = true;              // Block new trades around high-impact news
input int             InpMinutesBefore = 30;                // Block this many minutes BEFORE news
input int             InpMinutesAfter  = 30;                // Block this many minutes AFTER news
input ENUM_NEWS_SOURCE InpNewsSource   = NEWS_MT5_CALENDAR; // News data source
input string          InpNewsCurrencies= "USD";             // Currencies to watch (comma list, or ALL)
input int             InpNewsRefreshMin= 15;                // Refresh MT5-calendar list every N minutes

input group "========== FOREX FACTORY (only if source = Forex Factory) =========="
input double InpFF_GmtOffsetHours = 0.0;   // GMT offset of Forex Factory times (VERIFY vs the website!)
input int    InpFF_RefreshMin     = 60;    // Re-download the FF feed every N minutes (min 5)

input group "========== DASHBOARD =========="
input bool InpShowDashboard = true;        // Show the on-chart dashboard
input int  InpDashX         = 14;          // Dashboard X (pixels from left)
input int  InpDashY         = 26;          // Dashboard Y (pixels from top)

input group "========== MISC =========="
input bool InpVerbose     = true;    // Print actions to the Experts log
input bool InpAlerts      = true;    // Pop up an alert when a trade is blocked / limit hit
input long InpMagicFilter = -1;      // Only manage this magic (-1 = all, includes manual trades)
input int  InpSymbolScope = 0;       // Positions to manage: 0 = this chart only, 1 = ALL symbols

//==================================================================
//  Globals
//==================================================================
CTrade   trade;
ulong    g_failed[];          // tickets we already failed to MODIFY (avoid log spam)

// news events (times stored in SERVER time)
datetime g_evTime[];
string   g_evName[];
string   g_evCur[];
int      g_newsLoaded   = 0;
bool     g_ffError      = false;
datetime g_lastNewsFetch= 0;

// news window state (recomputed each evaluation)
bool     g_newsActive   = false;
datetime g_newsStart    = 0;
string   g_newsName      = "";
datetime g_nextTime     = 0;
string   g_nextName      = "";

// daily P/L state
datetime g_dayStart       = 0;
double   g_dailyPL        = 0.0;
double   g_realizedToday  = 0.0;
double   g_floating       = 0.0;
bool     g_dailyLatched   = false;   // sticky for the rest of the day once a limit is hit
datetime g_dailyBlockStart= 0;
string   g_dailyReason    = "";

// dashboard palette
#define PFX "ATP_"
#define COL_PANEL  C'28,33,45'
#define COL_BORDER C'46,54,70'
#define COL_HEAD   C'36,118,221'
#define COL_TEXT   C'228,232,240'
#define COL_MUTE   C'140,151,168'
#define COL_GREEN  C'38,194,129'
#define COL_RED    C'233,80,96'
#define COL_AMBER  C'240,176,64'

//==================================================================
//  Initialization
//==================================================================
int OnInit()
{
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   EventSetTimer(1);   // drives news refresh + evaluation even without ticks

   if(InpTakeProfitPips <= 0 && InpStopLossPips <= 0)
      Print("AutoTakeProfit: note - both TP and SL are 0, no targets will be set.");

   // Concrete example on the current symbol so you can verify the pip maths.
   const int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double pip     = PipSize(_Symbol);
   PrintFormat("AutoTakeProfit v2 on %s | 1 pip = %s | TP %.1f pips = %s",
               _Symbol, DoubleToString(pip, digits), InpTakeProfitPips,
               DoubleToString(InpTakeProfitPips * pip, digits));
   if(InpTakeProfitPips > 0)
      PrintFormat("Example: BUY at %s -> TP %s   |   SELL at %s -> TP %s",
                  DoubleToString(4000.0, digits), DoubleToString(4000.0 + InpTakeProfitPips*pip, digits),
                  DoubleToString(4000.0, digits), DoubleToString(4000.0 - InpTakeProfitPips*pip, digits));

   // Load news now so the dashboard is populated. WebRequest is not allowed
   // from OnInit, so the Forex Factory fetch is left to the first timer tick.
   if(InpNewsSource == NEWS_MT5_CALENDAR)
      RefreshNews();

   // Draw an initial dashboard without touching trades (management starts on
   // the first tick / timer, once the terminal is fully ready).
   CheckNewDay();
   ComputeDailyPL();
   UpdateNewsWindow();
   if(InpShowDashboard)
      UpdateDashboard();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
}

//==================================================================
//  Triggers
//==================================================================
void OnTick()
{
   Evaluate();
}

void OnTimer()
{
   RefreshNewsIfDue();
   Evaluate();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)   // a trade just filled -> react now
      Evaluate();
}

//==================================================================
//  One evaluation pass
//==================================================================
void Evaluate()
{
   CheckNewDay();
   ComputeDailyPL();
   UpdateDailyLatch();
   UpdateNewsWindow();
   ManagePositions();
   if(InpShowDashboard)
      UpdateDashboard();
}

//------------------------------------------------------------------
//  Pip size for a symbol (see README for the gold note)
//------------------------------------------------------------------
double PipSize(const string sym)
{
   const int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   const double point  = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(InpPointsPerPip > 0)
      return InpPointsPerPip * point;

   string u = sym;
   StringToUpper(u);
   const bool metal = (StringFind(u,"XAU")>=0 || StringFind(u,"GOLD")>=0 ||
                       StringFind(u,"XAG")>=0 || StringFind(u,"SILVER")>=0);
   if(metal)
      return (digits >= 3) ? 100 * point : 10 * point;   // -> 1 pip = 0.10 on gold

   if(digits == 3 || digits == 5)
      return 10 * point;
   return point;
}

//==================================================================
//  DAILY P/L  +  LIMIT LATCH
//==================================================================
datetime StartOfDay(const datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

void CheckNewDay()
{
   const datetime ds = StartOfDay(TimeTradeServer());
   if(ds != g_dayStart)
   {
      g_dayStart        = ds;
      g_dailyLatched    = false;
      g_dailyBlockStart = 0;
      g_dailyReason     = "";
   }
}

double RealizedToday()
{
   const datetime from = g_dayStart;
   if(!HistorySelect(from, TimeTradeServer() + 1))
      return 0.0;

   double sum = 0.0;
   const int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      const ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      const long dt = HistoryDealGetInteger(t, DEAL_TYPE);
      if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL) continue;   // skip deposits etc.
      sum += HistoryDealGetDouble(t, DEAL_PROFIT)
           + HistoryDealGetDouble(t, DEAL_SWAP)
           + HistoryDealGetDouble(t, DEAL_COMMISSION);
   }
   return sum;
}

void ComputeDailyPL()
{
   g_realizedToday = RealizedToday();
   g_floating      = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyPL       = g_realizedToday + g_floating;   // net result since server midnight
}

void UpdateDailyLatch()
{
   if(g_dailyLatched)
      return;

   bool hit = false;
   if(InpDailyProfitTarget > 0 && g_dailyPL >= InpDailyProfitTarget)
   { g_dailyReason = "DAILY TARGET"; hit = true; }
   else if(InpDailyLossLimit > 0 && g_dailyPL <= -InpDailyLossLimit)
   { g_dailyReason = "DAILY LOSS LIMIT"; hit = true; }

   if(hit)
   {
      g_dailyLatched    = true;
      g_dailyBlockStart = TimeTradeServer();
      Notify(StringFormat("%s reached (%s). New trades are blocked for the rest of the day.",
                          g_dailyReason, MoneyStr(g_dailyPL)));
   }
}

//==================================================================
//  NEWS WINDOW
//==================================================================
void UpdateNewsWindow()
{
   g_newsActive = false;
   g_newsStart  = 0;
   g_newsName    = "";
   g_nextTime   = 0;
   g_nextName    = "";

   const datetime now = TimeTradeServer();
   const int n = ArraySize(g_evTime);
   for(int i = 0; i < n; i++)
   {
      const datetime ws = g_evTime[i] - InpMinutesBefore * 60;
      const datetime we = g_evTime[i] + InpMinutesAfter  * 60;

      if(InpBlockNews && now >= ws && now <= we)
      {
         if(!g_newsActive || ws < g_newsStart)
         {
            g_newsActive = true;
            g_newsStart  = ws;
            g_newsName    = g_evName[i];
         }
      }

      if(g_evTime[i] >= now && (g_nextTime == 0 || g_evTime[i] < g_nextTime))
      {
         g_nextTime = g_evTime[i];
         g_nextName  = g_evName[i];
      }
   }
}

bool TradingBlocked()
{
   return (g_newsActive || g_dailyLatched);
}

//==================================================================
//  POSITION / ORDER MANAGEMENT
//==================================================================
bool InScope(const string sym)       { return (InpSymbolScope == 1 || sym == _Symbol); }
bool MagicOk(const long magic)        { return (InpMagicFilter < 0 || magic == InpMagicFilter); }

// should a position opened at posTime be force-closed by a block?
bool ShouldClose(const datetime posTime)
{
   if(g_dailyLatched && InpCloseAllOnLimit)              return true;   // hard stop
   if(g_newsActive   && posTime >= g_newsStart)          return true;   // opened inside news window
   if(g_dailyLatched && posTime >= g_dailyBlockStart)    return true;   // opened after limit hit
   return false;
}

void ManagePositions()
{
   // 1) Delete pending orders placed during a block
   if(TradingBlocked())
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         const ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(!InScope(OrderGetString(ORDER_SYMBOL)))        continue;
         if(!MagicOk(OrderGetInteger(ORDER_MAGIC)))         continue;
         const datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if((g_newsActive   && setup >= g_newsStart) ||
            (g_dailyLatched && setup >= g_dailyBlockStart) ||
            (g_dailyLatched && InpCloseAllOnLimit))
         {
            if(trade.OrderDelete(tk))
               Notify(StringFormat("Pending order #%I64u deleted - %s.", tk, BlockReason()));
         }
      }
   }

   // 2) Positions: close if blocked, otherwise apply TP/SL
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      const string sym = PositionGetString(POSITION_SYMBOL);
      if(!InScope(sym))                               continue;
      if(!MagicOk(PositionGetInteger(POSITION_MAGIC)))continue;

      const long     type    = PositionGetInteger(POSITION_TYPE);
      const datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(ShouldClose(posTime))
      {
         if(trade.PositionClose(ticket))
            Notify(StringFormat("Trade #%I64u (%s) CLOSED - %s.", ticket, sym, BlockReason()));
         else
            PrintFormat("AutoTakeProfit: could not close #%I64u, retcode=%u (%s)",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         continue;
      }

      // not blocked -> normal auto TP/SL
      if(type == POSITION_TYPE_BUY  && !InpApplyToBuy)   continue;
      if(type == POSITION_TYPE_SELL && !InpApplyToSell)  continue;

      const double curTP = PositionGetDouble(POSITION_TP);
      const double curSL = PositionGetDouble(POSITION_SL);
      if(InpOnlyIfNoTP && curTP != 0.0) continue;
      if(AlreadyFailed(ticket))          continue;

      ApplyTpSl(ticket, sym, type, curSL, curTP);
   }
}

string BlockReason()
{
   if(g_dailyLatched) return g_dailyReason;
   if(g_newsActive)   return "news window: " + g_newsName;
   return "trading blocked";
}

//------------------------------------------------------------------
//  Compute + apply TP/SL for one position (unchanged core logic)
//------------------------------------------------------------------
void ApplyTpSl(const ulong ticket, const string sym, const long type,
               const double curSL, const double curTP)
{
   const int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   const double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   const double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   const double pip    = PipSize(sym);

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

   const double tol = point / 2.0;
   const bool tpChanged = (InpTakeProfitPips > 0 && MathAbs(newTP - curTP) > tol);
   const bool slChanged = (InpStopLossPips   > 0 && MathAbs(newSL - curSL) > tol);
   if(!tpChanged && !slChanged)
      return;

   const double stopsLvl = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   const double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   const double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   if(InpTakeProfitPips > 0)
   {
      const bool tooClose = (type == POSITION_TYPE_BUY  && newTP <= bid + stopsLvl) ||
                            (type == POSITION_TYPE_SELL && newTP >= ask - stopsLvl);
      if(tooClose)
      {
         if(InpVerbose)
            PrintFormat("AutoTakeProfit: skip #%I64u (%s) - TP %s too close to price (min stop %s).",
                        ticket, sym, DoubleToString(newTP, digits), DoubleToString(stopsLvl, digits));
         MarkFailed(ticket);
         return;
      }
   }
   if(InpStopLossPips > 0)
   {
      const bool tooClose = (type == POSITION_TYPE_BUY  && newSL >= bid - stopsLvl) ||
                            (type == POSITION_TYPE_SELL && newSL <= ask + stopsLvl);
      if(tooClose)
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
         PrintFormat("AutoTakeProfit: #%I64u (%s) %s @ %s -> SL %s / TP %s",
                     ticket, sym, (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     DoubleToString(open, digits), DoubleToString(newSL, digits),
                     DoubleToString(newTP, digits));
   }
   else
   {
      PrintFormat("AutoTakeProfit: FAILED to modify #%I64u (%s). retcode=%u (%s)",
                  ticket, sym, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      MarkFailed(ticket);
   }
}

bool AlreadyFailed(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_failed); i++)
      if(g_failed[i] == ticket) return true;
   return false;
}
void MarkFailed(const ulong ticket)
{
   const int n = ArraySize(g_failed);
   ArrayResize(g_failed, n + 1);
   g_failed[n] = ticket;
}

//==================================================================
//  NEWS LOADING
//==================================================================
void ClearEvents()
{
   ArrayResize(g_evTime, 0);
   ArrayResize(g_evName, 0);
   ArrayResize(g_evCur,  0);
}
void PushEvent(const datetime t, const string name, const string cur)
{
   const int n = ArraySize(g_evTime);
   ArrayResize(g_evTime, n + 1);
   ArrayResize(g_evName, n + 1);
   ArrayResize(g_evCur,  n + 1);
   g_evTime[n] = t; g_evName[n] = name; g_evCur[n] = cur;
}

bool CurrencyWatched(const string cur)
{
   string f = InpNewsCurrencies;
   StringToUpper(f);
   if(StringFind(f, "ALL") >= 0) return true;

   string c = cur; StringToUpper(c);
   if(c == "" || c == "ALL") return false;

   string parts[];
   const int k = StringSplit(f, ',', parts);
   for(int i = 0; i < k; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(p == c) return true;
   }
   return false;
}

void RefreshNewsIfDue()
{
   const datetime now = TimeTradeServer();
   int refresh = (InpNewsSource == NEWS_FOREX_FACTORY) ? InpFF_RefreshMin : InpNewsRefreshMin;
   int minv    = (InpNewsSource == NEWS_FOREX_FACTORY) ? 5 : 1;
   int due     = (refresh < minv) ? minv : refresh;
   if(g_lastNewsFetch == 0 || (now - g_lastNewsFetch) >= due * 60)
      RefreshNews();
}

void RefreshNews()
{
   if(InpNewsSource == NEWS_FOREX_FACTORY)
      RefreshNewsFF();
   else
      RefreshNewsMT5();
   g_lastNewsFetch = TimeTradeServer();
   g_newsLoaded    = ArraySize(g_evTime);
}

//--- MT5 built-in economic calendar (times already in SERVER time) --
void RefreshNewsMT5()
{
   ClearEvents();

   MqlCalendarValue values[];
   const datetime from = TimeTradeServer() - 24 * 3600;
   const datetime to   = TimeTradeServer() + 7 * 24 * 3600;
   const int count = CalendarValueHistory(values, from, to);
   if(count <= 0)
      return;   // calendar empty / unavailable (e.g. Strategy Tester)

   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

      string cur = "";
      MqlCalendarCountry country;
      if(CalendarCountryById(ev.country_id, country))
         cur = country.currency;
      if(!CurrencyWatched(cur)) continue;

      PushEvent(values[i].time, ev.name, cur);
   }
}

//--- Forex Factory weekly feed (times in InpFF_GmtOffsetHours tz) ----
void RefreshNewsFF()
{
   g_ffError = false;
   ClearEvents();

   uchar  post[];
   uchar  result[];
   string headers;
   const string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";

   ResetLastError();
   const int r = WebRequest("GET", url, NULL, NULL, 7000, post, 0, result, headers);
   if(r == -1)
   {
      g_ffError = true;
      const int e = GetLastError();
      Notify(StringFormat("Forex Factory blocked (err %d). Add %s to Tools>Options>Expert Advisors WebRequest list.", e, url));
      return;
   }
   if(r != 200)
   {
      g_ffError = true;
      if(InpVerbose) PrintFormat("AutoTakeProfit: FF HTTP status %d", r);
      return;
   }

   const string page = CharArrayToString(result, 0, WHOLE_ARRAY, CP_ACP);
   if(StringFind(page, "DOCTYPE") >= 0)   // rate-limited -> HTML page instead of XML
   {
      g_ffError = true;
      if(InpVerbose) Print("AutoTakeProfit: FF returned HTML (rate limited). Will retry later.");
      return;
   }

   int pos = 0;
   while(true)
   {
      const int a = StringFind(page, "<event>", pos);
      if(a < 0) break;
      const int b = StringFind(page, "</event>", a);
      if(b < 0) break;
      const string blk = StringSubstr(page, a, b - a);
      pos = b + 8;

      if(GetTag(blk, "impact") != "High") continue;
      const string cur = GetTag(blk, "country");
      if(!CurrencyWatched(cur)) continue;

      datetime et;
      if(!ParseFFDateTime(GetTag(blk, "date"), GetTag(blk, "time"), et)) continue;
      PushEvent(et, GetTag(blk, "title"), cur);
   }
}

string GetTag(const string block, const string tag)
{
   const string op = "<" + tag + ">";
   const string cl = "</" + tag + ">";
   int a = StringFind(block, op);
   if(a < 0) return "";
   a += StringLen(op);
   const int b = StringFind(block, cl, a);
   if(b < 0) return "";
   string v = StringSubstr(block, a, b - a);

   const int ca = StringFind(v, "<![CDATA[");
   if(ca >= 0)
   {
      const int s = ca + 9;
      const int e = StringFind(v, "]]>", s);
      if(e >= 0) v = StringSubstr(v, s, e - s);
   }
   StringTrimLeft(v); StringTrimRight(v);
   return v;
}

bool ParseFFDateTime(string d, string t, datetime &out)
{
   out = 0;
   string tl = t; StringToLower(tl);
   if(t == "" || StringFind(tl,"all")>=0 || StringFind(tl,"tentative")>=0 || StringFind(tl,"day")>=0)
      return false;   // no precise time -> cannot build a window

   string dp[];
   if(StringSplit(d, '-', dp) != 3) return false;
   const int mm = (int)StringToInteger(dp[0]);
   const int dd = (int)StringToInteger(dp[1]);
   const int yy = (int)StringToInteger(dp[2]);

   const bool pm = (StringFind(tl, "pm") >= 0);
   StringReplace(tl, "am", "");
   StringReplace(tl, "pm", "");
   string tp[];
   if(StringSplit(tl, ':', tp) != 2) return false;
   int hh = (int)StringToInteger(tp[0]);
   const int mi = (int)StringToInteger(tp[1]);
   if(pm && hh < 12) hh += 12;
   if(!pm && hh == 12) hh = 0;

   MqlDateTime s;
   s.year = yy; s.mon = mm; s.day = dd;
   s.hour = hh; s.min = mi; s.sec = 0;
   const datetime naive = StructToTime(s);

   const int ffOff  = (int)MathRound(InpFF_GmtOffsetHours * 3600.0);
   const int srvOff = (int)(TimeTradeServer() - TimeGMT());   // server minus GMT
   out = naive - ffOff + srvOff;                              // -> server time
   return true;
}

//==================================================================
//  NOTIFY
//==================================================================
void Notify(const string msg)
{
   if(InpVerbose) Print("AutoTakeProfit: ", msg);
   if(InpAlerts)  Alert("AutoTakeProfit: ", msg);
}

string MoneyStr(const double v)
{
   return (v >= 0 ? "+" : "") + DoubleToString(v, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
}

//==================================================================
//  DASHBOARD
//==================================================================
void SetRect(const string key, const int x, const int y, const int w, const int h,
             const color bg, const color border)
{
   const string nm = PFX + key;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, border);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
}

void SetText(const string key, const int x, const int y, const string text,
             const color clr, const int size, const string font = "Segoe UI",
             const ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER)
{
   const string nm = PFX + key;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, nm, OBJPROP_FONT, font);
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
}

void Row(const string key, const int lx, const int rx, const int y,
         const string label, const string value, const color vcol, const int vsize = 10)
{
   SetText("l_" + key, lx, y, label, COL_MUTE, 9);
   SetText("v_" + key, rx, y, value, vcol, vsize, "Segoe UI", ANCHOR_RIGHT_UPPER);
}

string Clip(string s, const int n)
{
   if(StringLen(s) > n) s = StringSubstr(s, 0, n - 1) + "...";
   return s;
}

void UpdateDashboard()
{
   const int X = InpDashX, Y = InpDashY, W = 300, pad = 14, hh = 34, H = 300;
   const int lx = X + pad, rx = X + W - pad;

   SetRect("bg", X, Y, W, H, COL_PANEL, COL_BORDER);
   SetRect("hd", X, Y, W, hh, COL_HEAD, COL_HEAD);
   SetText("title", lx, Y + 9, "AUTO TP  -  RISK GUARD", clrWhite, 11, "Segoe UI Semibold");
   SetText("sym",   rx, Y + 10, _Symbol, (color)C'205,223,255', 9, "Segoe UI", ANCHOR_RIGHT_UPPER);

   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   const double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   const string cur = AccountInfoString(ACCOUNT_CURRENCY);

   int y = Y + hh + 10;
   Row("bal", lx, rx, y,       "Balance",       DoubleToString(bal,2)+" "+cur, COL_TEXT);        y += 24;
   Row("eq",  lx, rx, y,       "Equity",        DoubleToString(eq,2)+" "+cur,  COL_TEXT);        y += 24;
   Row("fl",  lx, rx, y,       "Floating P/L",  MoneyStr(g_floating), g_floating>=0?COL_GREEN:COL_RED); y += 26;

   Row("dpl", lx, rx, y,       "DAILY P/L",     MoneyStr(g_dailyPL),  g_dailyPL>=0?COL_GREEN:COL_RED, 12); y += 25;
   Row("tgt", lx, rx, y,       "Daily target",  InpDailyProfitTarget>0 ? "+"+DoubleToString(InpDailyProfitTarget,2)+" "+cur : "(off)", InpDailyProfitTarget>0?COL_TEXT:COL_MUTE); y += 24;
   Row("cap", lx, rx, y,       "Daily loss cap",InpDailyLossLimit>0    ? "-"+DoubleToString(InpDailyLossLimit,2)+" "+cur    : "(off)", InpDailyLossLimit>0?COL_TEXT:COL_MUTE);   y += 20;

   // status strip
   color sc; string st;
   if(g_dailyLatched)      { sc = (g_dailyReason=="DAILY TARGET") ? COL_GREEN : COL_RED; st = "BLOCKED - " + g_dailyReason; }
   else if(g_newsActive)   { sc = COL_AMBER; st = "BLOCKED - NEWS WINDOW"; }
   else                    { sc = COL_GREEN; st = "TRADING ALLOWED"; }
   const int stripY = y + 8;
   SetRect("strip", X + 10, stripY, W - 20, 28, sc, sc);
   SetText("stript", X + W/2, stripY + 6, st, clrWhite, 10, "Segoe UI Semibold", ANCHOR_UPPER);

   // news rows
   int ny = stripY + 38;
   string nextName = (g_nextName == "") ? "(none loaded)" : Clip(g_nextName, 26);
   string inStr;
   if(g_newsActive)        inStr = "ACTIVE NOW";
   else if(g_nextTime > 0) { long s=(long)(g_nextTime-TimeTradeServer()); if(s<0)s=0; inStr=StringFormat("%dh %02dm", (int)(s/3600), (int)((s%3600)/60)); }
   else                    inStr = "-";
   Row("nx",  lx, rx, ny,     "Next high-impact", nextName, COL_TEXT, 9);  ny += 22;
   Row("in",  lx, rx, ny,     "Starts in",        inStr, g_newsActive?COL_AMBER:COL_TEXT, 10); ny += 24;

   // footer
   string src  = (InpNewsSource == NEWS_FOREX_FACTORY) ? "ForexFactory" : "MT5 Calendar";
   string foot = StringFormat("TP %s pips  |  %s  |  %d events", DoubleToString(InpTakeProfitPips,0), src, g_newsLoaded);
   if(InpNewsSource == NEWS_FOREX_FACTORY && g_ffError)
      foot = "! Forex Factory feed blocked - whitelist the URL";
   SetText("foot", lx, ny, foot, (g_ffError ? COL_AMBER : COL_MUTE), 8);

   ChartRedraw();
}
//+------------------------------------------------------------------+
