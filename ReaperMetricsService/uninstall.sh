#!/bin/bash
# Uninstall ReaperMetricsService Launch Agent

set -e

SERVICE_NAME="com.reaper.metrics"
PLIST_FILE="$SERVICE_NAME.plist"
INSTALL_BIN="/usr/local/bin/ReaperMetricsService"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "Uninstalling ReaperMetricsService..."

# Unload service if running
if launchctl list | grep -q "$SERVICE_NAME"; then
    echo "Stopping service..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_FILE" 2>/dev/null || true
fi

# Remove plist
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_FILE" ]; then
    echo "Removing Launch Agent plist..."
    rm "$LAUNCH_AGENTS_DIR/$PLIST_FILE"
fi

# Remove binary
if [ -f "$INSTALL_BIN" ]; then
    echo "Removing binary..."
    sudo rm "$INSTALL_BIN"
fi

# Remove logs
rm -f /tmp/$SERVICE_NAME.out.log /tmp/$SERVICE_NAME.err.log

echo "✓ ReaperMetricsService uninstalled"
