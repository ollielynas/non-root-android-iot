# ─────────────────────────────────────────
#  log_gps.sh — Log GPS position via Termux:API
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
DOWNLOAD=0
UPLOAD=0
ACCURATE=0

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--download] [--upload]
Options:
  --accurate  use slow accurate GPS fix instead of fast network location
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
          accurate) ACCURATE=1 ;;
         download) DOWNLOAD=1 ;;
         upload)   UPLOAD=1 ;;
       esac ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Check / install termux-api ────────────
if ! command -v termux-location &>/dev/null; then
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

# ── Read GPS location ─────────────────────
# -p network = faster fix, uses cell/wifi instead of waiting for GPS satellite
LOCATION_PROVIDER="network"
if [[ "$ACCURATE" == "1" ]]; then
  LOCATION_PROVIDER="gps"
fi
echo "[gps] provider: $LOCATION_PROVIDER"
GPS_JSON=$(termux-location -p "$LOCATION_PROVIDER")

LATITUDE=$(echo "$GPS_JSON"  | grep -oE -- '"latitude": *-?[0-9.]+'  | grep -oE -- '-?[0-9.]+' | head -1 || true)
LONGITUDE=$(echo "$GPS_JSON" | grep -oE -- '"longitude": *-?[0-9.]+' | grep -oE -- '-?[0-9.]+' | head -1 || true)
ALTITUDE=$(echo "$GPS_JSON"  | grep -oE -- '"altitude": *-?[0-9.]+'  | grep -oE -- '-?[0-9.]+' | head -1 || true)
ACCURACY=$(echo "$GPS_JSON"  | grep -oE -- '"accuracy": *[0-9.]+'    | grep -oE -- '[0-9.]+' | head -1 || true)
BEARING=$(echo "$GPS_JSON"   | grep -oE -- '"bearing": *[0-9.]+'     | grep -oE -- '[0-9.]+' | head -1 || true)
SPEED=$(echo "$GPS_JSON"     | grep -oE -- '"speed": *[0-9.]+'       | grep -oE -- '[0-9.]+' | head -1 || true)

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/gps_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,latitude,longitude,altitude_m,accuracy_m,bearing_deg,speed_ms" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
ROW="$(date '+%Y-%m-%d %H:%M:%S'),$LATITUDE,$LONGITUDE,$ALTITUDE,$ACCURACY,$BEARING,$SPEED"
echo "[gps] row: $ROW"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  echo "[gps] uploading row with upload.sh --text"
  ./upload.sh --text "$ROW"
fi