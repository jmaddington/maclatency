#!/bin/bash
# MacThrottle Helper Installation Script
# Run with: sudo ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_DIR="$(dirname "$SCRIPT_DIR")/Helper"

echo "Installing MacThrottle Thermal Monitor..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

# Copy the monitor script
echo "Installing thermal monitor script..."
cp "$HELPER_DIR/thermal-monitor.sh" /usr/local/bin/mac-throttle-thermal-monitor
chmod 755 /usr/local/bin/mac-throttle-thermal-monitor

# Copy and load the LaunchDaemon
echo "Installing LaunchDaemon..."
cp "$HELPER_DIR/com.macthrottle.thermal-monitor.plist" /Library/LaunchDaemons/
chmod 644 /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist
chown root:wheel /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist

# Load the daemon
echo "Starting thermal monitor daemon..."
launchctl load /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist

echo ""
echo "Installation complete!"
echo "The thermal monitor daemon is now running."
echo "You can now start MacThrottle.app"
