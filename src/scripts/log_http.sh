#!/bin/bash
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

DOWNLOAD=0
UPLOAD=0

while getopts ":h-:" opt; do
  case $opt in
    h)
      cat <<EOF
Usage: $(basename "$0") [-h] [--download] [--upload]
EOF
      exit 0
      ;;
    -)
      case "$OPTARG" in
        download) DOWNLOAD=1 ;;
        upload) UPLOAD=1 ;;
        *) echo "Error: Unknown flag --$OPTARG"; exit 1 ;;
      esac
      ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

if [[ ! -d ~/storage ]]; then
  termux-setup-storage
  exit 0
fi

LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/http_response_log.csv"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,data" >> "$LOG_FILE"
fi

RAW=$(curl -L -s -o /dev/null -w 'code=%{http_code},time=%{time_total},size=%{size_download}' https://example.com 2>&1 || true)
RAW=${RAW//$'\r'/}
RAW=${RAW//$'\n'/; }
ROW="$(date '+%Y-%m-%d %H:%M:%S'),$RAW"

echo "[http] $ROW"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi
if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi
