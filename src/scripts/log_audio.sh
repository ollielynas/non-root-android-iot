#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export PATH=/data/data/com.termux/files/usr/bin:$PATH

BASE_DIR="/storage/emulated/0/AndroidIOT"
mkdir -p "$BASE_DIR"
OUT="$BASE_DIR/audio_level_log.csv"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TMP="$BASE_DIR/tmp_audio.m4a"

# ── GUARANTEED CLEANUP ────────────────────────────────────────────────
# This trap runs automatically when the script finishes or gets interrupted.
# It completely nukes the audio file so it never saves to your device.
cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT
# ──────────────────────────────────────────────────────────────────────

METHOD="termux-api"
LEVEL=""
RAW=""

# 1. Record 1 second of audio
termux-microphone-record -l 1 -f "$TMP" >/dev/null 2>&1 || true

# 2. Wait for Android to finish writing the file
sleep 1.5

# 3. Analyze with ffmpeg
if [ -f "$TMP" ] && command -v ffmpeg >/dev/null 2>&1; then
    FFMPEG_OUT=$(ffmpeg -hide_banner -nostats -i "$TMP" -af "volumedetect" -f null /dev/null 2>&1 || true)
    LEVEL=$(echo "$FFMPEG_OUT" | grep "mean_volume" | grep -oE "[-0-9.]+\s*dB" | head -n1 || true)
    RAW=$(echo "$FFMPEG_OUT" | tr '\n' ' ' || true)
else
    LEVEL="error"
    RAW="Recording failed or audio file not generated"
fi

# 4. Write out CSV Header if missing
if [ ! -f "$OUT" ]; then
  echo "timestamp,method,level_db,raw" >> "$OUT" || true
fi

# 5. Log data
RAW_ESCAPED=$(echo "$RAW" | sed 's/"/""/g')
ROW="$TIMESTAMP,$METHOD,$LEVEL,\"$RAW_ESCAPED\""
echo "$ROW" >> "$OUT" || true

# 6. Optional upload trigger
for arg in "$@"; do
  case "$arg" in
    --upload)
      "$BASE_DIR/upload.sh" --text "$ROW" || true
      ;;
  esac
done

exit 0
