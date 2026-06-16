#!/bin/bash
# ─────────────────────────────────────────
#  camera_motion.sh — Detect motion via camera frames
#  Requires: Termux:API, imagemagick
#  Install:  pkg install imagemagick
# ─────────────────────────────────────────
set -uo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Config ────────────────────────────────
CAMERA_ID=0          # 0 = back, 1 = front
THRESHOLD=50         # PHASH difference to count as motion (0–100ish; tune this)
DELAY=1             # seconds between frames
SAVE_ON_MOTION=0     # set to 1 to save a copy of frames where motion is detected

# ── Paths ─────────────────────────────────
TMP_DIR=$(mktemp -d)
FRAME_A="${TMP_DIR}/frame_a.jpg"
FRAME_B="${TMP_DIR}/frame_b.jpg"
MOTION_DIR="/storage/emulated/0/AndroidIOT/motion"

# ── Cleanup on exit ───────────────────────
cleanup() {
  echo ""
  echo "Stopping..."
  rm -rf "$TMP_DIR"
  exit 0
}
trap cleanup SIGINT SIGTERM

# ── Dependency check ──────────────────────
# ── Dependency check & auto-install ───────
if ! command -v magick &>/dev/null && ! command -v compare &>/dev/null; then
  echo "ImageMagick not found. Installing..."
  if command -v pkg &>/dev/null; then
    pkg install -y imagemagick
  elif command -v apt-get &>/dev/null; then
    apt-get install -y imagemagick
  else
    echo "Error: Could not find a package manager to install ImageMagick."
    echo "Please install it manually and re-run this script."
    exit 1
  fi

  # Verify the install succeeded
  if ! command -v magick &>/dev/null && ! command -v compare &>/dev/null; then
    echo "Error: ImageMagick installation failed. Please install it manually."
    exit 1
  fi

  echo "ImageMagick installed successfully."
fi

# Use 'magick compare' (v7) or fall back to 'compare' (v6)
IM_COMPARE="compare"
command -v magick &>/dev/null && IM_COMPARE="magick compare"
# ── Setup ─────────────────────────────────
if [[ "$SAVE_ON_MOTION" -eq 1 ]]; then
  mkdir -p "$MOTION_DIR"
  echo "Motion frames will be saved to: $MOTION_DIR"
fi

echo "Camera motion detector running"
echo "  Camera:    $CAMERA_ID (0=back, 1=front)"
echo "  Threshold: $PHASH difference > ${THRESHOLD}"
echo "  Interval:  ${DELAY}s between frames"
echo "Press Ctrl+C to stop."
echo "─────────────────────────────────────"

# ── Capture a frame, retry on empty file ──
capture_frame() {
  local output="$1"
  local attempts=3
  for ((i=1; i<=attempts; i++)); do
    termux-camera-photo -c "$CAMERA_ID" "$output" 2>/dev/null
    if [[ -s "$output" ]]; then
      return 0
    fi
    echo "  [warn] Camera returned empty frame, retrying ($i/$attempts)..."
    sleep 1
  done
  echo "  [error] Failed to capture frame after $attempts attempts."
  return 1
}

# ── Seed: capture the first frame ─────────
echo "Capturing initial frame..."
if ! capture_frame "$FRAME_A"; then
  echo "Could not get an initial frame. Check camera permissions."
  cleanup
fi
echo "Watching for motion..."

# ── Main loop ─────────────────────────────
while true; do
  sleep "$DELAY"

  if ! capture_frame "$FRAME_B"; then
    continue
  fi

  # Compare frames using PHASH (perceptual hash — tolerates minor exposure flicker)
  # compare exits 0 if similar, 1 if different; the score is on stderr
  DIFF=$($IM_COMPARE -metric PHASH "$FRAME_A" "$FRAME_B" /dev/null 2>&1 || true)

  # Sanitise: keep only the numeric part
  DIFF=$(echo "$DIFF" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)

  if [[ -z "$DIFF" ]]; then
    echo "[$(date +%H:%M:%S)] Could not compute difference, skipping frame"
    continue
  fi

  NOW=$(date +"%H:%M:%S")
  TRIGGERED=$(awk -v d="$DIFF" -v t="$THRESHOLD" 'BEGIN { print (d > t) ? "1" : "0" }')

  if [[ "$TRIGGERED" == "1" ]]; then
    echo "[$NOW] ⚠  MOTION DETECTED  (PHASH diff: ${DIFF})"

    if [[ "$SAVE_ON_MOTION" -eq 1 ]]; then
      SAVE_PATH="${MOTION_DIR}/motion_$(date +%Y%m%d_%H%M%S).jpg"
      cp "$FRAME_B" "$SAVE_PATH"
      echo "       Saved: $SAVE_PATH"
    fi


  else
    echo "[$NOW]    Still            (PHASH diff: ${DIFF})"
  fi

  # Current frame becomes the reference for the next comparison
  cp "$FRAME_B" "$FRAME_A"
done
