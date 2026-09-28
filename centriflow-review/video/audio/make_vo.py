#!/usr/bin/env python3
"""Energetic female voiceover via Microsoft Edge neural TTS (edge-tts).
Rising problem->solution arc, faster pace, jubilant CTA. Fits each line to
its scene window and assembles -> audio/vo_full.wav."""
import asyncio, os, subprocess, re
import imageio_ffmpeg, edge_tts

os.environ.setdefault("SSL_CERT_FILE", "/root/.ccr/ca-bundle.crt")
PROXY = os.environ.get("HTTPS_PROXY")
FF = imageio_ffmpeg.get_ffmpeg_exe()
os.makedirs("audio", exist_ok=True)

VOICE = "en-US-AvaNeural"   # natural + expressive female

# start, next_start, text, rate, pitch  (energy rises toward the CTA)
segs = [
 (0.6, 6.2,  "Let's be honest. Your team is drowning in busywork.",              "+10%", "+0Hz"),
 (6.3, 11.3, "Repetitive tasks. Stalled handoffs. Endless hiring.",              "+12%", "+0Hz"),
 (11.4,17.3, "It's time to change that. Meet GoCentriflow. AI agents for every department.", "+16%", "+8Hz"),
 (17.5,24.3, "One powerful control plane, with agents built around how you work.","+15%", "+4Hz"),
 (24.4,36.6, "HR documents in seconds. Invoicing that runs itself. Leads qualified around the clock. Content planned and published. Every meeting, handled.", "+17%", "+4Hz"),
 (37.2,44.3, "Your entire back office, running itself.", "+16%", "+6Hz"),
 (44.4,50.2, "Working twenty-four seven. Forty plus hours saved, every single week!", "+18%", "+8Hz"),
 (50.1,55.55,"Centralize the chaos. Automate the flow. Get started free, with GoCentriflow!", "+20%", "+12Hz"),
]

TRIM=("silenceremove=start_periods=1:start_silence=0.02:start_threshold=-40dB:detection=peak,"
      "areverse,silenceremove=start_periods=1:start_silence=0.02:start_threshold=-40dB:detection=peak,areverse")

def dur(f):
    e=subprocess.run([FF,"-i",f],capture_output=True,text=True).stderr
    m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',e); h,mn,s=m.groups()
    return int(h)*3600+int(mn)*60+float(s)

async def main():
    delays=[]
    for i,(st,nxt,txt,rate,pitch) in enumerate(segs):
        mp3=f"audio/raw_{i}.mp3"
        await edge_tts.Communicate(txt, VOICE, rate=rate, pitch=pitch, proxy=PROXY).save(mp3)
        trim=f"audio/trim_{i}.wav"
        subprocess.run([FF,"-y","-i",mp3,"-ar","44100","-ac","1","-af",TRIM,trim],capture_output=True)
        d=dur(trim); win=nxt-st
        tempo=min(1.18, d/(win-0.10)) if d>win-0.10 else 1.0
        eff=d/tempo
        af=(f"atempo={tempo:.4f}," if tempo!=1.0 else "")+f"afade=t=in:st=0:d=0.04,afade=t=out:st={max(0,eff-0.08):.3f}:d=0.08"
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
