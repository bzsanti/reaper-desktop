#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Building ReaperMenuBar.app...${NC}"

# Build Rust libraries first (needed for FFI)
echo -e "${BLUE}Building Rust libraries...${NC}"
cargo build --release

# Verify Rust libraries exist
if [ ! -f "target/release/libreaper_cpu_monitor.dylib" ]; then
    echo -e "${RED}Error: libreaper_cpu_monitor.dylib not found${NC}"
    exit 1
fi

if [ ! -f "target/release/libreaper_disk_monitor.dylib" ]; then
    echo -e "${RED}Error: libreaper_disk_monitor.dylib not found${NC}"
    exit 1
fi

# Navigate to ReaperMenuBar directory
cd ReaperMenuBar

# Build the menu bar app
echo -e "${BLUE}Building ReaperMenuBar...${NC}"
swift build -c release \
    -Xlinker -L../target/release \
    -Xlinker -lreaper_cpu_monitor \
    -Xlinker -lreaper_disk_monitor \
    -Xlinker -rpath \
    -Xlinker @executable_path/../Frameworks

# Create app bundle
echo -e "${BLUE}Creating app bundle...${NC}"
APP_BUNDLE="ReaperMenuBar.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy executable
cp .build/release/ReaperMenuBar "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
else
    # Create minimal Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Reaper Monitor</string>
    <key>CFBundleExecutable</key>
    <string>ReaperMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.reaper.menubar</string>
    <key>CFBundleName</key>
    <string>ReaperMenuBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.4.1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

# Copy Rust libraries
echo -e "${BLUE}Copying libraries...${NC}"
cp ../target/release/libreaper_cpu_monitor.dylib "$APP_BUNDLE/Contents/Frameworks/"
cp ../target/release/libreaper_disk_monitor.dylib "$APP_BUNDLE/Contents/Frameworks/"

# Update library paths
echo -e "${BLUE}Updating library paths...${NC}"
# Fix the library paths to use @rpath instead of absolute paths
install_name_tool -change \
    /Users/santifdezmunoz/Documents/repos/BelowZero/ReaperSuite/ReaperDesktop/target/release/deps/libreaper_cpu_monitor.dylib \
    @rpath/libreaper_cpu_monitor.dylib \
    "$APP_BUNDLE/Contents/MacOS/ReaperMenuBar"
    
install_name_tool -change \
    /Users/santifdezmunoz/Documents/repos/BelowZero/ReaperSuite/ReaperDesktop/target/release/deps/libreaper_disk_monitor.dylib \
    @rpath/libreaper_disk_monitor.dylib \
    "$APP_BUNDLE/Contents/MacOS/ReaperMenuBar"

# Add rpath if not already present
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/ReaperMenuBar" 2>/dev/null || true

# Sign the app
if command -v codesign &> /dev/null; then
    echo -e "${BLUE}Signing app...${NC}"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo -e "${GREEN}✓ ReaperMenuBar.app created successfully!${NC}"
echo -e "${GREEN}Location: ReaperMenuBar/$APP_BUNDLE${NC}"
echo ""
echo "To install as a login item:"
echo "1. Open System Preferences > Users & Groups"
echo "2. Select your user and click 'Login Items'"
echo "3. Click '+' and add ReaperMenuBar.app"
echo ""
echo "To run now: open $APP_BUNDLE"
