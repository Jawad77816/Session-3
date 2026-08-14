# RSI Blue-Zone + Signal — notify me only when both line up

Your rule:

- **BUY**  = your Buy signal fires **AND** RSI(14) is **above** the blue zone
- **SELL** = your Sell signal fires **AND** RSI(14) is **below** the blue zone

You want a notification (or an auto-trade) **only** when one of those two happens.
This folder gives you a working way to do it.

---

## The honest bottom line first

There are **two** free-plan limits in play, and the second one is the real wall:

| Limit on the free (Basic) plan | Effect on your idea |
| --- | --- |
| **2 indicators per chart** | You can't add a 3rd "combiner" indicator on top of your RSI + Buy/Sell. |
| **0 technical (indicator-based) alerts** — only price alerts | Even if you combine them, the free plan **can't fire an alert from an indicator condition at all.** |

So the popular advice "just merge the two indicators into one alert" is **half**
the story. Merging solves the 2-indicator limit, but on a strictly free plan you
still can't make the alert *fire*, because indicator/technical alerts + webhooks
start at the **Essential** tier (~$15/mo). Price-level alerts are the only alert
type on free. *(Plan limits verified against multiple mid-2026 sources — confirm
in your own "Create Alert" dialog, see below.)*

That leaves you three realistic routes. Pick based on whether you're willing to
pay:

1. **Merge into one indicator + upgrade to Essential** → the clean, reliable way.
2. **Stay 100% free** → run the same criteria *off* TradingView with the included
   `gold_signal_watcher.py`, which pings you on **WhatsApp**.
3. **Auto-execute trades** → possible, but needs webhooks (paid) + a broker
   bridge. Covered at the bottom, with the risk caveat you should hear.

---

## Route 1 — Merge both conditions into ONE indicator  ·  `rsi_bluezone_signal_alert.pine`

This single Pine script reproduces **RSI + the blue zone** and folds in your
**Buy/Sell signal**, then marks the chart / fires an alert **only** on a
confirmed setup. It uses **one** indicator slot instead of two.

### Install

1. TradingView → bottom panel → **Pine Editor**.
2. Paste the contents of `rsi_bluezone_signal_alert.pine`.
3. **Add to chart.**

### Tune it to match what you already use (important)

Open the indicator's **settings** and line it up with your current tools:

- **Blue zone TOP / BOTTOM** — set these to the exact levels your RSI band uses
  (defaults 60 / 40). "Above the blue zone" = RSI above TOP; "below" = RSI below
  BOTTOM.
- **Signal mode:**
  - **Built-in EMA** — the script makes its own Buy/Sell from price crossing an
    EMA. Change **EMA length** until its flips line up with your Buy/Sell
    indicator's arrows.
  - **External indicator** — if your Buy/Sell indicator exposes a numeric *plot*,
    set this script's **External signal** input to that plot (TradingView lets one
    indicator read another's plot as a source). Then keep your Buy/Sell indicator
    in the 2nd slot for its arrows. You still fire one clean combined alert.

When it's tuned, a green **BUY** / red **SELL** label prints **only** on bars
where both halves of your rule are true, and a top-right table shows live RSI and
which side of the zone it's on. Even with **no** alert, this makes eyeballing the
setup much easier.

### Turn it into an alert (needs Essential or higher)

1. Right-click chart → **Add Alert** (or the **Alert** button).
2. **Condition** → `RSI Blue-Zone + Signal Confirmation` → pick
   `Confirmed BUY`, `Confirmed SELL`, or `Confirmed BUY or SELL`.
3. Notifications → tick **App/push**, **Email**, or **Popup**.

**Free-plan test:** open that dialog now. If the only thing you can pick under
Condition is a price/value on the symbol and your indicator's named conditions
are missing or greyed out, your plan doesn't include technical alerts → use
Route 2.

---

## Route 2 — Stay 100% free, get pinged on WhatsApp  ·  `gold_signal_watcher.py`

This small Python script pulls XAUUSD candles from **OANDA's free API** (the same
broker your chart uses), computes **the exact same RSI(14) + blue-zone rule**, and
sends you a **WhatsApp** message when a confirmed BUY/SELL appears. No TradingView
alert needed, no indicator slots used.

> The RSI + blue-zone logic is exact (Wilder smoothing, matches TradingView).
> The Buy/Sell **signal** is an approximation (EMA cross) — tune `SIGNAL_EMA`, or
> replace `signal()`, so its flips match your indicator. This is the one part that
> can't be copied 1:1 without your indicator's formula.

First, the data source (needed for both WhatsApp options): create a *practice*
account at **oanda.com → Manage API Access → generate a token**.

### WhatsApp option A — CallMeBot (free, to your own number, ~2 min setup)

CallMeBot is a free service that WhatsApps **you** (your own number only — which is
exactly what a personal alert needs). One-time activation:

1. Save the CallMeBot WhatsApp number as a contact and send it the exact phrase
   **`I allow callmebot to send me messages`** from your WhatsApp. Get the current
   number + phrase from **callmebot.com/whatsapp** (at time of writing it's
   **+34 698 28 89 73** — verify on their site, it changes occasionally).
2. It replies **`API Activated ... Your APIKEY is 123123`** — copy that key.
3. Configure and run:

   ```bash
   export OANDA_TOKEN="your_practice_token"
   export GRANULARITY="M5"                     # match your chart timeframe
   export NOTIFY_PROVIDER="callmebot"
   export CALLMEBOT_PHONE="+92XXXXXXXXXX"       # your WhatsApp number, with country code
   export CALLMEBOT_APIKEY="123123"             # from the activation reply

   python3 gold_signal_watcher.py --selftest    # offline math check (no network)
   python3 gold_signal_watcher.py               # single check
   python3 gold_signal_watcher.py --loop --interval 60   # keep watching
   ```

### WhatsApp option B — Twilio sandbox (free trial, more robust)

1. Create a free Twilio account → Console → **Messaging → Try it out → WhatsApp
   sandbox**. Join by sending **`join <your-code>`** to the sandbox number
   (**+1 415 523 8886**) from your WhatsApp.
2. Copy your **Account SID** and **Auth Token** from the console.
3. Configure and run:

   ```bash
   export OANDA_TOKEN="your_practice_token"
   export NOTIFY_PROVIDER="twilio"
   export TWILIO_SID="ACxxxxxxxx"
   export TWILIO_TOKEN="your_auth_token"
   export TWILIO_FROM="whatsapp:+14155238886"   # sandbox sender (default)
   export TWILIO_TO="whatsapp:+92XXXXXXXXXX"     # your number

   python3 gold_signal_watcher.py --loop --interval 60
   ```

Run `--loop` on any always-on machine (an old laptop, a free-tier VPS, a Raspberry
Pi, or a scheduled cron job). It de-duplicates so you get **one** ping per confirmed
bar. `NOTIFY_PROVIDER` also accepts `telegram` or `console` if you ever want them.

---

## Route 3 — Auto-execute the trade (automation)

Yes, it can be automated, but not on the free plan. The standard chain is:

```
TradingView alert  ->  webhook (JSON)  ->  bridge  ->  broker API  ->  order on your account
```

You need **all** of:

- **A webhook-capable TradingView plan** (Essential+). Webhooks are **not** on the
  free plan. The `.pine` file already emits a webhook-ready JSON payload via its
  `alert()` calls (fires on *"Any alert() function call"*).
- **A bridge** that turns the webhook into a broker order — e.g. **PineConnector**
  or **Capitalise.ai** for MT4/MT5, or your own small server hitting **OANDA's
  v20 REST API** (OANDA has a real order API for XAUUSD).
- **A broker account** that the bridge can place orders on.

**Before you wire real money to this, hear this once:** "a confirmed 10-pip
profit" is not a property any signal actually has — RSI + a moving-average signal
will produce losing trades, gaps, spread/slippage on gold (which moves fast), and
strings of stop-outs. Automating it means automating the losers too. **Backtest
it, forward-test on the OANDA *practice* account first, and always attach a stop
loss.** Start on practice, not live.

---

## Which should you do?

- **Cheapest reliable path:** Route 1 + Essential (~$15/mo) → real push alerts,
  five minutes of setup.
- **Won't pay anything:** Route 2 → the Python watcher on WhatsApp (CallMeBot).
- **Want hands-off trading:** Route 3, but only after practice-account testing.

## Files

| File | What it is |
| --- | --- |
| `rsi_bluezone_signal_alert.pine` | Combined TradingView indicator (RSI+zone + signal) with one alert condition. |
| `gold_signal_watcher.py` | Free off-platform watcher: OANDA data → same rule → WhatsApp ping. |

*Not financial advice. Test on a practice account before risking real money.*
