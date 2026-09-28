#!/usr/bin/env python3
"""Generate a British female voiceover (gTTS), fit each line to its scene window,
assemble a padded timeline -> audio/vo_full.wav. Edit `segs` text to re-voice."""
from gtts import gTTS
import imageio_ffmpeg, subprocess, re, os
FF=imageio_ffmpeg.get_ffmpeg_exe(); os.makedirs("audio",exist_ok=True)

# (start, next_scene_start, text)
segs=[
 (0.6, 6.2,  "Your team isn't slow. They're buried in busywork."),
 (6.3, 11.3, "Repetitive tasks. Stalled handoffs. Hiring just to keep up."),
 (11.4,17.3, "Meet GoCentriflow. A.I. agents for every department."),
 (17.5,24.3, "One control plane, with agents customized to how you work."),
 (24.4,44.3, "H.R. documents in seconds. Invoicing that runs itself. Leads qualified around the clock. Content planned and published. And every meeting, managed."),
 (44.4,50.2, "Working twenty-four seven. Forty plus hours saved every week."),
 (50.4,55.4, "Centralize the chaos. Automate the flow. Start free."),
]
def dur(f):
    e=subprocess.run([FF,"-i",f],capture_output=True,text=True).stderr
    m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',e); h,mn,s=m.groups()
    return int(h)*3600+int(mn)*60+float(s)
delays=[]
for i,(st,nxt,txt) in enumerate(segs):
    mp3=f"audio/raw_{i}.mp3"; gTTS(txt,lang="en",tld="co.uk").save(mp3)
    d=dur(mp3); win=nxt-st; tempo=min(1.22,d/(win-0.12)) if d>win-0.12 else 1.0
    eff=d/tempo
    af=(f"atempo={tempo:.4f},afade=t=in:st=0:d=0.06,afade=t=out:st={max(0,eff-0.08):.3f}:d=0.08"
        if tempo!=1.0 else "afade=t=in:st=0:d=0.06")
    subprocess.run([FF,"-y","-i",mp3,"-ar","44100","-ac","1","-af",af,f"audio/vo_{i}.wav"],capture_output=True)
    delays.append(int(st*1000))
ins=[]; pre=[]; lab=[]
for i,dl in enumerate(delays):
    ins+=["-i",f"audio/vo_{i}.wav"]; pre.append(f"[{i}]adelay={dl}|{dl}[a{i}]"); lab.append(f"[a{i}]")
fc=";".join(pre)+";"+"".join(lab)+f"amix=inputs={len(delays)}:normalize=0:dropout_transition=0,apad,atrim=0:55.6[vo]"
subprocess.run([FF,"-y",*ins,"-filter_complex",fc,"-map","[vo]","-ar","44100","-ac","2","audio/vo_full.wav"],check=True,capture_output=True)
print("wrote audio/vo_full.wav")
