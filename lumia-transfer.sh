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
#   ./lumia-transfer.sh --profile P.xmp  # Also write XMP sidecar (color profile)
#
# NOTE on the macOS "camera daemon" (ptpcamerad):
#   macOS's ptpcamerad grabs the Lumia's USB interface exclusively, which makes
#   libmtp fail with libusb_claim_interface() = -3 (LIBUSB_ERROR_BUSY). This
#   script works around it automatically: while it runs, it keeps ptpcamerad
#   stopped (a tiny background reaper). ptpcamerad runs as YOU and respawns on
#   its own afterwards, so this is safe and reversible — and it means you do NOT
#   need to quit Photos / Image Capture / Chrome / ChatGPT to transfer.
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
DEFAULT_DEST="$HOME/Pictures/Lumia 1020"
HISTORY_FILE="$HOME/.lumia-transfer-history"
LIGHTROOM_APP="/Applications/Adobe Lightroom Classic.app"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- Parse arguments ---------------------------------------------------------
DEST="$DEFAULT_DEST"; ALL=false; LIST_ONLY=false; IMPORT=false; PROFILE=""
NEXT_IS_PROFILE=false
for arg in "$@"; do
    if [ "$NEXT_IS_PROFILE" = true ]; then PROFILE="$arg"; NEXT_IS_PROFILE=false; continue; fi
    case "$arg" in
        --all)     ALL=true ;;
        --list)    LIST_ONLY=true ;;
        --import)  IMPORT=true ;;
        --profile) NEXT_IS_PROFILE=true ;;
        --help|-h)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)         DEST="$arg" ;;
    esac
done


# --- Helpers -----------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# Validate profile path if provided
if [ -n "$PROFILE" ]; then
    if [ ! -f "$PROFILE" ]; then
        error "Profile not found: $PROFILE"
        exit 1
    fi
    PROFILE=$(cd "$(dirname "$PROFILE")" && pwd)/$(basename "$PROFILE")
    info "Color profile: $(basename "$PROFILE")"
fi

# libmtp merges stdout+stderr; these signatures mean another process holds the
# MTP interface. IMPORTANT: only ever call these in a condition position
# (if/||/&&) so `set -e` doesn't trip on grep's nonzero exit.
is_busy()     { grep -qiE 'claim_interface|unable to initialize device|unable to open raw device|libmtp panic' <<<"$1"; }
is_nodevice() { grep -qiE 'no raw devices|no devices' <<<"$1"; }

# --- ptpcamerad suppressor ---------------------------------------------------
# While this PID is set, a background loop reaps ptpcamerad ~2.5x/sec so it can
# never hold the USB interface long enough to block a single mtp-* call.
SUPPRESS_PID=""
ptpcam_suppress_start() {
    [ -n "$SUPPRESS_PID" ] && return 0
    ( while :; do pkill -9 -x ptpcamerad 2>/dev/null || true; sleep 0.4; done ) &
    SUPPRESS_PID=$!
}
ptpcam_suppress_stop() {
    [ -n "$SUPPRESS_PID" ] || return 0
    kill "$SUPPRESS_PID" 2>/dev/null || true
    SUPPRESS_PID=""
}
cleanup() { ptpcam_suppress_stop; }
trap cleanup EXIT

# --- Step 1: Detect the phone ------------------------------------------------
header "Detecting Nokia Lumia 1020"
ptpcam_suppress_start
info "Holding the macOS camera daemon (ptpcamerad) so libmtp can read the phone."

DETECT_OUTPUT=""
for attempt in 1 2 3 4; do
    DETECT_OUTPUT=$(mtp-detect 2>&1) || true
    is_busy "$DETECT_OUTPUT" || break
    warn "USB interface still busy (attempt $attempt/4) — waiting for it to free…"
    sleep 1
done

if is_busy "$DETECT_OUTPUT"; then
    error "The USB interface is locked by something other than ptpcamerad."
    echo "  This script already suppresses ptpcamerad, so the remaining holder is"
    echo "  usually Google Chrome or the ChatGPT/Codex desktop app (both probe USB)."
    echo "  Quit those, keep the phone unlocked in MTP mode, and re-run."
    exit 1
fi
if is_nodevice "$DETECT_OUTPUT"; then
    error "No MTP device found."
    echo "  1. Connect the Lumia 1020 with a USB *data* cable (not charge-only)."
    echo "  2. Unlock the phone and keep the screen awake."
    echo "  3. Notification shade → USB → “Media device (MTP)”."
    echo "  4. Wait ~3s and re-run. (Try another port/cable if still nothing.)"
    exit 1
fi

DEVICE_NAME=$(echo "$DETECT_OUTPUT" | grep -m1 'Friendly name:' | sed 's/.*Friendly name: *//' || true)
case "$DEVICE_NAME" in ""|"Nokia Lumia WP8") DEVICE_NAME="Nokia Lumia 1020" ;; esac
success "Found: $DEVICE_NAME"

# --- Step 2: Scan for DNG files ----------------------------------------------
header "Scanning phone storage"

FILETREE=""
for attempt in 1 2 3 4; do
    FILETREE=$(mtp-filetree 2>&1) || true
    is_busy "$FILETREE" || break
    sleep 1
done
if is_busy "$FILETREE"; then error "Lost the USB interface while scanning."; exit 1; fi
if is_nodevice "$FILETREE"; then error "Lost connection to device."; exit 1; fi

# Real mtp-filetree format here is "<indent><id> <name>" (id FIRST, no brackets).
# `read -r fid name` splits the first token (id) from the rest (name); leading
# whitespace is trimmed automatically. We only keep *.dng lines.
DNG_IDS=(); DNG_NAMES=()
while IFS= read -r line; do
    read -r fid name <<<"$line" || continue
    [[ "$fid" =~ ^[0-9]+$ ]] || continue
    [ -n "$name" ] || continue
    ext=$(printf '%s' "${name##*.}" | tr 'A-Z' 'a-z')
    [ "$ext" = "dng" ] || continue
    DNG_IDS+=("$fid"); DNG_NAMES+=("$name")
done <<<"$FILETREE"

DNG_COUNT=${#DNG_IDS[@]}

if [ "$DNG_COUNT" -eq 0 ]; then
    warn "No DNG files found on the phone."
    echo "  Shoot in RAW mode for future photos:"
    echo "  Nokia Camera → Settings → Capture mode → RAW + JPEG"
    exit 0
fi
info "Found $DNG_COUNT DNG file(s) on the phone"

# --- List-only mode ----------------------------------------------------------
if [ "$LIST_ONLY" = true ]; then
    header "DNG files on phone"
    for i in "${!DNG_IDS[@]}"; do
        echo "  📷 ${DNG_NAMES[$i]}  (ID ${DNG_IDS[$i]})"
    done
    exit 0
fi

# --- Step 3: Destination -----------------------------------------------------
mkdir -p "$DEST"
touch "$HISTORY_FILE"
info "Destination: $DEST"

# --- Step 4: Download (counters live in the main shell, not a subshell) ------
header "Downloading DNG files"
DOWNLOADED=0; SKIPPED=0; FAILED=0

for i in "${!DNG_IDS[@]}"; do
    fid="${DNG_IDS[$i]}"; name="${DNG_NAMES[$i]}"

    # -x = whole-line match. Plain -qF matches substrings, so history line
    # "10:IMG_1.dng" would falsely match a different file "0:IMG_1.dng" and skip it.
    if [ "$ALL" = false ] && grep -qxF "$fid:$name" "$HISTORY_FILE" 2>/dev/null; then
        SKIPPED=$((SKIPPED+1)); continue
    fi
    if [ "$ALL" = false ] && [ -f "$DEST/$name" ]; then
        info "Already exists: $name (skipping)"
        echo "$fid:$name" >> "$HISTORY_FILE"
        SKIPPED=$((SKIPPED+1)); continue
    fi

    info "Downloading: $name …"
    ok=0
    for t in 1 2 3; do
        if mtp-getfile "$fid" "$DEST/$name" >/dev/null 2>&1; then ok=1; break; fi
        warn "  retry $t/3 for $name (interface contention?)"
        sleep 1
    done
    if [ "$ok" = 1 ]; then
        success "  ✓ $name"
        echo "$fid:$name" >> "$HISTORY_FILE"
        DOWNLOADED=$((DOWNLOADED+1))
        # Write color profile sidecar if --profile was given
        if [ -n "$PROFILE" ]; then
            base="${name%.*}"
            cp "$PROFILE" "$DEST/${base}.xmp"
        fi
    else
        error "  ✗ Failed: $name"
        FAILED=$((FAILED+1))
    fi
done

# --- Step 5: Summary ---------------------------------------------------------
header "Transfer Complete"
info "Downloaded: $DOWNLOADED"
info "Skipped:    $SKIPPED (already transferred)"
[ "$FAILED" -gt 0 ] && warn "Failed:     $FAILED"
info "Saved to:   $DEST"

# --- Step 6: Optional Lightroom import ---------------------------------------
if [ "$IMPORT" = true ] && [ "$DOWNLOADED" -gt 0 ]; then
    header "Importing into Lightroom Classic"
    if [ -d "$LIGHTROOM_APP" ]; then
        open -a "Adobe Lightroom Classic" "$DEST"
        success "Lightroom Classic launched → use File → Import."
    else
        warn "Lightroom Classic not found at $LIGHTROOM_APP"
    fi
fi

echo ""; success "Done! 📷"
