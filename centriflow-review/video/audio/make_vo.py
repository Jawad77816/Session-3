#!/usr/bin/env python3
"""Natural female voiceover via Microsoft Edge neural TTS (edge-tts).
Fits each line to its scene window, assembles -> audio/vo_full.wav.
Edit `segs` text or VOICE to re-voice. Requires proxy + CA bundle in this env."""
import asyncio, os, subprocess, re
import imageio_ffmpeg, edge_tts

os.environ.setdefault("SSL_CERT_FILE", "/root/.ccr/ca-bundle.crt")
PROXY = os.environ.get("HTTPS_PROXY")
FF = imageio_ffmpeg.get_ffmpeg_exe()
os.makedirs("audio", exist_ok=True)

VOICE = "en-US-AriaNeural"   # natural, warm female. Alt: en-US-JennyNeural, en-GB-SoniaNeural
RATE  = "+6%"                 # slight lift for ad energy

# (start, next_scene_start, text)
segs = [
 (0.6, 6.2,  "Your team isn't slow. They're buried in busywork."),
 (6.3, 11.3, "Repetitive tasks. Stalled handoffs. Endless hiring."),
 (11.4,17.3, "Meet GoCentriflow. A.I. agents for every department."),
 (17.5,24.3, "One control plane, with agents customized to how you work."),
 (24.4,44.3, "H R documents in seconds. Invoicing that runs itself. Leads qualified around the clock. Content planned and published. And every meeting, managed."),
 (44.4,50.2, "Working twenty-four seven. Forty plus hours saved every week."),
 (50.1,55.55, "Centralize the chaos. Automate the flow. Start free."),
]

def dur(f):
    e=subprocess.run([FF,"-i",f],capture_output=True,text=True).stderr
    m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',e); h,mn,s=m.groups()
    return int(h)*3600+int(mn)*60+float(s)

async def synth(i,txt):
    mp3=f"audio/raw_{i}.mp3"
    await edge_tts.Communicate(txt, VOICE, rate=RATE, proxy=PROXY).save(mp3)
    return mp3

TRIM=("silenceremove=start_periods=1:start_silence=0.02:start_threshold=-40dB:detection=peak,"
      "areverse,silenceremove=start_periods=1:start_silence=0.02:start_threshold=-40dB:detection=peak,areverse")

async def main():
    delays=[]
    for i,(st,nxt,txt) in enumerate(segs):
        mp3=await synth(i,txt)
        # strip leading/trailing silence so fitting uses true speech length
        trim=f"audio/trim_{i}.wav"
        subprocess.run([FF,"-y","-i",mp3,"-ar","44100","-ac","1","-af",TRIM,trim],capture_output=True)
        d=dur(trim); win=nxt-st
        tempo=min(1.20, d/(win-0.12)) if d>win-0.12 else 1.0
        eff=d/tempo
        af=(f"atempo={tempo:.4f},afade=t=in:st=0:d=0.05,afade=t=out:st={max(0,eff-0.08):.3f}:d=0.09"
            if tempo!=1.0 else "afade=t=in:st=0:d=0.05,afade=t=out:st={:.3f}:d=0.09".format(max(0,d-0.09)))
        subprocess.run([FF,"-y","-i",trim,"-ar","44100","-ac","1","-af",af,f"audio/vo_{i}.wav"],capture_output=True)
        print(f"seg{i} start={st:5.1f} win={win:5.2f} spoken={d:5.2f} tempo={tempo:.3f} eff={eff:5.2f}")
        delays.append(int(st*1000))
    ins=[]; pre=[]; lab=[]
    for i,dl in enumerate(delays):
        ins+=["-i",f"audio/vo_{i}.wav"]; pre.append(f"[{i}]adelay={dl}|{dl}[a{i}]"); lab.append(f"[a{i}]")
    fc=";".join(pre)+";"+"".join(lab)+f"amix=inputs={len(delays)}:normalize=0:dropout_transition=0,apad,atrim=0:55.6[vo]"
    subprocess.run([FF,"-y",*ins,"-filter_complex",fc,"-map","[vo]","-ar","44100","-ac","2","audio/vo_full.wav"],check=True,capture_output=True)
    print("wrote audio/vo_full.wav", round(dur("audio/vo_full.wav"),2),"s")

asyncio.run(main())
