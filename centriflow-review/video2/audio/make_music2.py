#!/usr/bin/env python3
"""New cinematic/driving license-free track: moody intro -> lift -> four-on-the-
floor showcase -> big CTA. Anthemic Am-F-C-G with a melodic hook + sidechain pump.
-> audio/music.wav"""
import numpy as np, wave
sr=44100; T=30.1; n=int(sr*T); t=np.arange(n)/sr
L=np.zeros(n); R=np.zeros(n)
rng=np.random.default_rng(11)
def add(dst,s0,sig):
    s1=min(n,s0+len(sig));
    if s1>s0: dst[s0:s1]+=sig[:s1-s0]
def ramp(tt,pts): return np.interp(tt,[p[0] for p in pts],[p[1] for p in pts])
energy=ramp(t,[(0,0.4),(8.8,0.5),(9,0.72),(14,0.92),(23.8,0.98),(24,1.12),(27,1.18),(30.1,1.18)])

# ---- chords (Am F C G) 2s each ----
chords=[[220.00,261.63,329.63,440.0],[174.61,220.00,261.63,349.23],
        [261.63,329.63,392.00,523.25],[196.00,246.94,392.00,493.88]]
basses=[110.0,87.31,130.81,98.0]; seg=2.0; over=0.5
def envp(Ln,atk,rel):
    e=np.ones(Ln); a=int(atk*sr); r=int(rel*sr)
    if a>0:e[:a]=np.linspace(0,1,a)**1.4
    if r>0:e[-r:]=np.linspace(1,0,r)**1.4
    return e
pad=np.zeros(n); bass=np.zeros(n)
i=0;ti=0.0
while ti<T:
    ch=chords[i%4]; b=basses[i%4]; s0=int(ti*sr); Ln=int((seg+over)*sr); tt=np.arange(Ln)/sr
    buf=np.zeros(Ln)
    for f in ch:
        for d in (-0.2,0.2): buf+=np.sin(2*np.pi*(f+d)*tt)+0.16*np.sin(2*np.pi*2*(f+d)*tt)
    buf*=envp(Ln,0.25,over+0.2)/(len(ch)*2)
    add(pad,s0,buf)
    bb=np.sin(2*np.pi*b*tt)*np.exp(-tt*0.6)*envp(Ln,0.01,0.3)
    add(bass,s0,bb*1.2)
    i+=1; ti+=seg

# ---- melodic pluck hook (C pentatonic) from reveal ----
mel=[659.25,783.99,880.0,783.99, 659.25,587.33,659.25,0]  # E5 G5 A5 G5 E5 D5 E5 -
mt=9.0; step=0.5; k=0
while mt<T-0.2:
    f=mel[k%len(mel)]
    if f>0 and mt>=9.0:
        s0=int(mt*sr); d=int(0.42*sr); tt=np.arange(d)/sr
        tone=(0.6*np.sin(2*np.pi*f*tt)+0.25*np.sin(2*np.pi*2*f*tt)+0.12*np.sin(2*np.pi*3*f*tt))
        tone*=np.exp(-tt*4.2)*0.22*float(np.interp(mt,t,energy))
        add(L,s0,tone*0.95); add(R,s0,tone*1.05)
    k+=1; mt+=step

# ---- drums ----
def kick(dur=0.3):
    tt=np.arange(int(dur*sr))/sr; f=52+90*np.exp(-tt*42); return np.sin(2*np.pi*np.cumsum(f)/sr)*np.exp(-tt*6.5)
def hat(dur=0.05): tt=np.arange(int(dur*sr))/sr; return rng.standard_normal(len(tt))*np.exp(-tt*95)*0.5
def clap(dur=0.13): tt=np.arange(int(dur*sr))/sr; return rng.standard_normal(len(tt))*np.exp(-tt*26)*0.6
beat=0.5  # 120bpm
kick_times=[]
tb=9.0
while tb<T-0.05:
    g=float(np.interp(tb,t,energy)); s0=int(tb*sr)
    heavy = tb>=14.0
    add(L,s0,kick()*(0.75 if heavy else 0.4)*g); add(R,s0,kick()*(0.75 if heavy else 0.4)*g); kick_times.append(tb)
    if heavy:
        so=int((tb+beat/2)*sr); add(L,so,hat()*0.18*g); add(R,so,hat()*0.18*g)
        if int(round((tb-14.0)/beat))%2==1:
            add(L,s0,clap()*0.24*g); add(R,s0,clap()*0.24*g)
    tb+=beat

# ---- sidechain PUMP on pad+bass (classic ducking to the kick) ----
duck=np.ones(n)
for kt in kick_times:
    s0=int(kt*sr); Ln=int(0.42*sr); tt=np.arange(Ln)/sr
    dip=1-0.55*np.exp(-tt*7.0)   # dip then recover
    s1=min(n,s0+Ln); duck[s0:s1]=np.minimum(duck[s0:s1],dip[:s1-s0])
pad*=duck; bass*=duck
L+=pad; R+=pad; L+=bass*0.9; R+=bass*0.9

# ---- risers + impacts (reveal 9.0, CTA 24.0) ----
def riser(t0,t1,amp=0.3):
    ri=np.arange(int((t1-t0)*sr))/sr; sweep=np.sin(2*np.pi*np.cumsum(220+(2600-220)*(ri/(t1-t0)))/sr)
    sig=(0.5*sweep+0.5*rng.standard_normal(len(ri)))*np.linspace(0,amp,len(ri))**1.5
    add(L,int(t0*sr),sig); add(R,int(t0*sr),sig*0.98)
def impact(t0):
    it=np.arange(int(0.7*sr))/sr
    boom=np.sin(2*np.pi*np.cumsum(95*np.exp(-it*7)+42)/sr)*np.exp(-it*5.5)*0.85
    crash=rng.standard_normal(len(it))*np.exp(-it*7)*0.33
    add(L,int(t0*sr),boom+crash); add(R,int(t0*sr),boom+crash*0.96)
riser(7.6,9.0,0.28); riser(22.7,24.0,0.34); impact(9.0); impact(24.0)

# ---- energy, fades, normalize ----
lfo=0.92+0.08*np.sin(2*np.pi*0.1*t)
L*=energy*lfo; R*=energy*lfo
fin=int(0.8*sr); fout=int(0.7*sr)
for ch in (L,R):
    ch[:fin]*=np.linspace(0,1,fin)**1.3; ch[-fout:]*=np.linspace(1,0,fout)**1.2
M=np.stack([L,R],1); M=M/np.max(np.abs(M))*(10**(-15/20)); M=np.tanh(M*1.1)/1.1
with wave.open("audio/music.wav","w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes((M*32767).astype(np.int16).tobytes())
print("wrote audio/music.wav (cinematic/driving)")
