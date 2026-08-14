# Lumia Photo Transfer for Mac

**Pull photos (including 41 MP / 48 MP DNG RAW where supported) off any Nokia Lumia and into Lightroom Classic — natively on macOS, no Windows VM required.**

The Lumia line shoots great photos — the 1020's 48 MP RAW files are legend — but getting them off the phone on a modern Mac is surprisingly painful: there's no official Nokia software for macOS, and the phone's MTP implementation fights with macOS's camera daemon. This project solves that for **any Lumia** (and most other MTP phones) with two tools:

| Tool | What it is |
|------|-----------|
| **Lumia Photo Transfer** (GUI app) | A native SwiftUI app with a visual photo grid, thumbnail previews, one-click DNG/JPEG import, and a direct Lightroom Classic bridge. |
| **`lumia-transfer.sh`** (CLI) | A zero-dependency Bash script for headless / automated transfers with incremental history. |

Both wrap [libmtp](https://libmtp.sourceforge.io) under the hood and handle the macOS-specific headaches (ptpcamerad contention, Homebrew PATH injection, retry logic) so you don't have to. The tools are generic MTP clients, so they detect the device's real model name automatically and work across the whole Lumia line (and any other MTP camera/phone).

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [Option A: Download the DMG](#option-a-download-the-dmg)
  - [Option B: Build from Source](#option-b-build-from-source)
- [Usage — GUI App](#usage--gui-app)
- [Usage — CLI Script](#usage--cli-script)
- [Lightroom Classic Workflow](#lightroom-classic-workflow)
- [WiFi Transfer Alternatives](#wifi-transfer-alternatives)
- [Troubleshooting](#troubleshooting)
- [Building & Distributing (for Contributors)](#building--distributing-for-contributors)
- [How It Works (Technical)](#how-it-works-technical)
- [Project Structure](#project-structure)
- [License](#license)

---

## Requirements

| What | Why |
|------|-----|
| **macOS 13 Ventura** or later | App target; CLI works on older versions too |
| **Apple Silicon or Intel** | Universal — builds for whichever arch you're on |
| **[Homebrew](https://brew.sh)** | Package manager for libmtp |
| **libmtp** (`brew install libmtp`) | MTP protocol library + CLI tools (`mtp-detect`, `mtp-filetree`, `mtp-getfile`) |
| **A Nokia Lumia** | Any Windows Phone 7.5+/8.x Lumia over USB/MTP. Works with the whole line — 520, 620, 720, 820, 920, 1020, 1520, etc. |
| **USB data cable** | Micro-USB — must be a *data* cable, not charge-only |
| Adobe Lightroom Classic *(optional)* | For the one-click import bridge |

```bash
# Install the one dependency:
brew install libmtp
```

> **Which Lumias shoot RAW (DNG)?** Only the **Lumia 1020** (41 MP / 48 MP) and the **Lumia 1520** (with RAW capture enabled in Nokia Camera) store DNG files. Every other Lumia stores **JPEG only**. The app handles both automatically: it imports DNG+JPEG pairs when present, and gracefully falls back to JPEG-only for models that don't shoot RAW. Because the tools are generic MTP clients, they also work with any other MTP device (other phones, digital cameras, etc.), naming the destination folder after whatever device is connected.

---

## Installation

### Option A: Download the DMG

Download the latest DMG from [Releases](https://github.com/BrandonKNguyen192/Nokia-Lumia-1020-Photo-Transfer-for-Mac/releases):

1. Download **[Lumia Photo Transfer‑1.1.0.dmg](https://github.com/BrandonKNguyen192/Nokia-Lumia-1020-Photo-Transfer-for-Mac/releases/download/v1.1.0/Lumia.Photo.Transfer-1.1.0.dmg)**
2. Open the DMG → drag **Lumia Photo Transfer** to your **Applications** folder
3. Launch from Applications (or Spotlight — ⌘Space → "Lumia")

> The DMG is signed with an Apple Developer ID and notarized by Apple, so Gatekeeper will let it run on first launch without any right-click → Open workaround.

### Option B: Build from Source

```bash
# 1. Clone the repo
git clone https://github.com/BrandonKNguyen192/Nokia-Lumia-1020-Photo-Transfer-for-Mac.git
cd Nokia-Lumia-1020-Photo-Transfer-for-Mac

# 2. Install the dependency
brew install libmtp

# 3. Build + install the GUI app (ad-hoc signed, local use)
cd "Lumia Photo Transfer"
./build.sh
# → Installs to /Applications/Lumia Photo Transfer.app

# 4. (Optional) Use the CLI script directly — no build needed
cd ..
./lumia-transfer.sh --list
```

`build.sh` compiles the Swift package in Release mode, assembles the `.app` bundle, ad-hoc codesigns it, and copies it to `/Applications`. No Xcode project needed — just the Swift toolchain.

---

## Usage — GUI App

### Connecting Your Phone

Every time you want to transfer:

1. **Plug in** the phone via USB data cable
2. **Unlock** the phone screen (MTP won't work while locked)
3. Pull down the **notification shade** → tap the USB notification → select **"Media device (MTP)"**
4. Wait ~3 seconds for the Mac to recognize the device

### Importing Photos

1. Launch **Lumia Photo Transfer** (it auto-detects on startup)
2. The app scans the phone and shows a **thumbnail grid** of your photos
   - DNG (RAW) files are shown by default; toggle **"DNG only"** off to see JPEGs
   - Thumbnails are generated from the paired JPEG companions (fast, no RAW decode)
3. **Click photos** to select them, or hit **Select All**
4. Choose your action:
   - **Import** — saves photos to `~/Pictures/<Device Name>` (named after your connected phone; or a folder you pick with the 📁 button)
   - **Lightroom** — imports the photos, then automatically opens Lightroom Classic pointed at the folder

### Toolbar Reference

| Control | What it does |
|---------|-------------|
| 🟢 / 🔴 dot | Device connection status |
| **DNG only** | Filter to show only RAW files (default on) |
| **Sort** | Sort by name or file size, ascending/descending |
| **Select All / Deselect All** | Bulk selection |
| **Import** | Download selected photos to your destination folder |
| **Lightroom** | Download + open in Lightroom Classic |
| 📁 | Choose a custom destination folder |
| 🔄 (⌘R) | Re-detect the phone and rescan |

### Settings

Open **Lumia Photo Transfer → Settings** (⌘,) to set:
- Default destination folder
- Whether to auto-open Lightroom after import

---

## Usage — CLI Script

`lumia-transfer.sh` is a standalone Bash script — no compilation needed. It's ideal for quick terminal transfers, cron jobs, or when you don't want to quit USB-using apps (it suppresses ptpcamerad automatically).

```bash
cd ~/path/to/Nokia-Lumia-1020-Photo-Transfer-for-Mac

# Download new photos / DNG files (skips already-transferred ones)
./lumia-transfer.sh

# Download to a custom folder
./lumia-transfer.sh /Volumes/ExternalDrive/LumiaRAW

# Just list DNG files on the phone (no download)
./lumia-transfer.sh --list

# Re-download everything (ignore transfer history)
./lumia-transfer.sh --all

# Download + open in Lightroom Classic
./lumia-transfer.sh --import
```

### How Incremental History Works

The script keeps a record of every file it has downloaded in `~/.lumia-transfer-history`. On subsequent runs, it skips files already in the history — so you can run it repeatedly and only get new photos. Use `--all` to override this and re-download everything.

### Shell Alias (Optional)

```bash
# Add to ~/.zshrc for quick access:
echo 'alias lumia="~/path/to/lumia-transfer.sh"' >> ~/.zshrc
source ~/.zshrc

# Now just:
lumia            # transfer new DNGs
lumia --import   # transfer + open Lightroom
lumia --list     # see what's on the phone
```

---

## Lightroom Classic Workflow

### Method 1: One-Click (GUI App)

1. Select photos in the app → click **Lightroom**
2. The app downloads the photos to `~/Pictures/<Device Name>` (named after your phone)
3. Lightroom Classic launches, pointed at that folder
4. In Lightroom: **File → Import** → the photos are right there

### Method 2: CLI

```bash
./lumia-transfer.sh --import
```

### Method 3: Auto-Import Folder (Hands-Free)

Set up Lightroom to watch the download folder automatically:

1. In Lightroom Classic: **File → Auto Import → Auto Import Settings**
2. Enable **"Enable Auto Import"**
3. Set **Watched Folder** to the download folder (use the actual folder — by default `~/Pictures/<Device Name>`, e.g. `~/Pictures/Nokia Lumia`)
4. Set **Destination** to your catalog location
5. Now whenever the script (or app) downloads new DNGs, Lightroom imports them automatically

### Developing the DNGs

The Lumia 1020's (and 1520's) DNGs are standard Adobe DNG files. Lightroom reads them natively — no plugin needed. You get full RAW control: white balance, exposure, shadow/highlight recovery, lens corrections, etc.

---

## WiFi Transfer Alternatives

USB is the most reliable method and the **only one that transfers DNG files**. But if you don't have a cable handy:

### LocalSend (WiFi, supports DNG)

[LocalSend](https://localsend.org/) is a free, open-source, cross-platform file sharing tool over local WiFi. A community-built Windows Phone 8.1 client exists.

1. Install LocalSend on your Mac: `brew install --cask localsend`
2. Install the WP8.1 client on the phone (via the [Live Store](https://store.live.net.co) or sideload)
3. Both devices on the same WiFi → send files from the phone → accept on Mac

### FTP Server (WiFi, supports DNG)

1. Install an FTP server app on the phone (via Live Store)
2. Start the server, note the IP/port (e.g. `ftp://192.168.1.42:2121`)
3. On your Mac: `curl -O ftp://192.168.1.42:2121/Pictures/Camera%20Roll/*.dng`

### OneDrive (WiFi, JPEGs only ⚠️)

The built-in OneDrive camera roll sync **only uploads JPEGs** — DNG files are skipped. Not viable for RAW transfer.

> See the [Windows Setup Guide](Windows%20Setup%20Guide.md) for instructions on unlocking the bootloader and installing the Live Store to sideload WiFi transfer apps.

---

## Troubleshooting

### "No MTP device found"

| Check | Fix |
|-------|-----|
| Cable | Use a USB **data** cable, not charge-only. Try another cable. |
| Phone screen | Must be **unlocked**. MTP doesn't work while locked. |
| USB mode | Notification shade → USB → **"Media device (MTP)"** |
| USB port | Plug directly into the Mac — no hubs, no docks. |
| Wait | After selecting MTP, wait 3–5 seconds before detecting. |

### "Another process is holding the USB interface" (libusb -3)

macOS's `ptpcamerad` (the camera daemon behind Photos / Image Capture) grabs the phone's USB interface exclusively. Both the GUI app and the CLI script handle this automatically, but if you still see it:

1. **Quit Google Chrome** (it probes USB devices)
2. **Quit the ChatGPT / Codex desktop app** (it also probes USB)
3. **Quit Photos / Image Capture** if they're open
4. Unplug → wait 5s → replug → unlock → set MTP → try again

The CLI script runs a background "reaper" that keeps ptpcamerad suppressed for the duration of the transfer, so it's generally more resilient than the GUI for contentious setups.

### App shows "connected" but zero photos

The phone is **locked** or not actually in MTP mode. The MTP session opens but the storage is hidden. Unlock the phone and re-detect.

### `mtp-detect: command not found` (GUI app)

The GUI app injects Homebrew paths (`/opt/homebrew/bin`, `/usr/local/bin`) into its environment automatically. If you installed libmtp somewhere unusual, make sure `mtp-detect` is on your PATH:

```bash
which mtp-detect   # should print a path
brew install libmtp  # (re)install if missing
```

### Transfer is slow

Normal. The Lumia 1020's USB 2.0 + MTP overhead means ~2–4 MB/s. A 40 MB DNG takes ~10–15 seconds. The 48 MP files are worth the wait.

### Phone not recognized at all

1. Try another USB cable (most common fix)
2. Try another USB port
3. Restart the phone (hold Power → slide to power off)
4. On the Mac: `system_profiler SPUSBDataType` — check if the phone appears at all
5. If it appears but libmtp can't talk to it, the phone may be in the wrong USB mode

---

## Building & Distributing (for Contributors)

### Local Development Build

```bash
cd "Lumia Photo Transfer"
swift build              # debug build (fast)
swift build -c release   # release build (optimized)
./build.sh               # release build + .app bundle + install to /Applications
```

### Creating a Distributable DMG

`make-dmg.sh` builds a signed, notarized DMG ready for public distribution:

```bash
cd "Lumia Photo Transfer"
./make-dmg.sh
```

**What it does, step by step:**

1. **Builds** the Swift package in Release mode
2. **Assembles** a proper `.app` bundle (binary + Info.plist + icon)
3. **Code-signs** with your Developer ID Application certificate (with hardened runtime)
4. **Creates a DMG** with the classic drag-to-Applications layout
5. **Submits to Apple** for notarization via `xcrun notarytool`
6. **Staples** the notarization ticket to the DMG

**Prerequisites for distribution:**

| What | How to get it |
|------|--------------|
| **Developer ID Application certificate** | [developer.apple.com → Certificates → + → Developer ID Application](https://developer.apple.com/account/resources/certificates/add). Requires a paid Apple Developer account ($99/yr). |
| **App-specific password** | [appleid.apple.com → Sign-In and Security → App-Specific Passwords](https://appleid.apple.com). Used by `notarytool` to authenticate. |
| **Team ID** | Shown in your certificate name, e.g. `"Developer ID Application: You (ABC123DEF4)"` — the part in parentheses. |

The script auto-detects your signing identity from the keychain. For notarization, it prompts for your Apple ID and app-specific password (or you can set `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, and `NOTARY_TEAM_ID` environment variables for CI).

**Ad-hoc build (no developer account needed):**

```bash
./make-dmg.sh --skip-notarize
```

This produces a DMG signed ad-hoc. Users will need to **right-click → Open** on first launch to bypass Gatekeeper.

### Storing notarization credentials securely (recommended)

Instead of typing your app‑specific password on every build (or exporting it as
an env var), store it **once** in your login keychain. `notarytool` then reads it
automatically, and the password never appears on any command line:

```bash
xcrun notarytool store-credentials "LumiaNotary" --team-id 3GKZY82PF6
# prompts for your Apple ID + app-specific password, saves them encrypted
```

Then build with the profile name — no secrets on the command line:

```bash
NOTARY_KEYCHAIN_PROFILE=LumiaNotary ./make-dmg.sh
```

Your Apple ID and app‑specific password are typed only into your own Terminal and
saved encrypted in the keychain; `make-dmg.sh` never sees them as arguments.

### Verifying a DMG

```bash
# Check the signature
codesign --verify --deep --strict "dist/Lumia Photo Transfer.app"

# Check notarization
spctl --assess --type execute "dist/Lumia Photo Transfer.app"

# Check the stapled ticket
stapler validate "dist/Lumia Photo Transfer-1.0.0.dmg"
```

---

## How It Works (Technical)

### The MTP Problem on macOS

The phones expose their storage via **MTP** (Media Transfer Protocol), not as a regular USB mass-storage volume. macOS has no built-in MTP file browser (Finder only handles mass-storage), so we use [libmtp](https://libmtp.sourceforge.io) — an open-source MTP library with CLI tools. Because libmtp speaks standard MTP, the tools work with the entire Lumia line and most other MTP devices.

The wrinkle: macOS's **ptpcamerad** daemon (which powers Photos and Image Capture) grabs the phone's USB interface exclusively the moment it's plugged in. libmtp then fails with `libusb_claim_interface() = -3` (LIBUSB_ERROR_BUSY). Both tools work around this:

- **GUI app**: kills ptpcamerad before each MTP operation, retries on contention
- **CLI script**: runs a background reaper loop that suppresses ptpcamerad for the entire transfer session

ptpcamerad runs as your user (no sudo) and launchd respawns it automatically after the transfer, so this is safe and fully reversible.

### DNG/JPEG Pairing (RAW-capable models)

Only the Lumia 1020 (and 1520 in RAW mode) stores photos as a DNG + JPEG pair. For those models each photo looks like:

```
WP_20240101_001_Raw.jpg          ← 5 MP JPEG preview
WP_20240101_001_Raw__highres.dng ← 41 / 48 MP RAW
```

The app pairs them by basename (stripping the `__highres` suffix) so you see one entry per photo. Thumbnails are generated from the JPEG companion (fast), while the actual import downloads the full DNG. On models that store **JPEGs only** (most of the Lumia line), the same code path simply lists the JPEGs and imports them directly — no DNG required.

### Why Not Just Use Image Capture / Photos?

macOS's built-in PTP/MTP stack only sees the JPEG files on a Lumia — on RAW-capable models the DNGs are invisible to it. libmtp talks MTP directly and sees everything.

---

## Project Structure

```
Nokia Lumia 1020 for Mac/
├── README.md                           ← You are here
├── Windows Setup Guide.md              ← Bootloader unlock + Live Store sideloading
├── LICENSE                             ← MIT
├── lumia-transfer.sh                   ← CLI transfer script
├── .gitignore
└── Lumia Photo Transfer/
    ├── Package.swift                   ← Swift Package Manager manifest
    ├── build.sh                        ← Local build + install script
    ├── make-dmg.sh                     ← DMG + sign + notarize for distribution
    ├── Assets/
    │   ├── AppIcon.icns                ← App icon (macOS)
    │   ├── AppIcon.png                 ← App icon (source)
    │   └── AppIcon.svg                 ← App icon (vector source)
    └── Sources/
        ├── LumiaPhotoTransferApp.swift ← App entry point + Settings window
        ├── ContentView.swift           ← Main UI: toolbar, photo grid, states
        ├── PhotoCellView.swift         ← Individual photo cell with lazy thumbnail
        ├── MTPManager.swift            ← libmtp CLI wrapper (detect, scan, download)
        └── Models.swift                ← Data models (PhotoItem, TransferState, etc.)
```

---

## License

[MIT](LICENSE) — do whatever you want with it. Credit appreciated but not required.

The Nokia Lumia 1020 is a trademark of Microsoft / HMD Global. This project is not affiliated with or endorsed by Microsoft, HMD Global, or Nokia.
