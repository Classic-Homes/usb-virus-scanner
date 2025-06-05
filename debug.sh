#!/bin/bash
# Simplified USB Scanner Debug Tool

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER_SCRIPT="$SCRIPT_DIR/usb_scanner.py"

echo "🔍 USB Scanner Debug Tool"
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

# Check dependencies
echo "1. 📦 Checking dependencies..."
deps=("python3" "clamscan" "udevadm" "lsblk" "findmnt")
for dep in "${deps[@]}"; do
  if command -v "$dep" >/dev/null 2>&1; then
    print_status "$dep available"
  else
    print_error "$dep missing"
  fi
done

echo ""
echo "   Python modules:"
python3 -c "
modules = {'pyudev': 'python3-pyudev', 'tkinter': 'python3-tk', 'psutil': 'python3-psutil'}
for module, pkg in modules.items():
    try:
        __import__(module)
        print('   ✓ ' + module)
    except ImportError:
        print('   ❌ ' + module + ' (install: sudo apt install ' + pkg + ')')
"
echo ""

# Check permissions
echo "2. 🔐 Checking permissions..."
if [[ -f "/etc/sudoers.d/usb-scanner" ]]; then
  print_status "Sudoers file exists"
  echo "   Content:"
  cat /etc/sudoers.d/usb-scanner | sed 's/^/   /'
else
  print_error "Sudoers file missing"
fi

if sudo -n clamscan --version >/dev/null 2>&1; then
  print_status "ClamAV sudo access working"
else
  print_error "ClamAV sudo access failed"
fi
echo ""

# Check services
echo "3. 🔄 Checking processes..."
if pgrep -f "usb_scanner.py" >/dev/null; then
  print_status "Scanner processes found:"
  ps aux | grep usb_scanner.py | grep -v grep | sed 's/^/   /'
else
  print_info "No scanner processes running"
fi

if systemctl is-active --quiet clamav-freshclam; then
  print_status "ClamAV freshclam service running"
else
  print_warning "ClamAV freshclam service not running"
fi
echo ""

# Check udev
echo "4. 🔌 Checking USB system..."
if [[ -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
  print_status "Udev rule exists"
  echo "   Content:"
  cat /etc/udev/rules.d/99-usb-scanner.rules | sed 's/^/   /'
else
  print_error "Udev rule missing"
fi

echo ""
echo "   Current USB devices:"
lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN | grep -E "(NAME|usb)" | sed 's/^/   /' || print_info "No USB devices"
echo ""

# Check ClamAV
echo "5. 🛡️ Checking ClamAV..."
if command -v clamscan >/dev/null 2>&1; then
  print_status "ClamAV installed"
  clamscan --version | head -1 | sed 's/^/   /'

  if [[ -f "/var/lib/clamav/main.cvd" ]] || [[ -f "/var/lib/clamav/main.cld" ]]; then
    db_date=$(stat -c %y /var/lib/clamav/main.c?d 2>/dev/null | head -1 | cut -d' ' -f1)
    print_status "Virus database found (updated: $db_date)"
  else
    print_warning "Virus database not found"
  fi
else
  print_error "ClamAV not installed"
fi
echo ""

# Check logs
echo "6. 📋 Checking logs..."
log_files=(
  "/var/log/usb_scanner.log"
  "$HOME/.local/share/usb-scanner/usb_scanner.log"
  "/tmp/usb-events.log"
)

for log_file in "${log_files[@]}"; do
  if [[ -f "$log_file" ]]; then
    print_status "Log found: $log_file"
    echo "   Recent entries:"
    tail -3 "$log_file" | sed 's/^/   /' 2>/dev/null || echo "   (empty)"
  fi
done
echo ""

# Test scanner
echo "7. 🧪 Testing scanner..."
if [[ -f "$SCANNER_SCRIPT" ]]; then
  print_status "Scanner script exists"

  if python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR'); import usb_scanner" 2>/dev/null; then
    print_status "Scanner imports OK"
  else
    print_error "Scanner import failed"
  fi

  if python3 "$SCANNER_SCRIPT" --status >/dev/null 2>&1; then
    print_info "Status check completed"
  else
    print_info "Status check failed (normal if not running)"
  fi
else
  print_error "Scanner script not found"
fi
echo ""

# Generate report
echo "8. 📊 Generating report..."
REPORT_FILE="/tmp/usb-scanner-debug-$(date +%Y%m%d_%H%M%S).txt"

{
  echo "USB Scanner Debug Report"
  echo "Generated: $(date)"
  echo "User: $USER"
  echo "Host: $(hostname)"
  echo ""
  echo "=== SYSTEM ==="
  uname -a
  echo ""
  echo "=== PACKAGES ==="
  dpkg -l | grep -E "(clamav|python3-pyudev|python3-tk)" 2>/dev/null || echo "Package info not available"
  echo ""
  echo "=== USB DEVICES ==="
  lsblk -o NAME,FSTYPE,MOUNTPOINT,TRAN 2>/dev/null || echo "lsblk not available"
  echo ""
  echo "=== PROCESSES ==="
  ps aux | grep -E "(usb_scanner|clam)" | grep -v grep || echo "No relevant processes"
  echo ""
  echo "=== MOUNTS ==="
  mount | grep -E "(usb|media|mnt)" || echo "No USB mounts"
  echo ""
  echo "=== LOGS ==="
  for log in "${log_files[@]}"; do
    if [[ -f "$log" ]]; then
      echo "--- $log ---"
      tail -10 "$log" 2>/dev/null || echo "Cannot read"
    fi
  done
} >"$REPORT_FILE"

print_status "Debug report saved: $REPORT_FILE"
echo ""

# Show recommendations
echo "🔧 Recommendations:"
echo ""

issues=0
if ! sudo -n clamscan --version >/dev/null 2>&1; then
  print_error "Fix sudo permissions: Run setup.sh"
  ((issues++))
fi

if [[ ! -f "/etc/udev/rules.d/99-usb-scanner.rules" ]]; then
  print_error "Fix udev rule: Run setup.sh"
  ((issues++))
fi

if ! command -v clamscan >/dev/null 2>&1; then
  print_error "Install ClamAV: sudo apt install clamav"
  ((issues++))
fi

if [[ $issues -eq 0 ]]; then
  print_status "No critical issues found!"
else
  print_warning "Found $issues issue(s) - run setup.sh to fix"
fi

echo ""
echo "🛠️ Quick fixes:"
echo "  Restart services:    sudo systemctl restart clamav-freshclam"
echo "  Reload udev:         sudo udevadm control --reload-rules"
echo "  Test manually:       python3 $SCANNER_SCRIPT --headless"
echo "  Monitor USB:         udevadm monitor --subsystem-match=block"
echo "  View USB events:     tail -f /tmp/usb-events.log"
echo ""

# Offer live USB test
read -p "Test live USB detection? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Monitoring USB events for 15 seconds..."
  echo "Insert/remove USB devices to test..."
  timeout 15s udevadm monitor --subsystem-match=block | while read line; do
    if [[ "$line" == *"add"* ]] && [[ "$line" == *"usb"* ]]; then
      echo "✓ USB add event detected: $line"
    elif [[ "$line" == *"remove"* ]] && [[ "$line" == *"usb"* ]]; then
      echo "✓ USB remove event detected: $line"
    fi
  done
  echo "Monitoring complete."
fi
