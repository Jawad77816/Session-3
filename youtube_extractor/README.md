# YouTube Playlist Extractor (transcripts + frames)

Extracts, for every video in a YouTube playlist:

- **Transcripts** — Urdu (`ur`) auto-captions plus an English (`en`) translation,
  saved as timestamped `.srt` and cleaned, de-duplicated `.txt`.
- **Frames** — still images sampled from each video (scene changes or a fixed
  interval), for the charts/slides shown on screen.

Built for the *HASANXBT Free Trading Course* playlist (20 videos, ~24 h total,
spoken in Urdu/Hindi) but works on any playlist.

## Contents

| File | Purpose |
|------|---------|
| `extract_transcripts.sh` | Download + clean captions for the whole playlist |
| `extract_frames.sh` | Download each video (capped res) and extract frames |
| `clean_srt.py` | Turn rolling auto-caption `.srt` into readable text |
| `transcribe_whisper.py` | Optional Whisper fallback when captions are missing |

## Requirements

- `yt-dlp`  →  `pip install -U yt-dlp`
- `ffmpeg` / `ffprobe` (system package)
- Python 3.9+
- Optional (Whisper fallback): `pip install faster-whisper`

## ⚠️ Important: YouTube blocks cloud / datacenter IPs

From a normal home/office (**residential**) connection these scripts just work.
From a **cloud server, CI runner, or datacenter IP** (including Claude's cloud
sandbox) YouTube is far more hostile. Observed behaviour, and what gets past it:

| From a datacenter IP | No cookies | With cookies |
|----------------------|------------|--------------|
| Metadata / caption listing | ✅ works | ✅ works |
| **Caption text** (transcripts) | ❌ `LOGIN_REQUIRED` / `429` | ✅ works, but **rate-limited** (~16 fetches/window → the script paces + retries in cooldown sweeps) |
| **Video download** (needed for frames) | ❌ `403` on CDN | ❌ still blocked (web client returns *no* formats; other clients `403`) |

**Takeaway:** with cookies you can pull **transcripts** from a datacenter IP
(slowly). **Frames need a residential IP** — run `extract_frames.sh` on your
own machine. A PO-token provider (bgutil) helps but does not lift the video
block once the IP is flagged.

To run from a datacenter IP you must supply **cookies** from a logged-in
YouTube session:

1. In a browser logged in to YouTube, install a "Get cookies.txt LOCALLY"
   extension (Netscape format).
2. Export cookies for `youtube.com` to `cookies.txt`.
3. Point the scripts at it with the `COOKIES` env var (below).

> Note: scraping may conflict with YouTube's Terms of Service, and a cookie
> file ties requests to your account. Use on content you have the right to.

## Usage

```bash
# Transcripts (Urdu + English) for the whole playlist
COOKIES=cookies.txt ./extract_transcripts.sh \
    "https://youtube.com/playlist?list=PL0ZWSHleEKlxopaDleMZOyj-EyOzwLcAo" output

# Frames — scene-change mode (distinct charts), capped at 480p
COOKIES=cookies.txt ./extract_frames.sh \
    "https://youtube.com/playlist?list=PL0ZWSHleEKlxopaDleMZOyj-EyOzwLcAo" output scene 0.30 480

# Frames — one frame every 20 seconds instead
COOKIES=cookies.txt ./extract_frames.sh "<playlist>" output interval 20 480
```

Omit `COOKIES=` only on a residential IP.

### Output layout

```
output/
  01_WHAT_IS_TRADING.../
    captions.ur.srt     captions.ur.txt     # Urdu
    captions.en.srt     captions.en.txt     # English translation
    frames/
      frame_0001.jpg ...
  02_.../
  ...
```

### Optional: Whisper (higher quality / no captions)

```bash
# 1. download audio only
yt-dlp -f bestaudio --cookies cookies.txt \
    -o 'audio/%(playlist_index)02d_%(id)s.%(ext)s' "<playlist>"
# 2. transcribe (CPU is slow for long audio; a GPU is strongly recommended)
python3 transcribe_whisper.py audio --model medium --lang ur --out output_whisper
```

## Notes on the Urdu captions

YouTube detects the spoken language as Hindi/Urdu (they are near-identical when
spoken). The `ur` track is YouTube's Urdu rendering (Nastaʿlīq script); `hi` is
the same speech in Devanagari; `en` is a machine translation. Auto-captions
contain recognition errors — Whisper (`medium`/`large-v3`) gives cleaner Urdu
if you need publication quality.
