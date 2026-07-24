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

# Copy app icon (pre-built .icns from Assets/)
if [ -f Assets/AppIcon.icns ]; then
    cp Assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# This project lives under ~/Documents, which on macOS is often iCloud-synced
# ("Desktop & Documents"). iCloud stamps every file with xattrs like
# com.apple.fileprovider.fpfs#P and com.apple.FinderInfo, and codesign
# refuses to sign a bundle that carries them ("resource fork, Finder
# information, or similar detritus not allowed"). Strip them first so the
# ad-hoc signature actually applies.
xattr -cr "$APP_DIR"

# Sign ad-hoc. Do NOT swallow stderr: a signing failure must abort the
# script (set -e) so we never ship an unsigned /Applications copy.
codesign --force --deep --sign - "$APP_DIR"

# Install to /Applications
rm -rf "/Applications/Lumia Photo Transfer.app"
cp -R "$APP_DIR" /Applications/
# Clear detritus on the installed copy too, then re-sign in place so the
# copy in /Applications is the one Gatekeeper / LaunchServices sees as signed.
xattr -cr "/Applications/Lumia Photo Transfer.app"
codesign --force --deep --sign - "/Applications/Lumia Photo Transfer.app"

echo "✅ Built and installed to /Applications/Lumia Photo Transfer.app"
