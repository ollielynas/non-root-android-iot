#!/bin/bash
# ─────────────────────────────────────────
#  log_usb_serial.sh — Log USB serial devices via Termux
# ─────────────────────────────────────────
set -euo pipefail
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# ── Defaults ──────────────────────────────
LOG_DIR="/storage/emulated/0/AndroidIOT"
LOG_FILE="$LOG_DIR/usb_serial_log.csv"
DOWNLOAD=0
UPLOAD=0

# ── Help ──────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]
Log connected USB serial devices and their state.

Options:
  --download    Store log internally in CSV file
  --upload      Upload log using upload.sh
  -h            Show this help message

Example:
  $(basename "$0") --download
  $(basename "$0") --upload
  $(basename "$0") --download --upload
EOF
  exit 0
}

# ── Parse flags ───────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --download) DOWNLOAD=1; shift ;;
    --upload) UPLOAD=1; shift ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ── Create log directory ─────────────────
mkdir -p "$LOG_DIR"

# ── Initialize CSV ───────────────────────
if [[ ! -f "$LOG_FILE" ]]; then
  echo "timestamp,device_path,device_type,vendor_id,product_id,serial_number,manufacturer,product,permission_status,mount_point" > "$LOG_FILE"
fi

# ── Log individual device ─────────────────
log_device() {
  local timestamp="$1"
  local device_path="$2"
  local device_type="$3"
  local vendor_id="${4:-}"
  local product_id="${5:-}"
  local serial="${6:-}"
  local manufacturer="${7:-}"
  local product="${8:-}"
  local permission="${9:-}"
  local mount_point="${10:-}"
  
  # Sanitize fields (remove commas and newlines)
  device_path=$(echo "$device_path" | tr ',' ';' | tr -d '\n\r')
  manufacturer=$(echo "$manufacturer" | tr ',' ';' | tr -d '\n\r')
  product=$(echo "$product" | tr ',' ';' | tr -d '\n\r')
  
  local log_entry="$timestamp,$device_path,$device_type,$vendor_id,$product_id,$serial,$manufacturer,$product,$permission,$mount_point"
  
  echo "[$timestamp] USB Device Found:"
  echo "  Path: $device_path"
  echo "  Type: $device_type"
  [[ -n "$vendor_id" ]] && echo "  VID/PID: $vendor_id:$product_id"
  [[ -n "$manufacturer" ]] && echo "  Manufacturer: $manufacturer"
  [[ -n "$product" ]] && echo "  Product: $product"
  [[ -n "$serial" ]] && echo "  Serial: $serial"
  [[ -n "$mount_point" ]] && echo "  Mount: $mount_point"
  echo "  Permission: $permission"
  echo "---"
  
  # Handle download flag
  if [[ "$DOWNLOAD" == "1" ]]; then
    echo "$log_entry" >> "$LOG_FILE"
  fi
  
  # Handle upload flag
  if [[ "$UPLOAD" == "1" ]]; then
    if [[ -f "./upload.sh" ]]; then
      ./upload.sh --text "$log_entry"
    else
      echo "Warning: upload.sh not found in current directory"
    fi
  fi
}

# ── Main scan ─────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEVICES_FOUND=0

# Method 1: Check /dev for common serial devices (rarely works without root)
for dev_pattern in "ttyUSB*" "ttyACM*" "tty.usb*"; do
  for dev in /dev/$dev_pattern; do
    if [[ -e "$dev" ]]; then
      DEVICES_FOUND=1
      log_device "$TIMESTAMP" "$dev" "serial_port"
    fi
  done
done

# Method 2: Check sysfs for USB devices (works on some devices)
for device in /sys/bus/usb/devices/*/; do
  if [[ -d "$device" ]]; then
    vendor_id=""
    product_id=""
    serial=""
    manufacturer=""
    product=""
    
    # Read USB descriptors
    [[ -f "${device}idVendor" ]] && vendor_id=$(cat "${device}idVendor" 2>/dev/null)
    [[ -f "${device}idProduct" ]] && product_id=$(cat "${device}idProduct" 2>/dev/null)
    [[ -f "${device}serial" ]] && serial=$(cat "${device}serial" 2>/dev/null)
    [[ -f "${device}manufacturer" ]] && manufacturer=$(cat "${device}manufacturer" 2>/dev/null)
    [[ -f "${device}product" ]] && product=$(cat "${device}product" 2>/dev/null)
    
    # Check if it's a serial device by class
    if [[ -f "${device}bDeviceClass" ]]; then
      class=$(cat "${device}bDeviceClass" 2>/dev/null)
      # USB class 2 = communications, class 10 = CDC data (common for serial)
      if [[ "$class" == "02" || "$class" == "0a" ]]; then
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "usb_serial" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected"
      fi
    fi
    
    # Check for known serial adapters by VID/PID
    case "$vendor_id:$product_id" in
      "0403:"*) # FTDI
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "ftdi_adapter" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected" ;;
      "10c4:"*) # Silicon Labs CP210x
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "cp210x_adapter" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected" ;;
      "2341:"*) # Arduino
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "arduino" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected" ;;
      "1a86:"*) # CH340/CH341
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "ch341_adapter" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected" ;;
      "2e8a:"*) # Raspberry Pi Pico
        DEVICES_FOUND=1
        log_device "$TIMESTAMP" "${device}" "rp2040" "$vendor_id" "$product_id" "$serial" "$manufacturer" "$product" "detected" ;;
    esac
  fi
done

# Method 3: Check termux-usb if available
if command -v termux-usb &>/dev/null; then
  usb_list=$(termux-usb -l 2>/dev/null || echo "")
  if [[ -n "$usb_list" ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        DEVICES_FOUND=1
        device_path=$(echo "$line" | awk '{print $1}')
        permission=$(echo "$line" | grep -o "permission: [a-z]*" | awk '{print $2}')
        log_device "$TIMESTAMP" "$device_path" "termux_detected" "" "" "" "" "" "${permission:-unknown}"
      fi
    done <<< "$usb_list"
  fi
fi

# Method 4: Check for mounted USB storage
for mount_point in /storage/*/; do
  if [[ "$mount_point" != "/storage/emulated/" ]] && [[ -d "$mount_point" ]]; then
    DEVICES_FOUND=1
    log_device "$TIMESTAMP" "$mount_point" "usb_storage" "" "" "" "" "" "mounted" "$mount_point"
  fi
done

# Log if nothing found
if [[ $DEVICES_FOUND -eq 0 ]]; then
  NO_DEVICE_ENTRY="$TIMESTAMP,no_devices_found,,,,,,,"
  echo "$TIMESTAMP: No USB serial devices detected"
  
  if [[ "$DOWNLOAD" == "1" ]]; then
    echo "$NO_DEVICE_ENTRY" >> "$LOG_FILE"
  fi
  
  if [[ "$UPLOAD" == "1" ]]; then
    if [[ -f "./upload.sh" ]]; then
      ./upload.sh --text "$NO_DEVICE_ENTRY"
    else
      echo "Warning: upload.sh not found in current directory"
    fi
  fi
fi

# Status messages
if [[ "$DOWNLOAD" == "1" ]]; then
  echo "Data saved to: $LOG_FILE"
fi