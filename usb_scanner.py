#!/usr/bin/env python3

import os
import time
import subprocess
from pyudev import Context, Monitor, MonitorObserver


def on_device_event(device):
    """Callback function to be called when a device is added."""
    if device.action == 'add' and device.get('ID_FS_TYPE') in ['vfat', 'ntfs', 'exfat', 'ext4']:
        dev_path = device.get('DEVNAME')
        fs_type = device.get('ID_FS_TYPE')
        print(f"Device Added: {dev_path}, FS Type: {fs_type}")

        # Wait for the device to be mounted.
        time.sleep(2)

        # Find the mount point.
        mount_point = None
        result = subprocess.run(
            ['df', '--output=target', dev_path], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                # The second line contains the mount point.
                mount_point = lines[1]

        if mount_point:
            print(f"USB Device Added: {dev_path} at {mount_point}")
            scan_device(mount_point)
        else:
            print(
                f"Could not find the mount point for {dev_path}. Skipping scan.")


def scan_device(dev_path):
    """Function to scan the device using ClamAV"""
    if os.geteuid() != 0:
        print("You need to have root privileges to run the scan.")
        return

    # Prepare the command
    command = f'gnome-terminal --command "bash -c \'sudo clamscan -r --remove {dev_path}; echo Scan Completed! Press Enter to close.; read\'"'

    try:
        print(f"Running: {command}")
        subprocess.run(command, shell=True, check=True)
    except Exception as e:  # Catching all exceptions for better debugging
        print(f"Error occurred while scanning: {str(e)}")


def main():
    """Main function to setup device monitor"""
    context = Context()
    monitor = Monitor.from_netlink(context)
    monitor.filter_by(subsystem='block')

    observer = MonitorObserver(
        monitor, callback=on_device_event, name='observer')
    observer.daemon = False
    observer.start()

    print("Monitoring USB ports. Press Ctrl+C to exit.")
    try:
        observer.join()
    except KeyboardInterrupt:
        print("Exiting...")


if __name__ == "__main__":
    main()
