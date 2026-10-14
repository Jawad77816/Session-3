#!/usr/bin/env bash
# Download each video in a playlist (one at a time, capped resolution) and
# extract still frames with ffmpeg, deleting the video afterwards so disk use
# stays low. Scene-change mode captures each distinct chart/slide; interval
# mode grabs one frame every N seconds.
#
# Usage:
#   extract_frames.sh [PLAYLIST_URL] [OUTPUT_DIR] [MODE] [PARAM] [MAX_HEIGHT]
#     MODE       = scene (default) | interval
#     PARAM      = scene threshold 0..1 (default 0.30) | interval seconds (default 15)
#     MAX_HEIGHT = cap download resolution, e.g. 480 (default) | 360 | 720
#
# Environment variables:
#   COOKIES=/path/to/cookies.txt   REQUIRED from cloud/datacenter IPs (see
#                                   extract_transcripts.sh header).
#   CLIENT=web                     yt-dlp player_client for media. With cookies,
#                                   'web' gives the full format ladder.
set -uo pipefail

PLAYLIST="${1:-https://youtube.com/playlist?list=PL0ZWSHleEKlxopaDleMZOyj-EyOzwLcAo}"
OUTDIR="${2:-output}"
MODE="${3:-scene}"
PARAM="${4:-}"
MAXH="${5:-480}"
CLIENT="${CLIENT:-web}"

if [ "$MODE" = "scene" ]; then
  THRESH="${PARAM:-0.30}"
  VF="select='gt(scene,${THRESH})',scale='min(1280,iw)':-2"
  FPSFLAG=(-vsync vfr)
else
  SECS="${PARAM:-15}"
  VF="fps=1/${SECS},scale='min(1280,iw)':-2"
  FPSFLAG=()
fi

mkdir -p "$OUTDIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Frames need only the video stream (no audio), so download video-only — faster
# and smaller. A GVS PO-token provider on localhost:4416 is auto-detected by
# yt-dlp and is required for streaming URLs from datacenter IPs.
dl_args=(
  -f "bestvideo[height<=${MAXH}]/best[height<=${MAXH}]/best"
  --extractor-args "youtube:player_client=${CLIENT}"
  --sleep-requests 2 --retries 10 --retry-sleep 10 --extractor-retries 8
  --ignore-errors --no-warnings
)
[ -n "${COOKIES:-}" ] && dl_args+=(--cookies "$COOKIES")

echo ">> Frame extraction: mode=$MODE param=${PARAM:-default} maxheight=$MAXH client=$CLIENT"
[ -z "${COOKIES:-}" ] && echo "   (no COOKIES set — downloads will fail from a blocked/cloud IP)"

# Iterate playlist entries by index so we process (download -> frames -> delete) one at a time.
mapfile -t IDS < <(yt-dlp --flat-playlist --print "%(playlist_index)s|%(id)s|%(title).60s" --no-warnings "$PLAYLIST")

for row in "${IDS[@]}"; do
  idx="${row%%|*}"; rest="${row#*|}"; vid="${rest%%|*}"; title="${rest#*|}"
  safe=$(echo "$title" | tr -cs 'A-Za-z0-9' '_' | sed 's/_*$//')
  dest="$OUTDIR/$(printf '%02d' "$idx")_${safe}"
  framedir="$dest/frames"
  mkdir -p "$framedir"
  echo "---- [$idx] $vid ($title)"

  rm -f "$WORK"/*.mp4 2>/dev/null
  if ! yt-dlp "${dl_args[@]}" -o "$WORK/v.%(ext)s" "https://www.youtube.com/watch?v=$vid"; then
    echo "   download failed, skipping"; continue
  fi
  vfile=$(ls "$WORK"/v.* 2>/dev/null | head -1)
  [ -z "$vfile" ] && { echo "   no file, skipping"; continue; }

  ffmpeg -hide_banner -loglevel error -i "$vfile" \
    -vf "$VF" "${FPSFLAG[@]}" -q:v 3 "$framedir/frame_%04d.jpg" </dev/null
  n=$(ls "$framedir"/*.jpg 2>/dev/null | wc -l)
  echo "   -> $n frames in $framedir"
  rm -f "$WORK"/*.* 2>/dev/null
done

echo ">> Frame stage complete. Output in: $OUTDIR/"
