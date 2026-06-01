#!/bin/bash

DIR="/sdcard/AndroidIOT"
cd "$DIR" || exit 1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMMANDS_FILE="$DIR/commands.txt"

SCRIPT_NAME="$(basename "$0")"
LINE_NUM="${SCRIPT_NAME//[^0-9]/}"

if [ -z "$LINE_NUM" ]; then
    echo "Error: Could not parse line number from filename '$SCRIPT_NAME'"
    exit 1
fi

LINE_CONTENT=$(sed -n "${LINE_NUM}p" "$COMMANDS_FILE")
if [ -z "$LINE_CONTENT" ]; then
    echo "Error: Line $LINE_NUM is empty or does not exist."
    exit 1
fi

read -r interval script_name args <<< "$LINE_CONTENT"
cd "$DIR" || exit

period_ms=$((interval * 1000))

run_script() {
    local full_cmd="$script_name $args"
    /data/data/com.termux/files/usr/bin/bash -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH && $full_cmd" &
}

if [ "$period_ms" -lt 900000 ]; then
    echo "[+] Interval ${interval}s is under 15min, using wake lock loop"
    termux-wake-lock
    while true; do
        echo "[+] Executing: $script_name $args (Next run in ${interval}s)"
        run_script
        sleep "$interval"
    done
else
    echo "[+] Executing: $script_name $args (Next run in ${interval}s)"
    run_script

    SCRIPT_PATH="$DIR/$SCRIPT_NAME"
    TERMUX_HOME="/data/data/com.termux/files/home"
    EXEC_SCRIPT="$TERMUX_HOME/$SCRIPT_NAME"

    # Copy to termux home (noexec-safe) and make executable
    cp "$SCRIPT_PATH" "$EXEC_SCRIPT"
    chmod +x "$EXEC_SCRIPT"

    termux-job-scheduler \
        --script "$EXEC_SCRIPT" \
        --period-ms "$period_ms" \
        --battery-not-low false \
        --network any
fi