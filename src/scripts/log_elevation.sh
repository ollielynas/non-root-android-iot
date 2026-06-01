# ─────────────────────────────────────────
#  log_elevation.sh — Log elevation via Termux:API
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
DOWNLOAD=0
UPLOAD=0

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--download] [--upload]
Options:
  --download  store log internally
  --upload    upload log using upload.sh
  -h          Show this help message
Example:
  $(basename "$0") --download
EOF
  exit 0
}

# ── Parse flags ───────────────────────────
while getopts ":h-:" opt; do
  case $opt in
    h) usage ;;
    -) case "$OPTARG" in
         download) DOWNLOAD=1 ;;
         upload)   UPLOAD=1 ;;
       esac ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Check storage is set up ───────────────
if [[ ! -d ~/storage ]]; then
  echo "Storage not set up. Running termux-setup-storage..."
  termux-setup-storage
  echo "Re-run this script once storage is ready."
  exit 0
fi

# ── Read elevation ────────────────────────
# Use gps provider for more accurate altitude than network triangulation
echo "[elevation] provider: gps"
GPS_JSON=$(termux-location -p gps)

ALTITUDE=$(echo "$GPS_JSON" | grep -oE -- '"altitude": *-?[0-9.]+' | grep -oE -- '-?[0-9.]+' | head -1 || true)
ACCURACY=$(echo "$GPS_JSON" | grep -oE -- '"vertical_accuracy": *[0-9.]+' | grep -oE -- '[0-9.]+' | head -1 || true)

# Fallback: some devices don't report vertical_accuracy, use regular accuracy
if [[ -z "$ACCURACY" ]]; then
  ACCURACY=$(echo "$GPS_JSON" | grep -oE -- '"accuracy": *[0-9.]+' | grep -oE -- '[0-9.]+' | head -1 || true)
fi

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/elevation_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,altitude_m,vertical_accuracy_m" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
ROW="$(date '+%Y-%m-%d %H:%M:%S'),$ALTITUDE,$ACCURACY"
echo "[elevation] row: $ROW"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  echo "[elevation] uploading row with upload.sh --text"
  ./upload.sh --text "$ROW"
fi