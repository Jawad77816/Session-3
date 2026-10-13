#!/usr/bin/env bash
set -e
FF=$(python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")
"$FF" -y -i out/base_silent.mp4 -i audio/music.wav -i audio/vo_full.wav \
 -filter_complex "[1:a]acompressor=threshold=-22dB:ratio=4:attack=5:release=140:makeup=6,alimiter=limit=0.9[mc];\
[2:a]volume=1.12,asplit=2[v][vsc];\
[mc][vsc]sidechaincompress=threshold=0.02:ratio=16:attack=4:release=240:makeup=1[md];\
[md][v]amix=inputs=2:normalize=0:dropout_transition=0[mx];\
[mx]alimiter=limit=0.9,aresample=44100[aout]" \
 -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
 out/gocentriflow_ad3_16x9.mp4
