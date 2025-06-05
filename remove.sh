#!/bin/bash
# Comprehensive USB Scanner Cleanup Script

set -e

echo "🧹 === USB Scanner Comprehensive Cleanup ==="
echo ""

# Function to safely remove files
safe_remove() {
  if [[ -f "$1" ]]; then
    echo "🗑️  Removing file: $1"
    rm -f "$1"
  elif [[ -d "$1" ]]; then
    echo "🗑️  Removing directory: $1"
    rm -rf "$1"
  else
    echo "⚠️  Not found (already removed): $1"
  fi
}

# Function to stop processes
stop_processes() {
  echo "🛑 Stopping all USB scanner processes..."

  # Kill any running scanner processes
  if pgrep -f "usb_scanner.py" >/dev/null; then
    echo "   Stopping usb_scanner.py processes..."
    pkill -f "usb_scanner.py" || true
    sleep 2
    # Force kill if still running
    if pgrep -f "usb_scanner.py" >/dev/null; then
      pkill -9 -f "usb_scanner.py" || true
    fi
  fi

  # Kill any running monitor processes
  if pgrep -f "usb_monitor.sh" >/dev/null; then
    echo "   Stopping usb_monitor.sh processes..."
    pkill -f "usb_monitor.sh" || true
    sleep 1
    if pgrep -f "usb_monitor.sh" >/dev/null; then
      pkill -9 -f "usb_monitor.sh" || true
    fi
  fi

  # Kill any running launcher processes
  if pgrep -f "launch_scanner.sh" >/dev/null; then
    echo "   Stopping launch_scanner.sh processes..."
    pkill -f "launch_scanner.sh" || true
  fi

  echo "✅ All processes stopped"
}

# Stop all running processes first
stop_processes

echo ""
echo "🧹 Removing system services..."

# Stop and remove system service
sudo systemctl stop usb-scanner.service 2>/dev/null || echo "   System service not running"
sudo systemctl disable usb-scanner.service 2>/dev/null || echo "   System service not enabled"
safe_remove "/etc/systemd/system/usb-scanner.service"

# Stop and remove user service
systemctl --user stop usb-scanner.service 2>/dev/null || echo "   User service not running"
systemctl --user disable usb-scanner.service 2>/dev/null || echo "   User service not enabled"
safe_remove "$HOME/.config/systemd/user/usb-scanner.service"

# Reload systemd
echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload
systemctl --user daemon-reload 2>/dev/null || true

echo ""
echo "🧹 Removing udev rules..."

# Remove all udev rules
safe_remove "/etc/udev/rules.d/99-usb-scanner.rules"
safe_remove "/etc/udev/rules.d/98-usb-test.rules"

# Reload udev rules
echo "🔄 Reloading udev rules..."
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

echo ""
echo "🧹 Removing sudo permissions..."

# Remove sudoers configuration
safe_remove "/etc/sudoers.d/usb-scanner"

echo ""
echo "🧹 Removing desktop integration..."

# Remove desktop shortcuts
safe_remove "$HOME/Desktop/usb-scanner.desktop"
safe_remove "$HOME/Desktop/usb_scanner.desktop"

# Remove autostart entries
safe_remove "$HOME/.config/autostart/usb-scanner.desktop"
safe_remove "$HOME/.config/autostart/usb-monitor.desktop"

echo ""
echo "🧹 Removing log and temporary files..."

# Remove log files
safe_remove "/var/log/usb_scanner.log"
safe_remove "/tmp/usb-scanner.log"
safe_remove "/tmp/usb-monitor.log"
safe_remove "/tmp/usb-test.log"
safe_remove "/tmp/usb-scanner-output.log"
safe_remove "/tmp/usb_last_state"
safe_remove "/tmp/usb_current_state"
safe_remove "/tmp/usb-last-devices"
safe_remove "/tmp/usb-monitor.pid"
safe_remove "/tmp/scanner_pid"

# Remove any USB event logs
rm -f /tmp/usb-event-* 2>/dev/null || true

# Remove application data directory
safe_remove "$HOME/.local/share/usb-scanner/"

echo ""
echo "🧹 Cleaning up old script files..."

# Remove any old or backup scripts
safe_remove "$HOME/usb-virus-scanner/launch_scanner.sh"
safe_remove "$HOME/usb-virus-scanner/test_scanner.sh"
safe_remove "$HOME/usb-virus-scanner/check_scanner.sh"
safe_remove "$HOME/usb-virus-scanner/diagnose_service.sh"
safe_remove "$HOME/usb-virus-scanner/debug_usb.sh"
safe_remove "$HOME/usb-virus-scanner/fix_udev.sh"
safe_remove "$HOME/usb-virus-scanner/setup.sh.backup"

# Remove old monitor scripts
safe_remove "$HOME/usb-virus-scanner/usb_monitor.sh.backup"

echo ""
echo "🧹 Checking for any remaining processes..."

# Final process check
if pgrep -f "usb.*scanner" >/dev/null; then
  echo "⚠️  Found remaining processes:"
  ps aux | grep -E "usb.*scanner" | grep -v grep
  echo "   Attempting to stop them..."
  pkill -9 -f "usb.*scanner" 2>/dev/null || true
else
  echo "✅ No remaining scanner processes found"
fi

echo ""
echo "🧹 Verifying cleanup..."

# Verify cleanup
echo "📋 Checking what's left:"

echo ""
echo "System services:"
systemctl list-unit-files | grep usb-scanner || echo "   ✅ No system services found"

echo ""
echo "User services:"
systemctl --user list-unit-files | grep usb-scanner || echo "   ✅ No user services found"

echo ""
echo "Udev rules:"
ls -la /etc/udev/rules.d/*usb* 2>/dev/null || echo "   ✅ No USB udev rules found"

echo ""
echo "Running processes:"
ps aux | grep -E "(usb_scanner|usb_monitor|launch_scanner)" | grep -v grep || echo "   ✅ No scanner processes running"

echo ""
echo "Autostart entries:"
ls -la ~/.config/autostart/*usb* 2>/dev/null || echo "   ✅ No autostart entries found"

echo ""
echo "Desktop shortcuts:"
ls -la ~/Desktop/*usb* 2>/dev/null || echo "   ✅ No desktop shortcuts found"

echo ""
echo "🎉 === Cleanup Complete! ==="
echo ""
echo "✅ All system services removed"
echo "✅ All user services removed"
echo "✅ All udev rules removed"
echo "✅ All autostart entries removed"
echo "✅ All desktop shortcuts removed"
echo "✅ All log files removed"
echo "✅ All temporary files removed"
echo "✅ All running processes stopped"
echo "✅ Sudo permissions removed"
echo ""

# Ask about keeping the main application files
echo "📁 Application files status:"
if [[ -f "$HOME/usb-virus-scanner/usb_scanner.py" ]]; then
  echo "   📄 Main scanner script: KEPT"
  echo "   📄 Setup script: KEPT"
  echo "   📄 README: KEPT"
  echo ""
  read -p "🗂️  Do you want to keep the main application files (usb_scanner.py, setup.sh, README.md)? [Y/n]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "🗑️  Removing application files..."
    safe_remove "$HOME/usb-virus-scanner/usb_scanner.py"
    safe_remove "$HOME/usb-virus-scanner/setup.sh"
    safe_remove "$HOME/usb-virus-scanner/README.md"
    safe_remove "$HOME/usb-virus-scanner/requirements.txt"
    safe_remove "$HOME/usb-virus-scanner/usb_scanner.desktop"
    safe_remove "$HOME/usb-virus-scanner/remove.sh"
    safe_remove "$HOME/usb-virus-scanner/cleanup.sh"

    # Remove the entire directory if empty
    if [[ -d "$HOME/usb-virus-scanner" ]]; then
      if [[ -z "$(ls -A "$HOME/usb-virus-scanner" 2>/dev/null)" ]]; then
        echo "🗑️  Removing empty directory..."
        rmdir "$HOME/usb-virus-scanner"
        echo "✅ Complete removal finished"
      else
        echo "⚠️  Directory not empty, keeping: $HOME/usb-virus-scanner/"
        ls -la "$HOME/usb-virus-scanner/"
      fi
    fi
  else
    echo "✅ Application files kept for future use"
    echo ""
    echo " To reinstall the scanner cleanly:"
    echo "   cd ~/usb-virus-scanner"
    echo "   ./setup.sh"
  fi
else
  echo "   ✅ No application files found"
fi

echo ""
echo "🔄 System is now clean and ready for a fresh installation!"
echo ""

# Optional: Ask about removing packages
read -p "📦 Do you want to remove installed packages (clamav, python3-pyudev, etc.)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "🗑️  Removing packages..."
  sudo apt remove --purge -y clamav clamav-daemon clamav-freshclam python3-pyudev 2>/dev/null || echo "   Some packages might not be installed"
  sudo apt autoremove -y 2>/dev/null || true
  echo "✅ Packages removed"
else
  echo "✅ Packages kept (can be reused for reinstallation)"
fi

echo ""
echo "🎊 All done! System is completely clean."
echo ""
