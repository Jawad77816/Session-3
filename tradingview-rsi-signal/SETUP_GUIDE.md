# Complete setup guide — free WhatsApp alerts for your gold (XAUUSD) signal

This walks you from zero to a phone that buzzes on WhatsApp **only** when your
exact rule hits:

- **BUY**  = your buy signal fires **and** RSI(14) is **above** the blue zone
- **SELL** = your sell signal fires **and** RSI(14) is **below** the blue zone

No paid TradingView plan, no coding experience needed. Budget ~15 minutes.
It runs on your own computer, reads live gold prices from OANDA's free API, and
messages you on WhatsApp through CallMeBot (free).

> Uses the file **`gold_signal_watcher.py`** from this folder.

---

## The map (what you'll do)

1. Get the script file onto your computer
2. Install Python (if you don't have it)
3. Get a free OANDA API token (the price data)
4. Turn on free WhatsApp messages with CallMeBot
5. Put your details into the script
6. Test it
7. Leave it running
8. Tune the signal so it matches YOUR indicator

---

## Step 1 — Get the script onto your computer

Easiest way (no git needed):

1. On GitHub, open `tradingview-rsi-signal/gold_signal_watcher.py` in this repo.
2. Click **Download raw file** (top-right of the file view).
3. Put it in a folder you can find again, e.g. `Documents/gold-watcher/`.

Prefer git? From a terminal:

```bash
git clone -b claude/tradingview-rsi-notifications-gt3zou https://github.com/Jawad77816/Session-3.git
cd Session-3/tradingview-rsi-signal
```

---

## Step 2 — Install Python

**Check if you already have it.** Open a terminal:

- **Windows:** press `Win`, type **cmd**, hit Enter, then run `python --version`
- **Mac:** press `Cmd+Space`, type **Terminal**, hit Enter, then run `python3 --version`

If you see something like `Python 3.11.x`, skip ahead to Step 3.

**If not installed:**

- **Windows:** get it from python.org/downloads → run the installer →
  **tick "Add python.exe to PATH"** on the first screen → Install. Close and
  reopen cmd, then check `python --version` again.
- **Mac:** install from python.org/downloads (or `brew install python3` if you
  use Homebrew), then check `python3 --version`.

> No extra libraries are needed — the script only uses Python's built-ins.
> Throughout this guide, Windows users type `python`, Mac/Linux users type
> `python3`.

---

## Step 3 — Get your free OANDA API token (price data)

The script needs live gold candles. OANDA gives them away free on a *practice*
account (no funding required).

1. Go to **oanda.com** → create a free account → choose/confirm a **practice
   (demo)** account.
2. Open **Manage API Access** (Account → "Manage API Access", or search "v20 API"
   in your OANDA account settings).
3. Click **Generate** to create a **Personal Access Token**.
4. Copy the long token string somewhere safe. That's your `OANDA_TOKEN`.

> The instrument for gold on OANDA is `XAU_USD` (the script already uses it).

---

## Step 4 — Turn on free WhatsApp messages (CallMeBot)

CallMeBot is a free service that sends WhatsApp messages **to your own number**
— perfect for a personal alert. One-time activation:

1. Go to **callmebot.com/whatsapp** and note the **current bot number** and the
   activation phrase. *(At the time of writing the number is
   `+34 698 28 89 73`, but they change it occasionally — always take it from
   their site.)*
2. Save that number in your phone contacts.
3. From **your** WhatsApp, send that contact the **exact** phrase:

   ```
   I allow callmebot to send me messages
   ```

4. Within a minute you'll get a reply like:
   **`API Activated for your phone number. Your APIKEY is 123123`**
5. Copy that **APIKEY** and note your **own** phone number in full international
   format, e.g. `+923001234567`.

You now have two values: `CALLMEBOT_PHONE` (your number) and
`CALLMEBOT_APIKEY` (the key from the reply).

---

## Step 5 — Put your details into the script

Open `gold_signal_watcher.py` in any text editor (Notepad, TextEdit, VS Code).
Near the top you'll see a **CONFIG** block. The beginner-friendly way is to type
your values straight between the quotes at the end of each line:

```python
OANDA_TOKEN = os.environ.get("OANDA_TOKEN", "PUT_YOUR_OANDA_TOKEN_HERE")
GRANULARITY = os.environ.get("GRANULARITY", "M5")     # match your chart timeframe

NOTIFY_PROVIDER = os.environ.get("NOTIFY_PROVIDER", "callmebot")
CALLMEBOT_PHONE  = os.environ.get("CALLMEBOT_PHONE",  "+92XXXXXXXXXX")
CALLMEBOT_APIKEY = os.environ.get("CALLMEBOT_APIKEY", "123123")
```

- `GRANULARITY` must match your chart's timeframe: `M1`, `M5`, `M15`, `M30`,
  `H1`, `H4`, etc. Your screenshot was **M5** (5-minute).
- Leave `NOTIFY_PROVIDER` as `callmebot` for WhatsApp.

Save the file.

> Prefer not to edit the file? You can instead set these as environment
> variables before running. Windows PowerShell: `$env:OANDA_TOKEN="..."`.
> Mac/Linux: `export OANDA_TOKEN="..."`. Editing the file is simpler if you're
> not sure.

---

## Step 6 — Test it

In your terminal, move into the folder with the file and run the offline math
check first (this needs no internet and proves the script works):

```bash
cd path/to/your/folder
python gold_signal_watcher.py --selftest
```

You should see `OK` at the end.

Now a single live check (this hits OANDA and prints the current reading):

```bash
python gold_signal_watcher.py
```

You'll see a line like:

```
2026-08-14T20:05:00Z  close=4374.165  RSI=42.78 (BELOW zone)  signal=None
```

If a confirmed BUY/SELL happens to be true on that bar, you'll also get the
WhatsApp message. To prove the WhatsApp pipe works end-to-end, you can
temporarily widen the zone (e.g. set `ZONE_TOP = 0`) so a signal confirms, run
once, confirm the WhatsApp arrives, then set the zone back.

---

## Step 7 — Leave it running

To watch continuously, add `--loop`. It checks every 60 seconds and sends **one**
WhatsApp per confirmed bar (no spam):

```bash
python gold_signal_watcher.py --loop --interval 60
```

Keep that terminal window open and it keeps watching. For 24/5 coverage without
leaving your PC on, pick one:

- **Simplest:** leave it running on a computer that stays on.
- **Windows Task Scheduler / Mac cron:** run `python gold_signal_watcher.py`
  (without `--loop`) every 1–5 minutes on a schedule.
- **Free/cheap VPS** (Oracle Cloud free tier, a $5 droplet, a Raspberry Pi):
  copy the file over and run the `--loop` command inside `tmux`/`screen` or as a
  service so it survives disconnects.

---

## Step 8 — Make it match YOUR indicator (important)

The RSI + blue-zone part is **exact** (it matches TradingView). The **buy/sell
signal** in the script is an *approximation* — by default it's "price crossing an
EMA." You want its arrows to line up with your own Buy/Sell indicator. Two knobs,
both near the top of the file:

```python
RSI_LENGTH  = 14      # match your RSI
ZONE_TOP    = 60.0    # RSI above this = buy side of the blue zone
ZONE_BOTTOM = 40.0    # RSI below this = sell side of the blue zone
SIGNAL_EMA  = 20      # the approximate signal: price vs EMA(this length)
```

- Set `ZONE_TOP` / `ZONE_BOTTOM` to the **exact** levels your blue band uses.
- Change `SIGNAL_EMA` until the script's buy/sell flips roughly match your
  indicator's arrows on the same chart.
- If you know exactly what your Buy/Sell indicator is based on (e.g. an EMA/Hull
  color flip, a SuperTrend, a specific crossover), replace the `signal()`
  function with that logic for a precise match.

---

## Optional — the paid, TradingView-native route

If you'd rather get the alert straight from TradingView (cleaner, but needs a
paid tier):

1. Add **`rsi_bluezone_signal_alert.pine`** (in this folder) via TradingView's
   Pine Editor → **Add to chart**. It merges your RSI+zone and Buy/Sell signal
   into one indicator (one slot instead of two) and prints a confirmed BUY/SELL
   marker only when your rule is true.
2. Upgrade to **Essential** (~$15/mo) — required, because the free plan gives
   **0 technical (indicator-based) alerts**.
3. Right-click chart → **Add Alert** → Condition = `RSI Blue-Zone + Signal
   Confirmation` → pick `Confirmed BUY` / `Confirmed SELL` → enable App/push.

See `README.md` for the full comparison of routes (including auto-executing
trades via webhooks).

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `python: command not found` | Use `python3` (Mac/Linux) or reinstall Python with "Add to PATH" ticked (Windows). |
| `ERROR: set OANDA_TOKEN` | Your token is still blank — recheck Step 5. |
| `notify via callmebot failed` | Recheck `CALLMEBOT_PHONE` (full `+countrycode…`) and `CALLMEBOT_APIKEY`; re-run the CallMeBot activation if the key never arrived. |
| No WhatsApp ever arrives | The condition simply may not have hit yet. Confirm the pipe with the widen-the-zone test in Step 6. |
| `Not enough completed candles yet` | The market/timeframe just doesn't have enough closed bars yet; wait or use a smaller `GRANULARITY`. |
| RSI number looks off vs TradingView | Make sure `GRANULARITY` matches your chart timeframe and `RSI_LENGTH` matches your RSI. |

---

## One honest note on risk

A signal is never a guaranteed "10 pips." RSI + a moving-average signal will
produce losing trades, and gold moves fast (spread/slippage matter). Use this to
get **notified**, then apply your own judgement and a stop-loss. If you later
automate order execution, test on the OANDA **practice** account first.

*Not financial advice.*
