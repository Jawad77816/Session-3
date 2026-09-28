#!/usr/bin/env python3
"""Soft, license-free music bed that BUILDS: warm pad + subtle beat that grows,
a riser + impact into the CTA, and a brighter, louder climax. -> audio/music.wav"""
import numpy as np, wave
sr=44100; T=55.8; n=int(sr*T); t=np.arange(n)/sr
L=np.zeros(n); R=np.zeros(n)

# ---- energy curve (problem quiet -> solution -> climax) ----
def ramp(t, pts):
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    return np.interp(t, xs, ys)
energy=ramp(t, [(0,0.45),(6,0.5),(11,0.55),(11.4,0.7),(24,0.82),(44,0.9),(50.1,1.05),(52,1.12),(55.8,1.12)])

# ---- warm pad (C major I-V-vi-IV) ----
prog=[[261.63,329.63,392.00,587.33],[196.00,246.94,392.00,493.88],
      [220.00,261.63,329.63,392.00],[174.61,220.00,261.63,329.63]]
bass=[65.41,98.00,110.00,87.31]; seg=4.0; over=0.9
def env(Ln,atk,rel):
    e=np.ones(Ln); a=int(atk*sr); r=int(rel*sr)
    if a>0: e[:a]=np.linspace(0,1,a)**1.6
    if r>0: e[-r:]=np.linspace(1,0,r)**1.6
    return e
i=0; ti=0.0
while ti<T:
    ch=prog[i%4]; b=bass[i%4]; s0=int(ti*sr); s1=min(n,s0+int((seg+over)*sr)); Ln=s1-s0
    if Ln<=0: break
    tt=np.arange(Ln)/sr; buf=np.zeros(Ln)
    for f in ch:
        for det in (-0.25,0.25):
            buf+=np.sin(2*np.pi*(f+det)*tt)+0.18*np.sin(2*np.pi*2*(f+det)*tt)
    # brighter upper octave grows with energy
    for f in ch:
        buf+=0.12*np.sin(2*np.pi*2*f*tt)
    buf+=1.5*np.sin(2*np.pi*b*tt); buf*=env(Ln,0.6,over+0.3)/(len(ch)*2)
    L[s0:s1]+=buf*0.98; R[s0:s1]+=buf*1.02; i+=1; ti+=seg

# ---- subtle beat that builds (kick + offbeat hat + backbeat clap) ----
rng=np.random.default_rng(7)
def add(dst, s0, sig):
    s1=min(n, s0+len(sig)); dst[s0:s1]+=sig[:s1-s0]
bpm=120; beat=60.0/bpm
def kick(dur=0.28):
    tt=np.arange(int(dur*sr))/sr
    f=50+70*np.exp(-tt*45)
    return np.sin(2*np.pi*np.cumsum(f)/sr)*np.exp(-tt*7.0)
def hat(dur=0.05):
    tt=np.arange(int(dur*sr))/sr
    return (rng.standard_normal(len(tt)))*np.exp(-tt*90)*0.5
def clap(dur=0.12):
    tt=np.arange(int(dur*sr))/sr
    return (rng.standard_normal(len(tt)))*np.exp(-tt*30)*0.6
k=0; tb=11.4
while tb<T-0.1:
    g=float(np.interp(tb,t,energy))
    s0=int(tb*sr)
    add(L,s0,kick()*0.55*g); add(R,s0,kick()*0.55*g)
    if tb>=24:  # offbeat hats
        so=int((tb+beat/2)*sr); add(L,so,hat()*0.16*g); add(R,so,hat()*0.16*g)
    if tb>=24 and k%2==1:  # backbeat clap on 2 & 4
        add(L,s0,clap()*0.22*g); add(R,s0,clap()*0.22*g)
    k+=1; tb+=beat

# ---- riser + impact into the CTA (~50.1s) ----
r0=48.0; r1=50.15
ri=np.arange(int((r1-r0)*sr))/sr
sweep=np.sin(2*np.pi*np.cumsum(200+ (2200-200)*(ri/(r1-r0)))/sr)
noise=rng.standard_normal(len(ri))
riser=(0.5*sweep+0.5*noise)*np.linspace(0,0.35,len(ri))**1.5
add(L,int(r0*sr),riser); add(R,int(r0*sr),riser*0.98)
# impact boom + splash at CTA
imp_t=np.arange(int(0.6*sr))/sr
boom=np.sin(2*np.pi*np.cumsum(90*np.exp(-imp_t*8)+40)/sr)*np.exp(-imp_t*6)*0.8
splash=rng.standard_normal(len(imp_t))*np.exp(-imp_t*9)*0.3
add(L,int(50.15*sr),boom+splash); add(R,int(50.15*sr),boom+splash*0.97)

# ---- apply energy, gentle movement, master fades ----
lfo=0.9+0.1*np.sin(2*np.pi*0.09*t)
L*=energy*lfo; R*=energy*lfo
fin=int(1.5*sr); fout=int(0.7*sr)
for ch in (L,R):
    ch[:fin]*=np.linspace(0,1,fin)**1.4
    ch[-fout:]*=np.linspace(1,0,fout)**1.2
M=np.stack([L,R],1)
M=M/np.max(np.abs(M))*(10**(-18/20)); M=np.tanh(M*1.15)/1.15
with wave.open("audio/music.wav","w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((M*32767).astype(np.int16).tobytes())
print("wrote audio/music.wav (building mix)")
