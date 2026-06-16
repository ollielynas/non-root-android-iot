#!/bin/bash
# ---------------------------------------------------------------
#  loop.sh -- Universal periodic command runner (quiet mode)
#
#  This trimmed variant only writes log files when an ERROR occurs.
#  Routine INFO/WARN output is discarded.
#
#  Reads commands.txt:
#       interval  interpreter  [flags]  script_path  [args...]
#
#  Reads settings.txt:
#       START=<unix timestamp>   -- don't run before this time
#       END=<unix timestamp>     -- stop after this time
#
#  Flow:
#    1. START > NOW  -> schedule one-shot starter at (START + LINE_NUM secs)
#                       to stagger jobs, then exit
#    2. START <= NOW -> proceed with normal scheduling
#       Short interval (< 15 min) -> wake-lock loop (checks END each iteration)
#       Long interval  (>= 15 min) -> JobScheduler  (runner checks END each run)
# ---------------------------------------------------------------
set -euo pipefail

# --- Fixed paths -------------------------------------------------
BASE_DIR="/sdcard/AndroidIOT"
COMMANDS_FILE="$BASE_DIR/commands.txt"
TERMUX_HOME="/data/data/com.termux/files/home"
BASH="/data/data/com.termux/files/usr/bin/bash"
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# --- Read settings -----------------------------------------------
# pub fn generate_settings_file(&self) -> String {
#     format!("
#         START={}
#         END={}
#         ",
#         self.start_date.timestamp(),
#         self.start_date.timestamp() + self.collection_duration.as_secs() as i64
#     )
# }
source <(sed 's/[[:space:]]//g' "$BASE_DIR/settings.txt")
START=${START:-0}
END=${END:-0}
TAILSCALE=${TAILSCALE:-0}
TAILSCALE_AUTH_TOKEN=${TAILSCALE_AUTH_TOKEN:-0}


# --- Logging setup -----------------------------------------------
LOG_DIR="$BASE_DIR/logs"

log() {
    local level="$1"; shift
    if [[ "$level" != "ERROR" ]]; then
        return 0
    fi
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local logfile
    logfile="${LOG_FILE:-$LOG_DIR/loop_unknown.log}"
    mkdir -p "$(dirname "$logfile")"
    echo "[$ts] [ERROR] [loop.sh:line${LINE_NUM:-?}] $*" >> "$logfile"
}


if [[ "$TAILSCALE" == "true" ]]; then
    # Ensure Go binary directory is in PATH
    export PATH="$HOME/go/bin:$PATH"

    # Install both binaries if they're missing
    if ! command -v tailscale &> /dev/null || ! command -v tailscaled &> /dev/null; then
        log "INFO" "Installing tailscale and tailscaled..."
        pkg install golang   # (you already have this)
        go install tailscale.com/cmd/tailscale@latest
        go install tailscale.com/cmd/tailscaled@latest
        log "INFO" "Tailscale installed successfully."
    fi

    # Start tailscaled in userspace mode if it isn't already running
    if ! pgrep -x tailscaled > /dev/null; then
        log "INFO" "Starting tailscaled (userspace networking)..."
        tailscaled --tun=userspace-networking --socks5-server=localhost:1055 \
                   --state="$HOME/.tailscale.state" &
        # Give it a moment to initialise
        for i in {1..10}; do
                if tailscale status &>/dev/null; then
                    break
                fi
                sleep 1
            done
    fi

    # Authenticate / bring up Tailscale
    tailscale up --authkey="$TAILSCALE_AUTH_TOKEN" --accept-routes
    log "INFO" "Tailscale started successfully."
fi

# --- Identify this job by filename (1.sh, 2.sh, ...) ------------
SCRIPT_NAME="$(basename "$0")"
LINE_NUM="${SCRIPT_NAME//[^0-9]/}"

if [[ -z "$LINE_NUM" ]]; then
    log ERROR "Could not extract line number from '$SCRIPT_NAME'"
    exit 1
fi

LOG_FILE="$LOG_DIR/loop_line${LINE_NUM}.log"

cd "$BASE_DIR" || { log ERROR "Cannot cd to $BASE_DIR"; exit 1; }

# =================================================================
# STEP 1: Is it too early to start?
# Schedule a one-shot starter at (START + LINE_NUM) and exit.
# =================================================================
NOW="$(date +%s)"

if (( START > 0 && NOW < START )); then
    STAGGERED_START=$(( START + LINE_NUM ))
    DELAY_MS=$(( (STAGGERED_START - NOW) * 1000 ))
    SELF="$(realpath "$0")"
    STARTER="$TERMUX_HOME/starter_${LINE_NUM}.sh"

    cat > "$STARTER" << STARTER_EOF
#!/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:\$PATH"
exec "$BASH" "$SELF"
STARTER_EOF
    chmod +x "$STARTER"

    termux-job-scheduler \
        --script "$STARTER" \
        --job-id "$LINE_NUM" \
        --period-ms 0 \
        --battery-not-low false 2>/dev/null || true

    START_HUMAN="$(date -d "@$STAGGERED_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
                   || date -r "$STAGGERED_START" '+%Y-%m-%d %H:%M:%S')"

    termux-notification --id 99 --ongoing \
        --title "📅 Scheduled Jobs (waiting)" \
        --content "Will start at $START_HUMAN"

    exit 0
fi

# =================================================================
# STEP 2: START has passed — proceed with normal scheduling
# =================================================================

# --- Read the command for this line ------------------------------
if [[ ! -f "$COMMANDS_FILE" ]]; then
    log ERROR "commands.txt not found at $COMMANDS_FILE"
    exit 1
fi

LINE_CONTENT=$(sed -n "${LINE_NUM}p" "$COMMANDS_FILE")
if [[ -z "$LINE_CONTENT" ]]; then
    log ERROR "Line $LINE_NUM is empty or missing in $COMMANDS_FILE"
    exit 1
fi

read -r interval script_name rest <<< "$LINE_CONTENT"
read -ra ARGS <<< "${rest:-}"

# --- Resolve the script to an absolute path ----------------------
if [[ "$script_name" = /* ]]; then
    SCRIPT_PATH="$script_name"
else
    SCRIPT_PATH="$BASE_DIR/$script_name"
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    log ERROR "Script not found: $SCRIPT_PATH"
    exit 1
fi
if [[ ! -x "$SCRIPT_PATH" ]]; then
    chmod +x "$SCRIPT_PATH" || log ERROR "Cannot make $SCRIPT_PATH executable"
fi

# --- Validate interval -------------------------------------------
if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( interval == 0 )); then
    log ERROR "interval '$interval' is not a positive integer -- aborting"
    exit 1
fi

period_ms=$(( interval * 1000 ))

# --- Run a command immediately (fully detached) ------------------
run_now() {
    nohup "$BASH" -c 'cd "$1" && shift && "$@"' _ \
        "$BASE_DIR" "$SCRIPT_PATH" "${ARGS[@]:-}" \
        >/dev/null 2>&1 &
    disown $!
}

# =================================================================
# Short interval -> wake-lock loop
# Checks END on every iteration before running.
# =================================================================
MIN_JOBSCHEDULER_MS=900000

if (( period_ms < MIN_JOBSCHEDULER_MS )); then
    termux-wake-lock
    while true; do
        NOW="$(date +%s)"
        if (( END > 0 && NOW >= END )); then
            termux-wake-release
            termux-notification --id 99 --ongoing \
                --title "📅 Scheduled Jobs" \
                --content "Collection window ended. All jobs stopped."
            exit 0
        fi
        run_now
        sleep "$interval"
    done
    termux-wake-release
    exit 0
fi

# =================================================================
# Long interval -> JobScheduler
# Runner script checks END at the start of each execution.
# =================================================================

ARGS_QUOTED=""
for arg in "${ARGS[@]:-}"; do
    ARGS_QUOTED="${ARGS_QUOTED} $(printf '%q' "$arg")"
done
ARGS_QUOTED="${ARGS_QUOTED# }"

RUNNER="$TERMUX_HOME/runner_${LINE_NUM}.sh"

cat > "$RUNNER" << RUNNER_EOF
#!/bin/bash
# Auto-generated by loop.sh for line $LINE_NUM
# Script: $SCRIPT_PATH
# Args:   $ARGS_QUOTED

# Add Go binaries and standard Termux paths
export PATH="/data/data/com.termux/files/home/go/bin:/data/data/com.termux/files/usr/bin:\$PATH"

# Check END time – cancel and stop if window has passed
source <(sed 's/[[:space:]]//g' "$BASE_DIR/settings.txt")
END=\${END:-0}
NOW="\$(date +%s)"
if (( END > 0 && NOW >= END )); then
    termux-job-scheduler --cancel --job-id $LINE_NUM 2>/dev/null || true
    termux-notification --id 99 --ongoing \
        --title "Scheduled Jobs" \
        --content "Collection window ended. All jobs stopped."
    exit 0
fi

RUN_LOG="$LOG_DIR/run_line${LINE_NUM}_\$(date '+%Y%m%d_%H%M%S').log"

cd "$BASE_DIR" || {
    mkdir -p "\$(dirname "\$RUN_LOG")"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Cannot cd to $BASE_DIR" >> "\$RUN_LOG"
    exit 1
}

read -ra JOB_ARGS <<< "$ARGS_QUOTED"

"$SCRIPT_PATH" "\${JOB_ARGS[@]:-}" >/dev/null 2>&1
EXIT_CODE=\$?
if [[ \$EXIT_CODE -ne 0 ]]; then
    mkdir -p "\$(dirname "\$RUN_LOG")"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $SCRIPT_PATH exited with code \$EXIT_CODE" >> "\$RUN_LOG"
fi
exit \$EXIT_CODE
RUNNER_EOF

chmod +x "$RUNNER"

if [[ ! -x "$RUNNER" ]]; then
    log ERROR "Runner is not executable: $RUNNER"
    exit 1
fi

SCHED_OUTPUT=$(termux-job-scheduler \
    --script "$RUNNER" \
    --job-id "$LINE_NUM" \
    --period-ms "$period_ms" \
    --battery-not-low false 2>&1) || {
        log ERROR "termux-job-scheduler failed. Output: $SCHED_OUTPUT"
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
    }

if echo "$SCHED_OUTPUT" | grep -qi "error\|fail\|exception\|denied"; then
    log ERROR "termux-job-scheduler output: $SCHED_OUTPUT"
fi

# Run once immediately
run_now

# termux-notification --id 99 --ongoing \
#   --title "Scheduled Jobs ($(termux-job-scheduler --pending | grep -c 'Pending Job'))" \
#   --content "$(termux-job-scheduler --pending | grep 'Pending Job' | awk '{match($0, /runner_([0-9]+)\.sh/, arr); line=arr[1]; match($0, /periodic: ([0-9]+)ms/, ms); mins=ms[1]/60000; cmd=""; n=0; while((getline c < "/sdcard/AndroidIOT/commands.txt") > 0) {n++; if(n==line) {split(c,a," "); cmd=a[4]; sub(".*/","",cmd); sub("\\.sh$","",cmd); gsub("_"," ",cmd)}} close("/sdcard/AndroidIOT/commands.txt"); n=0; printf "%d. %s every %.0fmin\n", NR, cmd, mins}')"

exit 0
