#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export PATH=/data/data/com.termux/files/usr/bin:$PATH

BASE_DIR=/sdcard/AndroidIOT
mkdir -p "$BASE_DIR"
OUT="$BASE_DIR/audio_level_log.csv"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
METHOD="none"
LEVEL=""
RAW=""

if command -v termux-volume >/dev/null 2>&1; then
  METHOD="termux-volume"
  RAW=$(termux-volume 2>/dev/null | tr -d '\r\n' || true)
elif command -v termux-microphone-record >/dev/null 2>&1; then
  METHOD="termux-microphone-record"
  TMP="$BASE_DIR/tmp_audio.wav"
  termux-microphone-record -f "$TMP" -d 1 >/dev/null 2>&1 || true
  if command -v ffmpeg >/dev/null 2>&1; then
    FFMPEG_OUT=$(ffmpeg -hide_banner -nostats -i "$TMP" -af "volumedetect" -f null /dev/null 2>&1 || true)
    LEVEL=$(echo "$FFMPEG_OUT" | grep "mean_volume" -m1 -oE "[-0-9.]+dB" | head -n1 || true)
    RAW=$(echo "$FFMPEG_OUT" | tr '\n' ' ' || true)
  elif command -v sox >/dev/null 2>&1; then
    SOX_OUT=$(sox "$TMP" -n stat 2>&1 || true)
    LEVEL=$(echo "$SOX_OUT" | grep "RMS     amplitude" -m1 -oE "[-0-9.]+" | head -n1 || true)
    RAW="$SOX_OUT"
  else
    RAW="recorded:$TMP"
  fi
elif command -v rec >/dev/null 2>&1; then
  METHOD="rec"
  TMP="$BASE_DIR/tmp_audio.wav"
  rec -q "$TMP" trim 0 1 2>/dev/null || true
  if command -v ffmpeg >/dev/null 2>&1; then
    FFMPEG_OUT=$(ffmpeg -hide_banner -nostats -i "$TMP" -af "volumedetect" -f null /dev/null 2>&1 || true)
    LEVEL=$(echo "$FFMPEG_OUT" | grep "mean_volume" -m1 -oE "[-0-9.]+dB" | head -n1 || true)
    RAW=$(echo "$FFMPEG_OUT" | tr '\n' ' ' || true)
  else
    RAW="recorded:$TMP"
  fi
else
  METHOD="unavailable"
fi

if [ ! -f "$OUT" ]; then
  echo "timestamp,method,level_db,raw" >> "$OUT" || true
fi

RAW_ESCAPED=$(echo "$RAW" | sed 's/"/""/g')
ROW="$TIMESTAMP,$METHOD,$LEVEL,\"$RAW_ESCAPED\""
echo "$ROW" >> "$OUT" || true

for arg in "$@"; do
  case "$arg" in
    --upload)
      "$BASE_DIR/upload.sh" --text "$ROW" || true
      ;;
  esac
done

exit 0
