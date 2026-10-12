#!/usr/bin/env python3
"""Detection logic for the Sniper Entry false-breakout strategy.
Exact Python mirror of DetectBuy / DetectSell in
MQL5/Indicators/SniperEntry_FalseBreakout.mq5.  Index 0 = oldest bar."""
DBL_MAX = float("inf")

def is_pivot_high(i, L, rt, high):
    if i - L < 0 or i + L > rt - 1: return False
    v = high[i]
    for k in range(i - L, i + L + 1):
        if k != i and high[k] >= v: return False
    return True

def is_pivot_low(i, L, rt, low):
    if i - L < 0 or i + L > rt - 1: return False
    v = low[i]
    for k in range(i - L, i + L + 1):
        if k != i and low[k] <= v: return False
    return True

def detect_buy(i, rt, o, h, l, c, L=5, lookback=150, reclaim_bars=3,
               require_abcd=True, require_sweep_close=False):
    lo = max(L, i - lookback)
    cIdx = -1
    for j in range(i - 1, lo - 1, -1):
        if is_pivot_high(j, L, rt, h): cIdx = j; break
    if cIdx < 0: return None
    bIdx = -1
    for j in range(cIdx - 1, lo - 1, -1):
        if is_pivot_low(j, L, rt, l): bIdx = j; break
    if bIdx < 0: return None
    support = l[bIdx]
    dIdx = -1; sweep = DBL_MAX
    for j in range(cIdx + 1, i + 1):
        if l[j] < sweep: sweep = l[j]; dIdx = j
    if dIdx < 0 or sweep >= support: return None
    if i - dIdx > reclaim_bars: return None
    if c[i] <= support: return None
    if c[i] <= o[i]: return None
    if require_sweep_close and c[dIdx] >= support: return None
    for j in range(dIdx, i):
        if c[j] > support and c[j] > o[j]: return None
    aIdx = -1
    if require_abcd:
        for j in range(bIdx - 1, lo - 1, -1):
            if is_pivot_high(j, L, rt, h): aIdx = j; break
        if aIdx < 0: return None
        if h[cIdx] >= h[aIdx]: return None
    return dict(A=aIdx, B=bIdx, C=cIdx, D=dIdx, support=support, sweep=sweep)

def detect_sell(i, rt, o, h, l, c, L=5, lookback=150, reclaim_bars=3,
                require_abcd=True, require_sweep_close=False):
    lo = max(L, i - lookback)
    cIdx = -1
    for j in range(i - 1, lo - 1, -1):
        if is_pivot_low(j, L, rt, l): cIdx = j; break
    if cIdx < 0: return None
    bIdx = -1
    for j in range(cIdx - 1, lo - 1, -1):
        if is_pivot_high(j, L, rt, h): bIdx = j; break
    if bIdx < 0: return None
    resistance = h[bIdx]
    dIdx = -1; sweep = -DBL_MAX
    for j in range(cIdx + 1, i + 1):
        if h[j] > sweep: sweep = h[j]; dIdx = j
    if dIdx < 0 or sweep <= resistance: return None
    if i - dIdx > reclaim_bars: return None
    if c[i] >= resistance: return None
    if c[i] >= o[i]: return None
    if require_sweep_close and c[dIdx] <= resistance: return None
    for j in range(dIdx, i):
        if c[j] < resistance and c[j] < o[j]: return None
    aIdx = -1
    if require_abcd:
        for j in range(bIdx - 1, lo - 1, -1):
            if is_pivot_low(j, L, rt, l): aIdx = j; break
        if aIdx < 0: return None
        if l[cIdx] <= l[aIdx]: return None
    return dict(A=aIdx, B=bIdx, C=cIdx, D=dIdx, resistance=resistance, sweep=sweep)
