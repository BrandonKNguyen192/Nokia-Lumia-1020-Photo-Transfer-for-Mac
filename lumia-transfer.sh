#!/bin/bash
# =============================================================================
# lumia-transfer.sh — Pull DNG (RAW) files from Nokia Lumia 1020 via USB/MTP
# =============================================================================
# Usage:
#   ./lumia-transfer.sh                  # Download new DNGs to ~/Pictures/Lumia 1020
#   ./lumia-transfer.sh /path/to/dest    # Download new DNGs to a custom folder
#   ./lumia-transfer.sh --all            # Re-download ALL DNGs (ignore history)
#   ./lumia-transfer.sh --list           # Just list DNG files on the phone
#   ./lumia-transfer.sh --import         # Download + import into Lightroom
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
DEFAULT_DEST="$HOME/Pictures/Lumia 1020"
HISTORY_FILE="$HOME/.lumia-transfer-history"
LIGHTROOM_APP="/Applications/Adobe Lightroom Classic.app"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Parse arguments ---------------------------------------------------------
DEST="$DEFAULT_DEST"
ALL=false
LIST_ONLY=false
IMPORT=false

for arg in "$@"; do
    case "$arg" in
        --all)    ALL=true ;;
        --list)   LIST_ONLY=true ;;
        --import) IMPORT=true ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [destination]"
            echo ""
            echo "Options:"
            echo "  --all      Re-download ALL DNGs (ignore transfer history)"
            echo "  --list     List DNG files on the phone without downloading"
            echo "  --import   Import downloaded DNGs into Lightroom Classic"
            echo "  --help     Show this help"
            echo ""
            echo "Destination defaults to: $DEFAULT_DEST"
            exit 0
            ;;
        *)        DEST="$arg" ;;
    esac
done

# --- Helper functions --------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}\n"; }

# --- Step 1: Detect the phone ------------------------------------------------
header "Detecting Nokia Lumia 1020"

DETECT_OUTPUT=$(mtp-detect 2>&1) || true

if echo "$DETECT_OUTPUT" | grep -qi "No raw devices found\|No devices"; then
    error "No MTP device found."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Connect the Lumia 1020 to your Mac via USB cable"
    echo "  2. Unlock the phone screen"
    echo "  3. On the phone, pull down the notification shade"
    echo "  4. Tap the USB notification → select 'Media device (MTP)'"
    echo "  5. Wait a few seconds and run this script again"
    echo ""
    echo "If the phone is connected but not detected:"
    echo "  - Try a different USB cable (some are charge-only)"
    echo "  - Try a different USB port"
    echo "  - Run: mtp-detect   (to see raw USB device output)"
    exit 1
fi

# Extract device info
DEVICE_NAME=$(echo "$DETECT_OUTPUT" | grep "Friendly name:" | sed 's/.*Friendly name: *//' | head -1)
DEVICE_MODEL=$(echo "$DETECT_OUTPUT" | grep "Model:" | sed 's/.*Model: *//' | head -1)
DEVICE_SERIAL=$(echo "$DETECT_OUTPUT" | grep "Serial number:" | sed 's/.*Serial number: *//' | head -1)

if [ -n "$DEVICE_NAME" ]; then
    success "Found: $DEVICE_NAME ($DEVICE_MODEL)"
    [ -n "$DEVICE_SERIAL" ] && info "Serial: $DEVICE_SERIAL"
else
    success "MTP device detected"
fi

# --- Step 2: List files on the phone -----------------------------------------
header "Scanning phone storage for DNG files"

# Get the full file tree
FILETREE=$(mtp-filetree 2>&1) || true

if echo "$FILETREE" | grep -qi "No raw devices\|No devices"; then
    error "Lost connection to device. Please reconnect and try again."
    exit 1
fi

# Find all DNG files (case-insensitive)
DNG_FILES=$(echo "$FILETREE" | grep -i '\.dng$' || true)

if [ -z "$DNG_FILES" ]; then
    warn "No DNG files found on the phone."
    echo ""
    echo "Make sure you're shooting in RAW mode:"
    echo "  1. Open Nokia Camera (or Pro Cam) on the phone"
    echo "  2. Go to Settings → tap the gear icon"
    echo "  3. Set 'Capture mode' to 'RAW + JPEG' or 'RAW only'"
    echo "  4. Take some photos, then reconnect and run this script"
    exit 0
fi

DNG_COUNT=$(echo "$DNG_FILES" | wc -l | tr -d ' ')
info "Found $DNG_COUNT DNG file(s) on the phone"

# --- List-only mode ----------------------------------------------------------
if [ "$LIST_ONLY" = true ]; then
    header "DNG files on phone"
    echo "$DNG_FILES" | while IFS= read -r line; do
        FILENAME=$(echo "$line" | sed 's/.*\///' | sed 's/ *$//')
        FILEID=$(echo "$line" | grep -o '[0-9]*$' || true)
        echo "  📷 $FILENAME (ID: $FILEID)"
    done
    exit 0
fi

# --- Step 3: Create destination directory ------------------------------------
mkdir -p "$DEST"
info "Destination: $DEST"

# --- Step 4: Download new DNG files ------------------------------------------
header "Downloading DNG files"

DOWNLOADED=0
SKIPPED=0
FAILED=0
DOWNLOADED_FILES=()

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

echo "$DNG_FILES" | while IFS= read -r line; do
    # Parse the filetree line: "  /path/to/file.dng  [fileid]"
    FILEPATH=$(echo "$line" | sed 's/ *\[.*$//' | sed 's/^ *//')
    FILEID=$(echo "$line" | grep -o '\[[0-9]*\]' | tr -d '[]' || true)
    FILENAME=$(basename "$FILEPATH")

    # Skip if no file ID found
    if [ -z "$FILEID" ]; then
        warn "Could not parse file ID for: $FILENAME"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Check if already downloaded (unless --all)
    if [ "$ALL" = false ] && grep -qF "$FILEID:$FILENAME" "$HISTORY_FILE" 2>/dev/null; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Check if file already exists in destination
    if [ "$ALL" = false ] && [ -f "$DEST/$FILENAME" ]; then
        info "Already exists: $FILENAME (skipping)"
        echo "$FILEID:$FILENAME" >> "$HISTORY_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Download the file
    info "Downloading: $FILENAME ..."
    if mtp-getfile "$FILEID" "$DEST/$FILENAME" 2>/dev/null; then
        success "  ✓ $FILENAME"
        echo "$FILEID:$FILENAME" >> "$HISTORY_FILE"
        DOWNLOADED=$((DOWNLOADED + 1))
        DOWNLOADED_FILES+=("$DEST/$FILENAME")
    else
        error "  ✗ Failed to download: $FILENAME"
        FAILED=$((FAILED + 1))
    fi
done

# --- Step 5: Summary ---------------------------------------------------------
header "Transfer Complete"
info "Downloaded: $DOWNLOADED file(s)"
info "Skipped:    $SKIPPED file(s) (already transferred)"
[ "$FAILED" -gt 0 ] && warn "Failed:     $FAILED file(s)"
info "Files saved to: $DEST"

# --- Step 6: Optional Lightroom import ---------------------------------------
if [ "$IMPORT" = true ] && [ "$DOWNLOADED" -gt 0 ]; then
    header "Importing into Lightroom Classic"

    if [ -d "$LIGHTROOM_APP" ]; then
        info "Opening Lightroom Classic with folder: $DEST"
        open -a "Adobe Lightroom Classic" "$DEST"
        success "Lightroom Classic launched. Use File → Import to add the photos."
    else
        warn "Lightroom Classic not found at: $LIGHTROOM_APP"
        info "You can manually import from: $DEST"
    fi
fi

echo ""
success "Done! 📷"
