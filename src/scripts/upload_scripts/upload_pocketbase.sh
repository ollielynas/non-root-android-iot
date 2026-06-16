#!/usr/bin/env bash
# pb_log.sh — Log IoT data to a PocketBase collection
#
# Usage:
#   pb_log.sh --text "payload"
#   pb_log.sh --file "/path/to/file"

PB_URL="ADDRESS_HERE"
PB_API_KEY="API_KEY_HERE"
PB_COLLECTION="iot_logs"

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    echo "Usage:"
    echo "  $(basename "$0") --text \"payload\""
    echo "  $(basename "$0") --file \"/path/to/file\""
    exit 1
}

die() { echo "Error: $*" >&2; exit 1; }

# ── Dependencies ──────────────────────────────────────────────────────────────
command -v curl &>/dev/null || die "'curl' is required but not found."
command -v jq   &>/dev/null || die "'jq' is required but not found."

# ── Argument parsing ──────────────────────────────────────────────────────────
[[ $# -ne 2 ]] && usage

case "$1" in
    --text)
        [[ -z "$2" ]] && die "--text requires a non-empty value."
        PAYLOAD="$2"
        ;;
    --file)
        [[ ! -f "$2" ]] && die "File not found: $2"
        [[ ! -r "$2" ]] && die "File not readable: $2"
        PAYLOAD="$(cat "$2")"
        [[ -z "$PAYLOAD" ]] && die "File is empty: $2"
        ;;
    *)
        usage
        ;;
esac

AUTH_HEADER="Authorization: ${PB_API_KEY}"

# ── Ensure collection exists ──────────────────────────────────────────────────
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "$AUTH_HEADER" \
    "${PB_URL}/api/collections/${PB_COLLECTION}")

if [[ "$HTTP_STATUS" == "404" ]]; then
    curl -sf -X POST "${PB_URL}/api/collections" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{
            \"name\": \"${PB_COLLECTION}\",
            \"type\": \"base\",
            \"fields\": [
                { \"name\": \"data\", \"type\": \"text\", \"required\": true }
            ],
            \"createRule\": null,
            \"listRule\": null,
            \"viewRule\": null,
            \"updateRule\": null,
            \"deleteRule\": null
        }" > /dev/null || die "Failed to create collection '${PB_COLLECTION}'."
elif [[ "$HTTP_STATUS" != "200" ]]; then
    die "Could not reach PocketBase (HTTP ${HTTP_STATUS}). Check the baked-in URL and API key."
fi

# ── Post record ───────────────────────────────────────────────────────────────
BODY=$(jq -n --arg data "$PAYLOAD" '{ data: $data }')

RECORD_RESP=$(curl -sf -X POST "${PB_URL}/api/collections/${PB_COLLECTION}/records" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "$BODY") || die "Failed to post record."

echo "Logged → id: $(echo "$RECORD_RESP" | jq -r '.id')"
