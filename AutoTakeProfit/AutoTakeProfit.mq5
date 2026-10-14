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

input group "========== HIGH-IMPACT NEWS =========="
input bool            InpNewsFilter    = true;              // Enable high-impact news monitoring
input int             InpMinutesBefore = 30;                // Window starts this many minutes BEFORE news
input int             InpMinutesAfter  = 30;                // Window ends this many minutes AFTER news
input bool            InpNewsAlert     = true;              // Pop STOP / RESUME trading alerts at the window edges
input bool            InpNewsAutoClose = false;             // ALSO force-close trades opened inside the window
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
input bool InpAlerts      = true;    // Pop up terminal alerts (news / limits)
input bool InpPushNotify  = false;   // Also send push to the MT5 mobile app (needs MetaQuotes ID)
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
bool     g_newsActive     = false;
datetime g_newsStart      = 0;    // earliest active window start (for auto-close cut-off)
datetime g_newsEnd        = 0;    // latest active window end  (for the "resume in" countdown)
datetime g_newsEventTime  = 0;    // the active event's scheduled time
string   g_newsName       = "";
bool     g_newsPrevActive = false; // to fire STOP / RESUME alerts only on edges
datetime g_nextTime       = 0;
string   g_nextName       = "";

// daily P/L state
datetime g_dayStart       = 0;
double   g_dailyPL        = 0.0;
double   g_realizedToday  = 0.0;
double   g_floating       = 0.0;
bool     g_dailyLatched   = false;   // sticky for the rest of the day once a limit is hit
datetime g_dailyBlockStart= 0;
string   g_dailyReason    = "";

// dashboard palette (dark, card-based)
#define PFX            "ATP_"
#define COL_BG         C'15,19,27'
#define COL_CARD       C'25,31,43'
#define COL_CARDBORDER C'38,46,62'
#define COL_BORDER     C'38,46,62'
#define COL_WHITE      C'236,239,245'
#define COL_MUTE       C'128,139,158'
#define COL_GOLD       C'226,178,80'
#define COL_GREEN      C'46,204,128'
#define COL_RED        C'235,78,92'
#define COL_AMBER      C'240,182,72'
#define COL_BLUE       C'84,152,240'
#define COL_INK        C'20,20,26'

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
   HandleNewsTransitions();
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
   g_newsActive    = false;
   g_newsStart     = 0;
   g_newsEnd       = 0;
   g_newsEventTime = 0;
   g_newsName      = "";
   g_nextTime      = 0;
   g_nextName      = "";

   if(!InpNewsFilter)
      return;

   const datetime now = TimeTradeServer();
   const int n = ArraySize(g_evTime);
   for(int i = 0; i < n; i++)
   {
      const datetime ws = g_evTime[i] - InpMinutesBefore * 60;
      const datetime we = g_evTime[i] + InpMinutesAfter  * 60;

      if(now >= ws && now <= we)          // we are inside this event's window
      {
         // name/start come from the event with the earliest window start
         if(!g_newsActive || ws < g_newsStart)
         {
            g_newsStart     = ws;
            g_newsEventTime = g_evTime[i];
            g_newsName      = g_evName[i];
         }
         if(we > g_newsEnd) g_newsEnd = we;   // resume only when ALL windows clear
         g_newsActive = true;
      }

      if(g_evTime[i] >= now && (g_nextTime == 0 || g_evTime[i] < g_nextTime))
      {
         g_nextTime = g_evTime[i];
         g_nextName  = g_evName[i];
      }
   }
}

// Fire one-off "STOP" / "RESUME" alerts as we cross the window edges.
void HandleNewsTransitions()
{
   if(InpNewsFilter && InpNewsAlert)
   {
      if(g_newsActive && !g_newsPrevActive)
         Notify(StringFormat("STOP TRADING - high-impact news '%s' at %s. Resume at %s.",
                             g_newsName,
                             TimeToString(g_newsEventTime, TIME_MINUTES),
                             TimeToString(g_newsEnd, TIME_MINUTES)));
      else if(!g_newsActive && g_newsPrevActive)
         Notify("RESUME TRADING - the high-impact news window has passed.");
   }
   g_newsPrevActive = g_newsActive;
}

// Pending orders / new trades are force-closed only when a real block is on:
//   - a daily limit has latched, or
//   - we are in a news window AND the user turned on news auto-close.
bool TradingBlocked()
{
   return (g_dailyLatched || (g_newsActive && InpNewsAutoClose));
}

//==================================================================
//  POSITION / ORDER MANAGEMENT
//==================================================================
bool InScope(const string sym)       { return (InpSymbolScope == 1 || sym == _Symbol); }
bool MagicOk(const long magic)        { return (InpMagicFilter < 0 || magic == InpMagicFilter); }

// should a position opened at posTime be force-closed by a block?
bool ShouldClose(const datetime posTime)
{
   if(g_dailyLatched && InpCloseAllOnLimit)                       return true; // hard stop
   if(g_newsActive && InpNewsAutoClose && posTime >= g_newsStart) return true; // opened inside news window
   if(g_dailyLatched && posTime >= g_dailyBlockStart)             return true; // opened after limit hit
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
         if((g_newsActive && InpNewsAutoClose && setup >= g_newsStart) ||
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
   if(InpVerbose)    Print("AutoTakeProfit: ", msg);
   if(InpAlerts)     Alert("AutoTakeProfit: ", msg);
   if(InpPushNotify) SendNotification("AutoTakeProfit: " + msg);
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

// group an integer string with thousands commas: "1806" -> "1,806"
string Group(const string ip)
{
   string g = "";
   int c = 0;
   for(int i = StringLen(ip) - 1; i >= 0; i--)
   {
      g = StringSubstr(ip, i, 1) + g;
      c++;
      if(c % 3 == 0 && i > 0) g = "," + g;
   }
   return g;
}

// pretty money: "$1,806.54" / "+$337.83" / "-$120.00"
string Money(const double v, const string prefix, const bool showSign)
{
   const string sign = (v < 0) ? "-" : (showSign ? "+" : "");
   const string s    = DoubleToString(MathAbs(v), 2);
   const int    dot  = StringFind(s, ".");
   const string ip   = StringSubstr(s, 0, dot);
   const string fp   = StringSubstr(s, dot);
   return sign + prefix + Group(ip) + fp;
}

// one metric card: small label on top, big value below, colored left accent
void DrawCard(const string key, const int x, const int y, const int w, const int h,
              const string label, const string value, const color vcol, const color accent)
{
   SetRect("c_"  + key, x,     y, w, h, COL_CARD, COL_CARDBORDER);
   SetRect("ca_" + key, x,     y, 3, h, accent,   accent);
   SetText("cl_" + key, x + 12, y + 9,  label, COL_MUTE, 8);
   SetText("cv_" + key, x + 12, y + 25, value, vcol,     12, "Segoe UI Semibold");
}

string Clip(string s, const int n)
{
   if(StringLen(s) > n) s = StringSubstr(s, 0, n - 1) + "...";
   return s;
}

// "Xh YYm" countdown from now until target (clamped at 0)
string CountStr(const datetime target)
{
   long s = (long)(target - TimeTradeServer());
   if(s < 0) s = 0;
   return StringFormat("%dh %02dm", (int)(s / 3600), (int)((s % 3600) / 60));
}

void UpdateDashboard()
{
   const int X = InpDashX, Y = InpDashY;
   const int W = 332, pad = 12, gap = 9, headerH = 50;
   const int cardW = (W - 2 * pad - gap) / 2;   // two columns
   const int cardH = 54;
   const int statH = 46, alH = 54;
   const int hx = X + pad;                        // content left
   const int c2x = X + pad + cardW + gap;         // second column x

   // --- precompute all Y positions so the background can cover everything ---
   const int yDiv  = Y + headerH;
   const int r0    = yDiv + 8;
   const int r1    = r0 + cardH + gap;
   const int r2    = r1 + cardH + gap;
   const int yStat = r2 + cardH + gap;
   const int yAl   = yStat + statH + gap;
   const int yFoot = yAl + alH + 8;
   const int H     = (yFoot + 16) - Y;

   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   const double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   const string cur = AccountInfoString(ACCOUNT_CURRENCY);
   const string sym = (cur == "USD") ? "$" : (cur + " ");

   // --- panel + header ---
   SetRect("bg",  X, Y, W, H, COL_BG, COL_BORDER);
   SetRect("logo", hx, Y + 9, 32, 32, COL_GOLD, COL_GOLD);
   SetText("logoT", hx + 16, Y + 13, "A", COL_INK, 15, "Segoe UI Semibold", ANCHOR_UPPER);
   SetText("title", hx + 42, Y + 10, "AUTO TP GUARD", COL_WHITE, 13, "Segoe UI Semibold");
   SetText("sub",   hx + 42, Y + 31, "TP  /  LIMITS  /  NEWS", COL_MUTE, 8);
   SetRect("verbg", X + W - pad - 46, Y + 13, 46, 20, COL_CARD, COL_GOLD);
   SetText("ver",   X + W - pad - 23, Y + 16, "v2.0", COL_GOLD, 8, "Segoe UI", ANCHOR_UPPER);
   SetRect("div",   X + pad, yDiv, W - 2 * pad, 1, COL_BORDER, COL_BORDER);

   // --- metric cards ---
   DrawCard("bal", hx,  r0, cardW, cardH, "ACCOUNT BALANCE", sym + Money(bal, "", false), COL_WHITE, COL_GOLD);
   DrawCard("dpl", c2x, r0, cardW, cardH, "TODAY'S P/L",     Money(g_dailyPL, sym, true),
            g_dailyPL >= 0 ? COL_GREEN : COL_RED, g_dailyPL >= 0 ? COL_GREEN : COL_RED);
   DrawCard("eq",  hx,  r1, cardW, cardH, "EQUITY",          sym + Money(eq, "", false), COL_WHITE, COL_BLUE);
   DrawCard("fl",  c2x, r1, cardW, cardH, "FLOATING P/L",    Money(g_floating, sym, true),
            g_floating >= 0 ? COL_GREEN : COL_RED, g_floating >= 0 ? COL_GREEN : COL_RED);
   DrawCard("tgt", hx,  r2, cardW, cardH, "DAILY TARGET",
            InpDailyProfitTarget > 0 ? sym + Money(InpDailyProfitTarget, "", false) : "OFF",
            InpDailyProfitTarget > 0 ? COL_WHITE : COL_MUTE, InpDailyProfitTarget > 0 ? COL_GREEN : COL_CARDBORDER);
   DrawCard("cap", c2x, r2, cardW, cardH, "DAILY LOSS CAP",
            InpDailyLossLimit > 0 ? sym + Money(InpDailyLossLimit, "", false) : "OFF",
            InpDailyLossLimit > 0 ? COL_WHITE : COL_MUTE, InpDailyLossLimit > 0 ? COL_RED : COL_CARDBORDER);

   // --- status row ---
   color sc; string stt;
   if(g_dailyLatched)
   { bool tgt = (g_dailyReason == "DAILY TARGET"); sc = tgt ? COL_GREEN : COL_RED; stt = tgt ? "DAILY TARGET HIT" : "DAILY LOSS LIMIT HIT"; }
   else if(g_newsActive)
   { sc = COL_RED;   stt = "STOP TRADING - NEWS"; }
   else
   { sc = COL_GREEN; stt = "TRADING ALLOWED"; }
   SetRect("stbg", X + pad, yStat, W - 2 * pad, statH, COL_CARD, COL_CARDBORDER);
   SetRect("stac", X + pad, yStat, 3, statH, sc, sc);
   SetRect("stdot", X + pad + 16, yStat + statH / 2 - 5, 10, 10, sc, sc);
   SetText("stl",  X + pad + 36, yStat + 9,  "STATUS", COL_MUTE, 8);
   SetText("stt",  X + pad + 36, yStat + 23, stt, sc, 12, "Segoe UI Semibold");

   // --- alert / info box ---
   color ac; string at, ad;
   if(g_dailyLatched)
   {
      bool tgt = (g_dailyReason == "DAILY TARGET");
      ac = tgt ? COL_GREEN : COL_RED;
      at = tgt ? "Daily target reached" : "Daily loss limit reached";
      ad = "New trades blocked until server midnight.";
   }
   else if(g_newsActive)
   {
      ac = COL_RED;
      at = "News: " + Clip(g_newsName, 22);
      ad = "Resume " + TimeToString(g_newsEnd, TIME_MINUTES) + "  (in " + CountStr(g_newsEnd) + ")";
   }
   else if(g_nextTime > 0)
   {
      const datetime stopAt = g_nextTime - InpMinutesBefore * 60;
      const long secs = (long)(stopAt - TimeTradeServer());
      ac = (secs > 0 && secs <= 3600) ? COL_AMBER : COL_GREEN;
      at = "Next: " + Clip(g_nextName, 22);
      ad = "Stop " + TimeToString(stopAt, TIME_MINUTES) + "  (in " + CountStr(stopAt) + ")";
   }
   else
   {
      ac = COL_GREEN;
      at = "All clear";
      ad = InpNewsFilter ? "No high-impact news loaded." : "News monitoring is off.";
   }
   const color abg = (ac == COL_RED) ? C'40,24,28' : ((ac == COL_AMBER) ? C'40,34,22' : C'20,32,29');
   SetRect("albg", X + pad, yAl, W - 2 * pad, alH, abg, COL_CARDBORDER);
   SetRect("alac", X + pad, yAl, 3, alH, ac, ac);
   SetText("alt",  X + pad + 14, yAl + 9,  at, ac, 11, "Segoe UI Semibold");
   SetText("ald",  X + pad + 14, yAl + 30, Clip(ad, 40), COL_MUTE, 8);

   // --- footer ---
   string src = (InpNewsSource == NEWS_FOREX_FACTORY) ? "Forex Factory" : "MT5 Calendar";
   if(InpNewsSource == NEWS_FOREX_FACTORY && g_ffError) src = "FF BLOCKED-whitelist";
   SetText("ftl", hx, yFoot, "AutoTP v2  |  TP " + DoubleToString(InpTakeProfitPips, 0) + " pips", COL_MUTE, 8);
   SetText("ftr", X + W - pad, yFoot, src + "  |  " + (string)g_newsLoaded + " evt",
           g_ffError ? COL_RED : COL_MUTE, 8, "Segoe UI", ANCHOR_RIGHT_UPPER);

   ChartRedraw();
}
//+------------------------------------------------------------------+
