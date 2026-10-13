# GoCentriflow — 30s ad (v2, alt layout)

Distinct layout + audio from the 56s cut in ../video.
- `ad2.html` — animated timeline (Space Grotesk display, mesh bg, full-screen problem cuts, tilted product shots, integration marquee).
- `render2.js` — Playwright frame capture (`node render2.js full` / `preview`).
- `audio/make_vo2.py` — female VO via Piper (local neural, model in audio/piper/, git-ignored).
- `audio/make_music2.py` — new cinematic/driving track (Am-F-C-G, hook, beat, risers).
- `audio/mix2.sh` — dynamic ducking: music swells in gaps, drops under the voice.
- `out/gocentriflow_ad2_16x9.mp4` — final (1080p, 30fps, 30s).

Piper voice model (re-download if needed):
  curl -sSL -o audio/piper/en_US-hfc_female-medium.onnx \
    https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/hfc_female/medium/en_US-hfc_female-medium.onnx
  (+ the matching .onnx.json)
