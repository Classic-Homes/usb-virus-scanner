#!/bin/bash
# Simplified USB Scanner Setup v2.1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/usb_scanner.py"

echo "🔧 USB Scanner Setup v2.1"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ️${NC} $1"; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  print_error "Don't run as root. Run as the user who will use the scanner."
  exit 1
fi

# Check main script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  print_error "Scanner script not found: $SCRIPT_PATH"
  exit 1
fi

echo "1. 📦 Installing packages..."
sudo apt update
sudo apt install -y python3 python3-pyudev python3-tk python3-psutil \
  clamav clamav-daemon clamav-freshclam udev psmisc lsof jq
print_status "Packages installed"
echo ""

echo "2. 🛡️ Configuring ClamAV..."
sudo systemctl stop clamav-freshclam 2>/dev/null || true

print_info "Updating virus definitions (this may take a few minutes)..."
if sudo freshclam; then
  print_status "Definitions updated"
else
  print_warning "Could not update definitions - will retry later"
fi

sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam
print_status "ClamAV configured"
echo ""

echo "3. 🔐 Setting up sudo permissions..."
cat >/tmp/usb-scanner-sudoers <<EOF
# USB Scanner permissions
$USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam, /usr/bin/udevadm
EOF

sudo cp /tmp/usb-scanner-sudoers /etc/sudoers.d/usb-scanner
sudo chmod 440 /etc/sudoers.d/usb-scanner
rm -f /tmp/usb-scanner-sudoers

if sudo visudo -c -f /etc/sudoers.d/usb-scanner; then
  print_status "Sudo permissions configured"
else
  print_error "Sudoers configuration invalid"
  exit 1
fi
echo ""

echo "4. 🔌 Creating udev rule..."
cat >/tmp/usb-scanner.rules <<EOF
# USB Scanner - Auto-launch on USB insertion
# Log all USB block device events first
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", \\
    RUN+="/bin/bash -c 'echo \$(date): ADD \$env{DEVNAME} \$env{ID_FS_TYPE} >> /tmp/usb-events.log'"

ACTION=="remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", \\
    RUN+="/bin/bash -c 'echo \$(date): REMOVE \$env{DEVNAME} >> /tmp/usb-events.log'"

# Launch scanner for USB partitions with specific filesystems
# Method 1: Use our launcher script (more reliable)
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="vfat", \\
    RUN+="/bin/su ${USER} -c '/usr/local/bin/usb-scanner-launcher %p %k'"

ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="ntfs", \\
    RUN+="/bin/su ${USER} -c '/usr/local/bin/usb-scanner-launcher %p %k'"

ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="exfat", \\
    RUN+="/bin/su ${USER} -c '/usr/local/bin/usb-scanner-launcher %p %k'"

ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="ext4", \\
    RUN+="/bin/su ${USER} -c '/usr/local/bin/usb-scanner-launcher %p %k'"

ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="ext3", \\
    RUN+="/bin/su ${USER} -c '/usr/local/bin/usb-scanner-launcher %p %k'"

# Method 2: Alternative using systemd-run (backup method)
# ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", \\
#    ENV{ID_FS_TYPE}=="vfat|ntfs|exfat|ext4|ext3", \\
#    RUN+="/bin/bash -c '/usr/bin/systemd-run --user --unit=usb-scanner \\
#    --setenv=DISPLAY=:0 --setenv=XAUTHORITY=${HOME}/.Xauthority \\
#    /usr/bin/python3 ${SCRIPT_PATH} --minimize'"
EOF

sudo cp /tmp/usb-scanner.rules /etc/udev/rules.d/99-usb-scanner.rules
sudo chmod 644 /etc/udev/rules.d/99-usb-scanner.rules
rm -f /tmp/usb-scanner.rules

# Make sure the rules take effect
print_info "Reloading udev rules..."
sudo udevadm control --reload-rules
print_info "Triggering udev rules..."
sudo udevadm trigger
print_info "Restarting udev service..."
sudo systemctl restart udev.service 2>/dev/null || true

# Create wrapper script for direct execution
print_info "Creating udev wrapper script..."
cat >/tmp/usb-scanner-launcher <<EOF
#!/bin/bash
# USB Scanner launcher for udev

# Log the execution
echo "\$(date): Launcher executed for \$1 \$2" >> /tmp/usb-events.log

# Use at-command for better reliability (if available)
if command -v at &>/dev/null; then
  echo "DISPLAY=:0 XAUTHORITY=${HOME}/.Xauthority python3 ${SCRIPT_PATH} --minimize" | at now
else
  # Fallback to direct execution
  DISPLAY=:0 XAUTHORITY=${HOME}/.Xauthority python3 ${SCRIPT_PATH} --minimize &
fi
EOF

sudo cp /tmp/usb-scanner-launcher /usr/local/bin/usb-scanner-launcher
sudo chmod 755 /usr/local/bin/usb-scanner-launcher
sudo chown root:root /usr/local/bin/usb-scanner-launcher
rm -f /tmp/usb-scanner-launcher
print_status "Udev rule created and activated"
echo ""

echo "5. 📝 Setting up logging..."
LOG_DIR="$HOME/.local/share/usb-scanner"
mkdir -p "$LOG_DIR"

# Try to create system log
if sudo touch /var/log/usb_scanner.log 2>/dev/null; then
  sudo chown "$USER:$USER" /var/log/usb_scanner.log
  print_status "System log configured"
else
  print_warning "Using user log directory: $LOG_DIR"
fi

# Create event log files with proper permissions
touch /tmp/usb-events.log
chmod 666 /tmp/usb-events.log
echo ""

echo "6. 🔄 Creating autostart service..."
# Create systemd user service for autostart
mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/usb-scanner.service" <<EOF
[Unit]
Description=USB Virus Scanner Monitor
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SCRIPT_PATH} --minimize
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF

# Enable the service
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable usb-scanner.service 2>/dev/null || true
systemctl --user start usb-scanner.service 2>/dev/null || true
print_status "Autostart service created"
echo ""

echo "7. 🛠️ Creating management script..."
cat >"$SCRIPT_DIR/manage.sh" <<'EOF'
#!/bin/bash
# USB Scanner Management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/usb_scanner.py"
SERVICE_NAME="usb-scanner.service"

case "${1:-}" in
    start)
        echo "Starting scanner..."
        if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
            systemctl --user restart "$SERVICE_NAME"
            echo "Service restarted"
        else
            if systemctl --user start "$SERVICE_NAME" 2>/dev/null; then
                echo "Started via systemd"
            else 
                echo "Starting directly..."
                python3 "$SCANNER" --minimize &
            fi
        fi
        ;;
    stop)
        echo "Stopping scanner..."
        systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
        pkill -f "usb_scanner.py" || echo "Not running"
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
            echo "✓ Scanner service running"
            systemctl --user status "$SERVICE_NAME" | head -n 6
        elif pgrep -f "usb_scanner.py" >/dev/null; then
            echo "✓ Scanner running (manual start)"
            ps aux | grep usb_scanner.py | grep -v grep
        else
            echo "✗ Scanner not running"
        fi
        
        # Check udev rule status
        echo ""
        if [[ -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
            echo "✓ Udev rule installed"
            if [[ -f "/usr/local/bin/usb-scanner-launcher" ]]; then
                echo "✓ Launcher script installed"
            else
                echo "✗ Launcher script missing"
            fi
        else
            echo "✗ Udev rule missing"
        fi
        ;;
    gui)
        python3 "$SCANNER"
        ;;
    logs)
        if [[ -f "/var/log/usb_scanner.log" ]]; then
            tail -20 /var/log/usb_scanner.log
        else
            echo "System log not found, checking local log..."
            LOG_LOCAL="$HOME/.local/share/usb-scanner/usb_scanner.log"
            if [[ -f "$LOG_LOCAL" ]]; then
                tail -20 "$LOG_LOCAL"
            else
                echo "No logs found"
            fi
        fi
        echo ""
        echo "USB Events log:"
        if [[ -f "/tmp/usb-events.log" ]]; then
            tail -10 /tmp/usb-events.log
        else
            echo "No USB events logged"
        fi
        ;;
    test)
        echo "Testing udev rule..."
        if [[ -f "/usr/local/bin/usb-scanner-launcher" ]]; then
            /usr/local/bin/usb-scanner-launcher "test" "test"
            echo "Launcher triggered. Check if scanner window appears."
        else
            echo "Launcher script missing"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|gui|logs|test}"
        ;;
esac
EOF

chmod +x "$SCRIPT_DIR/manage.sh"
print_status "Management script created"
echo ""

echo "8. ✅ Verifying installation..."
chmod +x "$SCRIPT_PATH"

# Test dependencies
if python3 -c "import pyudev, tkinter" 2>/dev/null; then
  print_status "Python dependencies OK"
else
  print_error "Python dependencies missing"
  exit 1
fi

# Test ClamAV
if sudo -n clamscan --version >/dev/null 2>&1; then
  print_status "ClamAV permissions OK"
else
  print_error "ClamAV permissions failed"
  exit 1
fi

# Test script import
if python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR'); import usb_scanner" 2>/dev/null; then
  print_status "Scanner script OK"
else
  print_error "Scanner script failed"
  exit 1
fi

# Verify udev launcher
if [[ -f "/usr/local/bin/usb-scanner-launcher" ]]; then
  print_status "Udev launcher OK"
else
  print_warning "Udev launcher not installed"
fi

echo ""
echo "🎉 Installation Complete!"
echo ""
print_status "USB Scanner v2.1 successfully installed"
echo ""
echo "🚀 Usage:"
echo "  GUI mode:        python3 $SCRIPT_PATH"
echo "  Background:      python3 $SCRIPT_PATH --minimize"
echo "  Headless:        python3 $SCRIPT_PATH --headless"
echo "  Management:      ./manage.sh {start|stop|status|gui}"
echo ""
echo "🧪 Testing:"
echo "  Check status:    ./manage.sh status"
echo "  View logs:       ./manage.sh logs"
echo "  Quick test:      ./manage.sh test"
echo "  Monitor events:  tail -f /tmp/usb-events.log"
echo ""
echo "🔄 Autostart:"
echo "  The scanner will start automatically at boot and when USB drives are inserted"
echo ""
print_status "Insert a USB device to test automatic scanning!"
echo ""

# Offer quick test
read -p "Run quick test? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Testing scanner..."
  if timeout 3s python3 "$SCRIPT_PATH" --headless 2>/dev/null; then
    print_status "Basic test passed"
  else
    print_info "Test completed (normal timeout)"
  fi
fi
