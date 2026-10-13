#!/usr/bin/env python3
"""Cleaner/punchier license-free track: supersaw pads + sub bass + bright hook,
moody intro -> drop at reveal -> driving showcase -> big CTA, sidechain pump.
-> audio/music.wav"""
import numpy as np, wave
sr=44100; T=30.1; n=int(sr*T); t=np.arange(n)/sr
L=np.zeros(n); R=np.zeros(n); rng=np.random.default_rng(23)
def add(d,s0,s):
    s1=min(n,s0+len(s))
    if s1>s0: d[s0:s1]+=s[:s1-s0]
def ramp(tt,p): return np.interp(tt,[x[0] for x in p],[x[1] for x in p])
energy=ramp(t,[(0,0.38),(8.8,0.5),(9,0.74),(14,0.94),(23.8,1.0),(24,1.14),(27,1.2),(30.1,1.2)])
def saw(f,tt): x=f*tt; return 2*(x-np.floor(0.5+x))

chords=[[220.00,261.63,329.63,440.0],[174.61,220.00,261.63,349.23],
        [261.63,329.63,392.00,523.25],[196.00,246.94,392.00,493.88]]
roots=[55.0,43.66,65.41,49.0]; seg=2.0; over=0.5
det=[-0.18,-0.11,-0.04,0,0.04,0.11,0.18]
def envp(Ln,a,r):
    e=np.ones(Ln); ai=int(a*sr); ri=int(r*sr)
    if ai>0:e[:ai]=np.linspace(0,1,ai)**1.4
    if ri>0:e[-ri:]=np.linspace(1,0,ri)**1.4
    return e
pad=np.zeros(n); sub=np.zeros(n)
i=0;ti=0.0
while ti<T:
    ch=chords[i%4]; ro=roots[i%4]; s0=int(ti*sr); Ln=int((seg+over)*sr); tt=np.arange(Ln)/sr
    buf=np.zeros(Ln)
    for f in ch:
        for c in det: buf+=saw(f*(1+c*0.006),tt)
    buf*=envp(Ln,0.2,over+0.25)/(len(ch)*len(det))
    # soft lowpass (1-pole) to tame saw harshness
    a=0.18
    for _ in range(2):
        buf=np.concatenate([[buf[0]],buf[1:]*a+buf[:-1]*(1-a)])
    add(pad,s0,buf*1.3)
    bb=np.sin(2*np.pi*ro*tt)*envp(Ln,0.01,0.3)
    add(sub,s0,bb*1.4)
    i+=1; ti+=seg

# bright melodic hook (C penta) from reveal
mel=[659.25,987.77,880.0,659.25, 587.33,659.25,880.0,0]
k=0; mt=9.0
while mt<T-0.2:
    f=mel[k%len(mel)]
    if f>0:
        s0=int(mt*sr); d=int(0.4*sr); tt=np.arange(d)/sr
        tone=(0.5*np.sin(2*np.pi*f*tt)+0.3*saw(f,tt)+0.15*np.sin(2*np.pi*2*f*tt))
        tone*=np.exp(-tt*4.5)*0.2*float(np.interp(mt,t,energy))
        add(L,s0,tone*0.95); add(R,s0,tone*1.05)
    k+=1; mt+=0.5

# drums
def kick(dur=0.3):
    tt=np.arange(int(dur*sr))/sr; body=np.sin(2*np.pi*np.cumsum(50+95*np.exp(-tt*40))/sr)*np.exp(-tt*6.2)
    click=rng.standard_normal(int(0.004*sr))*np.linspace(1,0,int(0.004*sr))
    out=body.copy(); out[:len(click)]+=click*0.6; return out
def hat(dur=0.045): tt=np.arange(int(dur*sr))/sr; return rng.standard_normal(len(tt))*np.exp(-tt*110)*0.5
def clap(dur=0.12): tt=np.arange(int(dur*sr))/sr; return rng.standard_normal(len(tt))*np.exp(-tt*28)*0.6
beat=0.5; kt=[]; tb=9.0
while tb<T-0.05:
    g=float(np.interp(tb,t,energy)); s0=int(tb*sr); heavy=tb>=14.0
    add(L,s0,kick()*(0.8 if heavy else 0.42)*g); add(R,s0,kick()*(0.8 if heavy else 0.42)*g); kt.append(tb)
    if heavy:
        so=int((tb+beat/2)*sr); add(L,so,hat()*0.17*g); add(R,so,hat()*0.17*g)
        if int(round((tb-14.0)/beat))%2==1: add(L,s0,clap()*0.23*g); add(R,s0,clap()*0.23*g)
    tb+=beat

# sidechain pump on pad+sub
duck=np.ones(n)
for x in kt:
    s0=int(x*sr); Ln=int(0.4*sr); tt=np.arange(Ln)/sr; dip=1-0.6*np.exp(-tt*7.5)
    s1=min(n,s0+Ln); duck[s0:s1]=np.minimum(duck[s0:s1],dip[:s1-s0])
pad*=duck; sub*=duck
L+=pad; R+=pad; L+=sub; R+=sub

def riser(t0,t1,amp):
    ri=np.arange(int((t1-t0)*sr))/sr; sw=np.sin(2*np.pi*np.cumsum(220+(2600-220)*(ri/(t1-t0)))/sr)
    s=(0.5*sw+0.5*rng.standard_normal(len(ri)))*np.linspace(0,amp,len(ri))**1.5
    add(L,int(t0*sr),s); add(R,int(t0*sr),s*0.98)
def impact(t0):
    it=np.arange(int(0.7*sr))/sr
    boom=np.sin(2*np.pi*np.cumsum(95*np.exp(-it*7)+42)/sr)*np.exp(-it*5.5)*0.85
    crash=rng.standard_normal(len(it))*np.exp(-it*7)*0.32
    add(L,int(t0*sr),boom+crash); add(R,int(t0*sr),boom+crash*0.96)
riser(7.6,9.0,0.3); riser(22.7,24.0,0.36); impact(9.0); impact(24.0)

lfo=0.93+0.07*np.sin(2*np.pi*0.1*t); L*=energy*lfo; R*=energy*lfo
fin=int(0.8*sr); fout=int(0.7*sr)
for ch in (L,R): ch[:fin]*=np.linspace(0,1,fin)**1.3; ch[-fout:]*=np.linspace(1,0,fout)**1.2
M=np.stack([L,R],1); M=M/np.max(np.abs(M))*(10**(-15/20)); M=np.tanh(M*1.1)/1.1
with wave.open("audio/music.wav","w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes((M*32767).astype(np.int16).tobytes())
print("wrote audio/music.wav (v3)")
