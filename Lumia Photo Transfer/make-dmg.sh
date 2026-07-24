#!/bin/bash
# =============================================================================
# make-dmg.sh — Build, sign, notarize, and package Lumia Photo Transfer as a
#               distributable DMG.
#
# Prerequisites:
#   • macOS 13+ with Xcode command-line tools
#   • A "Developer ID Application" certificate installed in your keychain
#   • Notarization credentials — EITHER a stored keychain profile (recommended)
#     OR an app-specific password (create at appleid.apple.com)
#
# Usage:
#   NOTARY_KEYCHAIN_PROFILE=LumiaNotary ./make-dmg.sh   # recommended, no secrets on CLI
#   ./make-dmg.sh                                       # interactive (prompts for secrets)
#   ./make-dmg.sh --skip-notarize                       # signed DMG only (ad-hoc if no cert)
#
# Environment variables (all optional):
#   SIGNING_IDENTITY        — e.g. "Developer ID Application: You (TEAMID)" (auto-detected)
#   NOTARY_KEYCHAIN_PROFILE — name passed to `notarytool store-credentials`; if set,
#                             notarization uses the keychain and needs NO password here.
#   NOTARY_APPLE_ID / NOTARY_PASSWORD / NOTARY_TEAM_ID — fallback for CI / one-off runs.
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")"

# --- Configuration -----------------------------------------------------------
APP_NAME="Lumia Photo Transfer"
BUNDLE_ID="com.lumia.phototransfer"
VERSION="1.0.0"
MIN_MACOS="13.0"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
err()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }

# --- Parse flags -------------------------------------------------------------
SKIP_NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
    esac
done

# --- Step 1: Build release binary --------------------------------------------
info "Building release binary…"
swift build -c release 2>&1 | grep -E '(error|Build complete)' || true
BINARY=".build/release/LumiaPhotoTransfer"
if [ ! -f "$BINARY" ]; then
    err "Build failed — no binary at $BINARY"
    exit 1
fi
ok "Binary built: $BINARY"

# --- Step 2: Assemble .app bundle --------------------------------------------
info "Assembling app bundle…"
APP_DIR="dist/$APP_NAME.app"
rm -rf dist
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/LumiaPhotoTransfer"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>LumiaPhotoTransfer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lumia Photo Transfer needs to control Finder to open your imported photos.</string>
</dict>
</plist>
PLIST

if [ -f Assets/AppIcon.icns ]; then
    cp Assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
    ok "App icon bundled"
fi

xattr -cr "$APP_DIR"
ok "App bundle assembled: $APP_DIR"

# --- Step 3: Code sign -------------------------------------------------------
if [ "$SKIP_NOTARIZE" = true ]; then
    IDENTITY="${SIGNING_IDENTITY:--}"   # ad-hoc unless an identity was given
    if [ "$IDENTITY" = "-" ]; then info "Signing ad-hoc (--skip-notarize)…"; fi
else
    if [ -z "${SIGNING_IDENTITY:-}" ]; then
        SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application" \
            | head -1 \
            | sed 's/.*"\(.*\)".*/\1/' || true)
    fi
    if [ -z "${SIGNING_IDENTITY:-}" ]; then
        err "No 'Developer ID Application' certificate found."
        err "Re-run with --skip-notarize for an ad-hoc local build."
        exit 1
    fi
    IDENTITY="$SIGNING_IDENTITY"
    info "Signing with: $IDENTITY"
fi

codesign --force --options runtime --sign "$IDENTITY" "$APP_DIR"
ok "Code signed"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" 2>/dev/null && ok "Signature verified" || {
    err "Signature verification failed"; exit 1; }

# --- Step 4: Create DMG ------------------------------------------------------
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="dist/$DMG_NAME.dmg"
STAGING="dist/dmg-staging"

info "Creating DMG…"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
xattr -cr "$STAGING"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG_PATH" -quiet
rm -rf "$STAGING"
ok "DMG created: $DMG_PATH"

if [ "$SKIP_NOTARIZE" != true ]; then
    codesign --force --sign "$IDENTITY" "$DMG_PATH"
    ok "DMG signed"
fi

# --- Step 5: Notarize --------------------------------------------------------
if [ "$SKIP_NOTARIZE" = true ]; then
    info "Skipping notarization (--skip-notarize)"
    echo ""; ok "Done! DMG ready at: $DMG_PATH"
    info "(Ad-hoc signed — users right-click → Open on first launch)"
    exit 0
fi

if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    # Recommended path: credentials live encrypted in the keychain; nothing
    # secret appears on this command line.
    info "Notarizing with stored keychain profile: $NOTARY_KEYCHAIN_PROFILE"
    NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait 2>&1) || true
else
    APPLE_ID="${NOTARY_APPLE_ID:-}"
    PASSWORD="${NOTARY_PASSWORD:-}"
    TEAM_ID="${NOTARY_TEAM_ID:-}"
    [ -z "$APPLE_ID" ] && read -rp "Apple ID email: " APPLE_ID
    if [ -z "$PASSWORD" ]; then
        read -rsp "App-specific password (appleid.apple.com): " PASSWORD; echo ""
    fi
    [ -z "$TEAM_ID" ] && TEAM_ID=$(echo "$IDENTITY" | sed 's/.*(\(.*\))/\1/')
    info "Submitting for notarization (2–10 min)…"
    NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" --password "$PASSWORD" --team-id "$TEAM_ID" \
        --wait 2>&1) || true
fi

echo "$NOTARY_OUTPUT"

if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
    ok "Notarization ACCEPTED ✓"
    info "Stapling notarization ticket…"
    xcrun stapler staple "$DMG_PATH"
    ok "Ticket stapled"
else
    err "Notarization failed or timed out."
    err "Inspect with: xcrun notarytool log <id> --keychain-profile $NOTARY_KEYCHAIN_PROFILE"
    exit 1
fi

echo ""
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "  $DMG_PATH"
ok "  Signed ✓  Notarized ✓  Stapled ✓"
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "Distribute this DMG. Double-click → drag to Applications. Gatekeeper passes."
