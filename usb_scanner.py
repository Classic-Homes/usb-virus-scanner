#!/usr/bin/env python3
"""
Simplified USB Virus Scanner v2.1
Streamlined Python application for automatically scanning USB drives using ClamAV
"""

import os
import threading
import time
import sys
import subprocess
import logging
import json
import signal
from datetime import datetime
from pathlib import Path

try:
    import psutil
except ImportError:
    psutil = None
    print("Warning: psutil not available. Some features may be limited.")

try:
    from pyudev import Context, Monitor, MonitorObserver
except ImportError:
    print("Error: pyudev not installed. Run: sudo apt install python3-pyudev")
    sys.exit(1)

try:
    import tkinter as tk
    from tkinter import ttk, scrolledtext, messagebox
    GUI_AVAILABLE = True
except ImportError:
    GUI_AVAILABLE = False

import queue


class SimpleGUI:
    """Simplified GUI with essential features only"""
    
    def __init__(self, minimize=False):
        if not GUI_AVAILABLE:
            raise RuntimeError("GUI not available - tkinter not installed")
            
        self.root = tk.Tk()
        self.root.title("USB Virus Scanner v2.1")
        self.root.geometry("800x600")
        self.root.configure(bg='#1a1a1a')
        
        if minimize:
            self.root.withdraw()
            self.minimized = True
        else:
            self.minimized = False
            
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        self.message_queue = queue.Queue()
        
        self._setup_gui()
        self._process_queue()
        
    def _setup_gui(self):
        """Setup simplified GUI"""
        # Main container
        main_frame = tk.Frame(self.root, bg='#1a1a1a', padx=15, pady=15)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Title
        title = tk.Label(main_frame, text="🛡️ USB Virus Scanner v2.1", 
                        font=('Arial', 18, 'bold'), fg='#00ff88', bg='#1a1a1a')
        title.pack(pady=(0, 20))
        
        # Status frame
        status_frame = tk.LabelFrame(main_frame, text="Status", bg='#2d2d2d', 
                                   fg='#ffffff', font=('Arial', 12, 'bold'))
        status_frame.pack(fill=tk.X, pady=(0, 15))
        
        status_inner = tk.Frame(status_frame, bg='#2d2d2d', padx=10, pady=10)
        status_inner.pack(fill=tk.X)
        
        self.status_indicator = tk.Label(status_inner, text="●", font=('Arial', 16), 
                                       fg='#3498db', bg='#2d2d2d')
        self.status_indicator.pack(side=tk.LEFT, padx=(0, 10))
        
        self.status_label = tk.Label(status_inner, text="Initializing...", 
                                   font=('Arial', 11), fg='#ffffff', bg='#2d2d2d')
        self.status_label.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.progress = ttk.Progressbar(status_inner, mode='indeterminate', length=150)
        self.progress.pack(side=tk.RIGHT)
        
        # Device info
        self.device_info = tk.Label(main_frame, text="No USB device detected", 
                                  font=('Arial', 10), fg='#cccccc', bg='#1a1a1a',
                                  justify=tk.LEFT, anchor=tk.W)
        self.device_info.pack(fill=tk.X, pady=(0, 15))
        
        # Log
        log_frame = tk.LabelFrame(main_frame, text="Activity Log", bg='#2d2d2d', 
                                fg='#ffffff', font=('Arial', 12, 'bold'))
        log_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        self.log_text = scrolledtext.ScrolledText(
            log_frame, height=15, bg='#0a0a0a', fg='#00ff88', 
            font=('Consolas', 9), wrap=tk.WORD)
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Configure log colors
        self.log_text.tag_configure('INFO', foreground='#00ff88')
        self.log_text.tag_configure('WARNING', foreground='#ffaa00')
        self.log_text.tag_configure('ERROR', foreground='#ff4444')
        self.log_text.tag_configure('SUCCESS', foreground='#00ffff')
        
        # Buttons
        button_frame = tk.Frame(main_frame, bg='#1a1a1a')
        button_frame.pack(fill=tk.X)
        
        tk.Button(button_frame, text="Clear Log", command=self._clear_log, 
                 bg='#e74c3c', fg='white', relief=tk.FLAT, padx=15).pack(side=tk.LEFT)
        
        tk.Button(button_frame, text="Minimize", command=self.minimize, 
                 bg='#3498db', fg='white', relief=tk.FLAT, padx=15).pack(side=tk.LEFT, padx=(10, 0))
        
        tk.Button(button_frame, text="Exit", command=self.exit_app, 
                 bg='#c0392b', fg='white', relief=tk.FLAT, padx=15).pack(side=tk.RIGHT)
    
    def _process_queue(self):
        """Process message queue"""
        try:
            while True:
                message, level = self.message_queue.get_nowait()
                self._log_internal(message, level)
        except queue.Empty:
            pass
        finally:
            self.root.after(100, self._process_queue)
    
    def log(self, message, level='INFO'):
        """Thread-safe logging"""
        self.message_queue.put((message, level))
    
    def _log_internal(self, message, level):
        """Internal log method"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        indicators = {'INFO': '🔵', 'WARNING': '🟡', 'ERROR': '🔴', 'SUCCESS': '🟢'}
        
        self.log_text.insert(tk.END, f"[{timestamp}] {indicators.get(level, '🔵')} {message}\n", level)
        self.log_text.see(tk.END)
        self.root.update_idletasks()
    
    def update_status(self, status, color='#3498db'):
        """Update status"""
        self.status_label.config(text=status)
        self.status_indicator.config(fg=color)
        self.root.update_idletasks()
    
    def update_device_info(self, info):
        """Update device info"""
        self.device_info.config(text=info, fg='#2ecc71')
        self.root.update_idletasks()
    
    def start_progress(self):
        self.progress.start(10)
    
    def stop_progress(self):
        self.progress.stop()
    
    def show(self):
        """Show window"""
        if self.minimized:
            self.root.deiconify()
            self.root.lift()
            self.minimized = False
    
    def minimize(self):
        """Minimize window"""
        self.root.withdraw()
        self.minimized = True
    
    def _clear_log(self):
        """Clear log"""
        self.log_text.delete(1.0, tk.END)
        self.log("Log cleared")
    
    def on_closing(self):
        """Handle close"""
        if messagebox.askokcancel("Quit", "Exit USB Scanner?"):
            self.exit_app()
    
    def exit_app(self):
        """Exit application"""
        self.root.quit()
        self.root.destroy()


class USBScanner:
    """Simplified USB virus scanner"""
    
    def __init__(self, headless=False, minimize=False):
        self.headless = headless
        self.gui = None if headless else SimpleGUI(minimize) if GUI_AVAILABLE else None
        self.scanning = False
        self.running = True
        
        # Setup logging
        self._setup_logging()
        
        # Setup USB monitoring
        self.context = Context()
        self.monitor = Monitor.from_netlink(self.context)
        self.monitor.filter_by(subsystem='block', device_type='partition')
        self.observer = None
        
        # Signal handlers
        signal.signal(signal.SIGTERM, self._shutdown)
        signal.signal(signal.SIGINT, self._shutdown)
    
    def _setup_logging(self):
        """Setup logging"""
        log_dir = Path('/var/log')
        if not log_dir.exists() or not os.access(log_dir, os.W_OK):
            log_dir = Path.home() / '.local' / 'share' / 'usb-scanner'
            log_dir.mkdir(parents=True, exist_ok=True)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_dir / 'usb_scanner.log'),
                logging.StreamHandler() if self.headless else logging.NullHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def _shutdown(self, signum, frame):
        """Handle shutdown"""
        self.log("Shutting down...")
        self.running = False
        if self.observer:
            self.observer.stop()
        sys.exit(0)
    
    def log(self, message, level='INFO'):
        """Log message"""
        if self.gui:
            self.gui.log(message, level)
        else:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] {level}: {message}")
        
        # Log to file
        if level == 'ERROR':
            self.logger.error(message)
        elif level == 'WARNING':
            self.logger.warning(message)
        else:
            self.logger.info(message)
    
    def check_dependencies(self):
        """Check required dependencies"""
        missing = []
        
        # Check ClamAV
        if subprocess.run(['which', 'clamscan'], capture_output=True).returncode != 0:
            missing.append("clamscan (install: sudo apt install clamav)")
        
        # Check sudo permissions
        try:
            if subprocess.run(['sudo', '-n', 'clamscan', '--version'], 
                            capture_output=True, timeout=5).returncode != 0:
                missing.append("sudo permissions (run setup.sh)")
        except:
            missing.append("sudo permissions (run setup.sh)")
        
        if missing:
            self.log("Missing dependencies:", 'ERROR')
            for dep in missing:
                self.log(f"  - {dep}", 'ERROR')
            return False
        
        self.log("✓ Dependencies satisfied")
        return True
    
    def update_virus_definitions(self):
        """Update ClamAV definitions"""
        self.log("Updating virus definitions...")
        if self.gui:
            self.gui.update_status("Updating definitions...", '#f39c12')
            self.gui.start_progress()
        
        try:
            result = subprocess.run(['sudo', 'freshclam'], 
                                  capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                self.log("✓ Definitions updated", 'SUCCESS')
            else:
                self.log("⚠ Could not update definitions", 'WARNING')
        except subprocess.TimeoutExpired:
            self.log("⚠ Update timed out", 'WARNING')
        except Exception as e:
            self.log(f"⚠ Update error: {e}", 'WARNING')
        finally:
            if self.gui:
                self.gui.stop_progress()
                self.gui.update_status("Monitoring...", '#3498db')
    
    def get_device_info(self, device):
        """Get device information"""
        return {
            'path': device.get('DEVNAME', 'Unknown'),
            'fs_type': device.get('ID_FS_TYPE', 'Unknown'),
            'label': device.get('ID_FS_LABEL', 'No Label'),
            'vendor': device.get('ID_VENDOR', 'Unknown'),
            'model': device.get('ID_MODEL', 'Unknown')
        }
    
    def wait_for_mount(self, device_path, timeout=30):
        """Wait for device to mount"""
        self.log(f"Waiting for {device_path} to mount...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(['findmnt', '-S', device_path, '-o', 'TARGET', '-n'], 
                                      capture_output=True, text=True)
                if result.returncode == 0 and result.stdout.strip():
                    mount_point = result.stdout.strip()
                    self.log(f"✓ Mounted at: {mount_point}")
                    return mount_point
                time.sleep(1)
            except Exception:
                time.sleep(1)
        
        self.log(f"⚠ Mount timeout for {device_path}", 'WARNING')
        return None
    
    def scan_existing_devices(self):
        """Scan existing USB devices"""
        self.log("Checking for existing USB devices...")
        try:
            result = subprocess.run(['lsblk', '-o', 'NAME,FSTYPE,MOUNTPOINT,TRAN', '-J'], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                for device in data.get('blockdevices', []):
                    if device.get('tran') == 'usb':
                        for child in device.get('children', []):
                            fstype = child.get('fstype')
                            mountpoint = child.get('mountpoint')
                            if fstype in ['vfat', 'ntfs', 'exfat', 'ext4', 'ext3'] and mountpoint:
                                device_info = {
                                    'path': f'/dev/{child.get("name")}',
                                    'fs_type': fstype,
                                    'label': child.get('label', 'No Label'),
                                    'vendor': 'Unknown',
                                    'model': 'USB Device'
                                }
                                self.log(f"Found existing device: {mountpoint}")
                                if self.gui:
                                    self.gui.update_device_info(f"Device: USB Storage\nPath: {mountpoint}\nType: {fstype}")
                                threading.Thread(target=self.scan_device, args=(mountpoint, device_info), daemon=True).start()
                                return
        except Exception as e:
            self.log(f"Error checking devices: {e}", 'WARNING')
        
        self.log("No existing USB devices found")
    
    def on_device_event(self, device):
        """Handle device events"""
        if not self.running or self.scanning:
            return
        
        if (device.action == 'add' and 
            device.get('ID_FS_TYPE') in ['vfat', 'ntfs', 'exfat', 'ext4', 'ext3']):
            
            device_info = self.get_device_info(device)
            device_path = device_info['path']
            
            self.log(f"🔌 USB device detected: {device_path}")
            
            if self.gui:
                self.gui.show()
                vendor = device_info['vendor']
                model = device_info['model']
                device_name = f"{vendor} {model}" if vendor != 'Unknown' else 'USB Device'
                self.gui.update_device_info(f"Device: {device_name}\nPath: {device_path}\nType: {device_info['fs_type']}\nMounting...")
                self.gui.update_status("Device detected...", '#f39c12')
            
            mount_point = self.wait_for_mount(device_path)
            if mount_point:
                if self.gui:
                    self.gui.update_device_info(f"Device: {device_name}\nPath: {device_path}\nType: {device_info['fs_type']}\nMount: {mount_point}")
                threading.Thread(target=self.scan_device, args=(mount_point, device_info), daemon=True).start()
            else:
                self.log(f"❌ Mount failed for {device_path}", 'ERROR')
                if self.gui:
                    self.gui.update_status("Mount failed", '#e74c3c')
    
    def scan_device(self, mount_point, device_info):
        """Scan device with ClamAV"""
        if self.scanning:
            self.log("Scan already in progress", 'WARNING')
            return
        
        self.scanning = True
        start_time = datetime.now()
        
        try:
            self.log(f"🔍 Scanning {mount_point}")
            if self.gui:
                self.gui.update_status("Scanning...", '#e67e22')
                self.gui.start_progress()
            
            # Scan command
            command = [
                'sudo', 'clamscan', '-r', '--remove', '--infected',
                '--suppress-ok-results', mount_point
            ]
            
            process = subprocess.Popen(command, stdout=subprocess.PIPE, 
                                     stderr=subprocess.PIPE, text=True)
            
            infected_files = []
            for line in process.stdout:
                line = line.strip()
                if 'FOUND' in line:
                    infected_files.append(line)
                    self.log(f"🦠 THREAT: {line}", 'ERROR')
            
            return_code = process.wait()
            duration = datetime.now() - start_time
            
            if self.gui:
                self.gui.stop_progress()
            
            # Results
            if return_code == 0:
                self.log("✅ Scan complete - No threats", 'SUCCESS')
                if self.gui:
                    self.gui.update_status("Clean", '#27ae60')
            elif return_code == 1:
                self.log(f"⚠️ {len(infected_files)} threats removed", 'WARNING')
                if self.gui:
                    self.gui.update_status(f"Threats removed: {len(infected_files)}", '#e74c3c')
            else:
                self.log(f"⚠️ Scan warnings (code: {return_code})", 'WARNING')
                if self.gui:
                    self.gui.update_status("Scan warnings", '#f39c12')
            
            # Summary
            self.log("=" * 40)
            self.log(f"Device: {mount_point}")
            self.log(f"Duration: {duration}")
            self.log(f"Threats: {len(infected_files)}")
            self.log("=" * 40)
            
            # Save report
            self._save_report(mount_point, device_info, return_code, start_time, duration, infected_files)
            
        except Exception as e:
            if self.gui:
                self.gui.stop_progress()
                self.gui.update_status("Scan failed", '#e74c3c')
            self.log(f"❌ Scan error: {e}", 'ERROR')
        finally:
            self.scanning = False
            if self.gui:
                self.gui.root.after(5000, lambda: self.gui.update_status("Monitoring...", '#3498db'))
    
    def _save_report(self, mount_point, device_info, exit_code, start_time, duration, infected_files):
        """Save scan report"""
        report = {
            'timestamp': start_time.isoformat(),
            'device': device_info,
            'mount_point': mount_point,
            'duration': str(duration),
            'exit_code': exit_code,
            'threats_found': len(infected_files),
            'infected_files': infected_files
        }
        
        timestamp_str = start_time.strftime('%Y%m%d_%H%M%S')
        filename = f"scan_report_{timestamp_str}.json"
        
        # Try multiple save locations
        locations = [
            os.path.join(mount_point, filename),
            os.path.join(os.path.expanduser('~'), 'Desktop', filename),
            f"/tmp/{filename}"
        ]
        
        for location in locations:
            try:
                with open(location, 'w') as f:
                    json.dump(report, f, indent=2)
                self.log(f"📄 Report saved: {location}", 'SUCCESS')
                break
            except Exception:
                continue
    
    def start(self):
        """Start monitoring"""
        if not self.check_dependencies():
            return False
        
        self.log("🛡️ USB Scanner v2.1 started")
        if self.gui:
            self.gui.update_status("Starting...", '#f39c12')
        
        # Check existing devices
        self.scan_existing_devices()
        
        # Update definitions in background
        threading.Thread(target=self.update_virus_definitions, daemon=True).start()
        
        # Start monitoring
        try:
            self.observer = MonitorObserver(self.monitor, callback=self.on_device_event)
            self.observer.daemon = True
            self.observer.start()
            
            self.log("✅ Monitoring active", 'SUCCESS')
            if self.gui:
                self.gui.update_status("Monitoring...", '#3498db')
            return True
        except Exception as e:
            self.log(f"❌ Failed to start: {e}", 'ERROR')
            return False
    
    def run(self):
        """Run the scanner"""
        if not self.start():
            return False
        
        try:
            if self.gui:
                self.gui.root.mainloop()
            else:
                self.log("Running in daemon mode...")
                while self.running:
                    time.sleep(1)
        except KeyboardInterrupt:
            self.log("Stopped by user")
        finally:
            if self.observer:
                self.observer.stop()
            self.log("Scanner stopped")


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='USB Virus Scanner v2.1')
    parser.add_argument('--minimize', action='store_true', help='Start minimized')
    parser.add_argument('--headless', action='store_true', help='No GUI')
    parser.add_argument('--status', action='store_true', help='Show status')
    
    args = parser.parse_args()
    
    if args.status:
        # Check if running
        try:
            result = subprocess.run(['pgrep', '-f', 'usb_scanner.py'], capture_output=True, text=True)
            if result.returncode == 0:
                pids = result.stdout.strip().split('\n')
                print(f"USB Scanner running (PIDs: {', '.join(pids)})")
                sys.exit(0)
            else:
                print("USB Scanner not running")
                sys.exit(1)
        except Exception:
            print("Status check failed")
            sys.exit(1)
    
    # Auto-enable headless if no GUI
    if not args.headless and not GUI_AVAILABLE:
        print("GUI not available, running headless")
        args.headless = True
    
    try:
        scanner = USBScanner(headless=args.headless, minimize=args.minimize)
        success = scanner.run()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()