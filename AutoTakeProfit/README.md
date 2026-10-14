# AutoTakeProfit v2 — Auto TP + Daily Limits + News Block + Dashboard (MT5)

An MT5 Expert Advisor (EA) for **manual traders** (built with Exness / XAUUSD in
mind). It does four jobs:

1. **Auto Take Profit** — the instant you open a trade by hand, a TP is placed a
   fixed number of pips from your entry (default **10 pips** → Buy 4000 → TP 4001).
2. **Daily limits** — set a **daily profit target** and/or **daily loss limit**
   (in account money). When either is reached, no new trades for the rest of the
   day. Set **both to 0 → no limit that day.**
3. **High-impact news block** — no new trades **30 min before and 30 min after**
   high-impact news (NFP, CPI, PCE, FOMC, GDP, etc.). Trades opened *before* the
   window keep running.
4. **Dashboard** — a clean on-chart panel: balance, equity, floating P/L, daily
   P/L vs your limits, trading status, and the next high-impact news.

---

## ⚠️ One important truth about "blocking" trades

An EA **cannot stop MetaTrader's manual Buy/Sell window from executing** — no EA
can intercept a human click before it fills. So the EA enforces a block the only
way possible: **it closes the trade instantly (within ~1 second) after it opens**
inside a blocked window, and alerts you. Pending orders placed during a block are
deleted the same way.

That means a blocked trade may exist for a second or two before it's flattened.
Trades you opened **before** the block began are left alone, exactly as you asked.

---

## Install (one time)

1. MT5 → **File → Open Data Folder → MQL5 → Experts**.
2. Copy **`AutoTakeProfit.mq5`** into that `Experts` folder.
3. Open **MetaEditor (F4)**, select the file, click **Compile (F7)** → *0 errors*.
4. In MT5 enable **Algo Trading** (green button on the toolbar) and
   **Tools → Options → Expert Advisors → ✅ Allow algorithmic trading**.
5. Drag the **AutoTakeProfit** EA from the Navigator onto **one** XAUUSD chart,
   tick **Allow Algo Trading**, set your options, click OK. A 🙂 appears = running.

> Run **one instance only**. The daily-limit and news logic are account-wide; the
> dashboard and news list live on the chart you attach it to.

---

## Settings

### Take Profit / Stop Loss
| Setting | Default | Meaning |
|---|---|---|
| Take Profit in pips | `10` | TP distance from entry. `0` = no TP. |
| Stop Loss in pips | `0` | Optional auto SL. `0` = leave SL alone. |
| Points per pip | `0` (auto) | Advanced pip sizing. See "Pips on gold" below. |
| Manage Buy / Sell | `true` | Which sides to auto-TP. |
| Only if no TP | `true` | Set TP once; don't fight your manual edits afterwards. |

### Daily limits (account currency; 0 & 0 = no limit)
| Setting | Default | Meaning |
|---|---|---|
| Daily profit target | `0` | Stop trading after **+this** profit today. `0` = off. |
| Daily loss limit | `0` | Stop trading after **−this** loss today. `0` = off. |
| Close all on limit | `false` | If on, also **close open trades** when a limit hits (hard stop). If off, open trades keep running and only *new* trades are blocked. |

- "Daily P/L" = closed profit since **broker-server midnight** + current floating
  P/L. Once a limit is hit it **stays blocked for the rest of the day** (even if
  price recovers). It resets at the next server midnight.

### High-impact news block
| Setting | Default | Meaning |
|---|---|---|
| Block new trades around news | `true` | Master on/off for news blocking. |
| Minutes before | `30` | Block window start before each event. |
| Minutes after | `30` | Block window end after each event. |
| News data source | `MT5 Calendar` | `MT5 Calendar` (recommended) or `Forex Factory`. |
| Currencies to watch | `USD` | Comma list (e.g. `USD,EUR`) or `ALL`. For gold, `USD` is what moves it. |
| Refresh every N min | `15` | How often to rebuild the MT5-calendar list. |

### Forex Factory (only used if source = Forex Factory)
| Setting | Default | Meaning |
|---|---|---|
| FF GMT offset (hours) | `0` | **The timezone of the feed's times — you must verify this.** See below. |
| FF refresh min | `60` | Re-download the feed every N minutes (min 5; FF rate-limits). |

### Dashboard / Misc
Show dashboard, X/Y position, verbose log, alerts on/off, magic filter
(`-1` = all incl. manual), symbol scope (`0` = this chart, `1` = all symbols).

---

## Which news source should I use?

**MT5 Calendar (default, recommended).** MetaTrader's own economic calendar is
provided by your broker, updates automatically, needs **no setup**, and its event
times are already in your **broker-server time** — so the 30-min windows are
correct with no timezone guessing. It tags each event's importance, and this EA
blocks only **High** importance events for your watched currencies. This covers
NFP, CPI, Core CPI, PCE/Core PCE, PPI, FOMC rate decision, FOMC minutes, Fed Chair
(Powell) speeches, GDP, Retail Sales, ISM Manufacturing/Services PMI, ADP,
JOLTS, Unemployment Claims, Consumer Confidence and more — whatever the calendar
marks High.

**Forex Factory (optional — you asked for it).** The EA can instead pull the
weekly feed at `https://nfs.faireconomy.media/ff_calendar_thisweek.xml` and block
events whose impact is **High**. Two things are required to make it work:

1. **Whitelist the URL:** MT5 → Tools → Options → Expert Advisors →
   ✅ *Allow WebRequest for listed URL* → add
   `https://nfs.faireconomy.media`. Without this the feed is blocked and the
   dashboard shows **"! Forex Factory feed blocked — whitelist the URL"**.
2. **Set the timezone:** the feed does **not** state its timezone, so you must set
   **FF GMT offset (hours)** to match it and **verify against the forexfactory.com
   calendar**. If the dashboard's "Next high-impact" time is off by a few hours
   vs the website, adjust the offset until it matches. (This timezone ambiguity is
   exactly why MT5 Calendar is the safer default.)

Either way the dashboard shows the active source and how many events it loaded, so
you can see at a glance that news data is live.

> Geopolitical shocks (wars, surprise crises, emergency statements) have **no
> scheduled time**, so no calendar — FF or MT5 — can pre-block them. Those remain
> your judgement call.

---

## About "pips" on gold

The word *pip* is ambiguous on gold, so the EA is explicit. By default
(**Points per pip = 0**) it treats **1 pip = 0.10** on gold → **10 pips = 1.00** →
Buy 4000 → TP 4001, which is what you asked for. If your broker quotes gold
differently or you want another distance, set **Points per pip** (1 pip =
`Points per pip × point`). The log line on startup prints the exact pip size and a
worked example so you can confirm before trading.

---

## Reading the dashboard

- **Balance / Equity** — account figures.
- **Floating P/L** — profit/loss of currently open trades (green up / red down).
- **DAILY P/L** — your net result today vs the **Daily target** and **Daily loss cap**.
- **Status strip** — `TRADING ALLOWED` (green), `BLOCKED – NEWS WINDOW` (amber),
  or `BLOCKED – DAILY TARGET / DAILY LOSS LIMIT` (green/red).
- **Next high-impact** — the next watched event and a countdown ("Starts in").
- **Footer** — TP size, active news source, and events loaded.

---

## Good to know / limits

- The EA must be **running** (🙂 on the chart, Algo Trading green) when you trade.
- Blocking works by **instant close** — see the warning at the top.
- Daily P/L resets at **broker-server midnight** (not your local midnight).
- **Strategy Tester:** auto-TP and daily limits work, but the MT5 calendar and
  Forex Factory WebRequest are **not available in the tester**, so news blocking
  can't be backtested there — test it on a **demo account** on a live chart.
- This is a trading tool, not financial advice. **Test on demo first.**
