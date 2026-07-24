# Nokia Lumia 1020 → Mac: Complete DNG Transfer Guide

> **Goal:** Get 48MP DNG (RAW) files off your Nokia Lumia 1020 and into Lightroom Classic on your Mac — without spinning up a Windows 11 VM.

---

## Table of Contents

1. [Quick Start (USB — Recommended)](#1-quick-start-usb--recommended)
2. [WiFi Transfer via LocalSend](#2-wifi-transfer-via-localsend)
3. [WiFi Transfer via FTP Server](#3-wifi-transfer-via-ftp-server)
4. [OneDrive Cloud Transfer (JPGs Only)](#4-onedrive-cloud-transfer-jpgs-only)
5. [Automation](#5-automation)
6. [Troubleshooting](#6-troubleshooting)
7. [Background & Technical Details](#7-background--technical-details)

---

## 1. Quick Start (USB — Recommended)

This is the most reliable method and the **only one that transfers DNG files**.

### What's Already Installed on Your Mac

| Tool | Status | Purpose |
|------|--------|---------|
| `libmtp` (v1.1.23) | ✅ Installed | MTP protocol library + CLI tools |
| `macFUSE` | ✅ Installed | FUSE filesystem support |
| `OpenMTP` | ✅ Installed | GUI file manager for MTP devices |
| `lumia-transfer.sh` | ✅ Created | Automated DNG download script |

### Option A: Automated Script (Easiest)

```bash
# Connect your Lumia 1020 via USB, unlock the screen, then:
cd ~/Documents/Nokia\ Lumia\ 1020\ for\ Mac

# Download new DNG files to ~/Pictures/Lumia 1020
./lumia-transfer.sh

# Download to a custom folder
./lumia-transfer.sh /path/to/destination

# Just list DNG files on the phone
./lumia-transfer.sh --list

# Re-download everything (ignore transfer history)
./lumia-transfer.sh --all

# Download + open in Lightroom Classic
./lumia-transfer.sh --import
```

The script remembers which files it has already downloaded (stored in `~/.lumia-transfer-history`), so you can run it repeatedly without re-downloading everything.

### Option B: OpenMTP (GUI)

1. Connect the Lumia 1020 via USB
2. Unlock the phone → set USB mode to **Media device (MTP)**
3. Open **OpenMTP** from `/Applications/OpenMTP.app`
4. The phone should appear on the left panel
5. Navigate to **Phone → Pictures → Camera Roll**
6. Select the `.dng` files → drag them to your Mac folder

```bash
# Or launch from terminal:
open -a OpenMTP
```

### Option C: Manual CLI (libmtp)

```bash
# 1. Detect the phone
mtp-detect

# 2. List all folders
mtp-folders

# 3. List all files (look for .dng files)
mtp-filetree

# 4. Download a specific file by its ID
#    (the ID is the number in brackets at the end of each filetree line)
mtp-getfile <FILE_ID> ~/Pictures/Lumia\ 1020/photo.dng
```

### USB Connection Steps (Every Time)

1. Plug the Lumia 1020 into your Mac via USB cable
2. **Unlock the phone screen** (MTP won't work while locked)
3. Pull down the notification shade on the phone
4. Tap the USB notification → select **"Media device (MTP)"**
5. Wait 3–5 seconds for the Mac to recognize the device
6. Run the transfer script or open OpenMTP

---

## 2. WiFi Transfer via LocalSend

[LocalSend](https://localsend.org/) is a free, open-source, cross-platform file sharing tool that works over your local WiFi network. **Someone built a Windows Phone 8.1 client!**

### Setup

**On your Mac:**
```bash
brew install --cask localsend
```
Or download from [localsend.org](https://localsend.org/)

**On your Lumia 1020:**
1. Open the browser (IE11) on the phone
2. Go to the **Live Store**: `https://store.live.net.co`
3. Search for **"LocalSend"** or **"Share Files"**
4. Download and install the XAP
5. Alternatively, sideload the XAP via the [8Marketplace](https://8marketplace.net) or the [Live Store web portal](https://store.live.net.co)

### How to Use

1. Make sure both devices are on the **same WiFi network**
2. Open LocalSend on both the Mac and the Lumia 1020
3. On the phone: select the DNG files from Camera Roll → tap Share/Send
4. On the Mac: accept the incoming transfer
5. Files appear in your LocalSend downloads folder

### Pros & Cons

| ✅ Pros | ❌ Cons |
|---------|---------|
| No USB cable needed | Requires same WiFi network |
| Works with DNG files | Phone app may need sideloading |
| Fast over local network | No auto-sync — manual each time |
| No internet required | WP8.1 app is community-built |

---

## 3. WiFi Transfer via FTP Server

You can install an FTP server app on the Lumia 1020 and pull files wirelessly.

### Setup

**On your Lumia 1020:**
1. Go to the **Live Store** (`https://store.live.net.co`) or **8Marketplace** (`https://8marketplace.net`)
2. Search for **"FTP Server"** or **"File Transfer"**
3. Install the app
4. Open it and start the FTP server
5. Note the IP address and port shown (e.g., `ftp://192.168.1.42:2121`)

**On your Mac:**
```bash
# Connect via Finder
# Press Cmd+K in Finder, then enter:
# ftp://192.168.1.42:2121

# Or use the command line:
curl -O ftp://192.168.1.42:2121/Pictures/Camera%20Roll/*.dng

# Or mount as a network drive:
# Finder → Go → Connect to Server → ftp://192.168.1.42:2121
```

### Pros & Cons

| ✅ Pros | ❌ Cons |
|---------|---------|
| No USB cable needed | FTP is unencrypted (fine on home WiFi) |
| Works with DNG files | Requires FTP app on phone |
| Can script/automate | Phone must stay awake during transfer |
| Works from any computer | Slower than USB for large batches |

---

## 4. OneDrive Cloud Transfer (JPGs Only)

> ⚠️ **Critical Limitation:** The Windows Phone 8.1 OneDrive app **does NOT auto-upload DNG/RAW files**. It only uploads the 5MP JPEG versions. This is a platform limitation that was never fixed by Microsoft.

### What Works

- **Camera Roll auto-upload** (Settings → OneDrive → Camera Roll → "Upload at best quality") — uploads **JPGs only**
- The OneDrive app on WP8.1 is **partially functional** as of 2025–2026 (login and basic sync may work, but Microsoft has deprecated all WP8.1 services)
- The IE11 browser on WP8.1 **cannot reliably access modern OneDrive.com** (the web app requires modern browser features)

### What Doesn't Work

- ❌ DNG/RAW auto-upload to OneDrive
- ❌ OneDrive.com via the phone's browser (IE11 is too old)
- ❌ Reliable OneDrive app sync (Microsoft deprecated WP8.1 APIs)

### If You Still Want OneDrive for JPGs

1. On the phone: **Settings → OneDrive → Camera Roll**
2. Set upload quality to **"Best quality"**
3. Choose **"Upload using WiFi only"** (to save mobile data)
4. JPGs will sync to your OneDrive → download on Mac via [onedrive.com](https://onedrive.com) or the OneDrive Mac app

### Verdict

**OneDrive is NOT a viable solution for DNG files.** Use USB (Method 1) or LocalSend (Method 2) instead.

---

## 5. Automation

### USB Auto-Import (Recommended)

The `lumia-transfer.sh` script handles incremental transfers automatically:

```bash
# Add to your shell profile for quick access:
echo 'alias lumia="~/Documents/Nokia\ Lumia\ 1020\ for\ Mac/lumia-transfer.sh"' >> ~/.zshrc
source ~/.zshrc

# Now just run:
lumia              # Download new DNGs
lumia --import     # Download + open in Lightroom
```

### Lightroom Classic Auto-Import Folder

You can set up Lightroom to automatically watch a folder for new files:

1. Open Lightroom Classic
2. Go to **File → Auto Import → Auto Import Settings**
3. Enable **"Enable Auto Import"**
4. Set the **Watched Folder** to `~/Pictures/Lumia 1020`
5. Set the **Destination** to your Lightroom catalog location
6. Now whenever the script downloads new DNGs, Lightroom will auto-import them

### WiFi Auto-Transfer (Limited)

True "connect to WiFi → auto-upload" automation is **not possible** on Windows Phone 8.1 because:

- The OS doesn't expose WiFi connection events to third-party apps
- Background tasks are severely limited (30-second execution windows)
- The OneDrive camera roll sync is the only built-in auto-upload, and it skips DNGs

**Best WiFi workflow:**
1. Install LocalSend on both devices
2. When you want to transfer, open LocalSend on both
3. Select and send files from the phone
4. Accept on the Mac

This is still much faster than spinning up a Windows VM!

---

## 6. Troubleshooting

### Phone Not Detected via USB

| Problem | Solution |
|---------|----------|
| `mtp-detect` shows "No raw devices found" | Unlock the phone screen, set USB mode to MTP |
| Phone charges but isn't detected | Try a different USB cable (some are charge-only) |
| Still not detected | Try a different USB port; avoid USB hubs |
| `mtp-detect` shows the device but tools fail | Unplug, wait 5 sec, replug, unlock, set MTP mode |

### DNG Files Not Appearing

| Problem | Solution |
|---------|----------|
| No `.dng` files in filetree | Make sure you're shooting in RAW mode in Nokia Camera |
| Only `.jpg` files visible | In Nokia Camera: Settings → Capture mode → "RAW + JPEG" |
| DNG files are 0 bytes | The phone may be low on storage (DNGs are ~48MB each) |

### OpenMTP Issues

| Problem | Solution |
|---------|----------|
| OpenMTP doesn't see the phone | Make sure phone is unlocked and in MTP mode |
| OpenMTP crashes on macOS 27 | Use the CLI tools (`mtp-filetree`, `mtp-getfile`) instead |
| Files show but can't download | Try the CLI: `mtp-getfile <ID> <destination>` |

### General Tips

- **Always unlock the phone** before connecting via USB — MTP requires an unlocked device
- **Use a data cable**, not a charge-only cable (most Nokia cables are data cables)
- **Don't eject** the phone while files are transferring
- **DNG files are large** (~48MB each for 48MP shots) — a full 32GB phone can hold ~600 DNG+JPEG pairs
- **Battery level matters** — if the phone dies mid-transfer, files may be corrupted

---

## 7. Background & Technical Details

### Why the Old Methods Don't Work

| Old Method | Why It's Dead |
|------------|---------------|
| **Nokia Photo Transfer for Mac** | 32-bit Intel app; macOS dropped 32-bit support in Catalina (10.15). Won't run on Apple Silicon. |
| **Windows Phone app for Mac** | 32-bit Intel app; same issue. Microsoft discontinued it years ago. |
| **Android File Transfer** | 32-bit Intel app; same issue. (Some forks exist but are unreliable.) |
| **Windows 11 VM + Windows Phone app** | Works but is slow, heavy, and requires a VM license. This is what you're trying to avoid! |

### How MTP Works

The Lumia 1020 uses **MTP (Media Transfer Protocol)** over USB. Unlike USB Mass Storage (which presents the phone as a disk), MTP is a file-level protocol:

- The phone acts as an MTP "responder"
- The Mac acts as an MTP "initiator"
- Files are transferred one at a time via `mtp-getfile`
- The phone's filesystem is never directly mounted (it's mediated by the MTP layer)

`libmtp` is the open-source library that implements the MTP initiator protocol. The CLI tools (`mtp-detect`, `mtp-filetree`, `mtp-getfile`, etc.) are thin wrappers around this library.

### Where DNG Files Live on the Phone

```
Phone (Internal Storage)
└── Pictures
    └── Camera Roll
        ├── WP_20260723_001.jpg      ← 5MP JPEG (always saved)
        ├── WP_20260723_001_Raw_highres.dng  ← 48MP DNG RAW
        ├── WP_20260723_002.jpg
        ├── WP_20260723_002_Raw_highres.dng
        └── ...
```

- DNG files have the suffix `_Raw_highres` in the filename
- Each DNG is approximately **48MB** (48 megapixels, uncompressed)
- The JPEG is always saved alongside the DNG (even in "RAW only" mode, a 5MP JPEG is generated)
- The Lumia 1020 has **no microSD slot** — all storage is internal (32GB or 64GB)

### Your Mac's Setup

| Component | Details |
|-----------|---------|
| Mac | MacBook Pro (M1 Max, 64GB RAM) |
| macOS | 27.0 (Tahoe) |
| libmtp | 1.1.23 (Homebrew) |
| macFUSE | Installed |
| OpenMTP | 3.2.25 (Homebrew Cask) |
| Transfer script | `~/Documents/Nokia Lumia 1020 for Mac/lumia-transfer.sh` |

### Links & Resources

- [libmtp](https://libmtp.sourceforge.net/) — MTP protocol library
- [OpenMTP](https://openmtp.ganeshrvel.com/) — GUI MTP file manager
- [LocalSend](https://localsend.org/) — Cross-platform WiFi file sharing
- [Live Store (WP8.1)](https://store.live.net.co) — Community app store for Windows Phone 8.1
- [8Marketplace](https://8marketplace.net) — Another WP8.1 app store
- [macFUSE](https://osxfuse.github.io/) — FUSE for macOS

---

*Last updated: July 23, 2026*

---

## 8. GUI App: Lumia Photo Transfer

A native macOS app with a visual photo browser, DNG previews, and one-click import.

### Launch

```bash
open -a "Lumia Photo Transfer"
# Or find it in /Applications/Lumia Photo Transfer.app
```

### Features

- **Visual grid** of all photos on the phone with thumbnail previews
- **DNG/JPEG pairing** — automatically matches RAW files with their JPEG companions
- **Select/deselect** individual photos or use Select All
- **Import** selected DNGs to a folder on your Mac
- **Import to Lightroom** — downloads and opens directly in Lightroom Classic
- **Colour Looks, no Lightroom needed** — pick a `.xmp` Look (e.g. a Cobalt film
  simulation) and an **Apply** mode: *Off*, *Sidecar (LR)*, or *Process JPEG*.
  *Process* renders the Look onto your photos with CoreImage and writes graded
  JPEGs to a `Processed/` folder — works on **both JPEG and DNG**, entirely on
  your Mac, with zero Adobe software.
- **Sort** by name or size, filter to DNG-only
- **Progress tracking** during transfers
- **Right-click** any photo to download it to Desktop

### How It Works

1. Connect the Lumia 1020 via USB → unlock → set MTP mode
2. Launch the app → click **"Detect Device"**
3. The app scans the phone and loads thumbnail previews (using the JPEG companions)
4. Click photos to select them (or "Select All")
5. Click **"Import"** to save to `~/Pictures/Lumia 1020`
6. Or click **"Lightroom"** to import directly into Lightroom Classic

### Rebuilding the App

If you modify the source code:

```bash
cd ~/Documents/Nokia\ Lumia\ 1020\ for\ Mac/Lumia\ Photo\ Transfer
./build.sh
```

### Source Code

```
Lumia Photo Transfer/
├── Sources/
│   ├── LumiaPhotoTransferApp.swift   — App entry point + Settings
│   ├── ContentView.swift             — Main UI (grid, toolbar, states)
│   ├── PhotoCellView.swift           — Individual photo cell with thumbnail
│   ├── MTPManager.swift              — libmtp CLI wrapper (detect, scan, download)
│   ├── Models.swift                  — Data models
│   ├── LookKit/                      — Adobe "Look" LUT decoder + CoreImage renderer
│   │   ├── AdobeLookLUT.swift        —   base-85 + zlib decode of crs:RGBTable → 3-D LUT
│   │   └── LookProcessor.swift       —   apply the LUT to JPEG/DNG, write graded output
│   └── lumia-look/                   — standalone CLI that grades photos (see §9)
│       └── main.swift
├── Package.swift
├── build.sh                          — Build + install script
├── ../Profiles/                      — YOUR Look profiles (gitignored, not shipped)
└── Lumia Photo Transfer.app          — Compiled app bundle
```

## 9. Colour Looks — grade your photos without Lightroom

The toolkit can apply Adobe Camera Raw **"Look"** profiles (the `crs:RGBTable`
3-D LUTs that packs like *Cobalt-Image* ship as `.xmp` files) **directly on your
Mac**, with no Adobe software and no Lightroom. The whole pipeline lives in
`LookKit/` and is shared by the GUI app and the `lumia-look` command-line tool.

### How it works (the short version)

A Look `.xmp` stores its colour grade as a compressed, custom-base-85-encoded
3-D LUT. `LookKit` decodes that blob (base-85 → zlib inflate → 32×32×32 LUT),
then applies it on the GPU with CoreImage's `CIColorCubeWithColorSpace`. Inputs
are first normalised into **sRGB** (the space these display-referred Looks are
authored in), so the same code grades a phone JPEG and a freshly-developed DNG
identically. Originals are never modified — graded files are written separately.

### In the GUI app

1. Drop one or more Look `.xmp` files into
   `~/Library/Application Support/Lumia Photo Transfer/Profiles/`
   (the app also reads any `Profiles/` folder bundled next to its binary).
2. Select photos, choose the Look in the **Profile** picker.
3. Choose an **Apply** mode:
   - **Off** — download originals only.
   - **Sidecar (LR)** — also write a `.xmp` next to each file so *Lightroom*
     reads the Look on import (the Lightroom-dependent path).
   - **Process JPEG** — render the Look ourselves and write graded JPEGs to a
     `Processed/` sub-folder. **This needs no Lightroom at all.**
4. Import. The completed screen reports how many files were graded.

> The **Lightroom** toolbar button always writes a sidecar (that's its whole
> purpose), regardless of the Apply mode.

### From the terminal: `lumia-look`

`lumia-look` is a standalone binary that grades any JPEG or DNG with a Look —
handy for folders you already have on disk, or to wire into your own scripts.

```bash
cd "Lumia Photo Transfer"
swift build -c release           # builds .build/release/lumia-look

# Grade a single file
.build/release/lumia-look \
    --profile "../Profiles/Cobalt Ricoh GR Standard v3.0.xmp" \
    --input  photo.dng --output graded.jpg

# Grade a whole folder (writes to <dir>/Processed by default)
.build/release/lumia-look \
    --profile LOOK.xmp --input-dir RAW/ --format jpg --quality 0.95

# Verify the GPU LUT matches the reference decoder (axis order / colour space)
.build/release/lumia-look --selftest --profile LOOK.xmp
```

Options: `--profile` (required), `--input`/`--output`, `--input-dir`/`--output-dir`,
`--format jpg|tiff|png`, `--quality 0..1`, `--selftest`.

### Adding your own Looks

Any ACR "Look" `.xmp` that carries a `crs:RGBTable` works — just copy it into the
Profiles folder above and it appears in the picker (and in `lumia-look`). The
decoder is format-agnostic; a whole pack of 24 Cobalt Ricoh GR / GRIII Looks was
validated end-to-end.

> **Licensing:** the Look `.xmp` files themselves are third-party creative work
> (e.g. © Cobalt-Image). This repo does **not** ship any Look files;
> you install them locally from packs you've purchased/downloaded. Don't
> redistribute Look packs you don't have the rights to share.

### A note on DNGs and colour spaces

A DNG's decoded image is typically tagged **Display P3** (or another wide/linear
space), *not* sRGB. Feeding that straight to a Look keyed in sRGB samples the LUT
at the wrong coordinates and produces a badly wrong colour cast (e.g. electric
blue shadows). `LookKit` avoids this by normalising the input to sRGB *before*
the cube — which is also why grading a DNG costs no extra RAW decode than
encoding it would anyway.

## 10. Open-source / security notes

This project is intended to be safe to publish:

- **No secrets, keys, tokens, or personal paths** are in the source or history.
- No third-party Look profiles are bundled; the `Profiles/` directory is gitignored.
- The app is ad-hoc signed by `build.sh`; there is no hardcoded signing identity.
- Transfer history (`~/.lumia-transfer-history`) and downloaded photos stay on
  your machine and are never committed (see `.gitignore`).

If you add your own Look packs locally, keep them in
`~/Library/Application Support/Lumia Photo Transfer/Profiles/` (outside the repo)
so they aren't accidentally committed.
