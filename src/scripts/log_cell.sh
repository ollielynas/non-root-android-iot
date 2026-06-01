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

if ! command -v termux-telephony-cellinfo &>/dev/null; then
  echo "termux-api not found. Installing..."
  pkg install -y termux-api
fi

if [[ ! -d ~/storage ]]; then
  termux-setup-storage
  exit 0
fi

LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cell_info_log.csv"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,data" >> "$LOG_FILE"
fi

RAW=$(termux-telephony-cellinfo 2>&1 || true)
RAW=${RAW//$'\r'/}
RAW=${RAW//$'\n'/; }
ROW="$(date '+%Y-%m-%d %H:%M:%S'),$RAW"

echo "[cell] $ROW"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi
if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi
