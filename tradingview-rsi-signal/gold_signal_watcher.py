#!/usr/bin/env python3
"""
gold_signal_watcher.py - free, off-platform notifier for the
"RSI blue-zone + Buy/Sell signal" setup (XAUUSD / gold on OANDA).

It re-creates the same criteria you use on TradingView, but runs on your own
machine, so it works WITHOUT a paid TradingView plan and WITHOUT using up your
two free-plan indicator slots:

    BUY  alert  =  buy  signal  AND  RSI(14) is ABOVE the blue zone
    SELL alert  =  sell signal  AND  RSI(14) is BELOW the blue zone

Data source : OANDA v20 REST API (free "practice" account token)
Notify      : WhatsApp - free via CallMeBot (to your own number), or the Twilio
              WhatsApp sandbox; falls back to console.

IMPORTANT: the buy/sell signal below is an APPROXIMATION (EMA cross by default).
Tune SIGNAL_EMA - or replace signal() - so its flips line up with your own
Buy/Sell indicator. The RSI + blue-zone logic is exact (matches TradingView's
Wilder-smoothed ta.rsi).

Quick start (WhatsApp via CallMeBot - free, to your own number):
    export OANDA_TOKEN="...."           # oanda.com -> practice account -> API
    export NOTIFY_PROVIDER="callmebot"  # callmebot | twilio | telegram | console
    export CALLMEBOT_PHONE="+9230...."  # your WhatsApp number, with country code
    export CALLMEBOT_APIKEY="......"    # from the CallMeBot activation reply
    python3 gold_signal_watcher.py --selftest   # offline math check
    python3 gold_signal_watcher.py              # one check
    python3 gold_signal_watcher.py --loop --interval 60
"""

from __future__ import annotations
import argparse
import base64
import json
import os
import sys
import time
import urllib.parse
import urllib.request

# ─────────────────────────────── CONFIG ────────────────────────────────
OANDA_TOKEN = os.environ.get("OANDA_TOKEN", "")            # free practice token
OANDA_ENV = os.environ.get("OANDA_ENV", "practice")        # "practice" or "live"
INSTRUMENT = os.environ.get("INSTRUMENT", "XAU_USD")       # OANDA symbol for gold
GRANULARITY = os.environ.get("GRANULARITY", "M5")          # M1 M5 M15 H1 ... match your chart

RSI_LENGTH = 14
ZONE_TOP = 60.0            # RSI above this = buy-side of the blue zone
ZONE_BOTTOM = 40.0         # RSI below this = sell-side of the blue zone

SIGNAL_EMA = 20           # built-in signal: price vs EMA(SIGNAL_EMA) - TUNE THIS

# Where to send alerts: callmebot (WhatsApp, free) | twilio (WhatsApp) | telegram | console
NOTIFY_PROVIDER = os.environ.get("NOTIFY_PROVIDER", "callmebot")

# CallMeBot - free WhatsApp to YOUR OWN number (see README for one-time activation)
CALLMEBOT_PHONE = os.environ.get("CALLMEBOT_PHONE", "")      # e.g. +923001234567
CALLMEBOT_APIKEY = os.environ.get("CALLMEBOT_APIKEY", "")

# Twilio WhatsApp sandbox (free trial) - more robust alternative
TWILIO_SID = os.environ.get("TWILIO_SID", "")
TWILIO_TOKEN = os.environ.get("TWILIO_TOKEN", "")
TWILIO_FROM = os.environ.get("TWILIO_FROM", "whatsapp:+14155238886")   # sandbox sender
TWILIO_TO = os.environ.get("TWILIO_TO", "")                           # whatsapp:+9230...

# Telegram (kept as an option; not required)
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

STATE_FILE = os.environ.get("STATE_FILE", ".gold_watcher_state.json")
# ────────────────────────────────────────────────────────────────────────


def rma(values, length):
    """Wilder's moving average (RMA), seeded with an SMA - matches the
    smoothing inside TradingView's ta.rsi."""
    out = [None] * len(values)
    if len(values) < length:
        return out
    seed = sum(values[:length]) / length
    out[length - 1] = seed
    prev = seed
    alpha = 1.0 / length
    for i in range(length, len(values)):
        prev = (values[i] - prev) * alpha + prev
        out[i] = prev
    return out


def rsi(closes, length=14):
    """RSI matching TradingView's ta.rsi (Wilder smoothing)."""
    gains = [0.0]
    losses = [0.0]
    for i in range(1, len(closes)):
        ch = closes[i] - closes[i - 1]
        gains.append(max(ch, 0.0))
        losses.append(max(-ch, 0.0))
    avg_gain = rma(gains, length)
    avg_loss = rma(losses, length)
    out = [None] * len(closes)
    for i in range(len(closes)):
        if avg_gain[i] is None or avg_loss[i] is None:
            continue
        if avg_loss[i] == 0:
            out[i] = 100.0
        else:
            rs = avg_gain[i] / avg_loss[i]
            out[i] = 100.0 - 100.0 / (1.0 + rs)
    return out


def ema(values, length):
    """EMA seeded with an SMA - matches TradingView's ta.ema."""
    out = [None] * len(values)
    if len(values) < length:
        return out
    seed = sum(values[:length]) / length
    out[length - 1] = seed
    prev = seed
    k = 2.0 / (length + 1.0)
    for i in range(length, len(values)):
        prev = (values[i] - prev) * k + prev
        out[i] = prev
    return out


def signal(closes):
    """APPROXIMATE buy/sell signal: price crossing EMA(SIGNAL_EMA).
    Returns 'buy', 'sell', or None for the last closed bar.
    Replace / tune this so it matches your own Buy/Sell indicator."""
    e = ema(closes, SIGNAL_EMA)
    if e[-1] is None or e[-2] is None:
        return None
    up_now = closes[-1] > e[-1]
    up_prev = closes[-2] > e[-2]
    if up_now and not up_prev:
        return "buy"
    if (not up_now) and up_prev:
        return "sell"
    return None


def fetch_closes(count=200):
    host = "api-fxpractice.oanda.com" if OANDA_ENV == "practice" else "api-fxtrade.oanda.com"
    url = (
        f"https://{host}/v3/instruments/{INSTRUMENT}/candles"
        f"?count={count}&granularity={GRANULARITY}&price=M"
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {OANDA_TOKEN}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    candles = [c for c in data.get("candles", []) if c.get("complete")]
    times = [c["time"] for c in candles]
    closes = [float(c["mid"]["c"]) for c in candles]
    return times, closes


def _notify_callmebot(msg):
    """Free WhatsApp to your own number via CallMeBot."""
    if not (CALLMEBOT_PHONE and CALLMEBOT_APIKEY):
        print("[warn] set CALLMEBOT_PHONE and CALLMEBOT_APIKEY for WhatsApp (see README).", flush=True)
        return
    q = urllib.parse.urlencode({"phone": CALLMEBOT_PHONE, "text": msg, "apikey": CALLMEBOT_APIKEY})
    urllib.request.urlopen(f"https://api.callmebot.com/whatsapp.php?{q}", timeout=15).read()


def _notify_twilio(msg):
    """WhatsApp via the Twilio sandbox (free trial)."""
    if not (TWILIO_SID and TWILIO_TOKEN and TWILIO_TO):
        print("[warn] set TWILIO_SID, TWILIO_TOKEN and TWILIO_TO for WhatsApp.", flush=True)
        return
    url = f"https://api.twilio.com/2010-04-01/Accounts/{TWILIO_SID}/Messages.json"
    body = urllib.parse.urlencode({"From": TWILIO_FROM, "To": TWILIO_TO, "Body": msg}).encode()
    req = urllib.request.Request(url, data=body)
    token = base64.b64encode(f"{TWILIO_SID}:{TWILIO_TOKEN}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    urllib.request.urlopen(req, timeout=20).read()


def _notify_telegram(msg):
    if not (TELEGRAM_TOKEN and TELEGRAM_CHAT_ID):
        print("[warn] set TELEGRAM_TOKEN and TELEGRAM_CHAT_ID for Telegram.", flush=True)
        return
    q = urllib.parse.urlencode({"chat_id": TELEGRAM_CHAT_ID, "text": msg})
    urllib.request.urlopen(f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage?{q}", timeout=15).read()


def notify(msg):
    """Print to console, then push via the configured provider."""
    print(msg, flush=True)
    provider = NOTIFY_PROVIDER.strip().lower()
    senders = {
        "callmebot": _notify_callmebot,
        "twilio": _notify_twilio,
        "telegram": _notify_telegram,
        "console": lambda _m: None,
    }
    sender = senders.get(provider)
    if sender is None:
        print(f"[warn] unknown NOTIFY_PROVIDER '{provider}'; console only.", flush=True)
        return
    try:
        sender(msg)
    except Exception as e:  # noqa: BLE001
        print(f"[warn] notify via {provider} failed: {e}", flush=True)


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def save_state(state):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception as e:  # noqa: BLE001
        print(f"[warn] could not save state: {e}", flush=True)


def check_once():
    if not OANDA_TOKEN:
        print("ERROR: set OANDA_TOKEN (free at oanda.com -> practice account -> API).", file=sys.stderr)
        return
    times, closes = fetch_closes()
    if len(closes) < max(RSI_LENGTH, SIGNAL_EMA) + 2:
        print("Not enough completed candles yet.", flush=True)
        return

    r = rsi(closes, RSI_LENGTH)[-1]
    sig = signal(closes)
    bar = times[-1]

    above = r is not None and r > ZONE_TOP
    below = r is not None and r < ZONE_BOTTOM
    confirmed = None
    if sig == "buy" and above:
        confirmed = "BUY"
    elif sig == "sell" and below:
        confirmed = "SELL"

    zone = "ABOVE" if above else "BELOW" if below else "INSIDE"
    print(f"{bar}  close={closes[-1]:.3f}  RSI={r:.2f} ({zone} zone)  signal={sig}", flush=True)

    if confirmed:
        st = load_state()
        if st.get("last_bar") == bar and st.get("last_signal") == confirmed:
            return  # already alerted for this bar
        notify(
            f"CONFIRMED {confirmed}  {INSTRUMENT} @ {closes[-1]:.3f}\n"
            f"RSI(14)={r:.2f} ({zone} blue zone)\n"
            f"bar={bar} [{GRANULARITY}]"
        )
        save_state({"last_bar": bar, "last_signal": confirmed})


def selftest():
    # deterministic ramp up then down - just proves the math runs end to end.
    closes = [100 + i for i in range(30)] + [130 - i for i in range(30)]
    r = rsi(closes, 14)
    tail = [round(x, 2) for x in r[-5:] if x is not None]
    print("selftest RSI (last 5):", tail)
    print("selftest signal:", signal(closes))
    assert r[-1] is not None and 0 <= r[-1] <= 100, "RSI out of range"
    print("OK")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--loop", action="store_true", help="run forever, polling each interval")
    ap.add_argument("--interval", type=int, default=60, help="poll seconds in --loop mode")
    ap.add_argument("--selftest", action="store_true", help="run offline math check and exit")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return
    if args.loop:
        while True:
            try:
                check_once()
            except Exception as e:  # noqa: BLE001
                print(f"[warn] {e}", flush=True)
            time.sleep(args.interval)
    else:
        check_once()


if __name__ == "__main__":
    main()
