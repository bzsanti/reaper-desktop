#!/bin/bash

set -e

echo "Building Reaper.app bundle..."

# Build Rust libraries
echo "Building Rust libraries..."
cargo build --release

# Build Swift executable
echo "Building Swift executable..."
cd ReaperApp
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
APP_BUNDLE="../Reaper.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy executable
cp .build/release/ReaperApp "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy Rust libraries
cp ../target/release/*.dylib "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
cp ../target/release/*.a "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true

# Create basic icon (placeholder)
echo "Creating placeholder icon..."
touch "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "✓ Reaper.app bundle created successfully!"
echo "Run with: open ../Reaper.app"