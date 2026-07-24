#!/bin/bash
# =============================================================================
# make-dmg.sh — Build, sign, notarize, and package Lumia Photo Transfer as a
#               distributable DMG.
#
# Prerequisites:
#   • macOS 13+ with Xcode command-line tools
#   • A "Developer ID Application" certificate installed in your keychain
#   • An app-specific password for notarization (create at appleid.apple.com)
#
# Usage:
#   ./make-dmg.sh                          # Interactive (prompts for secrets)
#   ./make-dmg.sh --skip-notarize          # Build + sign + DMG only (ad-hoc)
#
# Environment variables (optional, for CI):
#   SIGNING_IDENTITY    — e.g. "Developer ID Application: Brandon Nguyen (ABC123)"
#   NOTARY_APPLE_ID     — your Apple ID email
#   NOTARY_PASSWORD     — app-specific password (xxxx-xxxx-xxxx-xxxx)
#   NOTARY_TEAM_ID      — your team ID (shown in the certificate)
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
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
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

# Info.plist
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

# App icon
if [ -f Assets/AppIcon.icns ]; then
    cp Assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
    ok "App icon bundled"
fi

# Strip iCloud / Finder xattrs that break codesign
xattr -cr "$APP_DIR"
ok "App bundle assembled: $APP_DIR"

# --- Step 3: Code sign -------------------------------------------------------
if [ "$SKIP_NOTARIZE" = true ]; then
    IDENTITY="-"  # ad-hoc
    info "Signing ad-hoc (--skip-notarize)…"
else
    # Auto-detect Developer ID Application identity
    if [ -z "${SIGNING_IDENTITY:-}" ]; then
        SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application" \
            | head -1 \
            | sed 's/.*"\(.*\)".*/\1/' || true)
    fi
    if [ -z "$SIGNING_IDENTITY" ]; then
        err "No 'Developer ID Application' certificate found."
        err "Create one at: https://developer.apple.com/account/resources/certificates/add"
        err "Or re-run with --skip-notarize for an ad-hoc local build."
        exit 1
    fi
    info "Signing with: $SIGNING_IDENTITY"
fi

codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
ok "Code signed"

# Verify signature
codesign --verify --deep --strict "$APP_DIR" 2>/dev/null && ok "Signature verified" || {
    err "Signature verification failed"
    exit 1
}

# --- Step 4: Create DMG ------------------------------------------------------
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="dist/$DMG_NAME.dmg"
STAGING="dist/dmg-staging"

info "Creating DMG…"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
# Symlink to /Applications for the classic drag-to-install UX
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG_PATH" -quiet
rm -rf "$STAGING"
ok "DMG created: $DMG_PATH"

# Sign the DMG itself (required for notarization)
if [ "$SKIP_NOTARIZE" != true ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    ok "DMG signed"
fi

# --- Step 5: Notarize --------------------------------------------------------
if [ "$SKIP_NOTARIZE" = true ]; then
    info "Skipping notarization (--skip-notarize)"
    echo ""
    ok "Done! DMG ready at: $DMG_PATH"
    info "(Ad-hoc signed — users will need to right-click → Open on first launch)"
    exit 0
fi

# Gather notarization credentials
APPLE_ID="${NOTARY_APPLE_ID:-}"
PASSWORD="${NOTARY_PASSWORD:-}"
TEAM_ID="${NOTARY_TEAM_ID:-}"

if [ -z "$APPLE_ID" ]; then
    read -rp "Apple ID email: " APPLE_ID
fi
if [ -z "$PASSWORD" ]; then
    read -rsp "App-specific password (create at appleid.apple.com): " PASSWORD
    echo ""
fi
if [ -z "$TEAM_ID" ]; then
    # Extract team ID from the signing identity (the parenthesized suffix)
    TEAM_ID=$(echo "$SIGNING_IDENTITY" | sed 's/.*(\(.*\))/\1/')
    info "Team ID (from certificate): $TEAM_ID"
fi

info "Submitting for notarization (this can take 2–10 minutes)…"
NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1) || true

echo "$NOTARY_OUTPUT"

if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
    ok "Notarization ACCEPTED ✓"

    # Staple the ticket so offline Gatekeeper checks pass
    info "Stapling notarization ticket…"
    xcrun stapler staple "$DMG_PATH"
    ok "Ticket stapled"
else
    err "Notarization failed or timed out."
    err "Check: xcrun notarytool log <submission-id> --apple-id ... --password ... --team-id ..."
    exit 1
fi

# --- Done --------------------------------------------------------------------
echo ""
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "  $DMG_PATH"
ok "  Signed ✓  Notarized ✓  Stapled ✓"
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "Distribute this DMG. Users can double-click → drag to Applications."
info "Gatekeeper will pass on first launch (no right-click → Open needed)."
