#!/bin/bash
# Enhanced USB Scanner Debug and Troubleshooting Tool v2.1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER_SCRIPT="$SCRIPT_DIR/usb_scanner.py"

echo "🔍 === Enhanced USB Scanner Debug Tool v2.1 ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
  echo -e "${RED}❌${NC} $1"
}

print_info() {
  echo -e "${BLUE}ℹ️${NC} $1"
}

print_debug() {
  echo -e "${CYAN}🔧${NC} $1"
}

# Enhanced permission and setup check
check_permissions() {
  echo "1. 🔐 Checking permissions and setup..."

  if [[ ! -f "$SCANNER_SCRIPT" ]]; then
    print_error "Scanner script not found: $SCANNER_SCRIPT"
    return 1
  fi

  if [[ -x "$SCANNER_SCRIPT" ]]; then
    print_status "Scanner script is executable"
  else
    print_warning "Scanner script not executable"
    echo "   Fix: chmod +x $SCANNER_SCRIPT"
  fi

  # Check sudo permissions more thoroughly
  print_debug "Testing sudo permissions for clamscan..."
  if timeout 10s sudo -n clamscan --version >/dev/null 2>&1; then
    print_status "Sudo permissions for clamscan working"

    # Test actual scanning permission
    if timeout 10s sudo -n clamscan /bin/ls >/dev/null 2>&1; then
      print_status "Sudo scanning permissions verified"
    else
      print_warning "Sudo scanning test failed"
    fi
  else
    print_error "Cannot run clamscan with sudo"
    echo "   Check: /etc/sudoers.d/usb-scanner"
    echo "   Should contain: $USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam"
  fi

  # Check sudoers file content
  if [[ -f "/etc/sudoers.d/usb-scanner" ]]; then
    print_status "Sudoers file exists"
    echo "📄 Content:"
    cat /etc/sudoers.d/usb-scanner | sed 's/^/   /'
  else
    print_error "Sudoers file missing"
    echo "   Create with: echo '$USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam' | sudo tee /etc/sudoers.d/usb-scanner"
  fi

  echo ""
}

# Enhanced dependency checking
check_dependencies() {
  echo "2. 📦 Checking system dependencies..."

  local deps=("python3" "clamscan" "udevadm" "lsblk" "findmnt" "jq" "ps" "pkill")
  local optional_deps=("systemctl" "journalctl" "xdpyinfo")

  echo "   Core dependencies:"
  for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      print_status "$dep is available"
    else
      print_error "$dep is missing"
    fi
  done

  echo ""
  echo "   Optional dependencies:"
  for dep in "${optional_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      print_status "$dep is available"
    else
      print_warning "$dep is missing (optional)"
    fi
  done

  echo ""
  echo "   Python dependencies:"
  python3 -c "
import sys
import importlib.util

deps = {
    'pyudev': 'python3-pyudev',
    'tkinter': 'python3-tk', 
    'psutil': 'pip3 install --user psutil',
    'json': 'built-in',
    'threading': 'built-in',
    'subprocess': 'built-in'
}

for dep, install_cmd in deps.items():
    try:
        if importlib.util.find_spec(dep):
            print(f'   ✓ {dep} available')
        else:
            print(f'   ❌ {dep} not found - install: {install_cmd}')
    except ImportError:
        print(f'   ❌ {dep} not available - install: {install_cmd}')
"

  # Check GUI availability
  echo ""
  echo "   GUI Environment:"
  if [[ -n "$DISPLAY" ]]; then
    print_info "DISPLAY set to: $DISPLAY"

    if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo >/dev/null 2>&1; then
      print_status "X11 display is accessible"
    else
      print_warning "X11 display not accessible"
    fi
  else
    print_warning "DISPLAY not set (headless mode will be used)"
  fi

  if [[ -n "$SSH_CONNECTION" ]]; then
    print_info "SSH session detected"
    if [[ -n "$DISPLAY" ]]; then
      print_info "X11 forwarding appears to be enabled"
    else
      print_warning "No X11 forwarding in SSH session"
    fi
  fi

  echo ""
}

# Enhanced process and service checking
check_processes() {
  echo "3. 🔄 Checking running processes and services..."

  # Check for scanner processes
  if pgrep -f "usb_scanner.py" >/dev/null; then
    print_status "Scanner processes found:"
    ps aux | grep usb_scanner.py | grep -v grep | sed 's/^/   /' | while read line; do
      echo "   → $line"
    done

    # Show process details
    echo ""
    echo "   Process details:"
    pgrep -f "usb_scanner.py" | while read pid; do
      if [[ -f "/proc/$pid/cmdline" ]]; then
        cmdline=$(cat /proc/$pid/cmdline | tr '\0' ' ')
        echo "   PID $pid: $cmdline"
      fi
    done
  else
    print_info "No scanner processes currently running"
  fi

  # Check systemd services if available
  if command -v systemctl >/dev/null 2>&1; then
    echo ""
    echo "   Systemd services:"

    # Check if service exists
    if systemctl list-unit-files | grep -q usb-scanner; then
      if systemctl is-active --quiet usb-scanner.service; then
        print_status "USB scanner systemd service is active"
      else
        print_info "USB scanner systemd service is inactive"
      fi

      if systemctl is-enabled --quiet usb-scanner.service; then
        print_status "USB scanner systemd service is enabled"
      else
        print_info "USB scanner systemd service is disabled"
      fi
    else
      print_info "No USB scanner systemd service found (using udev auto-launch)"
    fi

    # Check ClamAV services
    if systemctl is-active --quiet clamav-freshclam; then
      print_status "ClamAV freshclam service is running"
    else
      print_warning "ClamAV freshclam service not running"
      echo "   Start with: sudo systemctl start clamav-freshclam"
    fi
  fi

  echo ""
}

# Enhanced USB system checking
check_usb_system() {
  echo "4. 🔌 Checking USB system and udev..."

  # Check udev rule
  if [[ -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
    print_status "Udev rule exists"
    echo "📄 Content:"
    cat /etc/udev/rules.d/99-usb-scanner.rules | sed 's/^/   /'
  else
    print_error "Udev rule missing!"
    echo "   Expected: /etc/udev/rules.d/99-usb-scanner.rules"
    echo "   Create with setup script or manually"
  fi

  echo ""
  echo "🔍 USB device detection test:"

  # Show current USB storage devices
  echo "   Current USB storage devices:"
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN,SIZE,LABEL | grep -E "(NAME|usb)" | sed 's/^/   /' || print_info "No USB devices found"
  fi

  echo ""
  echo "   Detailed USB device information:"
  if [[ -d "/sys/bus/usb/devices" ]]; then
    for device in /sys/bus/usb/devices/*; do
      if [[ -f "$device/product" ]] && [[ -f "$device/manufacturer" ]]; then
        product=$(cat "$device/product" 2>/dev/null || echo "Unknown")
        manufacturer=$(cat "$device/manufacturer" 2>/dev/null || echo "Unknown")
        echo "   → $manufacturer $product"
      fi
    done
  fi

  echo ""
  echo "   Testing udev rule trigger:"
  print_info "Checking if udev rules can be triggered..."

  # Test udev rule syntax
  if sudo udevadm control --reload-rules 2>/dev/null; then
    print_status "Udev rules reloaded successfully"
  else
    print_warning "Failed to reload udev rules"
  fi

  echo ""
}

# Enhanced ClamAV checking
check_clamav() {
  echo "5. 🛡️ Checking ClamAV configuration..."

  if command -v clamscan >/dev/null 2>&1; then
    print_status "ClamAV is installed"

    # Get version info
    clamscan_version=$(clamscan --version 2>/dev/null | head -1)
    echo "   Version: $clamscan_version"

    # Check virus database
    if [[ -f "/var/lib/clamav/main.cvd" ]] || [[ -f "/var/lib/clamav/main.cld" ]]; then
      db_date=$(stat -c %y /var/lib/clamav/main.c?d 2>/dev/null | head -1 | cut -d' ' -f1)
      print_status "Main virus database found (updated: $db_date)"
    else
      print_warning "Main virus database not found"
    fi

    if [[ -f "/var/lib/clamav/daily.cvd" ]] || [[ -f "/var/lib/clamav/daily.cld" ]]; then
      daily_date=$(stat -c %y /var/lib/clamav/daily.c?d 2>/dev/null | head -1 | cut -d' ' -f1)
      print_status "Daily virus database found (updated: $daily_date)"
    else
      print_warning "Daily virus database not found"
    fi

    # Test scanning capability
    echo ""
    echo "   Testing scanning capability:"
    if timeout 30s sudo clamscan --version >/dev/null 2>&1; then
      print_status "ClamAV sudo access working"

      # Test actual scan on a safe file
      if timeout 30s sudo clamscan /bin/ls >/dev/null 2>&1; then
        print_status "Test scan completed successfully"
      else
        print_warning "Test scan failed or timed out"
      fi
    else
      print_error "Cannot access ClamAV with sudo"
    fi

  else
    print_error "ClamAV not installed"
    echo "   Install: sudo apt install clamav clamav-daemon clamav-freshclam"
  fi

  # Check freshclam service
  if command -v systemctl >/dev/null 2>&1; then
    echo ""
    echo "   ClamAV services:"
    if systemctl is-active --quiet clamav-freshclam; then
      print_status "Freshclam service is running"

      # Show last update
      if journalctl -u clamav-freshclam --no-pager -n 1 2>/dev/null | grep -q "Database updated"; then
        last_update=$(journalctl -u clamav-freshclam --no-pager | grep "Database updated" | tail -1)
        echo "   Last update: $last_update"
      fi
    else
      print_warning "Freshclam service not running"
      echo "   Start: sudo systemctl start clamav-freshclam"
    fi
  fi

  echo ""
}

# Enhanced log checking
check_logs() {
  echo "6. 📋 Checking logs and recent activity..."

  # Application logs
  local log_files=(
    "/var/log/usb_scanner.log"
    "$HOME/.local/share/usb-scanner/usb_scanner.log"
    "/tmp/usb-scanner-events.log"
    "/tmp/usb-events.log"
  )

  for log_file in "${log_files[@]}"; do
    if [[ -f "$log_file" ]]; then
      print_status "Log file exists: $log_file"
      echo "📋 Recent entries (last 5):"
      tail -n 5 "$log_file" | sed 's/^/   /' || echo "   (empty or unreadable)"
      echo ""
    fi
  done

  if ! ls /var/log/usb_scanner.log "$HOME"/.local/share/usb-scanner/usb_scanner.log 2>/dev/null; then
    print_warning "No application log files found"
  fi

  # Systemd service logs
  if command -v journalctl >/dev/null 2>&1; then
    echo "   Recent systemd logs:"
    if journalctl -u usb-scanner.service --no-pager -n 3 2>/dev/null | grep -v "No entries"; then
      journalctl -u usb-scanner.service --no-pager -n 3 | sed 's/^/   /'
    else
      print_info "No systemd service logs found"
    fi
  fi

  # Check for ClamAV logs
  if [[ -d "/var/log/clamav" ]]; then
    echo ""
    echo "   ClamAV logs:"
    find /var/log/clamav -name "*.log" -type f | head -3 | while read log; do
      echo "   Found: $log"
      if [[ -r "$log" ]]; then
        echo "   Recent entries:"
        tail -n 2 "$log" | sed 's/^/     /'
      fi
    done
  fi

  echo ""
}

# Live USB detection test
test_usb_detection() {
  echo "7. 🔌 Testing live USB device detection..."
  print_info "This will monitor USB events for 30 seconds"
  print_info "Insert or remove USB devices to test detection"
  print_info "Press Ctrl+C to stop early"
  echo ""

  # Create temporary log for this test
  TEST_LOG="/tmp/usb-test-$$.log"

  # Start monitoring in background
  udevadm monitor --subsystem-match=block --property >"$TEST_LOG" &
  MONITOR_PID=$!

  # Monitor the log file
  timeout 30s tail -f "$TEST_LOG" 2>/dev/null | while read -r line; do
    if [[ "$line" == UDEV* ]]; then
      device_path=$(echo "$line" | cut -d' ' -f3)
      print_debug "Device event: $device_path"
    elif [[ "$line" == *"ACTION=add"* ]]; then
      echo "   ➕ Device added"
    elif [[ "$line" == *"ACTION=remove"* ]]; then
      echo "   ➖ Device removed"
    elif [[ "$line" == *"ID_FS_TYPE"* ]]; then
      fs_type=$(echo "$line" | cut -d'=' -f2)
      echo "   💾 Filesystem detected: $fs_type"
    elif [[ "$line" == *"ID_BUS=usb"* ]]; then
      echo "   🔌 USB device detected!"
      print_status "This should trigger the scanner if properly configured!"
    fi
  done

  # Cleanup
  kill $MONITOR_PID 2>/dev/null || true
  rm -f "$TEST_LOG"

  echo ""
}

# Enhanced scanner functionality test
test_scanner() {
  echo "8. 🧪 Testing scanner functionality..."

  print_info "Testing Python imports and basic functionality..."

  # Test imports
  python3 -c "
import sys
import os
sys.path.insert(0, '$SCRIPT_DIR')

try:
    print('   Testing basic imports...')
    import json, threading, time, subprocess, logging
    print('   ✓ Basic Python modules working')
    
    print('   Testing USB monitoring...')
    import pyudev
    context = pyudev.Context()
    print('   ✓ pyudev context created successfully')
    
    print('   Testing GUI availability...')
    try:
        import tkinter
        print('   ✓ tkinter (GUI) available')
    except ImportError:
        print('   ⚠️  tkinter not available (headless mode only)')
    
    print('   Testing process utilities...')
    import psutil
    print('   ✓ psutil available')
    
    print('   Testing scanner import...')
    # Try to import the main scanner
    import importlib.util
    spec = importlib.util.spec_from_file_location('usb_scanner', '$SCANNER_SCRIPT')
    if spec:
        print('   ✓ Scanner module can be loaded')
    else:
        print('   ❌ Scanner module cannot be loaded')
        
except Exception as e:
    print(f'   ❌ Error: {e}')
    sys.exit(1)
"

  echo ""
  echo "   Testing CLI arguments:"

  # Test help argument
  if python3 "$SCANNER_SCRIPT" --help >/dev/null 2>&1; then
    print_status "Help argument working"
  else
    print_warning "Help argument test failed"
  fi

  # Test status argument
  if python3 "$SCANNER_SCRIPT" --status >/dev/null 2>&1; then
    print_info "Status check completed"
  else
    print_info "Status check returned non-zero (normal if not running)"
  fi

  echo ""
}

# Generate comprehensive troubleshooting report
generate_troubleshooting_report() {
  echo "9. 📊 Generating troubleshooting report..."

  REPORT_FILE="/tmp/usb-scanner-debug-$(date +%Y%m%d_%H%M%S).txt"

  cat >"$REPORT_FILE" <<EOF
USB Scanner Debug Report
Generated: $(date)
Host: $(hostname)
User: $USER
Working Directory: $PWD

=== SYSTEM INFO ===
$(uname -a)
$(cat /etc/os-release 2>/dev/null || echo "OS info not available")

=== PYTHON INFO ===
$(python3 --version)
Python path: $(which python3)

=== INSTALLED PACKAGES ===
$(dpkg -l | grep -E "(clamav|python3-pyudev|python3-tk)" || echo "Package info not available")

=== USB DEVICES ===
$(lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN,SIZE,LABEL 2>/dev/null || echo "lsblk not available")

=== PROCESSES ===
$(ps aux | grep -E "(usb_scanner|clam)" | grep -v grep || echo "No relevant processes")

=== MOUNT POINTS ===
$(mount | grep -E "(usb|media|mnt)" || echo "No USB mount points")

=== UDEV RULES ===
$(cat /etc/udev/rules.d/99-usb-scanner.rules 2>/dev/null || echo "Udev rule not found")

=== SUDOERS CONFIG ===
$(cat /etc/sudoers.d/usb-scanner 2>/dev/null || echo "Sudoers config not found")

=== RECENT LOGS ===
$(tail -20 /var/log/usb_scanner.log 2>/dev/null || echo "No system logs")

=== CLAMAV STATUS ===
$(clamscan --version 2>/dev/null || echo "ClamAV not available")
$(ls -la /var/lib/clamav/*.c?d 2>/dev/null || echo "No ClamAV databases found")

=== ENVIRONMENT ===
DISPLAY=$DISPLAY
SSH_CONNECTION=$SSH_CONNECTION
XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP
EOF

  print_status "Debug report saved to: $REPORT_FILE"
  echo ""
}

# Show comprehensive recommendations
show_recommendations() {
  echo "🔧 === Troubleshooting Recommendations ==="
  echo ""

  local issues=()
  local warnings=()

  # Collect issues
  if ! sudo -n clamscan --version >/dev/null 2>&1; then
    issues+=("sudo_permissions")
  fi

  if [[ ! -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
    issues+=("missing_udev_rule")
  fi

  if ! command -v clamscan >/dev/null 2>&1; then
    issues+=("clamav_missing")
  fi

  if ! python3 -c "import pyudev" 2>/dev/null; then
    issues+=("pyudev_missing")
  fi

  if [[ ! -f "$SCANNER_SCRIPT" ]]; then
    issues+=("scanner_missing")
  fi

  # Check for warnings
  if [[ -z "$DISPLAY" ]]; then
    warnings+=("no_display")
  fi

  if ! python3 -c "import tkinter" 2>/dev/null; then
    warnings+=("no_gui")
  fi

  # Provide specific recommendations
  if [[ ${#issues[@]} -eq 0 ]]; then
    print_status "No critical issues detected!"
  else
    print_warning "Found ${#issues[@]} critical issue(s):"
    echo ""

    for issue in "${issues[@]}"; do
      case $issue in
      "sudo_permissions")
        print_error "Sudo permissions not configured"
        echo "   Fix: Run setup.sh or manually create /etc/sudoers.d/usb-scanner"
        echo "   Content: $USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam"
        ;;
      "missing_udev_rule")
        print_error "Udev rule missing"
        echo "   Fix: Run setup.sh or manually create udev rule"
        ;;
      "clamav_missing")
        print_error "ClamAV not installed"
        echo "   Fix: sudo apt install clamav clamav-daemon clamav-freshclam"
        ;;
      "pyudev_missing")
        print_error "pyudev not available"
        echo "   Fix: sudo apt install python3-pyudev"
        ;;
      "scanner_missing")
        print_error "Scanner script not found"
        echo "   Fix: Ensure usb_scanner.py is in the current directory"
        ;;
      esac
      echo ""
    done
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    print_info "Warnings (non-critical):"
    for warning in "${warnings[@]}"; do
      case $warning in
      "no_display")
        print_warning "No display available - GUI mode disabled"
        echo "   Note: Scanner will run in headless mode"
        ;;
      "no_gui")
        print_warning "GUI libraries not available"
        echo "   Fix: sudo apt install python3-tk (optional)"
        ;;
      esac
    done
    echo ""
  fi

  echo "🛠️  Quick fixes:"
  echo ""
  echo "1. Restart all services:"
  echo "   sudo systemctl restart clamav-freshclam"
  echo "   sudo udevadm control --reload-rules && sudo udevadm trigger"
  echo ""
  echo "2. Manual testing:"
  echo "   python3 $SCANNER_SCRIPT --headless    # Test without GUI"
  echo "   python3 $SCANNER_SCRIPT --status      # Check if running"
  echo "   ./usb-scanner-manager.sh status       # Management script"
  echo ""
  echo "3. USB testing:"
  echo "   udevadm monitor --subsystem-match=block    # Monitor USB events"
  echo "   lsblk -f                                  # Show current devices"
  echo ""
  echo "4. Log analysis:"
  echo "   tail -f /var/log/usb_scanner.log         # Application logs"
  echo "   tail -f /tmp/usb-events.log              # USB event logs"
  echo "   journalctl -u clamav-freshclam -f        # ClamAV logs"
  echo ""
  echo "5. Complete reinstallation:"
  echo "   ./remove.sh                              # Clean removal"
  echo "   ./setup.sh                               # Fresh install"
  echo ""
}

# Main execution
main() {
  check_permissions
  check_dependencies
  check_processes
  check_usb_system
  check_clamav
  check_logs
  test_scanner
  generate_troubleshooting_report

  # Ask if user wants to test USB detection
  echo ""
  read -p "🔌 Test live USB device detection? [y/N]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    test_usb_detection
  fi

  show_recommendations

  echo ""
  echo "📝 Debug complete. Use the recommendations above to resolve any issues."
  echo "📊 Full debug report available at: /tmp/usb-scanner-debug-*.txt"
  echo ""
}

# Handle command line arguments
case "${1:-}" in
"help" | "-h" | "--help")
  echo "Enhanced USB Scanner Debug Tool v2.1"
  echo ""
  echo "Usage: $0 [command]"
  echo ""
  echo "Commands:"
  echo "  (no args)     Run full diagnostic suite"
  echo "  quick         Quick status check only"
  echo "  logs          Show recent logs only"
  echo "  usb           Test USB detection only"
  echo "  permissions   Check permissions only"
  echo "  clamav        Check ClamAV only"
  echo "  report        Generate debug report only"
  echo "  help          Show this help"
  echo ""
  ;;
"quick")
  check_processes
  check_permissions
  ;;
"logs")
  check_logs
  ;;
"usb")
  test_usb_detection
  ;;
"permissions")
  check_permissions
  ;;
"clamav")
  check_clamav
  ;;
"report")
  generate_troubleshooting_report
  ;;
*)
  main
  ;;
esac
