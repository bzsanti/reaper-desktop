#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# CPU Limiting Configuration
TOTAL_CORES=$(sysctl -n hw.ncpu)
# Use only 50% of cores to prevent system blocking
MAX_CORES=$((TOTAL_CORES / 2))
MAX_CORES=$((MAX_CORES > 0 ? MAX_CORES : 1))

echo -e "${YELLOW}Building Reaper.app bundle...${NC}"
echo -e "${BLUE}CPU Limit: Using $MAX_CORES of $TOTAL_CORES cores (50%)${NC}"

# Generate build timestamp
BUILD_TIMESTAMP=$(date '+%Y%m%d%H%M%S')
echo -e "${BLUE}Build timestamp: $BUILD_TIMESTAMP${NC}"

# Function to verify file size
verify_file() {
    local file=$1
    local min_size=$2
    local actual_size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    
    if [ "$actual_size" -lt "$min_size" ]; then
        echo -e "${RED}Error: $file is too small (${actual_size} bytes, expected > ${min_size})${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ $file (${actual_size} bytes)${NC}"
    return 0
}

# Update build timestamp in source files
echo "Updating build timestamp in source files..."

# Update ContentView.swift
if [ -f "ReaperApp/Sources/ContentView.swift" ]; then
    sed -i '' "s/private let buildVersion = \"[0-9]*\"/private let buildVersion = \"$BUILD_TIMESTAMP\"/" ReaperApp/Sources/ContentView.swift
    echo -e "${GREEN}✓ Updated ContentView.swift${NC}"
fi

# Update ReaperApp/Info.plist (handles multiline format)
if [ -f "ReaperApp/Info.plist" ]; then
    # Use a more robust approach for plist files
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_TIMESTAMP" ReaperApp/Info.plist
    echo -e "${GREEN}✓ Updated ReaperApp/Info.plist${NC}"
fi

# Kill any running instances
echo "Stopping any running instances..."
pkill -f ReaperApp 2>/dev/null || true
sleep 1

# Build Rust libraries with CPU limit and nice priority
echo "Building Rust libraries (limited to $MAX_CORES cores with minimal priority)..."
nice -n 19 cargo build --release -j $MAX_CORES

# Verify Rust libraries
echo "Verifying Rust libraries..."
verify_file "target/release/libreaper_cpu_monitor.dylib" 400000 || exit 1
verify_file "target/release/libreaper_memory_monitor.dylib" 400000 || exit 1
verify_file "target/release/libreaper_hardware_monitor.dylib" 400000 || exit 1
verify_file "target/release/libreaper_network_monitor.dylib" 400000 || exit 1
verify_file "target/release/libreaper_disk_monitor.dylib" 300000 || exit 1

# Build Swift executable with all monitor libraries and CPU limit
echo "Building Swift executable (limited to $MAX_CORES cores with minimal priority)..."
cd ReaperApp
nice -n 19 swift build -c release -j $MAX_CORES -Xlinker -lreaper_memory_monitor -Xlinker -lreaper_hardware_monitor -Xlinker -lreaper_disk_monitor

# Verify Swift executable
verify_file ".build/release/ReaperApp" 1000000 || exit 1

# Create app bundle structure
echo "Creating app bundle..."
REAPER_APP_DIR="/Users/santifdezmunoz/Documents/repos/BelowZero/ReaperSuite/ReaperDesktop/ReaperApp"
APP_BUNDLE="$REAPER_APP_DIR/Reaper.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy executable
echo "Copying executable..."
cp .build/release/ReaperApp "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist and update build timestamp
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_TIMESTAMP" "$APP_BUNDLE/Contents/Info.plist"
echo -e "${GREEN}✓ Updated bundle Info.plist with build $BUILD_TIMESTAMP${NC}"

# Copy Rust libraries with verification
echo "Copying and verifying libraries..."
cd ..
for lib in target/release/*.dylib; do
    if [ -f "$lib" ]; then
        basename=$(basename "$lib")
        cp "$lib" "$APP_BUNDLE/Contents/Frameworks/"
        
        # Verify the copy
        src_size=$(stat -f%z "$lib")
        dst_size=$(stat -f%z "$APP_BUNDLE/Contents/Frameworks/$basename")
        
        if [ "$src_size" != "$dst_size" ]; then
            echo -e "${RED}Error: Failed to copy $basename correctly${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Copied $basename (${src_size} bytes)${NC}"
    fi
done

# Fix library paths in executable to use @executable_path
echo "Fixing library paths..."
for lib in libreaper_core libreaper_cpu_monitor libreaper_memory_monitor libreaper_hardware_monitor libreaper_network_monitor libreaper_disk_monitor; do
    if [ -f "$APP_BUNDLE/Contents/Frameworks/${lib}.dylib" ]; then
        # Fix the path in the main executable
        install_name_tool -change "$PWD/target/release/deps/${lib}.dylib" "@executable_path/../Frameworks/${lib}.dylib" "$APP_BUNDLE/Contents/MacOS/ReaperApp" 2>/dev/null || true
        install_name_tool -change "$PWD/target/release/${lib}.dylib" "@executable_path/../Frameworks/${lib}.dylib" "$APP_BUNDLE/Contents/MacOS/ReaperApp" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ Library paths fixed${NC}"

# Create/copy icon - check both possible locations
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo -e "${GREEN}✓ Icon copied from Resources/${NC}"
elif [ -f "../Resources/AppIcon.icns" ]; then
    cp "../Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo -e "${GREEN}✓ Icon copied from ../Resources/${NC}"
else
    # Create placeholder icon
    touch "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo -e "${YELLOW}⚠ Using placeholder icon${NC}"
fi

# Create version file
echo "0.4.0" > "$APP_BUNDLE/Contents/Resources/VERSION"
echo "Build: $BUILD_TIMESTAMP" >> "$APP_BUNDLE/Contents/Resources/VERSION"

# Sign the app
if command -v codesign &> /dev/null; then
    echo "Signing app..."
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo -e "${GREEN}✓ App signed${NC}"
fi

# Build ReaperMetricsService (Launch Agent for consistent metrics)
echo ""
echo "Building ReaperMetricsService..."
cd "$REAPER_APP_DIR/.."
if [ -d "ReaperMetricsService" ]; then
    cd ReaperMetricsService
    nice -n 19 swift build -c release -j $MAX_CORES
    if [ -f ".build/release/ReaperMetricsService" ]; then
        echo -e "${GREEN}✓ ReaperMetricsService built successfully${NC}"
        METRICS_SERVICE_BUILT=true
    else
        echo -e "${YELLOW}⚠ ReaperMetricsService build incomplete${NC}"
        METRICS_SERVICE_BUILT=false
    fi
    cd ..
else
    echo -e "${YELLOW}⚠ ReaperMetricsService directory not found${NC}"
    METRICS_SERVICE_BUILT=false
fi

# Final verification
echo ""
echo "Final verification:"
verify_file "$APP_BUNDLE/Contents/MacOS/ReaperApp" 1000000 || exit 1
verify_file "$APP_BUNDLE/Contents/Frameworks/libreaper_cpu_monitor.dylib" 400000 || exit 1
verify_file "$APP_BUNDLE/Contents/Frameworks/libreaper_memory_monitor.dylib" 400000 || exit 1
verify_file "$APP_BUNDLE/Contents/Frameworks/libreaper_hardware_monitor.dylib" 400000 || exit 1
verify_file "$APP_BUNDLE/Contents/Frameworks/libreaper_network_monitor.dylib" 400000 || exit 1
verify_file "$APP_BUNDLE/Contents/Frameworks/libreaper_disk_monitor.dylib" 300000 || exit 1

echo ""
echo -e "${GREEN}✓ Reaper.app bundle created successfully!${NC}"
echo "Run with: open Reaper.app"

# Show metrics service installation instructions
if [ "$METRICS_SERVICE_BUILT" = true ]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}ReaperMetricsService (Launch Agent)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "The metrics service ensures consistent CPU readings"
    echo "between Desktop and MenuBar apps."
    echo ""
    echo "To install the service, run:"
    echo -e "  ${GREEN}cd ReaperMetricsService && ./install.sh${NC}"
    echo ""
    echo "To uninstall:"
    echo -e "  ${GREEN}cd ReaperMetricsService && ./uninstall.sh${NC}"
    echo ""
fi