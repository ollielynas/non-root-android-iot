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

if ! command -v termux-sensor &>/dev/null; then
  echo "termux-api not found. Installing..."
  pkg install -y termux-api
fi

if [[ ! -d ~/storage ]]; then
  termux-setup-storage
  exit 0
fi

LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/linear_acceleration_log.csv"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,x_ms2,y_ms2,z_ms2,magnitude_ms2" >> "$LOG_FILE"
fi

RAW=$(termux-sensor -s "linear_acceleration" -n 1 2>&1 || true)
RAW=${RAW//$'\r'/}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
VALUES=$(printf '%s\n' "$RAW" | grep -oE -- '[0-9]+\.[0-9]+|[0-9]+' | tr '\n' ' ')
set -- $VALUES
X=${1:-}
Y=${2:-}
Z=${3:-}
if [[ -n "$X" && -n "$Y" && -n "$Z" ]]; then
  MAG=$(awk -v x="$X" -v y="$Y" -v z="$Z" 'BEGIN { printf "%.4f", sqrt(x*x + y*y + z*z) }')
else
  MAG=""
fi
ROW="$TIMESTAMP,$X,$Y,$Z,$MAG"

echo "[linear_acceleration] $ROW"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi
if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi
