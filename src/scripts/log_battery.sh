# ─────────────────────────────────────────
#  log_battery.sh — Log battery % via Termux:API
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

# ── Check / install termux-api ────────────
if ! command -v termux-battery-status &>/dev/null; then
  echo "termux-api not found. Installing..."
  pkg install -y termux-api
  echo "Done. Make sure the Termux:API companion app is also installed from F-Droid."
fi

# ── Check storage is set up ───────────────
if [[ ! -d ~/storage ]]; then
  echo "Storage not set up. Running termux-setup-storage..."
  termux-setup-storage
  echo "Re-run this script once storage is ready."
  exit 0
fi

# ── Read battery status ───────────────────
BATTERY_JSON=$(termux-battery-status)
PERCENTAGE=$(echo "$BATTERY_JSON" | grep -o '"percentage": *[0-9]*' | grep -o '[0-9]*')
STATUS=$(echo "$BATTERY_JSON"     | grep -o '"status": *"[^"]*"'   | grep -o '"[^"]*"$' | tr -d '"')
HEALTH=$(echo "$BATTERY_JSON"     | grep -o '"health": *"[^"]*"'   | grep -o '"[^"]*"$' | tr -d '"')
TEMP=$(echo "$BATTERY_JSON"       | grep -o '"temperature": *[0-9.]*' | grep -o '[0-9.]*')


# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/battery_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,percentage,status,health,temperature_c" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
ROW="$(date '+%Y-%m-%d %H:%M:%S'),$PERCENTAGE,$STATUS,$HEALTH,$TEMP"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi