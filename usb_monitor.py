import os
import subprocess
from pyudev import Context, Monitor, MonitorObserver

def on_device_event(device):
    """Callback function to be called when a device is added."""
    if device.action == 'add':
        dev_path = device.get('DEVNAME')
        fs_type = device.get('ID_FS_TYPE')
        print(f"Device Added: {dev_path}, FS Type: {fs_type}")
        
        if fs_type == 'vfat':
            print(f"USB Device Added: {dev_path}")
            scan_device(dev_path)

def scan_device(dev_path):
    """Function to scan the device using ClamAV"""
    if os.geteuid() != 0:
        print("You need to have root privileges to run the scan.")
        return
    
    # Prepare the command
    command = f'x-terminal-emulator -e "clamscan -r --remove {dev_path}; echo Scan Completed! Press Enter to close.; read"'

    try:
        print(f"Running: {command}")
        subprocess.run(command, shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error occurred while scanning: {str(e)}")

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
