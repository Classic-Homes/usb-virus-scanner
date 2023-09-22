#!/usr/bin/env python3

import os
import os.path
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

    command = ['sudo', 'clamscan', '-r', '--remove', dev_path]
    log_file_name = 'clamscan_log.txt'
    log_file_path = os.path.join(dev_path, log_file_name)
    backup_log_file_path = os.path.join(
        os.path.expanduser('~'), 'Desktop', log_file_name)

    try:
        print(f"Running: {' '.join(command)}")
        result = subprocess.run(command, capture_output=True, text=True)

        # Output the result to the terminal
        print(result.stdout)

        # Try to write the result to the log file on the drive
        try:
            with open(log_file_path, 'a') as log_file:
                log_file.write(result.stdout)
            print(f"Scan Completed! Log saved to {log_file_path}.")
        except Exception as e:
            print(f"Failed to write log to {log_file_path}, Error: {str(e)}")

            # Attempt to write to the backup location on Desktop
            try:
                with open(backup_log_file_path, 'a') as backup_log_file:
                    backup_log_file.write(result.stdout)
                print(f"Backup log saved to {backup_log_file_path}.")
            except Exception as e:
                print(
                    f"Failed to write backup log to {backup_log_file_path}, Error: {str(e)}")

        print("Press Enter to close.")
        input()  # Wait for the user to press Enter
    except Exception as e:
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

    print("Monitoring USB ports. Plug in a USB device to test...")
    for device in iter(monitor.poll, None):
        on_device_event(device)


if __name__ == "__main__":
    main()
