# ─────────────────────────────────────────
#  log_data_usage.sh — Log mobile data usage via Termux:API
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

# ── Read network stats ────────────────────
MOBILE_RX=0
MOBILE_TX=0
if command -v termux-network-stats &>/dev/null; then
  STATS_JSON=$(termux-network-stats)

  # ── Parse mobile rx/tx bytes ─────────────
  MOBILE_RX=$(echo "$STATS_JSON" | awk -F'[:,}]' '/"mobile"/ { for (i = 1; i <= NF; i++) if ($i ~ /"rx_bytes"/) { print $(i + 1); exit } }')
  MOBILE_TX=$(echo "$STATS_JSON" | awk -F'[:,}]' '/"mobile"/ { for (i = 1; i <= NF; i++) if ($i ~ /"tx_bytes"/) { print $(i + 1); exit } }')
  MOBILE_RX=${MOBILE_RX:-0}
  MOBILE_TX=${MOBILE_TX:-0}
else
  echo "termux-network-stats not found. Using zero values."
fi

MOBILE_TOTAL=$((MOBILE_RX + MOBILE_TX))

# ── Convert to MB for readability ─────────
MOBILE_RX_MB=$(echo "scale=2; $MOBILE_RX / 1048576" | bc)
MOBILE_TX_MB=$(echo "scale=2; $MOBILE_TX / 1048576" | bc)
MOBILE_TOTAL_MB=$(echo "scale=2; $MOBILE_TOTAL / 1048576" | bc)

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/data_usage_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,mobile_rx_bytes,mobile_tx_bytes,mobile_total_bytes,mobile_rx_mb,mobile_tx_mb,mobile_total_mb" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$MOBILE_RX,$MOBILE_TX,$MOBILE_TOTAL,$MOBILE_RX_MB,$MOBILE_TX_MB,$MOBILE_TOTAL_MB" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$(date '+%Y-%m-%d %H:%M:%S'),$MOBILE_RX,$MOBILE_TX,$MOBILE_TOTAL,$MOBILE_RX_MB,$MOBILE_TX_MB,$MOBILE_TOTAL_MB"
fi