#!/bin/bash
# Enhanced USB Virus Scanner Setup Script

set -e

echo "=== USB Virus Scanner Enhanced Setup ==="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  echo "Please don't run this script as root. Run as the user who will use the scanner."
  exit 1
fi

# Update system packages
echo "Updating system packages..."
sudo apt update

# Install required system packages
echo "Installing system dependencies..."
sudo apt install -y python3 python3-pip python3-pyudev python3-tk clamav clamav-daemon freshclam dbus-x11

# Install Python packages
echo "Installing Python dependencies..."
pip3 install --user pyudev==0.24.1

# Setup ClamAV
echo "Configuring ClamAV..."
sudo systemctl stop clamav-freshclam 2>/dev/null || true
sudo freshclam
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

# Configure sudoers for passwordless clamscan
echo "Configuring sudo permissions for clamscan..."
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam" | sudo tee /etc/sudoers.d/usb-scanner

# Make the main script executable
chmod +x usb_scanner.py

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/usb_scanner.log
sudo chown $USER:$USER /var/log/usb_scanner.log

# Install systemd service (optional - for auto-start)
read -p "Do you want to install the scanner as a system service (auto-start)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Installing systemd service..."

  # Create the service file
  cat >/tmp/usb-scanner.service <<EOF
[Unit]
Description=USB Virus Scanner Service
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
User=$USER
Group=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority
ExecStart=/usr/bin/python3 $PWD/usb_scanner.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=no
ReadWritePaths=$HOME /var/log /tmp

[Install]
WantedBy=graphical-session.target
EOF

  sudo mv /tmp/usb-scanner.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable usb-scanner.service

  echo "Service installed. It will start automatically on next login."
  echo "To start it now: sudo systemctl start usb-scanner.service"
  echo "To stop it: sudo systemctl stop usb-scanner.service"
  echo "To check status: sudo systemctl status usb-scanner.service"
fi

# Create desktop shortcut
echo "Creating desktop shortcut..."
cat >~/Desktop/usb-scanner.desktop <<EOF
[Desktop Entry]
Name=USB Virus Scanner
Comment=Automated USB virus scanning with ClamAV
Version=2.0.0
Exec=python3 $PWD/usb_scanner.py
Icon=security-high
Terminal=false
Type=Application
Categories=Security;System;
EOF

chmod +x ~/Desktop/usb-scanner.desktop

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "The enhanced USB scanner has been installed with the following features:"
echo "• Modern GUI with real-time feedback"
echo "• Automatic virus definition updates"
echo "• Detailed scan reports (JSON format)"
echo "• Better device detection and mounting"
echo "• Comprehensive logging"
echo ""
echo "You can now:"
echo "1. Run manually: python3 usb_scanner.py"
echo "2. Use the desktop shortcut"
echo "3. If installed as service, it will auto-start on login"
echo ""
echo "Test by plugging in a USB device!"
echo ""
