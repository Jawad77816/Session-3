#!/usr/bin/env bash
# Download + clean YouTube auto-caption transcripts for a whole playlist.
#
# Paces caption requests and retries in cooldown sweeps, because YouTube
# rate-limits the caption (timedtext) endpoint to ~16 fetches per window per
# IP/session. A naive bulk download succeeds for ~8 videos then gets HTTP 429
# for the rest; the pacing + cooldown here gets the whole playlist.
#
# Usage: extract_transcripts.sh [PLAYLIST_URL] [OUTPUT_DIR] [SUB_LANGS]
#
# Environment variables:
#   COOKIES=/path/to/cookies.txt  Netscape cookies for a logged-in YouTube
#                                  session. REQUIRED from datacenter/cloud IPs
#                                  (YouTube returns LOGIN_REQUIRED otherwise).
#   CLIENT=web                     yt-dlp player_client (web works with cookies).
#   PACE=70                        seconds between caption fetches.
#   COOLDOWN=1000                  seconds to wait before each retry sweep.
#   SWEEPS=5                       max retry sweeps for rate-limited videos.
set -uo pipefail

PLAYLIST="${1:-https://youtube.com/playlist?list=PL0ZWSHleEKlxopaDleMZOyj-EyOzwLcAo}"
OUTDIR="${2:-output}"
LANGS="${3:-ur,en}"
CLIENT="${CLIENT:-web}"
PACE="${PACE:-70}"
COOLDOWN="${COOLDOWN:-1000}"
SWEEPS="${SWEEPS:-5}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUTDIR"

common=(--skip-download --ignore-no-formats-error --write-auto-subs
  --convert-subs srt --extractor-args "youtube:player_client=${CLIENT}"
  --extractor-retries 8 --sleep-subtitles 6 --no-warnings)
[ -n "${COOKIES:-}" ] && common+=(--cookies "$COOKIES")

echo ">> Enumerating playlist ..."
mapfile -t ROWS < <(yt-dlp --flat-playlist --no-warnings \
  --print "%(playlist_index)02d|%(id)s|%(title).60s" "$PLAYLIST")
echo "   ${#ROWS[@]} videos"
[ -z "${COOKIES:-}" ] && echo "   (no COOKIES set — will fail from a blocked/cloud IP)"

dir_for(){ # index id title -> prints dir path (creates if needed)
  local idx=$1 id=$2 title=$3 d
  d=$(find "$OUTDIR" -maxdepth 1 -type d -name "${idx}_*" | head -1)
  if [ -z "$d" ]; then
    local safe; safe=$(echo "$title" | tr -cs 'A-Za-z0-9' '_' | cut -c1-60 | sed 's/_*$//')
    d="$OUTDIR/${idx}_${safe}"; mkdir -p "$d"
  fi
  echo "$d"
}

IFS=',' read -ra LANGARR <<< "$LANGS"
for lang in "${LANGARR[@]}"; do
  echo ">> Language: $lang"
  for sweep in $(seq 1 "$SWEEPS"); do
    # count missing
    missing=0
    for row in "${ROWS[@]}"; do
      IFS='|' read -r idx id title <<< "$row"
      d=$(dir_for "$idx" "$id" "$title")
      [ -f "$d/captions.$lang.srt" ] || missing=$((missing+1))
    done
    [ "$missing" -eq 0 ] && { echo "   all $lang present"; break; }
    if [ "$sweep" -gt 1 ]; then echo "   sweep $sweep: $missing left, cooldown ${COOLDOWN}s"; sleep "$COOLDOWN"; fi
    for row in "${ROWS[@]}"; do
      IFS='|' read -r idx id title <<< "$row"
      d=$(dir_for "$idx" "$id" "$title")
      [ -f "$d/captions.$lang.srt" ] && continue
      rm -f "$d/captions.$lang.vtt" 2>/dev/null
      yt-dlp "${common[@]}" --sub-langs "$lang" -o "$d/captions.%(ext)s" \
        "https://www.youtube.com/watch?v=$id" >/dev/null 2>&1
      if [ -f "$d/captions.$lang.srt" ]; then echo "   [$idx $lang] ok"; else echo "   [$idx $lang] miss (rate-limited?)"; fi
      sleep "$PACE"
    done
  done
done

echo ">> Cleaning .srt -> .txt ..."
find "$OUTDIR" -name "*.srt" | sort | while read -r s; do
  python3 -I "$HERE/clean_srt.py" "$s" "${s%.srt}.txt" || true
done
echo ">> Transcript stage complete. Output in: $OUTDIR/"
