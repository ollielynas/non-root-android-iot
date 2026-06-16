#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# upload_taildrop.sh — Send a text message or file to a Tailscale peer
#                      via Taildrop, using the local tailscale CLI.
#
# Usage:
#   upload_taildrop.sh --text "Your message here"
#   upload_taildrop.sh --file "/path/to/file.txt"
# =============================================================================

TARGETS=(DEST_NODES_GO_HERE)

TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
TEMP_FILE=""

LOG_FILE="/storage/emulated/0/AndroidIOT/upload_taildrop.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $*" >> "$LOG_FILE"
}

log_section() {
    log "INFO" "──────────────────────────────────────"
    log "INFO" "  $*"
    log "INFO" "──────────────────────────────────────"
}

log_cmd() {
    # Run a command and append its full output (stdout + stderr) to the log
    local label="$1"; shift
    log "INFO" "$ $*"
    "$@" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    log "INFO" "  └─ exit code: $exit_code"
    return $exit_code
}

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    echo "Usage:"
    echo "  $(basename "$0") --text \"message\""
    echo "  $(basename "$0") --file \"/path/to/file\""
    exit 1
}

cleanup() {
    [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
}
trap cleanup EXIT

# ── Argument parsing ──────────────────────────────────────────────────────────
[[ $# -lt 2 ]] && usage

FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --text)
            [[ -z "$2" ]] && { log "ERROR" "--text requires a non-empty message."; exit 1; }
            TEMP_FILE="${TMPDIR}/taildrop_payload_$(date +%Y%m%d_%H%M%S).txt"
            printf '%s\n' "$2" > "$TEMP_FILE"
            FILE="$TEMP_FILE"
            shift 2
            ;;
        --file)
            [[ -z "$2" ]]  && { log "ERROR" "--file requires a file path.";  exit 1; }
            [[ -f "$2"  ]] || { log "ERROR" "File not found: $2";             exit 1; }
            [[ -r "$2"  ]] || { log "ERROR" "File not readable: $2";          exit 1; }
            FILE="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown argument '$1'"
            usage
            ;;
    esac
done

[[ -z "$FILE" ]] && { log "ERROR" "No file or text provided."; usage; }

# ── Start ─────────────────────────────────────────────────────────────────────
log_section "upload_taildrop.sh starting"
log "INFO" "File     : $FILE"
log "INFO" "Size     : $(wc -c < "$FILE") bytes"
log "INFO" "Targets  : ${TARGETS[*]}"
log "INFO" "Tailscale: $(command -v tailscale || echo 'NOT FOUND')"

# ── Tailscale health checks ───────────────────────────────────────────────────
log_section "Tailscale binary check"
if ! command -v tailscale &>/dev/null; then
    log "ERROR" "tailscale not found in PATH"
    exit 1
fi
log_cmd "version" tailscale version

log_section "Tailscale daemon status"
if ! tailscale status &>/dev/null; then
    log "ERROR" "Tailscale daemon is not running"
    exit 1
fi
log_cmd "status" tailscale status

log_section "Tailscale self IP"
log_cmd "ip" tailscale ip

log_section "Network check (DERP / NAT)"
log_cmd "netcheck" tailscale netcheck

# ── Per-target send ───────────────────────────────────────────────────────────
OVERALL_EXIT=0

for TARGET in "${TARGETS[@]}"; do
    log_section "Target: $TARGET"

    # Ping to confirm the peer is reachable before attempting the transfer
    log "INFO" "Pinging $TARGET (1 probe)..."
    PING_OUT=$(tailscale ping --c=1 "$TARGET" 2>&1)
    PING_EXIT=$?
    log "INFO" "Ping exit=$PING_EXIT  output: $PING_OUT"

    if [[ $PING_EXIT -ne 0 ]]; then
        log "ERROR" "$TARGET is unreachable — skipping file send"
        OVERALL_EXIT=1
        continue
    fi

    # Send the file
    log "INFO" "Sending '$(basename "$FILE")' to $TARGET..."
    SEND_OUT=$(tailscale file cp "$FILE" "${TARGET}:" 2>&1)
    SEND_EXIT=$?
    log "INFO" "Send exit=$SEND_EXIT  output: ${SEND_OUT:-<no output>}"

    if [[ $SEND_EXIT -eq 0 ]]; then
        log "INFO" "OK — file sent to $TARGET"
    else
        log "ERROR" "Send FAILED to $TARGET (exit $SEND_EXIT)"
        OVERALL_EXIT=1
    fi
done

log_section "Done (overall exit=$OVERALL_EXIT)"
exit $OVERALL_EXIT
