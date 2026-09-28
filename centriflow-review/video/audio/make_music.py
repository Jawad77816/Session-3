#!/usr/bin/env python3
"""Synthesize a soft, license-free music pad (C-major I-V-vi-IV) -> audio/music.wav"""
import numpy as np, wave
sr=44100; T=55.8
n=int(sr*T); t=np.arange(n)/sr
master=np.zeros((n,2))
prog=[[261.63,329.63,392.00,587.33],[196.00,246.94,392.00,493.88],
      [220.00,261.63,329.63,392.00],[174.61,220.00,261.63,329.63]]
bass=[65.41,98.00,110.00,87.31]; seg=4.0; over=0.9
def env(L,atk,rel):
    e=np.ones(L); a=int(atk*sr); r=int(rel*sr)
    if a>0: e[:a]=np.linspace(0,1,a)**1.6
    if r>0: e[-r:]=np.linspace(1,0,r)**1.6
    return e
lfo=0.5+0.5*np.sin(2*np.pi*0.08*t)
i=0; ti=0.0
while ti<T:
    ch=prog[i%4]; b=bass[i%4]; s0=int(ti*sr); s1=min(n,s0+int((seg+over)*sr)); L=s1-s0
    if L<=0: break
    tt=np.arange(L)/sr; buf=np.zeros(L)
    for f in ch:
        for det in (-0.25,0.25):
            buf+=np.sin(2*np.pi*(f+det)*tt)+0.18*np.sin(2*np.pi*2*(f+det)*tt)
    buf+=1.6*np.sin(2*np.pi*b*tt); buf*=env(L,0.6,over+0.3)/(len(ch)*2)
    master[s0:s1,0]+=buf*0.98; master[s0:s1,1]+=buf*1.02; i+=1; ti+=seg
arp=[523.25,659.25,783.99,987.77]
for k in range(int(T/0.75)):
    s0=int((k*0.75+0.2)*sr); s1=min(n,s0+int(0.6*sr))
    if s1<=s0: continue
    tt=np.arange(s1-s0)/sr; bell=np.sin(2*np.pi*arp[k%4]*tt)*np.exp(-tt*5)*0.06
    master[s0:s1,0]+=bell; master[s0:s1,1]+=bell
master*=(0.85+0.15*lfo)[:,None]
fin=int(2*sr); fout=int(3.2*sr)
master[:fin]*=np.linspace(0,1,fin)[:,None]**1.5
master[-fout:]*=np.linspace(1,0,fout)[:,None]**1.4
master=master/np.max(np.abs(master))*(10**(-20/20)); master=np.tanh(master*1.2)/1.2
with wave.open("audio/music.wav","w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((master*32767).astype(np.int16).tobytes())
print("wrote audio/music.wav")
