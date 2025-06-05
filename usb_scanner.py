#!/usr/bin/env python3
"""
Enhanced USB Virus Scanner v2.1
Advanced Python application for automatically scanning USB drives using ClamAV
Compatible with SSH installation and GUI auto-launch
"""

import os
import threading
import time
import sys
import subprocess
import logging
import json
import signal
import psutil
from datetime import datetime
from pathlib import Path

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
    print("Warning: tkinter not available. GUI mode disabled.")

import queue

class USBScannerGUI:
    def __init__(self, minimize=False):
        if not GUI_AVAILABLE:
            raise RuntimeError("GUI not available - tkinter not installed")
            
        self.root = tk.Tk()
        self.root.title("Enhanced USB Virus Scanner v2.1")
        self.root.geometry("900x700")
        self.root.configure(bg='#1a1a1a')
        
        # Set window icon and properties
        self.root.resizable(True, True)
        self.root.minsize(700, 500)
        
        # Handle minimize flag for autostart
        if minimize:
            self.root.withdraw()
            self.minimized = True
        else:
            self.minimized = False
            
        # Bind window close event
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        # Create message queue for thread-safe GUI updates
        self.message_queue = queue.Queue()
        
        self.setup_gui()
        self.setup_logging()
        
        # Start message queue processor
        self.process_message_queue()
        
    def setup_gui(self):
        """Setup the modern GUI components"""
        # Configure styles
        style = ttk.Style()
        style.theme_use('clam')
        
        # Configure custom styles
        style.configure('Title.TLabel', background='#1a1a1a', foreground='#ffffff', font=('Arial', 20, 'bold'))
        style.configure('Header.TLabel', background='#2d2d2d', foreground='#ffffff', font=('Arial', 12, 'bold'))
        style.configure('Info.TLabel', background='#2d2d2d', foreground='#cccccc', font=('Arial', 10))
        
        # Main container
        main_frame = tk.Frame(self.root, bg='#1a1a1a')
        main_frame.pack(fill=tk.BOTH, expand=True, padx=15, pady=15)
        
        # Header section
        header_frame = tk.Frame(main_frame, bg='#1a1a1a')
        header_frame.pack(fill=tk.X, pady=(0, 20))
        
        # Title with icon
        title_frame = tk.Frame(header_frame, bg='#1a1a1a')
        title_frame.pack(fill=tk.X)
        
        title_label = tk.Label(title_frame, text="🛡️ Enhanced USB Virus Scanner", 
                              font=('Arial', 22, 'bold'), 
                              fg='#00ff88', bg='#1a1a1a')
        title_label.pack(side=tk.LEFT)
        
        version_label = tk.Label(title_frame, text="v2.1", 
                                font=('Arial', 10), 
                                fg='#888888', bg='#1a1a1a')
        version_label.pack(side=tk.RIGHT, anchor=tk.E)
        
        # Status section
        status_frame = tk.LabelFrame(main_frame, text="Scanner Status", 
                                   bg='#2d2d2d', fg='#ffffff', 
                                   font=('Arial', 12, 'bold'), bd=2, relief=tk.GROOVE)
        status_frame.pack(fill=tk.X, pady=(0, 15))
        
        status_inner = tk.Frame(status_frame, bg='#2d2d2d')
        status_inner.pack(fill=tk.X, padx=10, pady=10)
        
        # Status indicator
        self.status_indicator = tk.Label(status_inner, text="●", 
                                       font=('Arial', 16), 
                                       fg='#3498db', bg='#2d2d2d')
        self.status_indicator.pack(side=tk.LEFT, padx=(0, 10))
        
        self.status_label = tk.Label(status_inner, text="Initializing scanner...", 
                                   font=('Arial', 11, 'bold'), 
                                   fg='#ffffff', bg='#2d2d2d')
        self.status_label.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        # Progress bar
        self.progress_bar = ttk.Progressbar(status_inner, mode='indeterminate', length=200)
        self.progress_bar.pack(side=tk.RIGHT)
        
        # Device information section
        device_frame = tk.LabelFrame(main_frame, text="Device Information", 
                                   bg='#2d2d2d', fg='#ffffff', 
                                   font=('Arial', 12, 'bold'), bd=2, relief=tk.GROOVE)
        device_frame.pack(fill=tk.X, pady=(0, 15))
        
        device_inner = tk.Frame(device_frame, bg='#2d2d2d')
        device_inner.pack(fill=tk.X, padx=10, pady=10)
        
        self.device_info = tk.Label(device_inner, text="No USB device detected", 
                                  font=('Arial', 10), 
                                  fg='#cccccc', bg='#2d2d2d',
                                  justify=tk.LEFT, anchor=tk.W)
        self.device_info.pack(fill=tk.X)
        
        # Statistics section
        stats_frame = tk.LabelFrame(main_frame, text="Scan Statistics", 
                                  bg='#2d2d2d', fg='#ffffff', 
                                  font=('Arial', 12, 'bold'), bd=2, relief=tk.GROOVE)
        stats_frame.pack(fill=tk.X, pady=(0, 15))
        
        stats_inner = tk.Frame(stats_frame, bg='#2d2d2d')
        stats_inner.pack(fill=tk.X, padx=10, pady=10)
        
        # Create stats grid
        stats_grid = tk.Frame(stats_inner, bg='#2d2d2d')
        stats_grid.pack(fill=tk.X)
        
        # Stats labels
        tk.Label(stats_grid, text="Files Scanned:", fg='#cccccc', bg='#2d2d2d', font=('Arial', 9)).grid(row=0, column=0, sticky=tk.W, padx=(0, 10))
        self.files_scanned_label = tk.Label(stats_grid, text="0", fg='#ffffff', bg='#2d2d2d', font=('Arial', 9, 'bold'))
        self.files_scanned_label.grid(row=0, column=1, sticky=tk.W, padx=(0, 20))
        
        tk.Label(stats_grid, text="Threats Found:", fg='#cccccc', bg='#2d2d2d', font=('Arial', 9)).grid(row=0, column=2, sticky=tk.W, padx=(0, 10))
        self.threats_found_label = tk.Label(stats_grid, text="0", fg='#27ae60', bg='#2d2d2d', font=('Arial', 9, 'bold'))
        self.threats_found_label.grid(row=0, column=3, sticky=tk.W, padx=(0, 20))
        
        tk.Label(stats_grid, text="Scan Time:", fg='#cccccc', bg='#2d2d2d', font=('Arial', 9)).grid(row=0, column=4, sticky=tk.W, padx=(0, 10))
        self.scan_time_label = tk.Label(stats_grid, text="--", fg='#ffffff', bg='#2d2d2d', font=('Arial', 9, 'bold'))
        self.scan_time_label.grid(row=0, column=5, sticky=tk.W)
        
        # Log output section
        log_frame = tk.LabelFrame(main_frame, text="Activity Log", 
                                bg='#2d2d2d', fg='#ffffff', 
                                font=('Arial', 12, 'bold'), bd=2, relief=tk.GROOVE)
        log_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        log_inner = tk.Frame(log_frame, bg='#2d2d2d')
        log_inner.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Log text widget with custom colors
        self.log_text = scrolledtext.ScrolledText(
            log_inner, 
            height=12, 
            bg='#0a0a0a', 
            fg='#00ff88', 
            font=('Consolas', 9),
            insertbackground='#ffffff',
            selectbackground='#444444',
            wrap=tk.WORD
        )
        self.log_text.pack(fill=tk.BOTH, expand=True)
        
        # Configure text tags for colored logging
        self.log_text.tag_configure('INFO', foreground='#00ff88')
        self.log_text.tag_configure('WARNING', foreground='#ffaa00')
        self.log_text.tag_configure('ERROR', foreground='#ff4444')
        self.log_text.tag_configure('SUCCESS', foreground='#00ffff')
        self.log_text.tag_configure('TIMESTAMP', foreground='#888888')
        
        # Control buttons
        button_frame = tk.Frame(main_frame, bg='#1a1a1a')
        button_frame.pack(fill=tk.X)
        
        # Left side buttons
        left_buttons = tk.Frame(button_frame, bg='#1a1a1a')
        left_buttons.pack(side=tk.LEFT)
        
        self.clear_btn = tk.Button(left_buttons, text="Clear Log", 
                                 command=self.clear_log, 
                                 bg='#e74c3c', fg='white', 
                                 font=('Arial', 10), 
                                 relief=tk.FLAT, padx=20)
        self.clear_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        self.minimize_btn = tk.Button(left_buttons, text="Minimize", 
                                    command=self.minimize_window, 
                                    bg='#3498db', fg='white', 
                                    font=('Arial', 10), 
                                    relief=tk.FLAT, padx=20)
        self.minimize_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Right side buttons
        right_buttons = tk.Frame(button_frame, bg='#1a1a1a')
        right_buttons.pack(side=tk.RIGHT)
        
        self.exit_btn = tk.Button(right_buttons, text="Exit", 
                                command=self.exit_app, 
                                bg='#c0392b', fg='white', 
                                font=('Arial', 10), 
                                relief=tk.FLAT, padx=20)
        self.exit_btn.pack(side=tk.RIGHT)
        
    def setup_logging(self):
        """Setup logging configuration"""
        # Ensure log directory exists
        log_dir = Path('/var/log')
        if not log_dir.exists() or not os.access(log_dir, os.W_OK):
            log_dir = Path.home() / '.local' / 'share' / 'usb-scanner'
            log_dir.mkdir(parents=True, exist_ok=True)
            
        log_file = log_dir / 'usb_scanner.log'
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(str(log_file)),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def process_message_queue(self):
        """Process messages from other threads"""
        try:
            while True:
                message, level = self.message_queue.get_nowait()
                self._log_message_internal(message, level)
        except queue.Empty:
            pass
        finally:
            # Schedule next check
            self.root.after(100, self.process_message_queue)
    
    def log_message(self, message, level='INFO'):
        """Thread-safe log message method"""
        self.message_queue.put((message, level))
        
    def _log_message_internal(self, message, level='INFO'):
        """Internal method to actually update the log display"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        
        # Insert timestamp
        self.log_text.insert(tk.END, f"[{timestamp}] ", 'TIMESTAMP')
        
        # Insert level indicator
        level_indicators = {
            'INFO': '🔵',
            'WARNING': '🟡', 
            'ERROR': '🔴',
            'SUCCESS': '🟢'
        }
        indicator = level_indicators.get(level, '🔵')
        self.log_text.insert(tk.END, f"{indicator} ")
        
        # Insert message
        self.log_text.insert(tk.END, f"{message}\n", level)
        
        # Auto-scroll to bottom
        self.log_text.see(tk.END)
        self.root.update_idletasks()
        
        # Log to file
        if level == 'ERROR':
            self.logger.error(message)
        elif level == 'WARNING':
            self.logger.warning(message)
        else:
            self.logger.info(message)
    
    def update_status(self, status, color='#3498db', indicator_color=None):
        """Update status label and indicator"""
        self.status_label.config(text=status)
        if indicator_color:
            self.status_indicator.config(fg=indicator_color)
        self.root.update_idletasks()
    
    def update_device_info(self, info):
        """Update device information display"""
        self.device_info.config(text=info, fg='#2ecc71')
        self.root.update_idletasks()
    
    def update_stats(self, files_scanned=None, threats_found=None, scan_time=None):
        """Update scan statistics"""
        if files_scanned is not None:
            self.files_scanned_label.config(text=str(files_scanned))
        if threats_found is not None:
            color = '#e74c3c' if threats_found > 0 else '#27ae60'
            self.threats_found_label.config(text=str(threats_found), fg=color)
        if scan_time is not None:
            self.scan_time_label.config(text=scan_time)
        self.root.update_idletasks()
    
    def start_progress(self):
        """Start progress bar animation"""
        self.progress_bar.start(10)
    
    def stop_progress(self):
        """Stop progress bar animation"""
        self.progress_bar.stop()
    
    def show_window(self):
        """Show the window if minimized"""
        if self.minimized:
            self.root.deiconify()
            self.root.lift()
            self.root.focus_force()
            self.minimized = False
    
    def minimize_window(self):
        """Minimize the window"""
        self.root.withdraw()
        self.minimized = True
    
    def clear_log(self):
        """Clear the log display"""
        self.log_text.delete(1.0, tk.END)
        self.log_message("Log cleared", 'INFO')
    
    def on_closing(self):
        """Handle window close event"""
        if messagebox.askokcancel("Quit", "Do you want to quit the USB Scanner?"):
            self.exit_app()
    
    def exit_app(self):
        """Exit the application"""
        self.root.quit()
        self.root.destroy()


class USBVirusScanner:
    def __init__(self, headless=False, minimize=False, daemon=False):
        self.headless = headless or daemon
        self.daemon = daemon
        
        # Setup GUI if not in headless mode
        if not self.headless and GUI_AVAILABLE:
            self.gui = USBScannerGUI(minimize)
        else:
            self.gui = None
            
        # Initialize USB monitoring
        self.context = Context()
        self.monitor = Monitor.from_netlink(self.context)
        self.monitor.filter_by(subsystem='block', device_type='partition')
        self.observer = None
        self.scanning = False
        self.running = True
        
        # Setup signal handlers for daemon mode
        if self.daemon:
            signal.signal(signal.SIGTERM, self._signal_handler)
            signal.signal(signal.SIGINT, self._signal_handler)
        
        # Setup console logging for headless mode
        if self.headless:
            self.setup_console_logging()
            
    def setup_console_logging(self):
        """Setup logging for headless/daemon mode"""
        log_dir = Path('/var/log')
        if not log_dir.exists() or not os.access(log_dir, os.W_OK):
            log_dir = Path.home() / '.local' / 'share' / 'usb-scanner'
            log_dir.mkdir(parents=True, exist_ok=True)
            
        log_file = log_dir / 'usb_scanner.log'
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(str(log_file)),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.log_message(f"Received signal {signum}, shutting down...")
        self.running = False
        if self.observer:
            self.observer.stop()
        sys.exit(0)
        
    def log_message(self, message, level='INFO'):
        """Log message to GUI or console"""
        if self.gui:
            self.gui.log_message(message, level)
        else:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] {level}: {message}")
            if hasattr(self, 'logger'):
                if level == 'ERROR':
                    self.logger.error(message)
                elif level == 'WARNING':
                    self.logger.warning(message)
                else:
                    self.logger.info(message)
    
    def check_dependencies(self):
        """Check all required dependencies"""
        missing_deps = []
        
        # Check ClamAV
        try:
            result = subprocess.run(['which', 'clamscan'], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                missing_deps.append("clamscan (install: sudo apt install clamav)")
        except Exception:
            missing_deps.append("clamscan (install: sudo apt install clamav)")
            
        # Check sudo permissions
        try:
            result = subprocess.run(['sudo', '-n', 'clamscan', '--version'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                missing_deps.append("sudo permissions for clamscan (run setup.sh)")
        except Exception:
            missing_deps.append("sudo permissions for clamscan (run setup.sh)")
            
        # Check Python dependencies
        try:
            import pyudev
        except ImportError:
            missing_deps.append("python3-pyudev (install: sudo apt install python3-pyudev)")
            
        if missing_deps:
            self.log_message("Missing dependencies:", 'ERROR')
            for dep in missing_deps:
                self.log_message(f"  - {dep}", 'ERROR')
            return False
            
        self.log_message("✓ All dependencies satisfied")
        return True
    
    def update_virus_definitions(self):
        """Update ClamAV virus definitions"""
        self.log_message("Updating virus definitions...")
        if self.gui:
            self.gui.update_status("Updating virus definitions...", indicator_color='#f39c12')
            self.gui.start_progress()
        
        try:
            result = subprocess.run(['sudo', 'freshclam'], 
                                  capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                self.log_message("✓ Virus definitions updated successfully", 'SUCCESS')
            else:
                self.log_message("⚠ Could not update virus definitions", 'WARNING')
                if result.stderr:
                    self.log_message(f"Error: {result.stderr.strip()}", 'WARNING')
        except subprocess.TimeoutExpired:
            self.log_message("⚠ Virus definition update timed out", 'WARNING')
        except Exception as e:
            self.log_message(f"⚠ Error updating definitions: {str(e)}", 'WARNING')
        finally:
            if self.gui:
                self.gui.stop_progress()
                self.gui.update_status("Monitoring for USB devices...", indicator_color='#3498db')

    def get_device_info(self, device):
        """Get detailed device information"""
        info = {
            'device_path': device.get('DEVNAME', 'Unknown'),
            'fs_type': device.get('ID_FS_TYPE', 'Unknown'),
            'label': device.get('ID_FS_LABEL', 'No Label'),
            'size': device.get('ID_PART_SIZE', 'Unknown'),
            'vendor': device.get('ID_VENDOR', 'Unknown'),
            'model': device.get('ID_MODEL', 'Unknown'),
            'uuid': device.get('ID_FS_UUID', 'Unknown')
        }
        return info

    def wait_for_mount(self, dev_path, timeout=30):
        """Wait for device to be mounted with timeout"""
        self.log_message(f"Waiting for {dev_path} to mount...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                # Check multiple mount detection methods
                result = subprocess.run(['findmnt', '-S', dev_path, '-o', 'TARGET', '-n'], 
                                      capture_output=True, text=True)
                if result.returncode == 0 and result.stdout.strip():
                    mount_point = result.stdout.strip()
                    self.log_message(f"✓ Device mounted at: {mount_point}")
                    return mount_point
                    
                # Alternative: check /proc/mounts
                with open('/proc/mounts', 'r') as f:
                    for line in f:
                        if dev_path in line:
                            parts = line.split()
                            if len(parts) >= 2:
                                mount_point = parts[1]
                                self.log_message(f"✓ Device found in /proc/mounts: {mount_point}")
                                return mount_point
                                
                time.sleep(1)
            except Exception as e:
                self.log_message(f"Error checking mount: {e}", 'WARNING')
                time.sleep(1)
                
        self.log_message(f"⚠ Timeout waiting for {dev_path} to mount", 'WARNING')
        return None

    def scan_existing_usb_devices(self):
        """Scan for USB devices that are already connected"""
        self.log_message("Checking for existing USB devices...")
        
        try:
            result = subprocess.run(['lsblk', '-o', 'NAME,FSTYPE,MOUNTPOINT,TRAN,SIZE,LABEL', '-J'], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                import json
                data = json.loads(result.stdout)
                
                for device in data.get('blockdevices', []):
                    if device.get('tran') == 'usb':
                        for child in device.get('children', []):
                            fstype = child.get('fstype')
                            mountpoint = child.get('mountpoint')
                            
                            if fstype and mountpoint and fstype in ['vfat', 'ntfs', 'exfat', 'ext4', 'ext3']:
                                device_name = child.get('name')
                                self.log_message(f"Found existing USB device: {device_name} at {mountpoint}")
                                
                                # Create device info
                                device_info = {
                                    'device_path': f'/dev/{device_name}',
                                    'fs_type': fstype,
                                    'label': child.get('label', 'No Label'),
                                    'size': child.get('size', 'Unknown'),
                                    'vendor': 'Unknown',
                                    'model': 'USB Device'
                                }
                                
                                # Update GUI
                                if self.gui:
                                    info_text = self._format_device_info(device_info, mountpoint)
                                    self.gui.update_device_info(info_text)
                                
                                # Start scanning
                                threading.Thread(target=self.scan_device, 
                                               args=(mountpoint, device_info), 
                                               daemon=True).start()
                                return
                                
        except Exception as e:
            self.log_message(f"Error checking existing USB devices: {str(e)}", 'WARNING')
        
        self.log_message("No existing USB devices found to scan")

    def _format_device_info(self, device_info, mount_point):
        """Format device information for display"""
        vendor = device_info.get('vendor', 'Unknown')
        model = device_info.get('model', 'Unknown')
        
        if vendor == 'Unknown' and model == 'Unknown':
            device_name = "USB Storage Device"
        elif vendor == 'Unknown':
            device_name = model
        elif model == 'Unknown':
            device_name = vendor
        else:
            device_name = f"{vendor} {model}"
            
        info_lines = [
            f"Device: {device_name}",
            f"Path: {device_info['device_path']}",
            f"File System: {device_info['fs_type']}",
            f"Label: {device_info['label']}",
            f"Mount Point: {mount_point}"
        ]
        
        if device_info.get('size') != 'Unknown':
            info_lines.append(f"Size: {device_info['size']}")
            
        return "\n".join(info_lines)

    def on_device_event(self, device):
        """Callback function for device events"""
        if not self.running or self.scanning:
            return
            
        if (device.action == 'add' and 
            device.get('ID_FS_TYPE') in ['vfat', 'ntfs', 'exfat', 'ext4', 'ext3']):
            
            device_info = self.get_device_info(device)
            dev_path = device_info['device_path']
            
            self.log_message(f"🔌 USB device detected: {dev_path}")
            
            # Show GUI window if minimized
            if self.gui:
                self.gui.show_window()
                
                # Update device info display
                info_text = self._format_device_info(device_info, "Mounting...")
                self.gui.update_device_info(info_text)
                self.gui.update_status("Device detected, waiting for mount...", indicator_color='#f39c12')
            
            # Wait for device to mount
            mount_point = self.wait_for_mount(dev_path)
            
            if mount_point:
                if self.gui:
                    info_text = self._format_device_info(device_info, mount_point)
                    self.gui.update_device_info(info_text)
                    
                # Start scanning in separate thread
                threading.Thread(target=self.scan_device, 
                               args=(mount_point, device_info), 
                               daemon=True).start()
            else:
                self.log_message(f"❌ Could not find mount point for {dev_path}", 'ERROR')
                if self.gui:
                    self.gui.update_status("Mount failed", indicator_color='#e74c3c')

    def scan_device(self, mount_point, device_info):
        """Scan device using ClamAV with enhanced feedback and reporting"""
        if self.scanning:
            self.log_message("Scan already in progress, skipping", 'WARNING')
            return
            
        self.scanning = True
        scan_start_time = datetime.now()
        
        try:
            self.log_message(f"🔍 Starting comprehensive scan of {mount_point}")
            
            if self.gui:
                self.gui.update_status("Scanning for viruses...", indicator_color='#e67e22')
                self.gui.start_progress()
                self.gui.update_stats(files_scanned=0, threats_found=0, scan_time="--")
            
            # Prepare comprehensive scan command
            detailed_log = f"/tmp/clamscan_detailed_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
            
            command = [
                'sudo', 'clamscan',
                '-r',                    # Recursive
                '--remove',              # Remove infected files
                '--bell',                # Bell on detection
                '--verbose',             # Verbose output
                '--log=' + detailed_log, # Detailed log
                '--infected',            # Show only infected files
                '--suppress-ok-results', # Don't show OK results
                mount_point
            ]
            
            self.log_message(f"Command: {' '.join(command[2:])}")  # Don't log sudo
            
            # Run scan with real-time output processing
            process = subprocess.Popen(command, 
                                     stdout=subprocess.PIPE, 
                                     stderr=subprocess.PIPE, 
                                     text=True, 
                                     bufsize=1, 
                                     universal_newlines=True)
            
            infected_files = []
            total_files = 0
            
            # Process output in real-time
            for line in process.stdout:
                line = line.strip()
                if not line:
                    continue
                    
                if 'FOUND' in line:
                    infected_files.append(line)
                    self.log_message(f"🦠 THREAT FOUND: {line}", 'ERROR')
                    if self.gui:
                        self.gui.update_stats(threats_found=len(infected_files))
                elif 'scanned' in line.lower():
                    # Try to extract file count
                    try:
                        parts = line.split()
                        for part in parts:
                            if part.isdigit():
                                total_files = int(part)
                                if self.gui:
                                    self.gui.update_stats(files_scanned=total_files)
                                break
                    except:
                        pass
            
            # Wait for process to complete
            return_code = process.wait()
            
            scan_end_time = datetime.now()
            scan_duration = scan_end_time - scan_start_time
            
            # Update final statistics
            if self.gui:
                self.gui.stop_progress()
                self.gui.update_stats(scan_time=str(scan_duration).split('.')[0])
            
            # Process results
            if return_code == 0:
                self.log_message("✅ Scan completed successfully - No threats detected", 'SUCCESS')
                if self.gui:
                    self.gui.update_status("Scan completed - Clean", indicator_color='#27ae60')
            elif return_code == 1:
                self.log_message(f"⚠️ {len(infected_files)} threats found and removed", 'WARNING')
                if self.gui:
                    self.gui.update_status(f"Threats neutralized: {len(infected_files)}", indicator_color='#e74c3c')
            else:
                self.log_message(f"⚠️ Scan completed with warnings (exit code: {return_code})", 'WARNING')
                if self.gui:
                    self.gui.update_status("Scan completed with warnings", indicator_color='#f39c12')
            
            # Show detailed summary
            summary_lines = [
                "=" * 50,
                "SCAN SUMMARY",
                "=" * 50,
                f"Device: {device_info.get('vendor', 'Unknown')} {device_info.get('model', 'Unknown')}",
                f"Mount Point: {mount_point}",
                f"File System: {device_info.get('fs_type', 'Unknown')}",
                f"Files Scanned: {total_files:,}",
                f"Threats Found: {len(infected_files)}",
                f"Scan Duration: {scan_duration}",
                f"Exit Code: {return_code}",
                "=" * 50
            ]
            
            for line in summary_lines:
                self.log_message(line, 'INFO')
            
            # List infected files if any
            if infected_files:
                self.log_message("INFECTED FILES:", 'ERROR')
                for infected in infected_files:
                    self.log_message(f"  → {infected}", 'ERROR')
            
            # Save detailed report
            self.save_scan_report(mount_point, device_info, return_code, 
                                scan_start_time, scan_duration, infected_files, total_files)
            
        except Exception as e:
            if self.gui:
                self.gui.stop_progress()
                self.gui.update_status("Scan failed", indicator_color='#e74c3c')
            self.log_message(f"❌ Error during scan: {str(e)}", 'ERROR')
        finally:
            self.scanning = False
            # Reset status after delay
            if self.gui:
                self.gui.root.after(5000, lambda: self.gui.update_status("Monitoring for USB devices...", indicator_color='#3498db'))

    def save_scan_report(self, mount_point, device_info, exit_code, 
                        start_time, duration, infected_files, total_files):
        """Save comprehensive scan report"""
        report = {
            'scan_info': {
                'timestamp': start_time.isoformat(),
                'scanner_version': '2.1',
                'scan_duration': str(duration),
                'exit_code': exit_code
            },
            'device_info': device_info,
            'mount_point': mount_point,
            'results': {
                'total_files_scanned': total_files,
                'threats_found': len(infected_files),
                'infected_files': infected_files,
                'status': 'clean' if exit_code == 0 else 'threats_found' if exit_code == 1 else 'warnings'
            },
            'system_info': {
                'hostname': subprocess.run(['hostname'], capture_output=True, text=True).stdout.strip(),
                'scanner_user': os.getenv('USER', 'unknown'),
                'python_version': sys.version,
                'platform': sys.platform
            }
        }
        
        # Generate report filename
        timestamp_str = start_time.strftime('%Y%m%d_%H%M%S')
        report_filename = f"usb_scan_report_{timestamp_str}.json"
        
        # Try to save to USB device first, then fallback locations
        save_locations = [
            os.path.join(mount_point, report_filename),
            os.path.join(os.path.expanduser('~'), 'Desktop', report_filename),
            os.path.join(os.path.expanduser('~'), report_filename),
            f"/tmp/{report_filename}"
        ]
        
        saved = False
        for location in save_locations:
            try:
                with open(location, 'w') as f:
                    json.dump(report, f, indent=2)
                self.log_message(f"📄 Report saved: {location}", 'SUCCESS')
                saved = True
                break
            except Exception as e:
                continue
                
        if not saved:
            self.log_message("❌ Failed to save scan report to any location", 'ERROR')

    def start_monitoring(self):
        """Start USB device monitoring"""
        if not self.check_dependencies():
            return False
            
        self.log_message("🛡️ Enhanced USB Virus Scanner v2.1 started")
        self.log_message("Initializing USB monitoring system...")
        
        # Update status in GUI
        if self.gui:
            self.gui.update_status("Starting scanner...", indicator_color='#f39c12')
        
        # Check for existing USB devices
        self.scan_existing_usb_devices()
        
        # Update virus definitions in background
        threading.Thread(target=self.update_virus_definitions, daemon=True).start()
        
        # Start USB device monitoring
        try:
            self.observer = MonitorObserver(self.monitor, 
                                          callback=self.on_device_event, 
                                          name='usb-monitor')
            self.observer.daemon = True
            self.observer.start()
            
            self.log_message("✅ USB monitoring active - Insert USB device to scan", 'SUCCESS')
            if self.gui:
                self.gui.update_status("Monitoring for USB devices...", indicator_color='#3498db')
            return True
            
        except Exception as e:
            self.log_message(f"❌ Failed to start USB monitoring: {str(e)}", 'ERROR')
            return False

    def run(self):
        """Run the scanner application"""
        if not self.start_monitoring():
            self.log_message("❌ Failed to start scanner", 'ERROR')
            if self.gui:
                self.gui.root.after(5000, self.gui.exit_app)
            return False
        
        try:
            if self.gui:
                # GUI mode
                self.gui.root.mainloop()
            else:
                # Daemon mode - keep running
                self.log_message("Running in daemon mode...")
                while self.running:
                    time.sleep(1)
        except KeyboardInterrupt:
            self.log_message("Scanner stopped by user")
        finally:
            if self.observer:
                self.observer.stop()
            self.log_message("Scanner shutdown complete")


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Enhanced USB Virus Scanner v2.1')
    parser.add_argument('--minimize', action='store_true', 
                       help='Start minimized (for autostart)')
    parser.add_argument('--headless', action='store_true', 
                       help='Run without GUI (console mode)')
    parser.add_argument('--daemon', action='store_true', 
                       help='Run as daemon service')
    parser.add_argument('--status', action='store_true', 
                       help='Show scanner status')
    
    args = parser.parse_args()
    
    if args.status:
        # Show status of running scanner
        pids = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if 'usb_scanner.py' in ' '.join(proc.info['cmdline'] or []):
                    pids.append(proc.info['pid'])
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        if pids:
            print(f"USB Scanner running (PIDs: {', '.join(map(str, pids))})")
            sys.exit(0)
        else:
            print("USB Scanner not running")
            sys.exit(1)
    
    # Check for GUI availability when needed
    if not args.headless and not args.daemon and not GUI_AVAILABLE:
        print("Warning: GUI not available, running in headless mode")
        args.headless = True
    
    try:
        scanner = USBVirusScanner(
            headless=args.headless, 
            minimize=args.minimize, 
            daemon=args.daemon
        )
        
        success = scanner.run()
        sys.exit(0 if success else 1)
        
    except Exception as e:
        print(f"Fatal error: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()