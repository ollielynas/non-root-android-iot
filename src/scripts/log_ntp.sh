# ─────────────────────────────────────────
#  sync_time.sh — Realign device clock with NTP
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
DOWNLOAD=0
UPLOAD=0
NTP_SERVER="pool.ntp.org"

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--server <ntp_server>] [--download] [--upload]
Options:
  --server    NTP server to sync with (default: pool.ntp.org)
  --download  store log internally
  --upload    upload log using upload.sh
  -h          Show this help message
Example:
  $(basename "$0") --download
  $(basename "$0") --server time.google.com --download
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
         server)   NTP_SERVER="${!OPTIND}"; shift ;;
         *) echo "Error: Unknown flag --$OPTARG"; exit 1 ;;
       esac ;;
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Check / install ntpdate ───────────────
if ! command -v ntpdate &>/dev/null; then
  echo "ntpdate not found. Continuing with query-only fallback."
fi

# ── Check storage is set up ───────────────
if [[ ! -d ~/storage ]]; then
  echo "Storage not set up. Running termux-setup-storage..."
  termux-setup-storage
  echo "Re-run this script once storage is ready."
  exit 0
fi

# ── Record time before sync ───────────────
TIME_BEFORE=$(date '+%Y-%m-%d %H:%M:%S')

# ── Query NTP and calculate offset ────────
# -q = query only, don't set time (requires root to set)
OFFSET=""
DELAY=""
if command -v ntpdate &>/dev/null; then
  NTP_OUTPUT=$(ntpdate -q "$NTP_SERVER" 2>&1 || true)

  # Extract offset and delay from ntpdate output
  # Example: "offset -0.123456 sec"
  OFFSET=$(echo "$NTP_OUTPUT" | grep -oE -- 'offset -?[0-9.]+' | grep -oE -- '-?[0-9.]+' | tail -1)
  DELAY=$(echo "$NTP_OUTPUT"  | grep -oE -- 'delay [0-9.]+'    | grep -oE -- '[0-9.]+' | tail -1)
else
  NTP_OUTPUT=""
fi

# ── Attempt to set system time (requires root) ─
SYNC_STATUS="query_only"
if command -v su &>/dev/null && command -v ntpdate &>/dev/null; then
  if su -c "ntpdate -b $NTP_SERVER" &>/dev/null 2>&1; then
    SYNC_STATUS="synced"
  else
    SYNC_STATUS="query_only_no_root"
  fi
elif ! command -v ntpdate &>/dev/null; then
  SYNC_STATUS="ntpdate_unavailable"
fi

TIME_AFTER=$(date '+%Y-%m-%d %H:%M:%S')

echo "[+] NTP server:   $NTP_SERVER"
echo "[+] Offset:       ${OFFSET}s"
echo "[+] Delay:        ${DELAY}s"
echo "[+] Sync status:  $SYNC_STATUS"

# ── Log path ──────────────────────────────
LOG_DIR=/storage/emulated/0/AndroidIOT
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ntp_sync_log.csv"

# ── Write CSV header if file is new ───────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp_before,timestamp_after,ntp_server,offset_s,delay_s,sync_status" >> "$LOG_FILE"
fi

# ── Append row ────────────────────────────
ROW="$TIME_BEFORE,$TIME_AFTER,$NTP_SERVER,$OFFSET,$DELAY,$SYNC_STATUS"

if [[ "$DOWNLOAD" == "1" ]]; then
  echo "$ROW" >> "$LOG_FILE"
fi

if [[ "$UPLOAD" == "1" ]]; then
  ./upload.sh --text "$ROW"
fi