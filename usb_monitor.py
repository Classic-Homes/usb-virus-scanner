import os
import subprocess
from pyudev import Context, Monitor, MonitorObserver

def on_device_event(device):
    """Callback function to be called when a device is added."""
    if device.action == 'add' and device.get('ID_FS_TYPE') == 'vfat':
        dev_path = device.get('DEVNAME')
        print(f"USB Device Added: {dev_path}")
        scan_device(dev_path)

def scan_device(dev_path):
    """Function to scan the device using ClamAV"""
    if os.geteuid() != 0:
        print("You need to have root privileges to run the scan.")
        return

    command = f"clamscan -r --remove {dev_path}"
    print(f"Running: {command}")

    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("Error occurred while scanning.")

def main():
    """Main function to setup device monitor"""
    context = Context()
    monitor = Monitor.from_netlink(context)
    monitor.filter_by(subsystem='block')

    observer = MonitorObserver(monitor, callback=on_device_event, name='observer')
    observer.daemon = False
    observer.start()

    print("Monitoring USB ports. Press Ctrl+C to exit.")
    try:
        observer.join()
    except KeyboardInterrupt:
        print("Exiting...")

if __name__ == "__main__":
    main()
