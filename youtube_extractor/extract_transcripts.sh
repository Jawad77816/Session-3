#!/usr/bin/env bash
# Download YouTube auto-caption transcripts for a whole playlist and clean
# them into readable .txt alongside the raw timestamped .srt.
#
# Usage:
#   extract_transcripts.sh [PLAYLIST_URL] [OUTPUT_DIR] [SUB_LANGS]
#
# Environment variables:
#   COOKIES=/path/to/cookies.txt   Netscape-format cookies for a logged-in
#                                   YouTube session. REQUIRED from datacenter
#                                   / cloud IPs, which YouTube otherwise blocks
#                                   ("Sign in to confirm you're not a bot" /
#                                   HTTP 429 on captions).
#   CLIENT=tv_embedded             yt-dlp player_client. tv_embedded exposes
#                                   the Urdu (ur) auto-caption track; android
#                                   only exposes hi. Leave as default.
set -uo pipefail

PLAYLIST="${1:-https://youtube.com/playlist?list=PL0ZWSHleEKlxopaDleMZOyj-EyOzwLcAo}"
OUTDIR="${2:-output}"
LANGS="${3:-ur,en}"          # Urdu primary, English translation alongside
CLIENT="${CLIENT:-web}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUTDIR"

args=(
  --skip-download
  --ignore-no-formats-error
  --write-auto-subs
  --sub-langs "$LANGS"
  --convert-subs srt
  --restrict-filenames
  --extractor-args "youtube:player_client=${CLIENT}"
  --sleep-requests 2 --sleep-subtitles 3
  --retries 10 --retry-sleep 10 --extractor-retries 8
  --ignore-errors --no-warnings
  -o "$OUTDIR/%(playlist_index)02d_%(title).60s/captions.%(ext)s"
)
[ -n "${COOKIES:-}" ] && args+=(--cookies "$COOKIES")

echo ">> Downloading auto-captions ($LANGS) via client=$CLIENT ..."
[ -z "${COOKIES:-}" ] && echo "   (no COOKIES set — this will fail from a blocked/cloud IP)"
yt-dlp "${args[@]}" "$PLAYLIST"

echo ">> Cleaning .srt -> .txt ..."
find "$OUTDIR" -name "*.srt" | sort | while read -r srt; do
  python3 -I "$HERE/clean_srt.py" "$srt" "${srt%.srt}.txt" || true
done

echo ">> Transcript stage complete. Output in: $OUTDIR/"
