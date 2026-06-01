# ─────────────────────────────────────────
#  log_bluetooth.sh — Log nearby BT devices via Termux:API
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
if ! command -v termux-bluetooth-scaninfo &>/dev/null; then
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

# ── Scan for nearby bluetooth devices ─────
# termux-bluetooth-scaninfo returns a JSON array of devices
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BT_JSON='[]'

if command -v termux-bluetooth-scaninfo &>/dev/null; then
  BT_JSON=$(termux-bluetooth-scaninfo)
else
  echo "termux-bluetooth-scaninfo not found. Skipping bluetooth scan."
fi

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bluetooth_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,name,mac_address,rssi,device_class,bond_state" >> "$LOG_FILE"
fi

# ── Parse JSON array and append rows ──────
ROWS=$(echo "$BT_JSON" | awk -v ts="$TIMESTAMP" '
  BEGIN { RS="\{"; FS="[:,]" }
  /"address"/ {
    name=""; mac=""; rssi=""; dev_class=""; bond_state="";
    for (i = 1; i <= NF; i++) {
      if ($i ~ /"name"/) { name = $(i + 1) }
      if ($i ~ /"address"/) { mac = $(i + 1) }
      if ($i ~ /"rssi"/) { rssi = $(i + 1) }
      if ($i ~ /"device_class"/) { dev_class = $(i + 1) }
      if ($i ~ /"bond_state"/) { bond_state = $(i + 1) }
    }
    gsub(/"/, "", name); gsub(/"/, "", mac); gsub(/"/, "", rssi); gsub(/"/, "", dev_class); gsub(/"/, "", bond_state);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", name);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", mac);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rssi);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", dev_class);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", bond_state);
    print ts "," name "," mac "," rssi "," dev_class "," bond_state;
  }
')

if [[ "$DOWNLOAD" == "1" ]]; then
  printf "%s\n" "$ROWS" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROWS"
fi