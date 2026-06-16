
# ─────────────────────────────────────────
#  take_photo.sh — Take a photo via Termux:API
# ─────────────────────────────────────────

set -euo pipefail

# ── Defaults ──────────────────────────────
CAMERA=0   # 0 = back, 1 = front

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [-c <camera>] [-h]

Options:
  -c <0|1>   Camera to use: 0 = back (default), 1 = front
  -h         Show this help message
    --download  store file internally and log the action
    --upload    upload file using upload.sh
Example:
  $(basename "$0") -c 1    # Take a selfie
EOF
  exit 0
}

# ── Parse flags ───────────────────────────
# ── Parse flags ───────────────────────────
while getopts ":c:h-:" opt; do
  case $opt in
    c) CAMERA="$OPTARG" ;;
    h) usage ;;
    -) ;;   # silently skip long flags like --download, --upload
    :) echo "Error: -$OPTARG requires an argument."; exit 1 ;;
    \?) echo "Error: Unknown flag -$OPTARG"; exit 1 ;;
  esac
done

# ── Validate camera value ─────────────────
if [[ "$CAMERA" != "0" && "$CAMERA" != "1" ]]; then
  echo "Error: Camera must be 0 (back) or 1 (front). Got: $CAMERA"
  exit 1
fi

# ── Check / install termux-api ────────────
if ! command -v termux-camera-photo &>/dev/null; then
  echo "termux-api not found. Installing..."
  pkg install -y termux-api
  echo "Done. Make sure the Termux:API companion app is also installed from F-Droid."
  echo ""
fi

# ── Check storage is set up ───────────────
if [[ ! -d ~/storage ]]; then
  echo "Storage not set up. Running termux-setup-storage..."
  termux-setup-storage
  echo "Re-run this script once storage is ready."
  exit 0
fi

# ── Prepare output path ───────────────────
PHOTO_DIR=/storage/emulated/0/AndroidIOT/
mkdir -p "$PHOTO_DIR"

FILENAME="$(date +%Y%m%d_%H%M%S).jpg"
OUTPUT="$PHOTO_DIR/$FILENAME"

# ── Take the photo ────────────────────────
CAM_LABEL="back"
[[ "$CAMERA" == "1" ]] && CAM_LABEL="front"

echo "📷 Using $CAM_LABEL camera..."
termux-camera-photo -c "$CAMERA" "$OUTPUT"

echo "✅ Photo saved: $OUTPUT"

if [[ "$@" == *"--upload"* ]]; then
    ./upload.sh --file "$OUTPUT"
fi

if [[ "$@" == *"--download"* ]]; then
    echo "$(date), $CAMERA, $OUTPUT" >> /storage/emulated/0/AndroidIOT/camera_log.csv
else
    rm -f "$OUTPUT"
fi
