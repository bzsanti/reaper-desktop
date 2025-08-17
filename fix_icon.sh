#!/bin/bash

echo "Fixing Reaper app icon..."

# Kill running app
killall ReaperApp 2>/dev/null || true

# Clear icon cache
rm -rf ~/Library/Caches/com.apple.iconservices* 2>/dev/null
rm -rf ~/Library/Caches/com.apple.IconCache* 2>/dev/null

# Update app timestamp
touch /Applications/Reaper.app
touch /Applications/Reaper.app/Contents/Info.plist
touch /Applications/Reaper.app/Contents/Resources/AppIcon.icns

# Restart services
killall Dock
killall Finder

echo "Icon cache cleared. Please wait a moment and try launching Reaper again."
echo "If the icon still doesn't appear, try:"
echo "1. Move the app out of /Applications and back in"
echo "2. Log out and log back in"