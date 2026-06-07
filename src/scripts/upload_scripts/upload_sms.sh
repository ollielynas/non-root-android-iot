#!/data/data/com.termux/files/usr/bin/bash
# send_sms.sh — Send an SMS via Termux API
# Usage:
#   send_sms.sh --text "Your message here"
#   send_sms.sh --file "/path/to/message.txt"

DESTINATION_PHONE_NUMBER="DESTINATION_PHONE_NUMBER_HERE"

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
    echo "Usage:"
    echo "  $(basename "$0") --text \"message\""
    echo "  $(basename "$0") --file \"/path/to/file\""
    exit 1
}

check_dependency() {
    if ! command -v termux-sms-send &>/dev/null; then
        echo "'termux-api' package not found. Attempting to install..."
        if ! command -v pkg &>/dev/null; then
            echo "Error: 'pkg' not found — is this running inside Termux?"
            exit 1
        fi
        pkg install -y termux-api
        if ! command -v termux-sms-send &>/dev/null; then
            echo "Error: Installation appeared to succeed but 'termux-sms-send' is still not available."
            echo "Make sure the Termux:API companion app is also installed (F-Droid / Play Store)."
            exit 1
        fi
        echo "termux-api installed successfully."
    fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    usage
fi

MODE=""
PAYLOAD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --text)
            if [[ -z "$2" ]]; then
                echo "Error: --text requires a non-empty message argument."
                exit 1
            fi
            MODE="text"
            PAYLOAD="$2"
            shift 2
            ;;
        --file)
            if [[ -z "$2" ]]; then
                echo "Error: --file requires a file path argument."
                exit 1
            fi
            MODE="file"
            FILE_PATH="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            usage
            ;;
    esac
done

# ── Resolve message content ───────────────────────────────────────────────────

if [[ "$MODE" == "file" ]]; then
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: File not found: $FILE_PATH"
        exit 1
    fi
    if [[ ! -r "$FILE_PATH" ]]; then
        echo "Error: File is not readable: $FILE_PATH"
        exit 1
    fi
    PAYLOAD="$(cat "$FILE_PATH")"
    if [[ -z "$PAYLOAD" ]]; then
        echo "Error: File is empty: $FILE_PATH"
        exit 1
    fi
fi

if [[ -z "$PAYLOAD" ]]; then
    echo "Error: Message content is empty."
    exit 1
fi

# ── Send ──────────────────────────────────────────────────────────────────────

check_dependency

echo "Sending SMS to $DESTINATION_PHONE_NUMBER ..."

termux-sms-send -n "$DESTINATION_PHONE_NUMBER" "$PAYLOAD"

if [[ $? -eq 0 ]]; then
    echo "SMS sent successfully."
else
    echo "Error: Failed to send SMS (exit code $?)."
    exit 1
fi
