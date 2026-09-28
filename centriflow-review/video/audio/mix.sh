#!/usr/bin/env bash
# Mix ducked music + VO onto the silent video -> out/gocentriflow_ad_16x9_vo.mp4
set -e
FF=$(python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")
"$FF" -y -i out/gocentriflow_ad_16x9.mp4 -i audio/music.wav -i audio/vo_full.wav \
 -filter_complex "[1:a]volume=0.6[m];[m][2:a]sidechaincompress=threshold=0.02:ratio=8:attack=5:release=350[md];[md][2:a]amix=inputs=2:normalize=0:dropout_transition=0[mx];[mx]alimiter=limit=0.95,afade=t=out:st=55.0:d=0.7,aresample=44100[aout]" \
 -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
 out/gocentriflow_ad_16x9_vo.mp4
