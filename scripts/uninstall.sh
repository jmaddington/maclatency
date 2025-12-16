#!/bin/bash
# MacThrottle Helper Uninstallation Script
# Run with: sudo ./uninstall.sh

set -e

echo "Uninstalling MacThrottle Thermal Monitor..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

# Stop and unload the daemon
echo "Stopping thermal monitor daemon..."
launchctl unload /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist 2>/dev/null || true

# Remove files
echo "Removing files..."
rm -f /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist
rm -f /usr/local/bin/mac-throttle-thermal-monitor
rm -f /tmp/mac-throttle-thermal-state
rm -f /tmp/mac-throttle-thermal-monitor.err

echo ""
echo "Uninstallation complete!"
