# usb-virus-scanner

Simple python script to scan a usb drive when it is connected to a linux environment using ClamAV

## Table of contents

- Requirements
- Installation
- Troubleshooting
- Deploying Service
- Use

## Requirements

This script requires the following:

- [Ubuntu](https://ubuntu.com/)
- [ClamAV](https://www.clamav.net/)
- [Python](https://www.python.org/)
- [pyudev](https://pypi.org/project/pyudev/)
- [dbus-x11](https://packages.ubuntu.com/jammy/dbus-x11)

## Installation

Clone the repository

Make 'usb_scanner.py' executable 
`sudo chmod -u+x usb-virus-scanner/usb_scanner.py`

Install dependencies
`sudo apt install python3 python3-pyudev dbus-x11`

Allow User to run ClamAV without password:
`sudo visudo`
Add the following to the end of the file:
`administrator ALL=(ALL) NOPASSWD: /usr/bin/clamscan`

This script assumes you are using an account called 'administrator' with sudo permissions. This script is not intended to be used on a daily driver machine or workstation, but rather a testing environment that is capable of being wiped and rebuilt in the event of an uncontained infection.

## Deploying Service

1. Copy the service file: Copy 'usb_scanner.service' to the '/etc/systemd/system/' directory.
2. Reload systemd: Run `sudo systemctl daemon-reload` to make systemd aware of your new service.
3. Enable the Service: Run `sudo systemctl enable usb_scanner.service` to enable the service to start at boot.
4. Start the Service: Run `sudo systemctl start usb_scanner.service` to start the service immediately.

## Use

Simply plug in a USB drive and a terminal will launch and scan the drive. A report is generated at the end of the scan.
