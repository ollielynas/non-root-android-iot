#!/bin/bash
# ─────────────────────────────────────────
#  ding.sh — Play a ding sound via Termux
# ─────────────────────────────────────────
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

FREQ=880        # Hz — frequency of the tone (880 = A5, a bright "ding")
DURATION=0.3    # seconds for the main ding
DECAY=0.6       # seconds for the fade/tail

# ── Dependency check & auto-install ───────
if ! command -v play &>/dev/null; then
  echo "sox not found. Installing..."
  pkg install -y sox
  if ! command -v play &>/dev/null; then
    echo "Error: sox installation failed. Please install it manually: pkg install sox"
    exit 1
  fi
  echo "sox installed successfully."
fi

# ── Play ding ─────────────────────────────
play -n -q \
  synth "$DURATION" sine "$FREQ" \
  synth "$DECAY"    sine "$FREQ" fade 0 "$DECAY" "$DECAY" \
  gain -6
