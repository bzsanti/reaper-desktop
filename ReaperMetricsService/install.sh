#!/bin/bash
# Install ReaperMetricsService Launch Agent
# Run this after building the service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="com.reaper.metrics"
PLIST_FILE="$SERVICE_NAME.plist"
INSTALL_BIN="/usr/local/bin/ReaperMetricsService"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "Installing ReaperMetricsService..."

# Check if service binary exists
if [ ! -f "$SCRIPT_DIR/.build/release/ReaperMetricsService" ]; then
    echo "Error: Service binary not found. Build first with:"
    echo "  cd $SCRIPT_DIR && swift build -c release"
    exit 1
fi

# Create LaunchAgents directory if needed
mkdir -p "$LAUNCH_AGENTS_DIR"

# Unload existing service if running
if launchctl list | grep -q "$SERVICE_NAME"; then
    echo "Stopping existing service..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_FILE" 2>/dev/null || true
fi

# Copy binary to /usr/local/bin
echo "Installing binary to $INSTALL_BIN..."
sudo cp "$SCRIPT_DIR/.build/release/ReaperMetricsService" "$INSTALL_BIN"
sudo chmod 755 "$INSTALL_BIN"

# Copy Rust dylibs if they exist
RUST_LIB_DIR="$SCRIPT_DIR/../target/release"
if [ -d "$RUST_LIB_DIR" ]; then
    echo "Installing Rust libraries to /usr/local/lib/..."
    for dylib in "$RUST_LIB_DIR"/*.dylib; do
        if [ -f "$dylib" ]; then
            sudo cp "$dylib" /usr/local/lib/
        fi
    done
fi

# Fix library paths in the binary
echo "Fixing library paths..."
PROJECT_ROOT="$SCRIPT_DIR/.."

# Fix all possible paths for cpu_monitor
for old_path in \
    "$PROJECT_ROOT/target/release/deps/libreaper_cpu_monitor.dylib" \
    "$PROJECT_ROOT/target/release/libreaper_cpu_monitor.dylib" \
    "/Volumes/WD_BLACK/repos/BelowZero/ReaperSuite/ReaperDesktop/target/release/deps/libreaper_cpu_monitor.dylib"; do
    sudo install_name_tool -change "$old_path" /usr/local/lib/libreaper_cpu_monitor.dylib "$INSTALL_BIN" 2>/dev/null || true
done

# Fix all possible paths for disk_monitor
for old_path in \
    "$PROJECT_ROOT/target/release/deps/libreaper_disk_monitor.dylib" \
    "$PROJECT_ROOT/target/release/libreaper_disk_monitor.dylib" \
    "/Volumes/WD_BLACK/repos/BelowZero/ReaperSuite/ReaperDesktop/target/release/deps/libreaper_disk_monitor.dylib"; do
    sudo install_name_tool -change "$old_path" /usr/local/lib/libreaper_disk_monitor.dylib "$INSTALL_BIN" 2>/dev/null || true
done

# Re-sign the binary after modification
echo "Signing binary..."
sudo codesign --force --sign - "$INSTALL_BIN"

# Verify library paths
echo "Verifying library paths..."
otool -L "$INSTALL_BIN" | grep -E "libreaper" && echo "✓ Library paths updated" || echo "⚠ Library paths may need verification"

# Copy plist to LaunchAgents (with correct ownership)
echo "Installing Launch Agent plist..."
cp "$SCRIPT_DIR/$PLIST_FILE" "$LAUNCH_AGENTS_DIR/"
chmod 644 "$LAUNCH_AGENTS_DIR/$PLIST_FILE"

# Load the service (must run as user, not root)
echo "Loading service..."
if [ -n "$SUDO_USER" ]; then
    # Running via sudo - load as the original user
    sudo -u "$SUDO_USER" launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_FILE"
    VERIFY_CMD="sudo -u $SUDO_USER launchctl list"
else
    # Running directly as user
    launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_FILE"
    VERIFY_CMD="launchctl list"
fi

# Verify
sleep 1
if $VERIFY_CMD | grep -q "$SERVICE_NAME"; then
    echo "✓ ReaperMetricsService installed and running"
    echo ""
    echo "Logs:"
    echo "  stdout: /tmp/$SERVICE_NAME.out.log"
    echo "  stderr: /tmp/$SERVICE_NAME.err.log"
else
    echo "⚠ Service installed but may need manual start:"
    echo "  launchctl load $LAUNCH_AGENTS_DIR/$PLIST_FILE"
fi
