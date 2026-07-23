# Lumia 1020: Bootloader Unlock + Live Store Setup
## Step-by-Step for Your Windows 11 Mini PC

> **Goal:** Unlock the bootloader, install CMD Injector + Live Store, so you can
> sideload apps (LocalSend, FTP Server, etc.) directly on the phone forever after.
>
> **Time:** ~45–60 minutes (most of it is downloading firmware)
>
> **Risk:** Low but real. There are reports of Lumia 1020 RM-875 units bricking
> during unlock (recoverable via QDLoader 9008 mode). Follow each step carefully.

---

## Before You Start: Gather Everything

### On the Windows 11 Mini PC, download these:

| # | What | Where | Notes |
|---|------|-------|-------|
| 1 | **WPInternals 2.9.2** | [github.com/ReneLergner/WPinternals/releases/tag/2.9.2](https://github.com/ReneLergner/WPinternals/releases/tag/2.9.2) | ⚠️ Do NOT use 3.0 Preview — it's expired. Use **2.9.2** (latest stable). Extract the ZIP to a folder like `C:\WPInternals` |
| 2 | **FFU firmware** for your phone | [lumiadb.com](https://lumiadb.com) | Search for your exact RM model (see Step 1 below). Download the `.ffu` file. This is ~1.5 GB. |
| 3 | **CMD Injector WP8** | [github.com/fadilfadz01/CMD.Injector_WP8/releases](https://github.com/fadilfadz01/CMD.Injector_WP8/releases) | Download the latest `.xap` file |
| 4 | **Live Store XAP** | [store.live.net.co](https://store.live.net.co) | Browse to the Live Store app page and download the `.xap` |
| 5 | **Windows Phone SDK 8.1 Lite** | [archive.org/details/wpsdk8](https://archive.org/details/wpsdk8) (full SDK, 1.6 GB) **OR** search for "WP8.1 SDK Tools Lite" on [windowsphoneonline.com](https://windowsphoneonline.com/?dir=Tools) | You only need the **"Application Deployment 8.1"** tool from this. The Lite version is ~150 MB vs 1.6 GB for the full SDK. |
| 6 | **Microsoft Visual C++ Redistributable 2022 (x86)** | [aka.ms/vs/17/release/vc_redist.x86.exe](https://aka.ms/vs/17/release/vc_redist.x86.exe) | WPInternals needs this. Install it. |

### Also have ready:

- A **good USB data cable** (the Nokia cable that came with the phone, or any micro-USB data cable — NOT a charge-only cable)
- Phone charged to **>80%**
- **Do NOT use a USB hub** — plug directly into the Mini PC
- Close any other phone management software (iTunes, phone companions, etc.)

---

## Step 1: Find Your Phone's RM Model Number

You need the exact RM number to download the right firmware.

**On the Lumia 1020:**
1. Go to **Settings → about**
2. Look for **"More info"** or the model line
3. You'll see something like `RM-877` or `RM-875`

**Alternative:** Eject the SIM tray and look at the label underneath — the RM number is printed there.

**Which one do you have?**

| RM Model | Variant | Region |
|----------|---------|--------|
| **RM-877** | AT&T (LTE) | USA 🇺🇸 |
| **RM-875** | International / Unlocked GSM | Global |
| **RM-876** | 3G only | Europe / Asia |

> Since you're in the US, you most likely have **RM-877** (AT&T) or **RM-875** (unlocked).

---

## Step 2: Download the Correct FFU Firmware

1. Go to **[lumiadb.com](https://lumiadb.com)**
2. Search for your RM model (e.g., `RM-877` or `RM-875`)
3. Find the latest firmware entry for your model
4. Download the **`.ffu`** file (~1.5 GB)
5. Save it somewhere easy to find, like `C:\Lumia1020\firmware.ffu`

> **Can't find your exact model?** You can use **RM-1085** firmware as a "donor" —
> WPInternals only needs it to extract bootloader files, it won't flash your phone
> with the wrong OS. But try to get your exact model first.

> **lumiadb.com locked you out?** (It has rate limits.) Wait a few hours, or try
> [lumiafirmware.com](https://lumiafirmware.com) or the [HalabTech mirror](https://support.halabtech.com/index.php?a=downloads&b=folder&id=115314).

---

## Step 3: Create a Full ROM Backup (CRITICAL — Don't Skip)

This is your safety net. If anything goes wrong, you can restore the phone to exactly
where it is right now.

1. Connect the Lumia 1020 to the Mini PC via USB
2. Unlock the phone screen
3. Open **WPInternals** (run as Administrator)
4. Wait for it to detect your phone (you'll see the phone info in the left panel)
5. In the left panel, click **"Backup"**
6. Select **"Full ROM backup"** (or "Backup" → "Full backup")
7. Choose a save location (e.g., `C:\Lumia1020\backup\`)
8. Click **Start** and wait

> ⏱️ This takes 10–20 minutes. The phone will reboot into flash mode.
> **Do NOT disconnect the cable or touch anything until it's done.**

9. When it finishes, verify the backup files exist in your save folder.
   You should see files like `*.bin`, `*.efi`, etc.

> **Store this backup somewhere safe** — copy it to a USB drive or cloud storage.
> This is your "undo button" if anything goes wrong.

---

## Step 4: Unlock the Bootloader

1. Make sure the phone is still connected via USB
2. In WPInternals, click **"Unlock bootloader"** in the left panel
3. WPInternals will ask you to provide files:
   - **FFU file:** Browse to the `.ffu` you downloaded in Step 2
   - **Loaders:** WPInternals will usually auto-detect these from the FFU. If it asks for a folder, point it to the extracted FFU contents.
   - **SBL3:** (if asked) Also extracted from the FFU
4. Click **OK / Start**
5. The phone will reboot into **flash mode** (you'll see a screen with gears or a lightning bolt)
6. WPInternals will:
   - Flash the unlocked bootloader (Part 1)
   - Flash the unlocked bootloader (Part 2)
   - Reboot the phone

> ⏱️ This takes 5–10 minutes. **DO NOT disconnect the cable.**
> The phone may reboot several times. This is normal.

7. When it's done, WPInternals will show a success message.
8. The phone will boot back into Windows Phone 8.1 normally.

### If something goes wrong:

- **Phone stuck on gears/lightning bolt:** Wait 10 minutes. If still stuck, hold
  **Volume Down + Power** for 15 seconds to force restart.
- **Phone won't boot at all (bricked):** Don't panic. The phone is likely in
  **QDLoader 9008 mode**. You can recover by flashing the original FFU:
  1. Open WPInternals → **Flash** → **Flash original FFU**
  2. Select your `.ffu` file
  3. Flash and wait
  4. If WPInternals can't see the phone, install **Qualcomm QDLoader 9008 drivers**
     and use **Windows Device Recovery Tool** or flash via WPInternals in emergency mode.

---

## Step 5: Enable Root Access

1. Phone should be back on and connected via USB
2. In WPInternals, click **"Enable Root Access"** in the left panel
3. Follow the prompts — the phone will reboot into flash mode again
4. Wait for it to complete
5. Phone reboots normally

> This gives the phone the ability to run unsigned code and modify system files,
> which CMD Injector and Live Store need.

---

## Step 6: Install the Windows Phone Application Deployment Tool

This is the tool that lets you push `.xap` files to the phone from your PC.

### Option A: SDK Lite (recommended — smaller download)

1. Search for **"Windows Phone 8.1 SDK Tools Lite"** on
   [windowsphoneonline.com](https://windowsphoneonline.com/?dir=Tools)
2. Download and install it
3. You'll get **"Application Deployment 8.1"** in your Start Menu

### Option B: Full SDK (if Lite doesn't work)

1. Download from [archive.org/details/wpsdk8](https://archive.org/details/wpsdk8) (1.6 GB ISO)
2. Mount the ISO and run the installer
3. You only need the **"Tools for Windows Phone 8.1"** component
4. After install, find **"Application Deployment 8.1"** in:
   `C:\Program Files (x86)\Microsoft SDKs\Windows Phone\v8.1\Tools\XAP Deployment\`

---

## Step 7: Deploy CMD Injector

1. Connect the phone via USB, unlock the screen
2. Open **"Application Deployment 8.1"** (or "Windows Phone Application Deployment 8.1")
3. Click **Browse** → select the **CMD Injector `.xap`** file you downloaded
4. Click **Deploy**
5. Wait for it to install on the phone (~10 seconds)

### Now inject CMD system-wide:

6. On the phone, open **CMD Injector** from the app list
7. Tap **"Home"**
8. Scroll down and tap **"Inject"**
9. Wait for the injection to complete
10. The phone may reboot — this is normal

> ⚠️ **This step is critical.** The Live Store requires CMD to be injected
> system-wide. If you skip this, Live Store won't be able to install apps.

---

## Step 8: Deploy the Live Store

1. Open **"Application Deployment 8.1"** again
2. Click **Browse** → select the **Live Store `.xap`** file
3. Click **Deploy**
4. Wait for it to install

### Alternatively (on-device):

5. On the phone, open **IE11** (the browser)
6. Go to **https://store.live.net.co**
7. Find the Live Store app and download the `.xap`
8. Open the downloaded file — it should install via CMD Injector's sideloading

---

## Step 9: Verify Everything Works

1. Open the **Live Store** app on the phone
2. You should see the store interface with apps listed
3. Try installing a small app (e.g., a game or utility)
4. If it installs and opens → **you're done!** 🎉

---

## Step 10: Install the Apps You Actually Want

From the Live Store on the phone, search for and install:

| App | What it does | Why you want it |
|-----|-------------|-----------------|
| **LocalSend** | WiFi file sharing | Send DNGs to your Mac wirelessly |
| **FTP Server** | Turns phone into FTP server | Access phone files from Mac Finder |
| **File manager** | Browse phone storage | Manage files on the phone |

### For LocalSend specifically:

1. Install **LocalSend** from the Live Store on the phone
2. **LocalSend is already installed on your Mac** (`/Applications/LocalSend.app`)
3. Both devices on the same WiFi → open LocalSend on both
4. On the phone: select DNG files → Send
5. On the Mac: Accept the transfer

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│  WINDOWS 11 MINI PC — ONE-TIME SETUP                       │
│                                                             │
│  1. Download: WPInternals 2.9.2, FFU, CMD Injector,        │
│     Live Store XAP, SDK Lite, VC++ Redist                   │
│  2. Check phone RM model (Settings → about)                 │
│  3. Connect phone via USB → WPInternals → Backup            │
│  4. WPInternals → Unlock Bootloader                         │
│  5. WPInternals → Enable Root Access                        │
│  6. Install SDK Lite → Application Deployment 8.1           │
│  7. Deploy CMD Injector → Open it → Inject                  │
│  8. Deploy Live Store XAP                                   │
│  9. Open Live Store → install LocalSend, FTP Server         │
│                                                             │
│  AFTER THIS: You never need the Windows PC again.           │
│  Live Store installs apps on-device.                        │
│  Mac handles daily photo transfers via USB or WiFi.         │
└─────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### WPInternals doesn't detect the phone
- Make sure the phone is **unlocked** (screen on, past the lock screen)
- Try a different USB cable (must be a **data** cable)
- Try a different USB port on the Mini PC (avoid hubs)
- Install the **Microsoft Windows Phone drivers**:
  [microsoft.com/en-us/download/details.aspx?id=35471](https://www.microsoft.com/en-us/download/details.aspx?id=35471)
- Check Device Manager — if you see an unknown device, right-click → Update driver

### "BAD GPT" error when providing the FFU
- The FFU file may be corrupted — re-download it
- Try a different FFU version for your RM model
- Make sure you're using WPInternals **2.9.2** (not 3.0 Preview)

### Phone bricked / stuck on gears
- Hold **Volume Down + Power** for 15 seconds to force restart
- If that doesn't work, the phone is in QDLoader 9008 mode:
  1. Install Qualcomm drivers
  2. Open WPInternals → Flash → Flash original FFU
  3. Select your `.ffu` and flash
- Worst case: use **Windows Device Recovery Tool** (WDRT) from Microsoft

### Application Deployment tool can't see the phone
- Make sure the phone is **unlocked**
- Make sure **Developer Mode** is enabled on the phone:
  Settings → Update & security → For developers → Developer Mode
  (On WP8.1: Settings → Update → For developers)
- Restart the Application Deployment tool
- Try reconnecting the USB cable

### Live Store says "CMD not injected"
- Open CMD Injector → Home → Inject again
- Reboot the phone after injection
- Try deploying the Live Store XAP again via Application Deployment

### Live Store can't download/install apps
- Make sure the phone has an active internet connection (WiFi or data)
- Make sure CMD is injected system-wide
- Try rebooting the phone and opening Live Store again
- Check the Live Store help: [onelive.me/help/store](https://www.onelive.me/help/store/)

---

## Links

| Resource | URL |
|----------|-----|
| WPInternals 2.9.2 | [github.com/ReneLergner/WPinternals/releases/tag/2.9.2](https://github.com/ReneLergner/WPinternals/releases/tag/2.9.2) |
| LumiaDB (firmware) | [lumiadb.com](https://lumiadb.com) |
| LumiaFirmware (alt) | [lumiafirmware.com](https://lumiafirmware.com) |
| CMD Injector WP8 | [github.com/fadilfadz01/CMD.Injector_WP8/releases](https://github.com/fadilfadz01/CMD.Injector_WP8/releases) |
| Live Store | [store.live.net.co](https://store.live.net.co) |
| Live Store Help | [onelive.me/help/store](https://www.onelive.me/help/store/) |
| WP SDK 8.1 (full) | [archive.org/details/wpsdk8](https://archive.org/details/wpsdk8) |
| WP Tools (Lite SDK) | [windowsphoneonline.com](https://windowsphoneonline.com/?dir=Tools) |
| Bootloader unlock guide | [lumiadb.com/guide-viewer.html?post=how-to-unlock-bootloader](https://lumiadb.com/guide-viewer.html?post=how-to-unlock-bootloader) |
| LocalSend (Mac) | [localsend.org](https://localsend.org) |

---

*Created: July 23, 2026*

---

## Appendix A: Notes specific to YOUR phone (from your photo)

You sent a photo of **Settings → extras+info**. Here's what it told us and what it
*didn't* tell us.

### What the photo confirms

- ✅ It's a **Nokia Lumia 1020** (yellow shell).
- ✅ Software release = **Lumia Cyan** — this is the *original* Windows Phone 8.1
  firmware (mid‑2014), i.e. WP 8.1 **before** the "Lumia Denim" / 8.1 Update 1 release.
- ✅ The list (Accessories Agent 3.0.2.1, Nokia Share 2.3.0.5, SIM Unlock 1.0.0.5, …)
  are just Nokia's bundled "extras" component versions. They're normal and don't
  affect the unlock.

### What the photo does NOT show (and we still need)

The **extras+info** screen does *not* display the RM model number or the exact OS
build. Those live on a different page:

> **Settings (gear icon) → scroll down → `about`**

On that page you'll see four lines we care about:

| Line on the "about" page | Example | Why we need it |
|--------------------------|---------|----------------|
| **Model** | `RM-877` (or `RM-875` / `RM-876`) | **This selects the exact FFU firmware to download.** This is the single most important number. |
| **Windows Phone version** | `8.1` | Confirms the OS family. |
| **Software version** | `8.10.14157.2007` (Cyan) or `8.10.14219.341` (Denim) | Confirms the OS build. |
| **Firmware revision number** | `3051.40000.xxxx.xxxx` (Cyan) or `3051.50009.xxxx.xxxx` (Denim) | Confirms Cyan vs Denim at the firmware level. |

**Cheat sheet to read your "about" page:**
- Firmware revision starts with **`3051.40000`** → you're on **Lumia Cyan** (matches your photo). ✅
- Firmware revision starts with **`3051.50009`** → you'd be on **Lumia Denim**.

> Backup way to read the RM model (no menus needed): eject the SIM tray — the RM
> number and IMEI are printed on the label underneath.

### Does "Lumia Cyan" change the plan?

**No — and it's arguably good news.**

1. **Unlocking:** WPInternals 2.9.2 fully supports the Lumia 1020 on Cyan. The
   10‑step process in this guide is unchanged.
2. **FFU choice:** On [lumiadb.com](https://lumiadb.com) download the FFU that
   matches your **RM model**. If several versions are listed, prefer the **Cyan**
   one (closest to what's installed), but *any* FFU for your exact RM works as a
   donor — WPInternals patches the on‑device bootloader rather than reflashing your OS.
3. **Camera / DNG (your actual goal):** You do **not** need to update to Denim.
   The original Nokia Pro Cam on Cyan produces the full‑resolution 48 MP
   `_Raw_highres.dng` files cleanly, and many 1020 shooters deliberately stay on
   Cyan for exactly this reason. So feel no pressure to update firmware — staying
   on Cyan is a perfectly good (some say preferable) end state for a RAW‑shooting
   1020.

### Action item

Send a photo of **Settings → about** (or just type the **Model**, **Software
version**, and **Firmware revision number** lines), and I'll fill in the *exact*
lumiadb FFU link for your variant and stamp your RM model into Step 2 of this
guide so it's copy‑paste ready.

> P.S. The crack in the screen has zero effect on any of this — bootloader unlock,
> MTP/USB transfer, and WiFi transfer all work purely off the mainboard and radios.

---

## Appendix B — CONFIRMED device identity & exact firmware (from your `about` photo)

> This appendix is **photo‑confirmed** and **supersedes** the Cyan assumption and the
> "go look up your RM model" wording in Step 1 / Step 2 / Appendix A. Use the values
> below as copy‑paste truth. (Read Appendix A for *why*; read this for *what to type*.)

### ⚠️ Correction to Appendix A
Your `about` page is authoritative: **Software = "Windows Phone 8.1 Update"**,
**OS = 8.10.14226.359**, **Firmware = 3051.50009.1451.1001** → you are on
**Lumia Denim**, *not* Cyan. The "Lumia Cyan" line in `extras+info` is a stale
legacy label. **This changes nothing about the unlock** (WPInternals 2.9.2 fully
supports Denim on the 1020), and the camera still writes full‑res
`_Raw_highres.dng` on Denim — so **do not change your firmware**. Leave it as‑is.

### Your device — non‑sensitive spec table

| Field | Value |
|-------|-------|
| Phone | Nokia Lumia 1020 (internal model name **NOKIA 909**) |
| **RM model (determined)** | **RM‑877** (AT&T / North America) |
| Software / branch | Windows Phone 8.1 Update = **Lumia Denim** |
| OS version | 8.10.14226.359 |
| Firmware revision | **3051.50009.1451.1001** |
| Hardware revision | 3.3.0.3 |
| Radio software | 3.2.04059.1 |
| Chip / SOC | 8960 (Snapdragon S4 / MSM8960, LTE) |
| Screen | 768 × 1280 |

> 🔒 **Privacy note — read this.** Your `about` photo also contains your **IMEI,
> SIM ID (ICCID), MAC address, MDN (phone number) and SIM ID**. Those are
> personally identifying / clone‑able identifiers. I have **deliberately NOT**
> written any of them into this repo, and you should **NOT upload that photo to
> GitHub** (even a private repo). The RM model above was derived from the
> *carrier* of the SIM (AT&T ICCID prefix `8901410`) plus matching community
> reports — not by storing your identifiers.

### Why RM‑877 (evidence)
1. SIM ICCID prefix `8901410` = **AT&T**; product‑code tables list **AT&T / NAM US = RM‑877**.
2. A community device with your *identical* firmware `3051.50009.1451.1001` + AT&T
   + the same IMEI TAC family (`356…`) is explicitly an **RM‑877**.
3. `RM‑876` is 3G‑only → ruled out by your LTE SOC/radio.
4. Note: the build `…1451.1001` is a *shared* Denim OTA that also flashes on
   RM‑875, so the build number alone can't choose the RM — carrier + hardware does.

### ✅ 5‑second ground‑truth check (do before flashing)
The `RM-` number is **printed on the label under the SIM tray**, and shown at the
top of **extras+info** as `Product code: 059xxxx` / a `RM-877_…` line.
- If it reads **RM‑877** → use the RM‑877 firmware below. ✅ (expected)
- If it unexpectedly reads **RM‑875** → use the RM‑875 firmware below instead.
  (Everything else in the 10‑step plan is identical.)

---

### 📋 COPY‑PASTE STEP 2 — exact firmware (FFU) to download

You need an FFU for **RM‑877** to act as the WPInternals "donor" (it extracts the
bootloader loaders; it will *not* reflash your OS). Your installed build is
`3051.50009.1451.1001` (Denim), so prefer a **Denim (3051.50009.xxxx)** FFU.

**Primary — LumiaDB (recommended):**
1. Go to **https://lumiadb.com**
2. In the model search, type exactly: **`RM-877`**
3. From the results pick a build whose revision starts with **`3051.50009`**
   (Denim). If several are listed, prefer one whose provider/variant tag mentions
   **NAM / ATT / US**; otherwise any `3051.50009` RM‑877 FFU works as a donor.
4. Download the **`.ffu`** (~1.5 GB) → save as `C:\Lumia1020\RM-877.ffu`

**Mirrors / alternates for RM‑877 (if LumiaDB rate‑limits you):**
- HalabTech RM‑877 folder: **https://support.halabtech.com/index.php?a=downloads&b=folder&id=115821**
- FirmwareFile RM‑877: **https://firmwarefile.com/nokia-lumia-1020-rm-877**
- ChimeraTool lists your *exact* build `3051.50009.1451.1001` under RM‑877:
  **https://chimeratool.com/en/firmwares/p/99** (and `/zh/.../p/94`)

**Fallback — only if your SIM‑tray label says RM‑875:**
- LumiaDB search: **`RM-875`** → pick a `3051.50009` (Denim) FFU.
- FirmwareFile RM‑875: **https://firmwarefile.com/nokia-lumia-1020-rm-875**

> The exact installed build `3051.50009.1451.1001` is a cross‑flashing Denim OTA,
> so a *nearby* `3051.50009` FFU for the correct RM is a perfectly good donor —
> you do **not** need a byte‑identical match for the unlock to work.

---

### Effect on the rest of the plan
- **Step 1** (find RM model): already answered → **RM‑877** (verify via SIM‑tray label).
- **Step 2** (download FFU): use the RM‑877 sources above.
- **Steps 3–10**: unchanged. WPInternals 2.9.2 handles Denim; backup → unlock →
  root → CMD Injector → Live Store proceeds exactly as written.
- **Camera / DNG goal**: unaffected — Denim's Nokia/Pro Camera produces the same
  48 MP `_Raw_highres.dng` files. No firmware change required.

### TL;DR for the Mini PC run
```
Model to flash/unlock :  RM-877  (confirm on SIM-tray label)
FFU to download       :  lumiadb.com  →  search "RM-877"  →  a 3051.50009.* (Denim) build
WPInternals           :  2.9.2  (NOT the 3.0 preview)
Installed firmware    :  3051.50009.1451.1001  (Denim) — leave it, don't change it
```
