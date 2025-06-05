#!/bin/bash
# Improved USB Monitor - Detects mounted USB devices and launches scanner

LOGFILE="/tmp/usb-monitor.log"
PIDFILE="/tmp/usb-monitor.pid"

# Ensure only one instance runs
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "USB Monitor already running (PID: $(cat "$PIDFILE"))"
  exit 0
fi

echo $$ >"$PIDFILE"

echo "$(date): USB Monitor started as user $USER (PID: $$)" >>"$LOGFILE"

# Function to check if scanner is already running
is_scanner_running() {
  pgrep -f "usb_scanner.py" >/dev/null
}

# Function to get USB device details
get_usb_details() {
  local device="$1"
  local mountpoint="$2"

  # Try to get more device info
  local vendor=$(udevadm info --name="$device" --query=property | grep "ID_VENDOR=" | cut -d'=' -f2 2>/dev/null || echo "Unknown")
  local model=$(udevadm info --name="$device" --query=property | grep "ID_MODEL=" | cut -d'=' -f2 2>/dev/null || echo "USB Device")
  local label=$(udevadm info --name="$device" --query=property | grep "ID_FS_LABEL=" | cut -d'=' -f2 2>/dev/null || echo "No Label")

  echo "Device: $vendor $model"
  echo "Label: $label"
  echo "Mount: $mountpoint"
}

# Track known devices - include mount points to detect mounting/unmounting
LAST_STATE="/tmp/usb_last_state"
lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN 2>/dev/null | grep -E "sd[a-z][0-9].*usb" >"$LAST_STATE" || touch "$LAST_STATE"

echo "$(date): Initial USB devices:" >>"$LOGFILE"
cat "$LAST_STATE" >>"$LOGFILE"

while true; do
  CURRENT_STATE="/tmp/usb_current_state"
  lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN 2>/dev/null | grep -E "sd[a-z][0-9].*usb" >"$CURRENT_STATE" || touch "$CURRENT_STATE"

  # Check for newly mounted USB devices
  NEW_MOUNTED=$(comm -13 <(sort "$LAST_STATE") <(sort "$CURRENT_STATE"))

  if [[ -n "$NEW_MOUNTED" ]]; then
    echo "$(date): New USB mount detected:" >>"$LOGFILE"
    echo "$NEW_MOUNTED" >>"$LOGFILE"

    # Process each new mounted device
    echo "$NEW_MOUNTED" | while read -r line; do
      if [[ "$line" =~ ^[├└│[:space:]]*([a-z0-9]+)[[:space:]]+([a-z0-9]+)[[:space:]]+(/[^[:space:]]+)[[:space:]]+usb ]]; then
        device="${BASH_REMATCH[1]}"
        fstype="${BASH_REMATCH[2]}"
        mountpoint="${BASH_REMATCH[3]}"

        echo "$(date): Processing device: /dev/$device, fstype: $fstype, mount: $mountpoint" >>"$LOGFILE"

        # Only scan if it's a real filesystem and mounted somewhere useful
        if [[ "$fstype" =~ ^(vfat|ntfs|exfat|ext[234])$ ]] && [[ "$mountpoint" =~ ^(/media/|/mnt/|/run/media/) ]]; then

          # Check if scanner is already running
          if is_scanner_running; then
            echo "$(date): Scanner already running, skipping launch for $device" >>"$LOGFILE"
          else
            echo "$(date): Launching scanner for $device at $mountpoint" >>"$LOGFILE"

            # Get device details for logging
            get_usb_details "$device" "$mountpoint" >>"$LOGFILE"

            # Launch scanner
            cd /home/administrator/usb-virus-scanner || exit 1
            nohup python3 usb_scanner.py >>"$LOGFILE" 2>&1 &
            SCANNER_PID=$!

            echo "$(date): Scanner launched with PID $SCANNER_PID for device $device" >>"$LOGFILE"

            # Give it a moment to start and check
            sleep 2
            if kill -0 "$SCANNER_PID" 2>/dev/null; then
              echo "$(date): Scanner PID $SCANNER_PID confirmed running" >>"$LOGFILE"
              break # Exit the while loop to avoid multiple launches
            else
              echo "$(date): ERROR - Scanner PID $SCANNER_PID failed to start" >>"$LOGFILE"
            fi
          fi
        fi
      fi
    done
  fi

  # Update state
  cp "$CURRENT_STATE" "$LAST_STATE"

  # Check every 2 seconds
  sleep 2
done
