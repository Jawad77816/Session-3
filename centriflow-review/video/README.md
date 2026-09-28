# GoCentriflow LinkedIn Ad — build

- `ad.html` — the animated ad (deterministic, time-seekable via `window.seekTo(ms)`).
- `render.js` — Playwright frame capture (`node render.js full` → frames/, `preview` for spot frames).
- `assets/` — real product screenshots used in the cut.
- `out/gocentriflow_ad_16x9.mp4` — final render (1080p, 30fps, ~56s).
- `COPY-KIT.md` — voiceover script, music guidance, LinkedIn post copy.

Re-encode from frames (needs an ffmpeg with libx264, e.g. `pip install imageio-ffmpeg`):
```
ffmpeg -framerate 30 -i frames/%05d.jpg -f lavfi -i anullsrc=r=44100:cl=stereo \
  -vf "fade=t=in:st=0:d=0.3,fade=t=out:st=54.8:d=0.8,format=yuv420p" \
  -c:v libx264 -preset medium -crf 19 -profile:v high -level 4.2 \
  -c:a aac -b:a 128k -shortest -movflags +faststart -r 30 out/gocentriflow_ad_16x9.mp4
```
