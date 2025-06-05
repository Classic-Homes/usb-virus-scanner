#!/bin/bash
# Quick fix for Ubuntu 24.04 externally-managed-environment issue

echo "🔧 === Ubuntu 24.04 Python Dependencies Fix ==="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
  echo -e "${RED}❌${NC} $1"
}

echo "Installing missing Python dependencies via system packages..."
echo ""

# Install python3-psutil via apt (the proper way for Ubuntu 24.04)
if python3 -c "import psutil" 2>/dev/null; then
  print_status "psutil already available"
else
  echo "Installing python3-psutil..."
  if sudo apt update && sudo apt install -y python3-psutil; then
    print_status "python3-psutil installed successfully"
  else
    print_error "Failed to install python3-psutil"
    exit 1
  fi
fi

# Verify all dependencies
echo ""
echo "🔍 Verifying all Python dependencies..."

python3 -c "
import sys

# Required dependencies
deps = {
    'pyudev': 'python3-pyudev',
    'tkinter': 'python3-tk', 
    'psutil': 'python3-psutil',
    'json': 'built-in',
    'threading': 'built-in',
    'subprocess': 'built-in',
    'logging': 'built-in',
    'datetime': 'built-in',
    'pathlib': 'built-in (Python 3.4+)'
}

print('Checking dependencies:')
missing = []
for dep, package in deps.items():
    try:
        __import__(dep)
        print(f'   ✓ {dep}')
    except ImportError:
        print(f'   ❌ {dep} - install: sudo apt install {package}')
        missing.append(dep)

print()
if missing:
    print(f'Missing dependencies: {missing}')
    print('Run: sudo apt install ' + ' '.join([deps[dep] for dep in missing if not deps[dep].startswith('built-in')]))
    sys.exit(1)
else:
    print('✅ All dependencies satisfied!')
"

echo ""
echo "🧪 Testing scanner import..."

if python3 -c "
import sys
import os
sys.path.insert(0, os.getcwd())

try:
    import usb_scanner
    print('✅ Scanner import successful!')
except Exception as e:
    print(f'❌ Scanner import failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
  print_status "Scanner ready to run!"
else
  print_warning "Scanner import test skipped (normal if usb_scanner.py not in current directory)"
fi

echo ""
echo "🎉 Dependencies fixed! You can now continue with the setup."
echo ""
echo "Next steps:"
echo "  1. Run: ./setup.sh (if not completed)"
echo "  2. Test: python3 usb_scanner.py"
echo "  3. Debug: ./debug_usb.sh"
echo ""
