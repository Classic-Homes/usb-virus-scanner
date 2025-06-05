# Enhanced USB Virus Scanner

An advanced Python application for automatically scanning USB drives when connected to Ubuntu systems using ClamAV antivirus engine. Features a modern GUI interface with real-time feedback and comprehensive reporting.

## ✨ Features

### Core Functionality

- **Automatic Detection**: Monitors USB ports and automatically detects removable storage devices
- **Real-time Scanning**: Uses ClamAV engine for thorough virus scanning
- **Automatic Remediation**: Removes detected threats automatically
- **Multiple File Systems**: Supports VFAT, NTFS, exFAT, EXT3, and EXT4

### Enhanced User Experience

- **Modern GUI Interface**: Intuitive graphical interface with real-time status updates
- **Progress Indicators**: Visual progress bars and status messages
- **Detailed Device Info**: Shows device vendor, model, file system, and capacity
- **Comprehensive Logging**: Both GUI log display and file-based logging
- **Scan Reports**: Detailed JSON reports saved to USB device and desktop

### System Integration

- **Auto-start Service**: Optional systemd service for automatic startup
- **Desktop Integration**: Desktop shortcut for manual launching
- **Security Hardened**: Runs with minimal required privileges
- **Error Handling**: Robust error handling and recovery mechanisms

## 📋 Requirements

### System Requirements

- **OS**: Ubuntu 20.04 LTS or newer (tested on Ubuntu 24.04)
- **Python**: Python 3.8 or newer
- **Desktop**: X11-based desktop environment (GNOME, XFCE, etc.)
- **Privileges**: Sudo access for initial setup

### Dependencies

```bash
# System packages
sudo apt install python3 python3-pip python3-pyudev python3-tk clamav clamav-daemon freshclam dbus-x11

# Python packages
pip3 install pyudev==0.24.1
```

## 🚀 Quick Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/yourusername/usb-virus-scanner.git
   cd usb-virus-scanner
   ```

2. **Run the setup script**:

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. **Test the installation**:
   ```bash
   python3 usb_scanner.py
   ```

The setup script will:

- Install all required dependencies
- Configure ClamAV with proper permissions
- Update virus definitions
- Optionally install as a system service
- Create a desktop shortcut

## 📖 Manual Installation

If you prefer manual installation:

### 1. Install System Dependencies

```bash
sudo apt update
sudo apt install python3 python3-pip python3-pyudev python3-tk clamav clamav-daemon freshclam dbus-x11
```

### 2. Install Python Dependencies

```bash
pip3 install --user pyudev==0.24.1
```

### 3. Configure ClamAV

```bash
# Stop freshclam service temporarily
sudo systemctl stop clamav-freshclam

# Update virus definitions
sudo freshclam

# Restart and enable freshclam
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam
```

### 4. Configure Sudo Permissions

```bash
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam" | sudo tee /etc/sudoers.d/usb-scanner
```

### 5. Make Script Executable

```bash
chmod +x usb_scanner.py
```

## 🔧 Usage

### Manual Launch

```bash
python3 usb_scanner.py
```

### Desktop Shortcut

Double-click the "USB Virus Scanner" icon on your desktop.

### Service Mode

If installed as a service:

```bash
# Start service
sudo systemctl start usb-scanner.service

# Stop service
sudo systemctl stop usb-scanner.service

# Check status
sudo systemctl status usb-scanner.service

# View logs
journalctl -u usb-scanner.service -f
```

## 🖥️ GUI Interface

The application features a modern dark-themed GUI with:

- **Status Panel**: Real-time status updates and progress indicators
- **Device Information**: Detailed info about connected USB devices
- **Scan Log**: Scrollable log with timestamps and color-coded messages
- **Control Buttons**: Clear log and exit functions

### Status Indicators

- 🔵 **Blue**: Waiting for device or normal operation
- 🟡 **Yellow**: Device mounting or definition updates
- 🟠 **Orange**: Scanning in progress
- 🟢 **Green**: Scan completed successfully
- 🔴 **Red**: Threats found or errors occurred

## 📊 Scan Reports

The scanner generates detailed reports in JSON format containing:

```json
{
  "timestamp": "2025-06-05T10:30:00",
  "device_info": {
    "vendor": "SanDisk",
    "model": "Ultra USB 3.0",
    "fs_type": "vfat",
    "label": "MYDRIVE"
  },
  "mount_point": "/media/user/MYDRIVE",
  "scan_duration": "0:02:15",
  "total_files_scanned": 1542,
  "threats_found": 0,
  "infected_files": [],
  "exit_code": 0
}
```

Reports are saved to:

1. USB device root directory (preferred)
2. Desktop as backup location

## 🔐 Security Considerations

### Isolation

This scanner is designed for dedicated testing/scanning systems, not daily-use workstations:

- Run on isolated systems that can be rebuilt if compromised
- Use dedicated scanning stations for unknown USB devices
- Regularly backup the scanning system configuration

### Permissions

The scanner requires specific sudo permissions for:

- `clamscan`: Virus scanning with removal capabilities
- `freshclam`: Virus definition updates

These are configured with `NOPASSWD` to avoid interrupting automated scans.

### File System Access

The scanner needs read/write access to:

- USB mount points (for scanning and report writing)
- `/var/log` (for logging)
- User home directory (for backup reports)

## 🔍 Troubleshooting

### Common Issues

**"ClamAV not found" error**:

```bash
sudo apt install clamav
which clamscan  # Should return /usr/bin/clamscan
```

**"Cannot run clamscan with sudo" error**:

```bash
# Check sudoers configuration
sudo visudo -f /etc/sudoers.d/usb-scanner
# Should contain: username ALL=(ALL) NOPASSWD: /usr/bin/clamscan, /usr/bin/freshclam
```

**GUI doesn't appear**:

```bash
# Check if X11 forwarding is enabled
echo $DISPLAY  # Should show :0 or similar
xauth list     # Should show X11 authentication entries
```

**Device not detected**:

```bash
# Check if device appears in system
lsblk
dmesg | tail -20
# Ensure USB device has a supported file system
```

**Permission denied on USB device**:

```bash
# Check mount options
mount | grep /media
# Device might be mounted read-only or with noexec
```

### Log Files

Check these locations for diagnostic information:

- Application log: `/var/log/usb_scanner.log`
- System journal: `journalctl -u usb-scanner.service`
- ClamAV logs: `/var/log/clamav/`
- Detailed scan log: `/tmp/clamscan_detailed.log`

### Debug Mode

Run with verbose output:

```bash
python3 -u usb_scanner.py
```

## 🔄 Updates

### Virus Definitions

The scanner automatically updates virus definitions on startup and periodically through the `freshclam` service.

Manual update:

```bash
sudo freshclam
```

### Application Updates

```bash
cd usb-virus-scanner
git pull origin main
# Restart service if running
sudo systemctl restart usb-scanner.service
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This software is provided "as is" without warranty. While it uses industry-standard ClamAV engine, no antivirus solution is 100% effective. Always:

- Keep virus definitions updated
- Use multiple security layers
- Scan unknown devices on isolated systems
- Maintain regular backups

## 🆘 Support

For issues and questions:

1. Check the troubleshooting section above
2. Search existing GitHub issues
3. Create a new issue with:
   - Ubuntu version
   - Python version
   - Error messages
   - Steps to reproduce

---

**Version**: 2.0.0  
**Last Updated**: June 2025  
**Tested On**: Ubuntu 24.04 LTS
