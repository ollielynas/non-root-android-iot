# ─────────────────────────────────────────
#  log_acceleration.sh — Log accelerometer data via Termux:API
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
DOWNLOAD=0
UPLOAD=0
SAMPLES=10
DELAY=100  # ms between samples

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--samples <n>] [--delay <ms>] [--download] [--upload]
Options:
  --samples   Number of samples to collect (default: 10)
  --delay     Delay between samples in ms (default: 100)
  --download  store log internally
  --upload    upload log using upload.sh
  -h          Show this help message
Example:
  $(basename "$0") --samples 20 --delay 200 --download
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
         samples)  SAMPLES="${!OPTIND}"; shift ;;
         delay)    DELAY="${!OPTIND}";   shift ;;
         *) echo "Error: Unknown flag --$OPTARG"; exit 1 ;;
       esac ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Check / install termux-api ────────────
if ! command -v termux-sensor &>/dev/null; then
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

# ── Read accelerometer ────────────────────
# -s: sensor name, -d: delay ms, -n: sample count
SENSOR_JSON=$(termux-sensor -s "accelerometer" -d "$DELAY" -n "$SAMPLES")

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/acceleration_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,sample,x_ms2,y_ms2,z_ms2,magnitude_ms2" >> "$LOG_FILE"
fi

# ── Parse JSON and append rows ────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ROWS=$(printf '%s
' "$SENSOR_JSON" | grep -oE -- '\[[^][]*\]' | awk -v ts="$TIMESTAMP" '
{
  gsub(/[\[\],]/, " ");
  x = $1;
  y = $2;
  z = $3;
  if (x != "" || y != "" || z != "") {
    magnitude = sqrt((x + 0) * (x + 0) + (y + 0) * (y + 0) + (z + 0) * (z + 0));
    printf "%s,%d,%s,%s,%s,%.4f\n", ts, ++i, x, y, z, magnitude;
  }
}')

if [[ "$DOWNLOAD" == "1" ]]; then
  printf "%s\n" "$ROWS" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROWS"
fi