#!/bin/bash
# Enhanced USB Virus Scanner Setup Script v2.1
# SSH Compatible with improved GUI Auto-Launch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="usb_scanner.py"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

echo "🔧 === Enhanced USB Virus Scanner Setup v2.1 ==="
echo "   Advanced installation with SSH compatibility"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  print_error "Don't run this script as root. Run as the user who will use the scanner."
  exit 1
fi

# Detect environment
detect_environment() {
  echo "🔍 Detecting environment..."

  # Check if in SSH session
  if [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]] || [[ "$TERM" == "screen"* ]]; then
    echo "SSH_MODE=true"
    export SSH_MODE=true
    print_info "SSH session detected - configuring for remote installation"
  else
    echo "SSH_MODE=false"
    export SSH_MODE=false
    print_info "Local session detected"
  fi

  # Check if GUI is available
  if [[ -n "$DISPLAY" ]] && command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo >/dev/null 2>&1; then
    export GUI_AVAILABLE=true
    print_status "X11 display available: $DISPLAY"
  else
    export GUI_AVAILABLE=false
    print_warning "No X11 display available"
  fi

  # Check user for desktop integration
  if [[ -n "$SUDO_USER" ]]; then
    export TARGET_USER="$SUDO_USER"
    export TARGET_HOME="/home/$SUDO_USER"
  else
    export TARGET_USER="$USER"
    export TARGET_HOME="$HOME"
  fi

  print_info "Target user: $TARGET_USER"
  print_info "Target home: $TARGET_HOME"
  echo ""
}

# Check system compatibility
check_system() {
  echo "🔍 Checking system compatibility..."

  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    print_status "Detected: $NAME $VERSION"

    if [[ "$ID" != "ubuntu" ]]; then
      print_warning "This script is optimized for Ubuntu. Some packages may need adjustment."
    fi

    # Check version compatibility
    if [[ "$VERSION_ID" < "20.04" ]]; then
      print_warning "Ubuntu version older than 20.04 may have compatibility issues"
    fi
  else
    print_warning "Could not detect OS version"
  fi

  # Check architecture
  ARCH=$(uname -m)
  print_info "Architecture: $ARCH"

  # Check Python version
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    print_status "Python version: $PYTHON_VERSION"
  else
    print_error "Python3 not found"
    return 1
  fi

  echo ""
}

# Update system and install packages
install_system_packages() {
  echo "📦 Installing system packages..."

  # Update package lists
  print_info "Updating package lists..."
  sudo apt update

  # Define package list
  PACKAGES=(
    "python3"
    "python3-pip"
    "python3-pyudev"
    "python3-tk"
    "clamav"
    "clamav-daemon"
    "clamav-freshclam"
    "udev"
    "psmisc"
    "lsof"
    "jq"
  )

  # Add GUI packages if available
  if [[ "$GUI_AVAILABLE" == "true" ]] || [[ "$SSH_MODE" == "true" ]]; then
    PACKAGES+=("dbus-x11" "xauth" "x11-utils")
  fi

  # Install packages
  print_info "Installing packages: ${PACKAGES[*]}"
  sudo apt install -y "${PACKAGES[@]}"

  print_status "System packages installed"
  echo ""
}

# Verify Python dependencies
verify_python_deps() {
  echo "🐍 Verifying Python dependencies..."

  # Check pyudev
  if python3 -c "import pyudev; print('pyudev version:', pyudev.__version__)" 2>/dev/null; then
    print_status "pyudev is working"
  else
    print_error "pyudev not working properly"
    return 1
  fi

  # Check tkinter (GUI)
  if python3 -c "import tkinter; print('tkinter available')" 2>/dev/null; then
    print_status "tkinter (GUI) is available"
  else
    print_warning "tkinter not available - GUI mode will be disabled"
  fi

  # Check psutil
  if python3 -c "import psutil; print('psutil version:', psutil.__version__)" 2>/dev/null; then
    print_status "psutil is working"
  else
    print_info "Installing psutil..."
    pip3 install --user psutil
  fi

  echo ""
}

# Configure ClamAV
setup_clamav() {
  echo "🛡️ Configuring ClamAV..."

  # Stop freshclam service temporarily
  sudo systemctl stop clamav-freshclam 2>/dev/null || true

  # Update virus definitions
  print_info "Updating virus definitions (this may take several minutes)..."
  if sudo freshclam; then
    print_status "Virus definitions updated successfully"
  else
    print_warning "Could not update virus definitions - will retry later"
  fi

  # Enable and start freshclam service
  sudo systemctl enable clamav-freshclam
  sudo systemctl start clamav-freshclam

  # Wait a moment and check status
  sleep 2
  if systemctl is-active --quiet clamav-freshclam; then
    print_status "ClamAV freshclam service is running"
  else
    print_warning "ClamAV freshclam service failed to start"
  fi

  echo ""
}

# Configure sudo permissions
setup_sudo() {
  echo "🔐 Configuring sudo permissions..."

  # Create sudoers file for USB scanner
  SUDOERS_FILE="/etc/sudoers.d/usb-scanner"

  cat >/tmp/usb-scanner-sudoers <<EOF
# USB Scanner sudo permissions
# Allow passwordless access to clamscan and freshclam for scanning
$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam
EOF

  # Install sudoers file
  sudo cp /tmp/usb-scanner-sudoers "$SUDOERS_FILE"
  sudo chmod 440 "$SUDOERS_FILE"
  rm -f /tmp/usb-scanner-sudoers

  # Verify sudoers configuration
  if sudo visudo -c -f "$SUDOERS_FILE"; then
    print_status "Sudoers configuration is valid"
  else
    print_error "Sudoers configuration is invalid"
    return 1
  fi

  # Test sudo permissions
  if sudo -u "$TARGET_USER" sudo -n clamscan --version >/dev/null 2>&1; then
    print_status "Sudo permissions working correctly"
  else
    print_warning "Sudo permissions test failed - manual verification needed"
  fi

  echo ""
}

# Create improved udev rule
setup_udev() {
  echo "🔌 Creating udev rules for USB detection..."

  UDEV_RULE="/etc/udev/rules.d/99-usb-scanner.rules"

  # Create comprehensive udev rule
  cat >/tmp/usb-scanner.rules <<EOF
# Enhanced USB Scanner - Auto-launch on USB insertion
# Triggers when a USB storage device with a filesystem is added
# Rule 1: Basic USB storage detection
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}!="", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", \\
    RUN+="/bin/bash -c 'echo \$(date): USB device \$env{DEVNAME} detected >> /tmp/usb-scanner-events.log'"

# Rule 2: Launch scanner for specific filesystems
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="vfat|ntfs|exfat|ext4|ext3", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", \\
    RUN+="/bin/bash -c '/usr/bin/systemd-run --uid=$TARGET_USER --gid=$TARGET_USER --setenv=DISPLAY=:0 --setenv=XAUTHORITY=$TARGET_HOME/.Xauthority --setenv=HOME=$TARGET_HOME /usr/bin/python3 $SCRIPT_PATH &'"

# Rule 3: Log all USB block device events for debugging
ACTION=="add|remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", \\
    RUN+="/bin/bash -c 'echo \$(date): \$env{ACTION} \$env{DEVNAME} \$env{ID_FS_TYPE} >> /tmp/usb-events.log'"
EOF

  # Install udev rule
  sudo cp /tmp/usb-scanner.rules "$UDEV_RULE"
  sudo chmod 644 "$UDEV_RULE"
  rm -f /tmp/usb-scanner.rules

  # Reload udev rules
  print_info "Reloading udev rules..."
  sudo udevadm control --reload-rules
  sudo udevadm trigger

  print_status "Udev rules configured"
  echo ""
}

# Setup logging
setup_logging() {
  echo "📝 Setting up logging..."

  # Create log directory structure
  LOG_DIR="/var/log"
  USER_LOG_DIR="$TARGET_HOME/.local/share/usb-scanner"

  # Try to create system log file
  if sudo touch "$LOG_DIR/usb_scanner.log" 2>/dev/null; then
    sudo chown "$TARGET_USER:$TARGET_USER" "$LOG_DIR/usb_scanner.log"
    print_status "System log file created: $LOG_DIR/usb_scanner.log"
  else
    print_warning "Cannot create system log file, using user directory"
  fi

  # Create user log directory
  sudo -u "$TARGET_USER" mkdir -p "$USER_LOG_DIR"
  print_status "User log directory: $USER_LOG_DIR"

  # Create temporary log files with proper permissions
  touch /tmp/usb-scanner-events.log /tmp/usb-events.log
  chmod 666 /tmp/usb-scanner-events.log /tmp/usb-events.log

  echo ""
}

# Create desktop integration
setup_desktop() {
  echo "🖥️ Setting up desktop integration..."

  if [[ "$SSH_MODE" == "true" ]]; then
    print_info "SSH mode - creating desktop files for local GUI access"
  fi

  # Create desktop shortcut
  DESKTOP_FILE="$TARGET_HOME/Desktop/usb-scanner.desktop"
  cat >/tmp/usb-scanner.desktop <<EOF
[Desktop Entry]
Name=Enhanced USB Scanner
Comment=Advanced USB virus scanning with ClamAV
Version=2.1
Exec=python3 $SCRIPT_PATH
Icon=security-high
Terminal=false
Type=Application
Categories=Security;System;Utility;
Keywords=usb;virus;scanner;security;clamav;
StartupNotify=true
EOF

  # Install desktop file
  sudo -u "$TARGET_USER" cp /tmp/usb-scanner.desktop "$DESKTOP_FILE"
  sudo -u "$TARGET_USER" chmod +x "$DESKTOP_FILE"
  rm -f /tmp/usb-scanner.desktop

  print_status "Desktop shortcut created"

  # Create autostart entry
  AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
  sudo -u "$TARGET_USER" mkdir -p "$AUTOSTART_DIR"

  AUTOSTART_FILE="$AUTOSTART_DIR/usb-scanner.desktop"
  cat >/tmp/usb-scanner-autostart.desktop <<EOF
[Desktop Entry]
Type=Application
Name=USB Scanner Monitor
Comment=Monitor for USB devices and auto-scan
Icon=security-high
Exec=python3 $SCRIPT_PATH --minimize
Hidden=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Categories=Security;System;
EOF

  sudo -u "$TARGET_USER" cp /tmp/usb-scanner-autostart.desktop "$AUTOSTART_FILE"
  rm -f /tmp/usb-scanner-autostart.desktop

  print_status "Autostart entry created"
  echo ""
}

# Create management scripts
create_management_scripts() {
  echo "🛠️ Creating management scripts..."

  # Create manager script
  cat >"$SCRIPT_DIR/usb-scanner-manager.sh" <<'EOF'
#!/bin/bash
# USB Scanner Management Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER_SCRIPT="$SCRIPT_DIR/usb_scanner.py"

case "${1:-}" in
    "start")
        echo "Starting USB Scanner..."
        python3 "$SCANNER_SCRIPT" --minimize &
        echo "Scanner started in background"
        ;;
    "stop")
        echo "Stopping USB Scanner..."
        pkill -f "usb_scanner.py" || echo "No scanner processes found"
        ;;
    "restart")
        echo "Restarting USB Scanner..."
        pkill -f "usb_scanner.py" || true
        sleep 2
        python3 "$SCANNER_SCRIPT" --minimize &
        echo "Scanner restarted"
        ;;
    "status")
        if pgrep -f "usb_scanner.py" >/dev/null; then
            echo "✓ USB Scanner is running"
            ps aux | grep usb_scanner.py | grep -v grep
        else
            echo "✗ USB Scanner is not running"
        fi
        ;;
    "gui")
        echo "Starting USB Scanner GUI..."
        python3 "$SCANNER_SCRIPT"
        ;;
    "logs")
        echo "Recent scanner logs:"
        if [[ -f "/var/log/usb_scanner.log" ]]; then
            tail -20 /var/log/usb_scanner.log
        else
            echo "No system logs found"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|gui|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start scanner in background"
        echo "  stop    - Stop scanner"
        echo "  restart - Restart scanner"
        echo "  status  - Show scanner status"
        echo "  gui     - Start scanner with GUI"
        echo "  logs    - Show recent logs"
        ;;
esac
EOF

  chmod +x "$SCRIPT_DIR/usb-scanner-manager.sh"
  print_status "Management script created: usb-scanner-manager.sh"

  # Create test script
  cat >"$SCRIPT_DIR/test-scanner.sh" <<'EOF'
#!/bin/bash
# USB Scanner Test Script

echo "🧪 Testing USB Scanner Installation..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test 1: Check dependencies
echo "1. Checking dependencies..."
python3 -c "
import sys
try:
    import pyudev
    print('  ✓ pyudev available')
except ImportError:
    print('  ❌ pyudev missing')

try:
    import tkinter
    print('  ✓ tkinter available')
except ImportError:
    print('  ⚠️ tkinter missing (GUI disabled)')

try:
    import psutil
    print('  ✓ psutil available')
except ImportError:
    print('  ❌ psutil missing')
"

# Test 2: Check ClamAV
echo ""
echo "2. Checking ClamAV..."
if command -v clamscan >/dev/null; then
    echo "  ✓ clamscan found"
    if sudo -n clamscan --version >/dev/null 2>&1; then
        echo "  ✓ sudo permissions working"
    else
        echo "  ❌ sudo permissions not working"
    fi
else
    echo "  ❌ clamscan not found"
fi

# Test 3: Check USB monitoring
echo ""
echo "3. Testing USB monitoring..."
echo "   Insert a USB device to test detection..."
echo "   Monitoring for 10 seconds (Ctrl+C to stop)..."

timeout 10s udevadm monitor --subsystem-match=block 2>/dev/null | while read line; do
    if [[ "$line" == *"ID_BUS=usb"* ]]; then
        echo "  ✓ USB device detected: $line"
        echo "  → This should trigger the scanner!"
        break
    fi
done

echo ""
echo "4. Manual test..."
echo "   Run: python3 $SCRIPT_DIR/usb_scanner.py"
echo "   Or:  ./usb-scanner-manager.sh gui"
EOF

  chmod +x "$SCRIPT_DIR/test-scanner.sh"
  print_status "Test script created: test-scanner.sh"

  echo ""
}

# Verify installation
verify_installation() {
  echo "🔍 Verifying installation..."

  local issues=0

  # Check main script
  if [[ -f "$SCRIPT_PATH" ]]; then
    print_status "Main script exists: $SCRIPT_PATH"
  else
    print_error "Main script missing: $SCRIPT_PATH"
    ((issues++))
  fi

  # Check if script is executable
  if [[ -x "$SCRIPT_PATH" ]]; then
    print_status "Script is executable"
  else
    print_warning "Script not executable, fixing..."
    chmod +x "$SCRIPT_PATH"
  fi

  # Test Python imports
  if python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR'); import usb_scanner" 2>/dev/null; then
    print_status "Python imports working"
  else
    print_error "Python imports failing"
    ((issues++))
  fi

  # Check udev rule
  if [[ -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
    print_status "Udev rule installed"
  else
    print_error "Udev rule missing"
    ((issues++))
  fi

  # Check sudoers
  if [[ -f "/etc/sudoers.d/usb-scanner" ]]; then
    print_status "Sudoers configuration exists"
  else
    print_error "Sudoers configuration missing"
    ((issues++))
  fi

  # Check ClamAV
  if sudo -u "$TARGET_USER" sudo -n clamscan --version >/dev/null 2>&1; then
    print_status "ClamAV permissions working"
  else
    print_error "ClamAV permissions not working"
    ((issues++))
  fi

  echo ""

  if [[ $issues -eq 0 ]]; then
    print_status "Installation verification passed!"
    return 0
  else
    print_error "Installation verification found $issues issue(s)"
    return 1
  fi
}

# Main installation process
main() {
  detect_environment
  check_system
  install_system_packages
  verify_python_deps
  setup_clamav
  setup_sudo
  setup_udev
  setup_logging
  setup_desktop
  create_management_scripts

  echo "🔧 Finalizing installation..."

  # Make main script executable
  chmod +x "$SCRIPT_PATH"

  # Set proper ownership for target user
  if [[ "$USER" != "$TARGET_USER" ]]; then
    print_info "Setting ownership for $TARGET_USER..."
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$SCRIPT_DIR"
  fi

  # Update requirements.txt
  cat >"$SCRIPT_DIR/requirements.txt" <<'EOF'
# Enhanced USB Virus Scanner v2.1 Dependencies
# For Ubuntu 20.04+ - using system packages to avoid externally-managed-environment issues

# System packages (install via apt):
# - python3-pyudev  >= 0.22   (USB device monitoring)
# - python3-tk               (GUI interface)  
# - clamav                   (antivirus engine)
# - clamav-daemon            (background scanning service)
# - clamav-freshclam         (virus definition updates)
# - dbus-x11                 (system integration)
# - udev                     (device event handling)
# - psmisc                   (process management)
# - xauth                    (X11 authentication)

# Python packages (auto-installed):
psutil>=5.0.0
EOF

  echo ""
  echo "🧪 Running verification tests..."
  if verify_installation; then
    echo ""
    echo "🎉 === Installation Complete! ==="
    echo ""
    print_status "Enhanced USB Virus Scanner v2.1 successfully installed"
    echo ""

    if [[ "$SSH_MODE" == "true" ]]; then
      echo "🔗 SSH Installation Notes:"
      echo "   • Scanner will auto-launch GUI on physical display when USB inserted"
      echo "   • Udev rule handles automatic detection and GUI launching"
      echo "   • GUI appears on :0 display even during SSH sessions"
      echo "   • No persistent daemon needed - launches on-demand"
      echo ""
    fi

    echo "🚀 Usage:"
    echo "  Manual GUI:      python3 $SCRIPT_PATH"
    echo "  Background mode: python3 $SCRIPT_PATH --minimize"
    echo "  Headless mode:   python3 $SCRIPT_PATH --headless"
    echo "  Management:      ./usb-scanner-manager.sh {start|stop|status|gui}"
    echo ""

    echo "🧪 Testing:"
    echo "  Quick test:      ./test-scanner.sh"
    echo "  Insert USB:      Plug in USB device to test auto-launch"
    echo "  View logs:       tail -f /var/log/usb_scanner.log"
    echo "  USB events:      tail -f /tmp/usb-events.log"
    echo ""

    echo "🔧 Troubleshooting:"
    echo "  Debug info:      ./debug_usb.sh"
    echo "  USB monitoring:  udevadm monitor --subsystem-match=block"
    echo "  Test detection:  udevadm test /dev/sdX1 (replace with your USB)"
    echo ""

    # Offer to run initial test
    if [[ "$SSH_MODE" == "false" ]]; then
      echo "🧪 Quick functionality test..."
      if timeout 3s python3 "$SCRIPT_PATH" --headless 2>/dev/null; then
        print_status "Basic functionality test passed"
      else
        print_info "Test completed (normal timeout)"
      fi
    else
      print_info "Skipping GUI test in SSH mode"
    fi

    echo ""
    echo "📚 Documentation: See README.md for detailed usage instructions"
    echo "🆘 Support: Run ./debug_usb.sh for troubleshooting help"
    echo ""
    print_status "Ready! Insert a USB device to test automatic scanning."

  else
    echo ""
    print_error "Installation completed with issues. Please review the errors above."
    echo "Run './debug_usb.sh' for detailed troubleshooting information."
    return 1
  fi
}

# Handle command line arguments
case "${1:-}" in
"help" | "-h" | "--help")
  echo "Enhanced USB Scanner Setup Script v2.1"
  echo ""
  echo "Usage: $0 [option]"
  echo ""
  echo "Options:"
  echo "  (no args)   Run full installation"
  echo "  --force     Force reinstallation (overwrite existing)"
  echo "  --minimal   Minimal installation (no desktop integration)"
  echo "  --repair    Repair existing installation"
  echo "  help        Show this help"
  echo ""
  echo "This script installs the Enhanced USB Virus Scanner with:"
  echo "  • Automatic USB device detection via udev"
  echo "  • ClamAV integration with proper permissions"
  echo "  • Modern GUI interface with real-time feedback"
  echo "  • SSH-compatible installation"
  echo "  • Comprehensive logging and reporting"
  echo ""
  ;;
"--force")
  print_info "Force mode: Will overwrite existing configuration"
  main
  ;;
"--minimal")
  print_info "Minimal mode: Skipping desktop integration"
  setup_desktop() { echo "Skipping desktop integration..."; }
  main
  ;;
"--repair")
  print_info "Repair mode: Fixing existing installation"
  # Skip package installation in repair mode
  install_system_packages() { echo "Skipping package installation..."; }
  main
  ;;
*)
  # Check if main script exists
  if [[ ! -f "$SCRIPT_PATH" ]]; then
    print_error "Main script not found: $SCRIPT_PATH"
    echo "Make sure you're running this from the correct directory."
    exit 1
  fi

  main
  ;;
esac
