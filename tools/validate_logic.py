#!/usr/bin/env python3
"""Faithful Python port of the CORRECTED MQL5 DetectBuy logic.
Anchored on C (the lower high) so the sweep low D is never mistaken for the
support B. Index 0 = oldest bar (same convention as the indicator)."""
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
               require_abcd=True, require_sweep_close=False, debug=False):
    lo = max(L, i - lookback)
    # C : most recent pivot HIGH before i (the lower high before the breakdown)
    cIdx = -1
    for j in range(i - 1, lo - 1, -1):
        if is_pivot_high(j, L, rt, h): cIdx = j; break
    if cIdx < 0:
        if debug: print(f"    [{i}] no pivot-high C");
        return None
    # B : most recent pivot LOW before C (the support / pullback low)
    bIdx = -1
    for j in range(cIdx - 1, lo - 1, -1):
        if is_pivot_low(j, L, rt, l): bIdx = j; break
    if bIdx < 0:
        if debug: print(f"    [{i}] no pivot-low B before C({cIdx})")
        return None
    support = l[bIdx]
    # D : lowest low AFTER C up to i -> the sweep; must pierce below support
    dIdx = -1; sweep = DBL_MAX
    for j in range(cIdx + 1, i + 1):
        if l[j] < sweep: sweep = l[j]; dIdx = j
    if dIdx < 0 or sweep >= support:
        if debug: print(f"    [{i}] C={cIdx} B={bIdx} support={support:.2f} sweep={sweep:.2f} -> no break below support")
        return None
    if i - dIdx > reclaim_bars:
        if debug: print(f"    [{i}] reclaim too late i-D={i-dIdx}")
        return None
    if c[i] <= support:
        if debug: print(f"    [{i}] close {c[i]:.2f} <= support {support:.2f}")
        return None
    if c[i] <= o[i]:
        if debug: print(f"    [{i}] not bullish close")
        return None
    if require_sweep_close and c[dIdx] >= support:
        return None
    # one signal per sweep: bar i must be the FIRST bullish reclaim since the sweep
    for j in range(dIdx, i):
        if c[j] > support and c[j] > o[j]:
            if debug: print(f"    [{i}] already reclaimed at bar {j}")
            return None
    # A : most recent pivot HIGH before B -> require lower-high (A > C)
    aIdx = -1
    if require_abcd:
        for j in range(bIdx - 1, lo - 1, -1):
            if is_pivot_high(j, L, rt, h): aIdx = j; break
        if aIdx < 0:
            if debug: print(f"    [{i}] no A before B({bIdx})")
            return None
        if h[cIdx] >= h[aIdx]:
            if debug: print(f"    [{i}] C high {h[cIdx]:.2f} not lower than A {h[aIdx]:.2f}")
            return None
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
    # one signal per sweep: first bearish reclaim since the sweep
    for j in range(dIdx, i):
        if c[j] < resistance and c[j] < o[j]:
            return None
    aIdx = -1
    if require_abcd:
        for j in range(bIdx - 1, lo - 1, -1):
            if is_pivot_low(j, L, rt, l): aIdx = j; break
        if aIdx < 0: return None
        if l[cIdx] <= l[aIdx]: return None   # C must be a HIGHER low than A
    return dict(A=aIdx, B=bIdx, C=cIdx, D=dIdx, resistance=resistance, sweep=sweep)

def scan(o, h, l, c, L=5, fn=detect_buy, **kw):
    rt = len(c); sigs=[]
    for i in range(L + 1, rt - 1):
        r = fn(i, rt, o, h, l, c, L=L, **kw)
        if r: sigs.append((i, r))
    return sigs

def bars_from_path(path, rng=0.08):
    o=[];h=[];l=[];c=[]; prev=path[0][0]
    for cl, sh, sl in path:
        op=prev; hi=max(op,cl)+rng; loo=min(op,cl)-rng
        if sh: hi += 0.25
        if sl: loo -= 0.25
        o.append(op);h.append(hi);l.append(loo);c.append(cl); prev=cl
    return o,h,l,c

# ---- TEST 1 : ideal BUY A-B-C-D --------------------------------------------
L=3
path=[]
for _ in range(6): path.append((1819.0, False, False))        # filler 0..5
for cl in [1819.3,1819.7,1820.1,1820.5]: path.append((cl,False,False))  # up 6..9
path.append((1820.9, True, False))                            # A high  idx10
for cl in [1820.5,1820.1]: path.append((cl,False,False))      # 11,12
path.append((1819.85, False, True))                           # B low/support idx13
for cl in [1820.1,1820.4]: path.append((cl,False,False))      # 14,15
path.append((1820.55, True, False))                           # C lower high idx16
for cl in [1820.2,1819.95]: path.append((cl,False,False))     # 17,18
path.append((1819.70, False, True))                           # D sweep low idx19
path.append((1819.98, False, False))                          # reclaim idx20 (close>support)
for cl in [1820.3,1820.7,1821.1,1821.5]: path.append((cl,False,False))

o,h,l,c = bars_from_path(path); rt=len(c)
print(f"B(13).low={l[13]:.2f}  C(16).high={h[16]:.2f}  A(10).high={h[10]:.2f}  "
      f"D(19).low={l[19]:.2f}  reclaim(20) {o[20]:.2f}->{c[20]:.2f}")
print("Debug @ idx20:"); detect_buy(20, rt, o,h,l,c, L=L, debug=True)
sigs = scan(o,h,l,c, L=L, require_abcd=True)
print("TEST 1 (ideal A-B-C-D BUY):  SIGNALS=", len(sigs))
for i,r in sigs:
    entry=c[i]; sl=round(entry-2*0.10,2); risk=entry-sl
    print(f"  bar {i}: BUY  A={r['A']}(h={h[r['A']]:.2f}) B={r['B']}(l={l[r['B']]:.2f}) "
          f"C={r['C']}(h={h[r['C']]:.2f}) D={r['D']}(l={l[r['D']]:.2f}) support={r['support']:.2f} "
          f"sweep={r['sweep']:.2f} | entry={entry:.2f} SL={sl:.2f} TP={round(entry+risk*10,2)} (R:R 1:10)")
assert len(sigs) >= 1, "FAIL: expected a BUY"
i,r = sigs[0]
assert r['A'] < r['B'] < r['C'] < r['D'] <= i, "ABCD order"
assert h[r['C']] < h[r['A']], "C lower high than A"
assert r['sweep'] < r['support'], "D sweeps below support"
assert r['B'] == 13 and r['C'] == 16 and r['D'] == 19 and r['A'] == 10, f"unexpected pivots {r}"
print("  -> pivots A=10,B=13,C=16,D=19 correct; ordering + lower-high + sweep OK")

# ---- TEST 2 : flat noise ----------------------------------------------------
import random; random.seed(7)
o2=[];h2=[];l2=[];c2=[]; p=1800.0
for _ in range(150):
    op=p; cl=p+random.uniform(-0.04,0.04); o2.append(op)
    h2.append(max(op,cl)+0.02); l2.append(min(op,cl)-0.02); c2.append(cl); p=cl
print("TEST 2 (flat noise):         BUY=", len(scan(o2,h2,l2,c2,L=5,require_abcd=True)), "(expect 0)")

# ---- TEST 3 : genuine breakdown, price never closes back above support -----
o3,h3,l3,c3 = bars_from_path(path)
support13 = l3[13]
for k in range(20, len(c3)):          # whole tail stays below support
    o3[k]=support13-0.10; c3[k]=support13-0.15-0.02*(k-20)
    h3[k]=support13-0.05; l3[k]=c3[k]-0.05
s3=[s for s in scan(o3,h3,l3,c3,L=L,require_abcd=True) if s[0] >= 19]
print("TEST 3 (no reclaim):         BUY after sweep=", len(s3), "(expect 0)")
assert len(s3)==0

# ---- TEST 4 : no sweep below support ---------------------------------------
o4,h4,l4,c4 = bars_from_path(path); l4[19]=1819.95   # D stays above support 1819.85
s4=[s for s in scan(o4,h4,l4,c4,L=L,require_abcd=True) if s[0]==20]
print("TEST 4 (no false breakout):  BUY at reclaim=", len(s4), "(expect 0)")
assert len(s4)==0

# ---- TEST 5 : SELL mirror ---------------------------------------------------
pathS=[]
for _ in range(6): pathS.append((1821.0, False, False))
for cl in [1820.7,1820.3,1819.9,1819.5]: pathS.append((cl,False,False))
pathS.append((1819.1, False, True))                           # A low  idx10
for cl in [1819.5,1819.9]: pathS.append((cl,False,False))
pathS.append((1820.15, True, False))                          # B high/resistance idx13
for cl in [1819.9,1819.6]: pathS.append((cl,False,False))
pathS.append((1819.45, False, True))                          # C higher low idx16
for cl in [1819.8,1820.05]: pathS.append((cl,False,False))
pathS.append((1820.30, True, False))                          # D sweep high idx19
pathS.append((1820.02, False, False))                         # reclaim idx20 close<resistance
for cl in [1819.7,1819.3,1818.9,1818.5]: pathS.append((cl,False,False))
oS,hS,lS,cS = bars_from_path(pathS)
# make reclaim bar explicitly bearish
oS[20]=1820.18; cS[20]=1820.02; hS[20]=1820.20; lS[20]=1819.98
sigS = scan(oS,hS,lS,cS,L=L, fn=detect_sell, require_abcd=True)
print("TEST 5 (ideal A-B-C-D SELL): SIGNALS=", len(sigS))
for i,r in sigS[:3]:
    entry=cS[i]; sl=round(entry+2*0.10,2)
    print(f"  bar {i}: SELL A={r['A']}(l={lS[r['A']]:.2f}) B={r['B']}(h={hS[r['B']]:.2f}) "
          f"C={r['C']}(l={lS[r['C']]:.2f}) D={r['D']}(h={hS[r['D']]:.2f}) res={r['resistance']:.2f} "
          f"sweep={r['sweep']:.2f} | entry={entry:.2f} SL={sl:.2f}")
assert len(sigS) >= 1, "FAIL: expected a SELL"
print("  -> SELL mirror fires correctly")

print("\nALL LOGIC CHECKS PASSED")
