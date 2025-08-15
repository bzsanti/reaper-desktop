#!/bin/bash

set -e

echo "🔨 Building Reaper Menu Bar..."
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to script directory
cd "$(dirname "$0")"

# Step 1: Build Rust libraries
echo -e "${YELLOW}📦 Building Rust backend...${NC}"
cargo build --release
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Rust build successful${NC}"
else
    echo -e "${RED}❌ Rust build failed${NC}"
    exit 1
fi

# Step 2: Build Swift Menu Bar app
echo -e "${YELLOW}🔧 Building Swift Menu Bar app...${NC}"
cd ReaperMenuBar
swift build -c release
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Swift build successful${NC}"
else
    echo -e "${RED}❌ Swift build failed${NC}"
    exit 1
fi

# Step 3: Create app bundle
echo -e "${YELLOW}📁 Creating app bundle...${NC}"
APP_NAME="ReaperMenuBar"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="../$APP_BUNDLE"

# Remove old bundle if it exists
rm -rf "$BUILD_DIR"

# Create bundle structure
mkdir -p "$BUILD_DIR/Contents/MacOS"
mkdir -p "$BUILD_DIR/Contents/Resources"

# Copy executable
cp .build/release/ReaperMenuBar "$BUILD_DIR/Contents/MacOS/"

# Copy Info.plist
cp Info.plist "$BUILD_DIR/Contents/Info.plist"

# Create a simple icon (you can replace this with a real icon later)
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>" > "$BUILD_DIR/Contents/Resources/Info.plist"

# Sign the app (optional, but recommended)
if command -v codesign &> /dev/null; then
    echo -e "${YELLOW}🔐 Signing app...${NC}"
    codesign --force --deep --sign - "$BUILD_DIR"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ App signed${NC}"
    else
        echo -e "${YELLOW}⚠️  App signing failed (continuing anyway)${NC}"
    fi
fi

echo -e "${GREEN}🎉 Build complete!${NC}"
echo ""
echo "📍 App bundle created at: $(pwd)/$BUILD_DIR"
echo ""
echo "To run the menu bar app:"
echo "  open $BUILD_DIR"
echo ""
echo "To install (copy to Applications):"
echo "  cp -r $BUILD_DIR /Applications/"
echo ""
echo "To check CPU usage:"
echo "  ps aux | grep ReaperMenuBar"

# Return to original directory
cd ..

# Optional: Launch the app
read -p "Launch ReaperMenuBar now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "ReaperMenuBar.app"
    echo -e "${GREEN}✅ ReaperMenuBar launched!${NC}"
    echo "Check your menu bar for the CPU monitor."
fi