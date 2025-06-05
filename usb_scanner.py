#!/usr/bin/env python3

import os
import os.path
import threading
import time
import sys
import subprocess
import logging
import json
from datetime import datetime
from pyudev import Context, Monitor, MonitorObserver
import tkinter as tk
from tkinter import ttk, scrolledtext
import queue

class USBScannerGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("USB Virus Scanner")
        self.root.geometry("800x600")
        self.root.configure(bg='#2c3e50')
        
        # Create message queue for thread-safe GUI updates
        self.message_queue = queue.Queue()
        
        self.setup_gui()
        self.setup_logging()
        
    def setup_gui(self):
        """Setup the GUI components"""
        # Main frame
        main_frame = tk.Frame(self.root, bg='#2c3e50')
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Title
        title_label = tk.Label(main_frame, text="USB Virus Scanner", 
                              font=('Arial', 24, 'bold'), 
                              fg='#ecf0f1', bg='#2c3e50')
        title_label.pack(pady=(0, 20))
        
        # Status frame
        status_frame = tk.Frame(main_frame, bg='#34495e', relief=tk.RAISED, bd=2)
        status_frame.pack(fill=tk.X, pady=(0, 20))
        
        # Status label
        tk.Label(status_frame, text="Status:", font=('Arial', 12, 'bold'), 
                fg='#ecf0f1', bg='#34495e').pack(anchor=tk.W, padx=10, pady=5)
        
        self.status_label = tk.Label(status_frame, text="Waiting for USB device...", 
                                    font=('Arial', 11), fg='#3498db', bg='#34495e')
        self.status_label.pack(anchor=tk.W, padx=20, pady=(0, 5))
        
        # Progress bar
        self.progress_var = tk.StringVar()
        self.progress_var.set("Ready")
        self.progress_bar = ttk.Progressbar(status_frame, mode='indeterminate')
        self.progress_bar.pack(fill=tk.X, padx=10, pady=(0, 10))
        
        # Device info frame
        device_frame = tk.Frame(main_frame, bg='#34495e', relief=tk.RAISED, bd=2)
        device_frame.pack(fill=tk.X, pady=(0, 20))
        
        tk.Label(device_frame, text="Device Information:", font=('Arial', 12, 'bold'), 
                fg='#ecf0f1', bg='#34495e').pack(anchor=tk.W, padx=10, pady=5)
        
        self.device_info = tk.Label(device_frame, text="No device connected", 
                                   font=('Arial', 10), fg='#95a5a6', bg='#34495e')
        self.device_info.pack(anchor=tk.W, padx=20, pady=(0, 10))
        
        # Log output
        log_frame = tk.Frame(main_frame, bg='#34495e', relief=tk.RAISED, bd=2)
        log_frame.pack(fill=tk.BOTH, expand=True)
        
        tk.Label(log_frame, text="Scan Log:", font=('Arial', 12, 'bold'), 
                fg='#ecf0f1', bg='#34495e').pack(anchor=tk.W, padx=10, pady=5)
        
        self.log_text = scrolledtext.ScrolledText(log_frame, height=15, 
                                                 bg='#1e1e1e', fg='#00ff00', 
                                                 font=('Courier', 10))
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))
        
        # Control buttons frame
        button_frame = tk.Frame(main_frame, bg='#2c3e50')
        button_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.clear_btn = tk.Button(button_frame, text="Clear Log", 
                                  command=self.clear_log, bg='#e74c3c', 
                                  fg='white', font=('Arial', 10))
        self.clear_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        self.exit_btn = tk.Button(button_frame, text="Exit", 
                                 command=self.exit_app, bg='#c0392b', 
                                 fg='white', font=('Arial', 10))
        self.exit_btn.pack(side=tk.RIGHT)
        
    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/usb_scanner.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def log_message(self, message, level='INFO'):
        """Add message to log display"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        formatted_message = f"[{timestamp}] {level}: {message}\n"
        
        self.log_text.insert(tk.END, formatted_message)
        self.log_text.see(tk.END)
        self.root.update_idletasks()
        
        # Also log to file
        if level == 'ERROR':
            self.logger.error(message)
        elif level == 'WARNING':
            self.logger.warning(message)
        else:
            self.logger.info(message)
    
    def update_status(self, status, color='#3498db'):
        """Update status label"""
        self.status_label.config(text=status, fg=color)
        self.root.update_idletasks()
    
    def update_device_info(self, info):
        """Update device information"""
        self.device_info.config(text=info, fg='#2ecc71')
        self.root.update_idletasks()
    
    def start_progress(self):
        """Start progress bar animation"""
        self.progress_bar.start(10)
    
    def stop_progress(self):
        """Stop progress bar animation"""
        self.progress_bar.stop()
    
    def clear_log(self):
        """Clear the log display"""
        self.log_text.delete(1.0, tk.END)
    
    def exit_app(self):
        """Exit the application"""
        self.root.quit()
        self.root.destroy()


class USBVirusScanner:
    def __init__(self):
        self.gui = USBScannerGUI()
        self.context = Context()
        self.monitor = Monitor.from_netlink(self.context)
        self.monitor.filter_by(subsystem='block', device_type='partition')
        self.observer = None
        self.scanning = False
        
    def check_clamav_installed(self):
        """Check if ClamAV is installed and accessible"""
        try:
            result = subprocess.run(['which', 'clamscan'], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                self.gui.log_message("ClamAV not found! Please install: sudo apt install clamav", 'ERROR')
                return False
            
            # Check if we can run clamscan
            result = subprocess.run(['sudo', '-n', 'clamscan', '--version'], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                self.gui.log_message("Cannot run clamscan with sudo. Check sudoers configuration.", 'ERROR')
                return False
            
            self.gui.log_message("ClamAV is properly configured")
            return True
        except Exception as e:
            self.gui.log_message(f"Error checking ClamAV: {str(e)}", 'ERROR')
            return False
    
    def update_virus_definitions(self):
        """Update ClamAV virus definitions"""
        self.gui.log_message("Updating virus definitions...")
        self.gui.update_status("Updating virus definitions...", '#f39c12')
        self.gui.start_progress()
        
        try:
            result = subprocess.run(['sudo', 'freshclam'], 
                                  capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                self.gui.log_message("Virus definitions updated successfully")
            else:
                self.gui.log_message("Warning: Could not update virus definitions", 'WARNING')
        except subprocess.TimeoutExpired:
            self.gui.log_message("Virus definition update timed out", 'WARNING')
        except Exception as e:
            self.gui.log_message(f"Error updating definitions: {str(e)}", 'WARNING')
        finally:
            self.gui.stop_progress()
            self.gui.update_status("Waiting for USB device...", '#3498db')

    def get_device_info(self, device):
        """Get detailed device information"""
        info = {
            'device_path': device.get('DEVNAME', 'Unknown'),
            'fs_type': device.get('ID_FS_TYPE', 'Unknown'),
            'label': device.get('ID_FS_LABEL', 'No Label'),
            'size': device.get('ID_PART_SIZE', 'Unknown'),
            'vendor': device.get('ID_VENDOR', 'Unknown'),
            'model': device.get('ID_MODEL', 'Unknown')
        }
        return info

    def wait_for_mount(self, dev_path, timeout=30):
        """Wait for device to be mounted with timeout"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(['findmnt', '-S', dev_path, '-o', 'TARGET', '-n'], 
                                      capture_output=True, text=True)
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
                time.sleep(1)
            except Exception:
                time.sleep(1)
        return None

    def on_device_event(self, device):
        """Callback function for device events"""
        if self.scanning:
            return
            
        if (device.action == 'add' and 
            device.get('ID_FS_TYPE') in ['vfat', 'ntfs', 'exfat', 'ext4', 'ext3']):
            
            device_info = self.get_device_info(device)
            dev_path = device_info['device_path']
            
            self.gui.log_message(f"USB device detected: {dev_path}")
            
            # Update GUI with device info
            info_text = (f"Device: {device_info['vendor']} {device_info['model']}\n"
                        f"Path: {dev_path}\n"
                        f"File System: {device_info['fs_type']}\n"
                        f"Label: {device_info['label']}")
            self.gui.update_device_info(info_text)
            
            # Wait for device to be mounted
            self.gui.update_status("Waiting for device to mount...", '#f39c12')
            mount_point = self.wait_for_mount(dev_path)
            
            if mount_point:
                self.gui.log_message(f"Device mounted at: {mount_point}")
                threading.Thread(target=self.scan_device, 
                               args=(mount_point, device_info), 
                               daemon=True).start()
            else:
                self.gui.log_message(f"Could not find mount point for {dev_path}", 'ERROR')
                self.gui.update_status("Mount failed", '#e74c3c')

    def scan_device(self, mount_point, device_info):
        """Scan the device using ClamAV with enhanced feedback"""
        if self.scanning:
            return
            
        self.scanning = True
        scan_start_time = datetime.now()
        
        try:
            self.gui.update_status("Scanning for viruses...", '#e67e22')
            self.gui.start_progress()
            self.gui.log_message(f"Starting scan of {mount_point}")
            
            # Prepare scan command
            command = [
                'sudo', 'clamscan',
                '-r',  # Recursive
                '--remove',  # Remove infected files
                '--bell',  # Sound bell on virus detection
                '--log=/tmp/clamscan_detailed.log',  # Detailed log
                mount_point
            ]
            
            # Run the scan
            result = subprocess.run(command, capture_output=True, text=True)
            
            scan_end_time = datetime.now()
            scan_duration = scan_end_time - scan_start_time
            
            # Parse results
            stdout_lines = result.stdout.split('\n')
            infected_files = []
            total_files = 0
            
            for line in stdout_lines:
                if 'FOUND' in line:
                    infected_files.append(line.strip())
                elif 'scanned' in line.lower() and 'files' in line.lower():
                    try:
                        # Extract number of scanned files
                        words = line.split()
                        for i, word in enumerate(words):
                            if word.isdigit():
                                total_files = int(word)
                                break
                    except:
                        pass
            
            # Display results
            self.gui.stop_progress()
            
            if result.returncode == 0:
                self.gui.update_status("Scan completed - No threats found", '#27ae60')
                self.gui.log_message("✓ Scan completed successfully - No threats detected")
            elif result.returncode == 1:
                self.gui.update_status(f"Threats found and removed: {len(infected_files)}", '#e74c3c')
                self.gui.log_message(f"⚠ {len(infected_files)} threats found and removed:", 'WARNING')
                for infected in infected_files:
                    self.gui.log_message(f"  → {infected}", 'WARNING')
            else:
                self.gui.update_status("Scan completed with errors", '#e67e22')
                self.gui.log_message("Scan completed but encountered some errors", 'WARNING')
            
            # Show summary
            summary = (f"\n--- SCAN SUMMARY ---\n"
                      f"Device: {device_info['vendor']} {device_info['model']}\n"
                      f"Mount Point: {mount_point}\n"
                      f"Files Scanned: {total_files}\n"
                      f"Threats Found: {len(infected_files)}\n"
                      f"Scan Duration: {scan_duration}\n"
                      f"Exit Code: {result.returncode}\n")
            
            self.gui.log_message(summary)
            
            # Save scan report
            self.save_scan_report(mount_point, device_info, result, 
                                scan_start_time, scan_duration, infected_files, total_files)
            
        except Exception as e:
            self.gui.stop_progress()
            self.gui.update_status("Scan failed", '#e74c3c')
            self.gui.log_message(f"Error during scan: {str(e)}", 'ERROR')
        finally:
            self.scanning = False

    def save_scan_report(self, mount_point, device_info, scan_result, 
                        start_time, duration, infected_files, total_files):
        """Save detailed scan report"""
        report = {
            'timestamp': start_time.isoformat(),
            'device_info': device_info,
            'mount_point': mount_point,
            'scan_duration': str(duration),
            'total_files_scanned': total_files,
            'threats_found': len(infected_files),
            'infected_files': infected_files,
            'exit_code': scan_result.returncode,
            'scan_output': scan_result.stdout
        }
        
        # Try to save to USB device first
        report_filename = f"usb_scan_report_{start_time.strftime('%Y%m%d_%H%M%S')}.json"
        usb_report_path = os.path.join(mount_point, report_filename)
        desktop_report_path = os.path.join(os.path.expanduser('~'), 'Desktop', report_filename)
        
        try:
            with open(usb_report_path, 'w') as f:
                json.dump(report, f, indent=2)
            self.gui.log_message(f"Report saved to USB: {report_filename}")
        except Exception as e:
            try:
                with open(desktop_report_path, 'w') as f:
                    json.dump(report, f, indent=2)
                self.gui.log_message(f"Report saved to Desktop: {report_filename}")
            except Exception as e2:
                self.gui.log_message(f"Failed to save report: {str(e2)}", 'ERROR')

    def start_monitoring(self):
        """Start monitoring for USB devices"""
        if not self.check_clamav_installed():
            return False
            
        self.gui.log_message("USB Virus Scanner started")
        self.gui.log_message("Monitoring USB ports for removable devices...")
        
        # Update virus definitions on startup
        threading.Thread(target=self.update_virus_definitions, daemon=True).start()
        
        # Start device monitoring
        self.observer = MonitorObserver(self.monitor, 
                                       callback=self.on_device_event, 
                                       name='usb-monitor')
        self.observer.daemon = True
        self.observer.start()
        
        return True

    def run(self):
        """Run the scanner application"""
        if self.start_monitoring():
            try:
                self.gui.root.mainloop()
            except KeyboardInterrupt:
                self.gui.log_message("Scanner stopped by user")
            finally:
                if self.observer:
                    self.observer.stop()
        else:
            self.gui.log_message("Failed to start scanner", 'ERROR')
            self.gui.root.after(5000, self.gui.exit_app)  # Auto-close after 5 seconds


if __name__ == "__main__":
    try:
        scanner = USBVirusScanner()
        scanner.run()
    except Exception as e:
        print(f"Fatal error: {str(e)}")
        sys.exit(1)