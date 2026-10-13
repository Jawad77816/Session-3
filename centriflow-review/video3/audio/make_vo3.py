#!/usr/bin/env python3
"""Humanized female VO via Piper (en_GB jenny_dioco). Brand respelled
"Go Sentry-flow" so it reads /sen-tri-flow/ (not cen-TRY). -> audio/vo_full.wav"""
import os, subprocess, re
import imageio_ffmpeg
FF=imageio_ffmpeg.get_ffmpeg_exe()
HERE=os.path.dirname(os.path.abspath(__file__))
MODEL=os.path.join(HERE,"piper","en_GB-jenny_dioco-medium.onnx")
LEN="1.0"   # natural pace

# start, next, text  (punctuation guides natural prosody / pauses)
segs=[
 (0.5, 4.2, "Let's be honest. Your team is buried in busywork."),
 (4.6, 8.7, "Chasing invoices. Booking meetings. Copying the same data, over and over."),
 (9.3, 13.6,"So, meet Go Sentry-flow. Your very own team of A.I. agents."),
 (14.5,23.7,"They handle your H.R., your sales, invoicing and content. All day, every day. Right inside the tools you already use."),
 (24.6,29.9,"Get forty hours back, every week. Try Go Sentry-flow, free."),
]
TRIM=("silenceremove=start_periods=1:start_silence=0.02:start_threshold=-38dB:detection=peak,"
      "areverse,silenceremove=start_periods=1:start_silence=0.02:start_threshold=-38dB:detection=peak,areverse")
def dur(f):
    e=subprocess.run([FF,"-i",f],capture_output=True,text=True).stderr
    m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',e); h,mn,s=m.groups(); return int(h)*3600+int(mn)*60+float(s)
delays=[]
for i,(st,nxt,txt) in enumerate(segs):
    raw=f"audio/praw_{i}.wav"
    subprocess.run(["piper","-m",MODEL,"-f",raw,"--length-scale",LEN,"--sentence-silence","0.14"],
                   input=txt,text=True,capture_output=True)
    trim=f"audio/trim_{i}.wav"
    subprocess.run([FF,"-y","-i",raw,"-ar","44100","-ac","1","-af",TRIM,trim],capture_output=True)
    d=dur(trim); win=nxt-st; tempo=min(1.14,d/(win-0.1)) if d>win-0.1 else 1.0; eff=d/tempo
    af=(f"atempo={tempo:.4f}," if tempo!=1.0 else "")+f"afade=t=in:st=0:d=0.04,afade=t=out:st={max(0,eff-0.08):.3f}:d=0.08"
    subprocess.run([FF,"-y","-i",trim,"-ar","44100","-ac","1","-af",af,f"audio/vo_{i}.wav"],capture_output=True)
    print(f"seg{i} start={st:5.1f} win={win:5.2f} spoken={d:5.2f} tempo={tempo:.3f} eff={eff:5.2f}")
    delays.append(int(st*1000))
ins=[];pre=[];lab=[]
for i,dl in enumerate(delays):
    ins+=["-i",f"audio/vo_{i}.wav"]; pre.append(f"[{i}]adelay={dl}|{dl}[a{i}]"); lab.append(f"[a{i}]")
fc=";".join(pre)+";"+"".join(lab)+f"amix=inputs={len(delays)}:normalize=0:dropout_transition=0,apad,atrim=0:30.0[vo]"
subprocess.run([FF,"-y",*ins,"-filter_complex",fc,"-map","[vo]","-ar","44100","-ac","2","audio/vo_full.wav"],check=True,capture_output=True)
print("wrote audio/vo_full.wav", round(dur("audio/vo_full.wav"),2),"s")
