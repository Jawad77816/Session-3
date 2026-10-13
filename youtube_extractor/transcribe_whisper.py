#!/usr/bin/env python3
"""Optional: transcribe audio with Whisper when captions are unavailable or
you want higher quality than YouTube's auto-captions.

This is the fallback to extract_transcripts.sh. It transcribes LOCAL audio
files (download them first with yt-dlp, e.g.:
    yt-dlp -f bestaudio --cookies cookies.txt -o 'au/%(playlist_index)02d.%(ext)s' <playlist>
).

Requires (not installed by default; CPU-only works but is slow for long audio):
    pip install faster-whisper

Urdu note: Whisper supports Urdu ('ur'). On CPU prefer model 'small' or
'medium' with int8; 'large-v3' is most accurate but very slow without a GPU.

Usage:
    python3 transcribe_whisper.py <audio_or_dir> [--model medium] [--lang ur] [--out OUTDIR]
"""
import argparse
import os
import sys
from datetime import timedelta


def ts(seconds: float) -> str:
    td = timedelta(seconds=seconds)
    total_ms = int(td.total_seconds() * 1000)
    h, rem = divmod(total_ms, 3_600_000)
    m, rem = divmod(rem, 60_000)
    s, ms = divmod(rem, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def transcribe(model, path, lang, outdir):
    base = os.path.splitext(os.path.basename(path))[0]
    os.makedirs(outdir, exist_ok=True)
    segments, info = model.transcribe(path, language=lang, vad_filter=True)
    srt_path = os.path.join(outdir, f"{base}.{lang}.srt")
    txt_path = os.path.join(outdir, f"{base}.{lang}.txt")
    with open(srt_path, "w", encoding="utf-8") as srt, \
         open(txt_path, "w", encoding="utf-8") as txt:
        for i, seg in enumerate(segments, 1):
            srt.write(f"{i}\n{ts(seg.start)} --> {ts(seg.end)}\n{seg.text.strip()}\n\n")
            txt.write(seg.text.strip() + "\n")
    print(f"  {path} -> {srt_path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="audio file or directory of audio files")
    ap.add_argument("--model", default="medium", help="tiny|base|small|medium|large-v3")
    ap.add_argument("--lang", default="ur")
    ap.add_argument("--out", default="output_whisper")
    args = ap.parse_args()

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        sys.exit("faster-whisper not installed. Run: pip install faster-whisper")

    print(f"Loading Whisper model '{args.model}' (int8, CPU) ...")
    model = WhisperModel(args.model, device="cpu", compute_type="int8")

    if os.path.isdir(args.input):
        files = sorted(
            os.path.join(args.input, f) for f in os.listdir(args.input)
            if f.lower().endswith((".mp3", ".m4a", ".wav", ".opus", ".webm", ".mp4"))
        )
    else:
        files = [args.input]
    for f in files:
        transcribe(model, f, args.lang, args.out)


if __name__ == "__main__":
    main()
