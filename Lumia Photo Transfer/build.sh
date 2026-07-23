#!/bin/bash
# Build and install Lumia Photo Transfer
set -e
cd "$(dirname "$0")"

echo "Building Lumia Photo Transfer..."
swift build -c release 2>&1 | tail -3

APP_DIR="Lumia Photo Transfer.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/LumiaPhotoTransfer "$APP_DIR/Contents/MacOS/LumiaPhotoTransfer"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null

# Install to /Applications
rm -rf "/Applications/Lumia Photo Transfer.app"
cp -R "$APP_DIR" /Applications/

echo "✅ Built and installed to /Applications/Lumia Photo Transfer.app"
