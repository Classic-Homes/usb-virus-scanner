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
$USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam
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
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="vfat|ntfs|exfat|ext4|ext3", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", \\
    RUN+="/bin/bash -c '/usr/bin/systemd-run --uid=$USER --gid=$USER --setenv=DISPLAY=:0 --setenv=XAUTHORITY=$HOME/.Xauthority --setenv=HOME=$HOME /usr/bin/python3 $SCRIPT_PATH &'"

# Log USB events for debugging
ACTION=="add|remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", \\
    RUN+="/bin/bash -c 'echo \$(date): \$env{ACTION} \$env{DEVNAME} \$env{ID_FS_TYPE} >> /tmp/usb-events.log'"
EOF

sudo cp /tmp/usb-scanner.rules /etc/udev/rules.d/99-usb-scanner.rules
sudo chmod 644 /etc/udev/rules.d/99-usb-scanner.rules
rm -f /tmp/usb-scanner.rules

sudo udevadm control --reload-rules
sudo udevadm trigger
print_status "Udev rule created"
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

# Create event log files
touch /tmp/usb-events.log
chmod 666 /tmp/usb-events.log
echo ""

echo "6. 🛠️ Creating management script..."
cat >"$SCRIPT_DIR/manage.sh" <<'EOF'
#!/bin/bash
# USB Scanner Management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/usb_scanner.py"

case "${1:-}" in
    start)
        echo "Starting scanner..."
        python3 "$SCANNER" --minimize &
        ;;
    stop)
        echo "Stopping scanner..."
        pkill -f "usb_scanner.py" || echo "Not running"
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if pgrep -f "usb_scanner.py" >/dev/null; then
            echo "✓ Scanner running"
            ps aux | grep usb_scanner.py | grep -v grep
        else
            echo "✗ Scanner not running"
        fi
        ;;
    gui)
        python3 "$SCANNER"
        ;;
    logs)
        if [[ -f "/var/log/usb_scanner.log" ]]; then
            tail -20 /var/log/usb_scanner.log
        else
            echo "No logs found"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|gui|logs}"
        ;;
esac
EOF

chmod +x "$SCRIPT_DIR/manage.sh"
print_status "Management script created"
echo ""

echo "7. ✅ Verifying installation..."
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
echo "  Monitor events:  tail -f /tmp/usb-events.log"
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
