#!/bin/bash
# USB Scanner Launcher - Handles SSH + GUI scenarios

LOG_FILE="/tmp/usb-launcher.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER_SCRIPT="$SCRIPT_DIR/usb_scanner.py"

# Log function
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

log_message "USB Launcher started by udev"
log_message "Environment: USER=$USER, HOME=$HOME, DISPLAY=$DISPLAY"

# Function to find the best display
find_display() {
  local displays=()

  # Check for X11 sockets
  for socket in /tmp/.X11-unix/X*; do
    if [[ -S "$socket" ]]; then
      local display_num=$(basename "$socket" | sed 's/X//')
      displays+=("$display_num")
    fi
  done

  # Check who output for active sessions
  while IFS= read -r line; do
    if [[ "$line" =~ \(:([0-9]+)\) ]]; then
      displays+=("${BASH_REMATCH[1]}")
    fi
  done < <(who 2>/dev/null || true)

  # Remove duplicates and sort
  local unique_displays=($(printf '%s\n' "${displays[@]}" | sort -u))

  log_message "Found displays: ${unique_displays[*]}"

  if [[ ${#unique_displays[@]} -gt 0 ]]; then
    echo ":${unique_displays[0]}"
    return 0
  else
    echo ""
    return 1
  fi
}

# Function to find the X authority file
find_xauth() {
  local target_user="$1"

  local auth_files=(
    "/home/$target_user/.Xauthority"
    "/home/$target_user/.Xauth"
    "/var/run/gdm3/auth-for-$target_user-*/database"
  )

  for auth_file in "${auth_files[@]}"; do
    if [[ -f "$auth_file" ]] && [[ -r "$auth_file" ]]; then
      log_message "Found auth file: $auth_file"
      echo "$auth_file"
      return 0
    fi
  done

  log_message "No suitable auth file found"
  return 1
}

# Main launcher logic
main() {
  log_message "Starting main launcher logic"

  # Find the best display
  local display=$(find_display)
  if [[ -z "$display" ]]; then
    log_message "No display found, running in headless mode"
    python3 "$SCANNER_SCRIPT" --headless >>"$LOG_FILE" 2>&1 &
    return 0
  fi

  log_message "Using display: $display"

  # Find X authority
  local xauth_file=$(find_xauth "$USER")

  # Set up environment
  export DISPLAY="$display"
  if [[ -n "$xauth_file" ]]; then
    export XAUTHORITY="$xauth_file"
    log_message "Set XAUTHORITY to: $xauth_file"
  fi
  export HOME="/home/$USER"

  log_message "Final environment: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY, HOME=$HOME"

  # Test if display is accessible
  if command -v xdpyinfo >/dev/null 2>&1 && timeout 5s xdpyinfo >/dev/null 2>&1; then
    log_message "Display is accessible, launching GUI"
    python3 "$SCANNER_SCRIPT" >>"$LOG_FILE" 2>&1 &
  else
    log_message "Display not accessible, launching headless"
    python3 "$SCANNER_SCRIPT" --headless >>"$LOG_FILE" 2>&1 &
  fi

  local scanner_pid=$!
  log_message "Scanner launched with PID: $scanner_pid"
}

# Run main function
main "$@"
