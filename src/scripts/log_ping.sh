# ─────────────────────────────────────────
#  log_ping.sh — Log ping latency to a target address
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
DOWNLOAD=0
UPLOAD=0
TARGET=""
COUNT=4

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] --target <address> [--count <n>] [--download] [--upload]
Options:
  --target    Address or hostname to ping (required)
  --count     Number of ping packets to send (default: 4)
  --download  store log internally
  --upload    upload log using upload.sh
  -h          Show this help message
Example:
  $(basename "$0") --target 8.8.8.8 --download
  $(basename "$0") --target google.com --count 10 --upload
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
         target)   TARGET="${!OPTIND}"; shift ;;
         count)    COUNT="${!OPTIND}";  shift ;;
         *) echo "Error: Unknown flag --$OPTARG"; exit 1 ;;
       esac ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Validate target ───────────────────────
if [[ -z "$TARGET" ]]; then
  echo "Error: --target is required."
  usage
fi

# ── Check storage is set up ───────────────
if [[ ! -d ~/storage ]]; then
  echo "Storage not set up. Running termux-setup-storage..."
  termux-setup-storage
  echo "Re-run this script once storage is ready."
  exit 0
fi

# ── Run ping ──────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PING_OUTPUT=$(ping -c "$COUNT" "$TARGET" 2>&1 || true)

# ── Parse results ─────────────────────────
MIN=$(echo "$PING_OUTPUT"    | grep -o 'min/avg/max[^=]*= *[0-9.]*/[0-9.]*/[0-9.]*' | cut -d'/' -f4)
AVG=$(echo "$PING_OUTPUT"    | grep -o 'min/avg/max[^=]*= *[0-9.]*/[0-9.]*/[0-9.]*' | cut -d'/' -f5)
MAX=$(echo "$PING_OUTPUT"    | grep -o 'min/avg/max[^=]*= *[0-9.]*/[0-9.]*/[0-9.]*' | cut -d'/' -f6)
LOSS=$(echo "$PING_OUTPUT"   | grep -o '[0-9]*% packet loss'                         | grep -o '[0-9]*')
RECEIVED=$(echo "$PING_OUTPUT" | grep -o '[0-9]* received'                           | grep -o '[0-9]*')

# ── Handle unreachable host ───────────────
if [[ -z "$AVG" ]]; then
  MIN=""; AVG=""; MAX=""
fi

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"

# Separate log per target, replacing dots/colons with underscores
SAFE_TARGET="${TARGET//[.:]/_}"
LOG_FILE="$LOG_DIR/ping_${SAFE_TARGET}_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,target,packets_sent,packets_received,packet_loss_pct,min_ms,avg_ms,max_ms" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
ROW="$TIMESTAMP,$TARGET,$COUNT,$RECEIVED,$LOSS,$MIN,$AVG,$MAX"
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi