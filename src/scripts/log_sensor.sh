#!/bin/bash
# ─────────────────────────────────────────
#  sensor.sh — Log any sensor via Termux:API
# ─────────────────────────────────────────
set -uo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
SENSOR=""
VALUE_LABELS=""
DOWNLOAD=0
UPLOAD=0
SAMPLES=1
DELAY=100  # ms between samples

# ── Paths ─────────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
UPLOAD_SH="/sdcard/AndroidIOT/upload.sh"

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] --sensor <id> --value-labels <l1,l2,...> [--samples <n>] [--delay <ms>] [--download] [--upload]

Options:
  --sensor        Termux sensor ID (required) e.g. bmi320_acc
  --value-labels  Comma-separated column labels (required) e.g. x,y,z or lux or steps
  --samples       Number of samples to collect (default: 1)
  --delay         Delay between samples in ms (default: 100)
  --download      Append rows to local CSV
  --upload        Upload rows using upload.sh
  -h              Show this help message
EOF
  exit 1
}

# ── Parse Arguments ───────────────────────
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --sensor) SENSOR="$2"; shift ;;
    --value-labels) VALUE_LABELS="$2"; shift ;;
    --samples) SAMPLES="$2"; shift ;;
    --delay) DELAY="$2"; shift ;;
    --download) DOWNLOAD=1 ;;
    --upload) UPLOAD=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# ── Validation ────────────────────────────
if [[ -z "$SENSOR" || -z "$VALUE_LABELS" ]]; then
  echo "Error: --sensor and --value-labels are required."
  echo ""
  usage
fi

# ── Setup ─────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CSV_FILE="${LOG_DIR}/${SENSOR}.csv"

if [[ "$DOWNLOAD" -eq 1 ]]; then
  mkdir -p "$LOG_DIR"
  if [[ ! -f "$CSV_FILE" ]]; then
    echo "timestamp,${VALUE_LABELS}" > "$CSV_FILE"
    echo "Created new log file: $CSV_FILE"
  else
    echo "Appending to existing log file: $CSV_FILE"
  fi
fi

# Convert DELAY from ms to seconds for the bash sleep command
DELAY_SEC=$(awk "BEGIN {print $DELAY/1000}")

# ── Data Collection ───────────────────────
echo "Collecting $SAMPLES sample(s) from $SENSOR..."

for ((i=1; i<=SAMPLES; i++)); do
  NOW=$(date +"%Y-%m-%dT%H:%M:%S%z")

  # Fetch exactly 1 sample from the requested sensor
  RAW_JSON=$(termux-sensor -s "$SENSOR" -n 1)

  # Extract values natively using awk & paste (NO JQ REQUIRED)
  # 1. Finds the "values": [ block
  # 2. Strips spaces, brackets, and commas from the numbers
  # 3. Joins the resulting lines into a single comma-separated string
  VALUES=$(echo "$RAW_JSON" | awk '/"values": \[/{flag=1; next} /\]/{flag=0} flag {gsub(/[ \t\r\n,]/, ""); if ($0 != "") print $0}' | paste -sd "," -)



  ROW="${NOW},${VALUES}"
  echo "[$i/$SAMPLES] $ROW"

  if [[ "$DOWNLOAD" -eq 1 ]]; then
    echo "$ROW" >> "$CSV_FILE"
  fi

  if [[ "$UPLOAD" -eq 1 ]]; then
    if [[ -x "$UPLOAD_SH" ]]; then
      "$UPLOAD_SH" "$SENSOR" "$ROW"
    fi
  fi

  if [[ "$i" -lt "$SAMPLES" ]]; then
    sleep "$DELAY_SEC"
  fi
done

# ── Cleanup ───────────────────────────────
termux-sensor -c
echo "Collection complete."
