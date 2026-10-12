#!/usr/bin/env python3
"""Fetch real gold (GC=F, COMEX gold futures ~ spot proxy) OHLC for backtesting."""
import os, time, datetime as dt
import yfinance as yf
import pandas as pd

OUT = os.path.dirname(os.path.abspath(__file__))

def save(df, name):
    if df is None or len(df) == 0:
        print("  EMPTY", name); return 0
    # flatten yfinance multiindex columns
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [c[0] for c in df.columns]
    df = df[["Open","High","Low","Close"]].dropna()
    df.index.name = "Datetime"
    p = os.path.join(OUT, name)
    df.to_csv(p)
    print(f"  saved {name}: {len(df)} rows  {df.index.min()} -> {df.index.max()}")
    return len(df)

# --- 1-minute, chunked in 7-day windows over ~30 days ---------------------
print("1m (chunked):")
frames = []
end = dt.datetime.now()
for k in range(5):
    e = end - dt.timedelta(days=7*k)
    s = e - dt.timedelta(days=7)
    try:
        d = yf.download("GC=F", start=s.strftime("%Y-%m-%d"), end=e.strftime("%Y-%m-%d"),
                        interval="1m", progress=False, auto_adjust=False)
        if len(d): frames.append(d)
        print(f"   chunk {s.date()}..{e.date()}: {len(d)}")
        time.sleep(1)
    except Exception as ex:
        print("   chunk err", repr(ex)[:120])
if frames:
    df1 = pd.concat(frames).sort_index()
    df1 = df1[~df1.index.duplicated(keep="first")]
    save(df1, "gold_1m.csv")

# --- 5-minute and 15-minute over 60 days ----------------------------------
for interval in ["5m","15m"]:
    print(interval, "(60d):")
    try:
        d = yf.download("GC=F", period="60d", interval=interval, progress=False, auto_adjust=False)
        save(d, f"gold_{interval}.csv")
        time.sleep(1)
    except Exception as ex:
        print("  err", repr(ex)[:120])

# --- 1h over 2y for a longer, lower-frequency sample ----------------------
print("1h (730d):")
try:
    d = yf.download("GC=F", period="730d", interval="1h", progress=False, auto_adjust=False)
    save(d, "gold_1h.csv")
except Exception as ex:
    print("  err", repr(ex)[:120])
