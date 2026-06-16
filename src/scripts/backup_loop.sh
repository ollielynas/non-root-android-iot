#!/bin/bash
# ---------------------------------------------------------------
#  loop.sh -- Universal periodic command runner (quiet, robust)
#
#  This variant writes log files only when an ERROR occurs.
#  Routine INFO/WARN output is discarded.
#
#  Reads commands.txt:
#       interval  script_path  [args...]
#
#  Reads settings.txt:
#       START=<unix timestamp>   -- don't run before this time
#       END=<unix timestamp>     -- stop after this time
#       TAILSCALE=true/false
#       TAILSCALE_AUTH_TOKEN=<key>
#
#  Flow:
#    1. START > NOW  -> schedule one-shot starter at (START + LINE_NUM secs),
#                       then exit
#    2. START <= NOW -> proceed with normal scheduling
#       Short interval (< 15 min) -> wake-lock loop (checks END each iteration)
#       Long interval  (>= 15 min) -> termux-job-scheduler (runner checks END)
# ---------------------------------------------------------------
set -euo pipefail

# --- Fixed paths -------------------------------------------------
BASE_DIR="/sdcard/AndroidIOT"
COMMANDS_FILE="$BASE_DIR/commands.txt"
TERMUX_HOME="/data/data/com.termux/files/home"
BASH="/data/data/com.termux/files/usr/bin/bash"

# --- Make sure Go binaries are always found first -----------------
# (Required for the correct tailscale with 'file' subcommand)
GO_BIN="$TERMUX_HOME/go/bin"
export PATH="$GO_BIN:/data/data/com.termux/files/usr/bin:$PATH"

# --- Read settings -----------------------------------------------
SETTINGS_FILE="$BASE_DIR/settings.txt"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "FATAL: settings.txt not found at $SETTINGS_FILE" >&2
    exit 1
fi
# Strip whitespace and source
source <(sed 's/[[:space:]]//g' "$SETTINGS_FILE")
START=${START:-0}
END=${END:-0}
TAILSCALE=${TAILSCALE:-false}
TAILSCALE_AUTH_TOKEN=${TAILSCALE_AUTH_TOKEN:-0}

# --- Logging setup (errors only) ---------------------------------
LOG_DIR="$BASE_DIR/logs"
SCRIPT_NAME="$(basename "$0")"
LINE_NUM="${SCRIPT_NAME//[^0-9]/}"

if [[ -z "$LINE_NUM" ]]; then
    echo "FATAL: Could not extract line number from '$SCRIPT_NAME'" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/loop_line${LINE_NUM}.log"

log() {
    local level="$1"; shift
    if [[ "$level" != "ERROR" ]]; then
        return 0
    fi
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$ts] [ERROR] [loop.sh:line${LINE_NUM}] $*" >> "$LOG_FILE"
}

# --- Tailscale setup ---------------------------------------------
if [[ "$TAILSCALE" == "true" ]]; then
    # Ensure go is available
    if ! command -v go &>/dev/null; then
        log "ERROR" "go not found. Attempting to install golang..."
        if command -v pkg &>/dev/null; then
            pkg install golang -y || {
                log "ERROR" "Failed to install golang via pkg"
                exit 1
            }
        else
            log "ERROR" "No package manager available to install go"
            exit 1
        fi
    fi

    # Install tailscale and tailscaled if not present (with the updated PATH)
    if ! command -v tailscale &>/dev/null || ! command -v tailscaled &>/dev/null; then
        log "ERROR" "Tailscale binaries missing. Installing via go..."
        go install tailscale.com/cmd/tailscale@latest
        go install tailscale.com/cmd/tailscaled@latest
        # re-check after install
        if ! command -v tailscale &>/dev/null || ! command -v tailscaled &>/dev/null; then
            log "ERROR" "tailscale/tailscaled still not found after go install"
            exit 1
        fi
    fi

    # Start tailscaled if not already running
    if ! pgrep -x tailscaled &>/dev/null; then
        log "ERROR" "Starting tailscaled..."
        tailscaled --tun=userspace-networking \
                   --socks5-server=localhost:1055 \
                   --state="$TERMUX_HOME/.tailscale.state" \
                   > /dev/null 2>&1 &

        # Wait for the daemon to be fully ready (max 15 seconds)
        local waited=0
        local max_wait=15
        until tailscale status &>/dev/null || (( waited >= max_wait )); do
            sleep 1
            (( waited++ ))
        done

        if ! tailscale status &>/dev/null; then
            log "ERROR" "tailscaled failed to start within ${max_wait}s"
            exit 1
        fi
    fi

    # Authenticate / bring up Tailscale
    tailscale up --authkey="$TAILSCALE_AUTH_TOKEN" --accept-routes || {
        log "ERROR" "tailscale up failed"
        exit 1
    }
    log "ERROR" "Tailscale is up and connected."
fi

# --- Move to base directory --------------------------------------
cd "$BASE_DIR" || { log "ERROR" "Cannot cd to $BASE_DIR"; exit 1; }

# =================================================================
# STEP 1: Too early? Schedule a staggered start and exit.
# =================================================================
NOW="$(date +%s)"

if (( START > 0 && NOW < START )); then
    STAGGERED_START=$(( START + LINE_NUM ))
    DELAY_MS=$(( (STAGGERED_START - NOW) * 1000 ))
    SELF="$(realpath "$0")"
    STARTER="$TERMUX_HOME/starter_${LINE_NUM}.sh"

    cat > "$STARTER" << STARTER_EOF
#!/bin/bash
export PATH="$GO_BIN:/data/data/com.termux/files/usr/bin:\$PATH"
exec "$BASH" "$SELF"
STARTER_EOF
    chmod +x "$STARTER"

    termux-job-scheduler \
        --script "$STARTER" \
        --job-id "$LINE_NUM" \
        --period-ms 0 \
        --battery-not-low false 2>/dev/null || {
            log "ERROR" "Failed to schedule staggered start job"
            exit 1
        }

    START_HUMAN="$(date -d "@$STAGGERED_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
                   || date -r "$STAGGERED_START" '+%Y-%m-%d %H:%M:%S')"

    termux-notification --id 99 --ongoing \
        --title "📅 Scheduled Jobs (waiting)" \
        --content "Will start at $START_HUMAN"

    exit 0
fi

# =================================================================
# STEP 2: START has passed — normal scheduling
# =================================================================

# --- Read the command for this line ------------------------------
if [[ ! -f "$COMMANDS_FILE" ]]; then
    log "ERROR" "commands.txt not found at $COMMANDS_FILE"
    exit 1
fi

LINE_CONTENT=$(sed -n "${LINE_NUM}p" "$COMMANDS_FILE")
if [[ -z "$LINE_CONTENT" ]]; then
    log "ERROR" "Line $LINE_NUM is empty or missing in $COMMANDS_FILE"
    exit 1
fi

# Parse: first token = interval, second = script (can be relative), rest = args
read -r interval script_path rest <<< "$LINE_CONTENT"
read -ra ARGS <<< "${rest:-}"

# Resolve script path
if [[ "$script_path" = /* ]]; then
    FULL_SCRIPT="$script_path"
else
    FULL_SCRIPT="$BASE_DIR/$script_path"
fi

if [[ ! -f "$FULL_SCRIPT" ]]; then
    log "ERROR" "Script not found: $FULL_SCRIPT"
    exit 1
fi
if [[ ! -x "$FULL_SCRIPT" ]]; then
    chmod +x "$FULL_SCRIPT" || log "ERROR" "Cannot make $FULL_SCRIPT executable"
fi

# Validate interval
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval == 0 )); then
    log "ERROR" "interval '$interval' is not a positive integer"
    exit 1
fi

period_ms=$(( interval * 1000 ))

# --- Function to run the script immediately (fully detached) -----
run_now() {
    nohup "$BASH" -c 'cd "$1" && shift && "$@"' _ \
        "$BASE_DIR" "$FULL_SCRIPT" "${ARGS[@]:-}" \
        >/dev/null 2>&1 &
    disown $!
}

# =================================================================
# Short interval -> wake-lock loop
# =================================================================
MIN_JOBSCHEDULER_MS=900000   # 15 minutes

if (( period_ms < MIN_JOBSCHEDULER_MS )); then
    termux-wake-lock
    log "ERROR" "Entering wake-lock loop (interval=$interval s)."

    while true; do
        NOW="$(date +%s)"
        if (( END > 0 && NOW >= END )); then
            termux-wake-release
            termux-notification --id 99 --ongoing \
                --title "📅 Scheduled Jobs" \
                --content "Collection window ended. All jobs stopped."
            log "ERROR" "END time reached, exiting wake-lock loop."
            exit 0
        fi
        run_now
        sleep "$interval"
    done
    # Should never reach here
    termux-wake-release
    exit 0
fi

# =================================================================
# Long interval -> termux-job-scheduler
# =================================================================

# Build a quoted argument list for the runner
ARGS_QUOTED=""
for arg in "${ARGS[@]:-}"; do
    ARGS_QUOTED="${ARGS_QUOTED} $(printf '%q' "$arg")"
done
ARGS_QUOTED="${ARGS_QUOTED# }"

RUNNER="$TERMUX_HOME/runner_${LINE_NUM}.sh"

cat > "$RUNNER" << RUNNER_EOF
#!/bin/bash
# Auto-generated runner for line $LINE_NUM
# Script: $FULL_SCRIPT
# Args:   $ARGS_QUOTED

# Ensure the same PATH as the main loop (Go first, Termux second)
export PATH="$GO_BIN:/data/data/com.termux/files/usr/bin:\$PATH"

# Check END time – cancel and stop if window has passed
SETTINGS="$BASE_DIR/settings.txt"
source <(sed 's/[[:space:]]//g' "\$SETTINGS")
END=\${END:-0}
NOW="\$(date +%s)"
if (( END > 0 && NOW >= END )); then
    termux-job-scheduler --cancel --job-id $LINE_NUM 2>/dev/null || true
    termux-notification --id 99 --ongoing \
        --title "📅 Scheduled Jobs" \
        --content "Collection window ended. All jobs stopped."
    exit 0
fi

RUN_LOG="$LOG_DIR/run_line${LINE_NUM}_\$(date '+%Y%m%d_%H%M%S').log"

cd "$BASE_DIR" || {
    mkdir -p "\$(dirname "\$RUN_LOG")"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Cannot cd to $BASE_DIR" >> "\$RUN_LOG"
    exit 1
}

# Execute the actual script
read -ra JOB_ARGS <<< "$ARGS_QUOTED"
"$FULL_SCRIPT" "\${JOB_ARGS[@]:-}" >/dev/null 2>&1
EXIT_CODE=\$?
if [[ \$EXIT_CODE -ne 0 ]]; then
    mkdir -p "\$(dirname "\$RUN_LOG")"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $FULL_SCRIPT exited with code \$EXIT_CODE" >> "\$RUN_LOG"
fi
exit \$EXIT_CODE
RUNNER_EOF

chmod +x "$RUNNER"

# Try to schedule; if it fails, fall back to a wake‑lock loop
if SCHED_OUTPUT=$(termux-job-scheduler \
    --script "$RUNNER" \
    --job-id "$LINE_NUM" \
    --period-ms "$period_ms" \
    --battery-not-low false 2>&1); then
    # Check for suspicious words in output
    if echo "$SCHED_OUTPUT" | grep -qi "error\|fail\|exception\|denied"; then
        log "ERROR" "termux-job-scheduler reported: $SCHED_OUTPUT"
    fi
else
    log "ERROR" "termux-job-scheduler failed. Falling back to wake-lock loop."
    termux-wake-lock
    while true; do
        NOW="$(date +%s)"
        if (( END > 0 && NOW >= END )); then
            termux-wake-release
            exit 0
        fi
        run_now
        sleep "$interval"
    done
    exit 0
fi

# Run once immediately (the scheduled job will handle the rest)
run_now

exit 0
