#!/bin/bash
# -----------------------------------------
#  log_battery.sh -- Log battery % via Termux:API
# -----------------------------------------
# NOTE: You MUST pass at least one of --download or --upload,
# otherwise the script collects data and discards it silently.
# Example commands.txt entry:
#   900  log_battery.sh --download
# -----------------------------------------

# Do NOT use set -e -- we want to log errors rather than silently exit
set -uo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# -- Paths --------------------------------------------------------
# Use the hardcoded /storage/emulated/0 path directly.
# Do NOT rely on ~/storage -- that symlink is created by
# termux-setup-storage for interactive sessions only and will not
# exist when this script is invoked by JobScheduler or any other
# non-interactive background trigger.
LOG_DIR=/storage/emulated/0/AndroidIOT
SCRIPT_LOG="$LOG_DIR/log_battery_debug.log"
CSV_FILE="$LOG_DIR/battery_log.csv"

# -- Verify storage is actually mounted ---------------------------
# /storage/emulated/0 is a FUSE mount that may not be ready on the
# first background trigger after boot (Android "CE storage" is only
# available after the first user unlock). We test the mount directly
# rather than checking ~/storage, and we do NOT attempt any
# interactive setup -- that requires a UI prompt and will hang.
if [[ ! -d /storage/emulated/0 ]]; then
    # Can't write to our normal log yet, so fall back to Termux home.
    FALLBACK_LOG="/data/data/com.termux/files/home/log_battery_boot.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] /storage/emulated/0 is not mounted yet. " \
         "This usually means the device was just booted and the screen has not been unlocked. " \
         "Row skipped." >> "$FALLBACK_LOG"
    exit 1
fi

mkdir -p "$LOG_DIR"

# -- Internal logger ----------------------------------------------
log() {
    local level="$1"; shift
    # Only record ERROR-level messages to avoid noisy logs.
    if [[ "$level" != "ERROR" ]]; then
        return 0
    fi
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $*" >> "$SCRIPT_LOG"
}

log INFO "=== log_battery.sh started, args: '${*}' ==="

# -- Defaults -----------------------------------------------------
DOWNLOAD=0
UPLOAD=0

# -- Help ---------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--download] [--upload]
Options:
  --download  append row to local CSV
  --upload    upload row using upload.sh
  -h          show this help message
Example:
  $(basename "$0") --download
  $(basename "$0") --download --upload
EOF
  exit 0
}

# -- Parse flags --------------------------------------------------
while getopts ":h-:" opt; do
  case $opt in
    h) usage ;;
    -) case "$OPTARG" in
         download) DOWNLOAD=1 ;;
         upload)   UPLOAD=1 ;;
         *) log WARN "Unknown long flag --$OPTARG (ignored)" ;;
       esac ;;
    :) log ERROR "-$OPTARG requires an argument."; exit 1 ;;
    \?) log ERROR "Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

log INFO "Flags -> DOWNLOAD=$DOWNLOAD  UPLOAD=$UPLOAD"

# Warn early if no action will be taken
if [[ "$DOWNLOAD" == "0" && "$UPLOAD" == "0" ]]; then
    log WARN "Neither --download nor --upload was passed."
    log WARN "Battery data will be collected but NOT saved or uploaded."
    log WARN "Add --download to your commands.txt entry to fix this."
fi

# -- Check termux-api is available --------------------------------
# Do NOT attempt pkg install here -- package installation is
# interactive and will fail or hang in a background job.
if ! command -v termux-battery-status &>/dev/null; then
    log ERROR "termux-battery-status not found."
    log ERROR "Run 'pkg install termux-api' in a Termux terminal, then retry."
    exit 1
fi

# -- Read battery status ------------------------------------------
log INFO "Calling termux-battery-status..."
BATTERY_JSON=""
BATTERY_JSON=$(termux-battery-status 2>&1) || {
    log ERROR "termux-battery-status failed: $BATTERY_JSON"
    exit 1
}
log INFO "Raw JSON: $BATTERY_JSON"

# -- Parse with jq or grep fallback -------------------------------
# Same note: do NOT attempt pkg install jq here.
if command -v jq &>/dev/null; then
    log INFO "Parsing with jq"
    PERCENTAGE=$(echo "$BATTERY_JSON" | jq -r '.percentage // empty')
    STATUS=$(echo      "$BATTERY_JSON" | jq -r '.status      // empty')
    HEALTH=$(echo      "$BATTERY_JSON" | jq -r '.health      // empty')
    TEMP=$(echo        "$BATTERY_JSON" | jq -r '.temperature // empty')
else
    log WARN "jq not found -- using grep fallback (install jq for reliability)"
    PERCENTAGE=$(echo "$BATTERY_JSON" | grep -o '"percentage": *[0-9]*'   | grep -o '[0-9]*'    || echo "")
    STATUS=$(echo      "$BATTERY_JSON" | grep -o '"status": *"[^"]*"'      | grep -o '"[^"]*"$' | tr -d '"' || echo "")
    HEALTH=$(echo      "$BATTERY_JSON" | grep -o '"health": *"[^"]*"'      | grep -o '"[^"]*"$' | tr -d '"' || echo "")
    TEMP=$(echo        "$BATTERY_JSON" | grep -o '"temperature": *[0-9.]*' | grep -o '[0-9.]*'  || echo "")
fi

log INFO "Parsed -> percentage='$PERCENTAGE'  status='$STATUS'  health='$HEALTH'  temp='$TEMP'"

# -- Validate parse -----------------------------------------------
PARSE_OK=1
[[ -z "$PERCENTAGE" ]] && { log ERROR "Failed to parse 'percentage' from JSON"; PARSE_OK=0; }
[[ -z "$STATUS"     ]] && { log WARN  "Failed to parse 'status' (will use empty string)"; }
[[ -z "$HEALTH"     ]] && { log WARN  "Failed to parse 'health' (will use empty string)"; }
[[ -z "$TEMP"       ]] && { log WARN  "Failed to parse 'temperature' (will use empty string)"; }

if [[ "$PARSE_OK" == "0" ]]; then
    log ERROR "Critical parse failure -- aborting without writing CSV row"
    exit 1
fi

# -- Build CSV row ------------------------------------------------
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ROW="$TIMESTAMP,$PERCENTAGE,$STATUS,$HEALTH,$TEMP"
log INFO "CSV row: $ROW"

# -- Write CSV header if file is new ------------------------------
if [[ ! -f "$CSV_FILE" ]]; then
    log INFO "CSV not found -- writing header to $CSV_FILE"
    echo "timestamp,percentage,status,health,temperature_c" > "$CSV_FILE"
fi

# -- Append row ---------------------------------------------------
if [[ "$DOWNLOAD" == "1" ]]; then
    echo "$ROW" >> "$CSV_FILE"
    log INFO "Row appended to $CSV_FILE"
else
    log INFO "--download not set, skipping CSV write"
fi

if [[ "$UPLOAD" == "1" ]]; then
    log INFO "Uploading row via upload.sh..."
    UPLOAD_SH="/sdcard/AndroidIOT/upload.sh"
    if [[ ! -f "$UPLOAD_SH" ]]; then
        log ERROR "upload.sh not found at $UPLOAD_SH -- skipping upload"
    else
        UPLOAD_ERR="${SCRIPT_LOG}.upload.err"
        if ! /data/data/com.termux/files/usr/bin/bash "$UPLOAD_SH" --text "$ROW" >/dev/null 2>"$UPLOAD_ERR"; then
            ERR_TEXT="$(cat "$UPLOAD_ERR" 2>/dev/null || true)"
            log ERROR "upload.sh exited with error: $ERR_TEXT"
        fi
        rm -f "$UPLOAD_ERR"
    fi
else
    log INFO "--upload not set, skipping upload"
fi

log INFO "=== log_battery.sh complete ==="
