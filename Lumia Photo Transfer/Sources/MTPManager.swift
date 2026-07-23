import Foundation
import LookKit

// Directories that hold the Homebrew-installed mtp-* binaries.
// A double-clicked .app only inherits /usr/bin:/bin:/usr/sbin:/sbin,
// so we MUST inject these or `env mtp-detect` => "command not found".
// Kept at file scope (outside the @MainActor class) so the nonisolated
// PATH-builder below can read it without hopping to the main actor.
private let homebrewBins: [String] = [
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/opt/homebrew/opt/libmtp/bin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/usr/bin", "/bin", "/usr/sbin", "/sbin"
]


// MARK: - MTP Manager (wraps libmtp CLI tools)

@MainActor
class MTPManager: ObservableObject {

    @Published var deviceInfo: MTPDeviceInfo?
    @Published var photos: [PhotoItem] = []
    @Published var state: TransferState = .idle
    @Published var errorMessage: String = ""
    /// Raw, trimmed output from the last mtp-detect / mtp-filetree call.
    /// Surfaced in the UI so connection problems are diagnosable.
    @Published var rawDiagnostic: String = ""

    // MARK: - Color Profile Pipeline

    /// Available .xmp profile files found in the Profiles/ folder.
    @Published var availableProfiles: [URL] = []
    /// The profile the user has selected for sidecar writing on import (nil = none).
    @Published var selectedProfile: URL? = nil
    /// How the selected Look is applied on import (off / sidecar / standalone process).
    @Published var applyMode: ApplyMode = .sidecar
    /// How many files were graded by the standalone pipeline on the last import.
    @Published var processedCount: Int = 0

    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumiaPhotoTransfer", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        scanProfiles()
    }

    // MARK: - Profile Scanning

    func scanProfiles() {
        var found: [URL] = []
        let dirs = [Self.findProfilesDir(),
                    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                        .first?.appendingPathComponent("Lumia Photo Transfer/Profiles", isDirectory: true)
        ].compactMap { $0 }
        for dir in dirs {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                found.append(contentsOf: contents.filter { $0.pathExtension.lowercased() == "xmp" })
            }
        }
        // A profile can live in both the bundled Profiles/ and the user's
        // Application Support copy; show it once (bundle wins, it's first).
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.lastPathComponent).inserted }
        availableProfiles = unique.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func findProfilesDir() -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Profiles", isDirectory: true)
            if fm.fileExists(atPath: c.path) { return c }
            dir = dir.deletingLastPathComponent()
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Profiles", isDirectory: true)
        return fm.fileExists(atPath: cwd.path) ? cwd : nil
    }

    private func writeProfileSidecar(for filename: String, in destination: URL) {
        guard let profile = selectedProfile else { return }
        let base = (filename as NSString).deletingPathExtension
        let sidecar = destination.appendingPathComponent(base + ".xmp")
        try? FileManager.default.copyItem(at: profile, to: sidecar)
    }

    // MARK: - Device Detection

    func detectDevice() async {
        state = .detecting
        let output = await runMTPWithRetry("mtp-detect", arguments: [])
        rawDiagnostic = Self.trimDiagnostic(output)

        // Another process holds the MTP interface (libusb -3 / BUSY). Check this
        // BEFORE the "connected" path, otherwise we show a fake green dot while
        // every subsequent read silently fails (the original screenshot bug).
        if Self.isBusy(output) {
            deviceInfo = nil
            state = .error(Self.busyMessage)
            return
        }

        if output.contains("No raw devices found") || output.contains("No devices") {
            deviceInfo = nil
            state = .error("No MTP device found.\n\n"
                + "1) Connect the Lumia 1020 with a USB *data* cable (not charge-only).\n"
                + "2) Unlock the phone and keep the screen awake.\n"
                + "3) Pull down the notification shade → USB → “Media device (MTP)”.\n"
                + "4) Wait ~3s, then press Detect again.")
            return
        }

        let name = Self.friendlyName(from: output)
        let model = extractField(output, field: "Model:") ?? "Lumia 1020"
        let serial = extractField(output, field: "Serial number:") ?? ""

        deviceInfo = MTPDeviceInfo(name: name, model: model, serial: serial, isConnected: true)
    }

    // MARK: - File Scanning

    func scanFiles() async {
        state = .scanning
        let output = await runMTPWithRetry("mtp-filetree", arguments: [])
        rawDiagnostic = Self.trimDiagnostic(output)

        if Self.isBusy(output) {
            deviceInfo = nil
            state = .error(Self.busyMessage)
            return
        }

        if output.contains("No raw devices") || output.contains("No devices") {
            deviceInfo = nil
            state = .error("Lost connection to device. Reconnect, unlock, and Detect again.")
            return
        }

        // Real mtp-filetree format on this libmtp is "<indent><id> <name>" — the
        // numeric id comes FIRST, with no brackets and no full path. (The previous
        // parser assumed "path [id]" and silently matched nothing, which is why a
        // *successful* read still showed zero photos.) Directories share the same
        // shape but carry no image extension, so the whitelist drops them.
        let lines = output.components(separatedBy: .newlines)
        var parsed: [(id: String, name: String, ext: String)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let sp = trimmed.firstIndex(of: " ") else { continue }
            let idStr = String(trimmed[trimmed.startIndex..<sp])
            guard UInt32(idStr) != nil else { continue }                 // 1st token = id
            let name = String(trimmed[trimmed.index(after: sp)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            guard ext == "dng" || ext == "jpg" || ext == "jpeg" else { continue }
            parsed.append((idStr, name, ext))
        }

        // Pair DNG <-> JPEG by basename with the trailing "_*highres" stripped:
        //   WP_<ts>_Raw__highres.dng  +  WP_<ts>_Raw.jpg  ->  key "WP_<ts>_Raw"
        var jpegByKey: [String: (id: String, name: String)] = [:]
        for it in parsed where it.ext == "jpg" || it.ext == "jpeg" {
            jpegByKey[Self.pairKey(it.name)] = (it.id, it.name)
        }

        var dngFiles: [PhotoItem] = []
        var jpegOnly: [PhotoItem] = []
        for it in parsed {
            if it.ext == "dng" {
                let pj = jpegByKey[Self.pairKey(it.name)]
                dngFiles.append(PhotoItem(
                    id: it.id, filename: it.name, filepath: it.name,
                    fileSize: 0, isDNG: true, isJPEG: false,
                    dngFileID: nil, jpegFileID: pj?.id, jpegFilename: pj?.name))
            } else {
                jpegOnly.append(PhotoItem(
                    id: it.id, filename: it.name, filepath: it.name,
                    fileSize: 0, isDNG: false, isJPEG: true,
                    dngFileID: nil, jpegFileID: nil, jpegFilename: nil))
            }
        }

        if dngFiles.isEmpty {
            photos = jpegOnly.sorted { $0.filename < $1.filename }
        } else {
            photos = dngFiles.sorted { $0.filename < $1.filename }
        }

        // Connected, but libmtp returned an empty filesystem. This is the
        // known "MTP session open but storage hidden" state — almost always
        // means the phone is LOCKED or not in MTP mode, or the USB link is
        // in the flaky claim_interface state. Surface it explicitly.
        if photos.isEmpty {
            state = .error("Phone is connected, but libmtp sees an empty filesystem.\n\n"
                + "Most common causes:\n"
                + "• The phone screen is LOCKED — unlock it and keep it awake.\n"
                + "• USB mode isn’t “Media device (MTP)” — set it in the notification shade.\n"
                + "• A flaky USB link — unplug, wait 5s, "
                + "replug firmly into a direct port (no hub), unlock, then Detect.\n\n"
                + "Tip: also try opening OpenMTP (/Applications) as a cross-check — "
                + "if it sees files where this app doesn’t, tell me and I’ll swap the backend.")
            return
        }

        state = .ready
    }

    // MARK: - Thumbnail Generation

    /// Thumbnails the grid has built, keyed by photo id. Observed by the cells so
    /// launch never blocks on a whole-device thumbnail pass — previews are fetched
    /// lazily as cells scroll into view (requestThumbnail).
    @Published var thumbnailURLs: [String: URL] = [:]

    // Serializes thumbnail production so the grid’s concurrent on-appear requests
    // don’t spawn competing mtp-getfile processes (which would self-contend on the
    // single MTP interface, and on ptpcamerad).
    private var thumbGate: Task<Void, Never> = Task {}
    private var thumbWaiters: [String: [CheckedContinuation<URL?, Never>]] = [:]
    private var thumbQueued: Set<String> = []
    private var thumbResolved: [String: URL?] = [:]

    /// Called by a grid cell when it appears. Idempotent: a no-op if the thumbnail
    /// is already built/cached; otherwise enqueues one serial build and publishes
    /// the result. Returns true iff a URL is now available.
    @discardableResult
    func requestThumbnail(for photo: PhotoItem) async -> Bool {
        if thumbnailURLs[photo.id] != nil { return true }
        if let url = await buildThumbnailSerially(for: photo) {
            thumbnailURLs[photo.id] = url
            return true
        }
        return false
    }

    /// Cache-first, de-duplicated, serial thumbnail producer.
    private func buildThumbnailSerially(for photo: PhotoItem) async -> URL? {
        if let cached = existingCachedThumbnail(for: photo) { return cached }   // disk (survives relaunch)
        if let done = thumbResolved[photo.id] { return done }                   // this session (nil = prior failure)
        return await withCheckedContinuation { cont in
            thumbWaiters[photo.id, default: []].append(cont)
            guard thumbQueued.insert(photo.id).inserted else { return }
            let prev = thumbGate
            thumbGate = Task { [weak self] in
                _ = await prev.value
                guard let self else { return }
                let url = await self.produceThumbnail(for: photo)
                let waiters = self.thumbWaiters[photo.id] ?? []
                self.thumbWaiters[photo.id] = nil
                self.thumbResolved[photo.id] = url
                for w in waiters { w.resume(returning: url) }
            }
        }
    }

    private func existingCachedThumbnail(for photo: PhotoItem) -> URL? {
        let p = tempDir.appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent("thumb_\(photo.isDNG ? (photo.jpegFileID ?? photo.id) : photo.id).jpg")
        return FileManager.default.fileExists(atPath: p.path) ? p : nil
    }

    /// One thumbnail’s real work: free the camera daemon, fetch the paired JPEG
    /// (or the file itself), downscale to 400px. Two attempts ride out a ptpcamerad
    /// respawn. Always runs serially via buildThumbnailSerially.
    private func produceThumbnail(for photo: PhotoItem) async -> URL? {
        let targetID: String
        let targetName: String
        if photo.isDNG, let jpegID = photo.jpegFileID, let jpegName = photo.jpegFilename {
            targetID = jpegID; targetName = jpegName
        } else {
            targetID = photo.id; targetName = photo.filename
        }

        let thumbDir = tempDir.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbPath = thumbDir.appendingPathComponent("thumb_\(targetID).jpg")
        if FileManager.default.fileExists(atPath: thumbPath.path) { return thumbPath }

        let destPath = thumbDir.appendingPathComponent(targetName)
        for _ in 0..<2 {
            await reclaimPtpcamerad()
            _ = await runCommand("mtp-getfile", arguments: [targetID, destPath.path])
            if Self.nonEmptyFile(at: destPath) {
                _ = await runCommand("sips", arguments: ["-Z", "400", destPath.path, "--out", thumbPath.path])
                try? FileManager.default.removeItem(at: destPath)
                // sips writes thumbPath only on success. If it failed we've already
                // removed the full-res source, so there is nothing valid to return —
                // returning destPath here would hand back a just-deleted path.
                return FileManager.default.fileExists(atPath: thumbPath.path) ? thumbPath : nil
            }
            await Self.pause(0.6)
        }
        return nil
    }

    // MARK: - File Download

    func downloadFile(_ photo: PhotoItem, to destination: URL, forceSidecar: Bool = false) async -> Bool {
        let destPath = destination.appendingPathComponent(photo.filename)
        // ptpcamerad respawns ~2s after we free it and re-grabs the interface, so
        // release it right before each getfile and retry on contention. A 0-byte
        // leftover from a failed getfile does NOT count as success.
        for _ in 0..<3 {
            await reclaimPtpcamerad()
            _ = await runCommand("mtp-getfile", arguments: [photo.id, destPath.path])
            if Self.nonEmptyFile(at: destPath) {
                if applyMode == .sidecar || forceSidecar { writeProfileSidecar(for: photo.filename, in: destination) }
                return true
            }
            await Self.pause(0.8)
        }
        // Every attempt failed. Remove any 0-byte/partial leftover so it can't
        // masquerade as a real photo in the user's folder (and, for the shell
        // tool's "[ -f ]" check, get silently skipped on every later run).
        if !Self.nonEmptyFile(at: destPath) {
            try? FileManager.default.removeItem(at: destPath)
            return false
        }
        if applyMode == .sidecar || forceSidecar { writeProfileSidecar(for: photo.filename, in: destination) }
        return true
    }

    func downloadFiles(_ photos: [PhotoItem], to destination: URL,
                       forceSidecar: Bool = false,
                       progressHandler: @escaping (Double, String) -> Void) async -> Int {
        var successCount = 0
        processedCount = 0
        let total = Double(max(photos.count, 1))

        // Decode the Look once, off the main thread, when we'll grade on import.
        // The standalone pipeline renders each downloaded file through the Look
        // with CoreImage and writes a graded JPEG to <dest>/Processed/ — the
        // originals are never touched, so this is fully non-destructive.
        var lut: LookLUT? = nil
        let processDir = destination.appendingPathComponent("Processed", isDirectory: true)
        if applyMode == .process, !forceSidecar, let profile = selectedProfile {
            progressHandler(0, "Decoding look…")
            lut = await Task.detached(priority: .userInitiated) {
                try? AdobeLookLUT.decode(xmpAt: profile)
            }.value
            if lut != nil {
                try? FileManager.default.createDirectory(at: processDir, withIntermediateDirectories: true)
            }
        }

        for (index, photo) in photos.enumerated() {
            progressHandler(Double(index) / total, photo.filename)
            if await downloadFile(photo, to: destination, forceSidecar: forceSidecar) {
                successCount += 1
                if let lut {
                    let src = destination.appendingPathComponent(photo.filename)
                    let base = (photo.filename as NSString).deletingPathExtension
                    let out = processDir.appendingPathComponent("\(base).jpg")
                    let graded = await Task.detached(priority: .userInitiated) {
                        (try? LookProcessor().apply(lut: lut, to: src, outputURL: out,
                                                    format: .jpeg(quality: 0.95))) != nil
                    }.value
                    if graded { processedCount += 1 }
                }
            }
        }
        progressHandler(1.0, "Done")
        return successCount
    }

    // MARK: - Helpers

    private static func trimDiagnostic(_ s: String) -> String {
        let interesting = s.components(separatedBy: .newlines).filter { line in
            let l = line.lowercased()
            return l.contains("vid=") || l.contains("pid=") || l.contains("nokia")
                || l.contains("lumia") || l.contains("claim_interface")
                || l.contains("panic") || l.contains("unable to")
                || l.contains("storage") || l.contains("no raw devices")
                || l.contains("no devices") || l.contains("successfully connected")
                || l.contains("attempting to connect") || l.contains("ok.")
        }
        let trimmed = interesting.prefix(12).joined(separator: "\n")
        return trimmed.isEmpty ? String(s.prefix(400)) : trimmed
    }

    // MARK: - MTP contention / retry helpers

    /// libmtp merges stdout+stderr; these substrings appear when another process
    /// holds the MTP interface (libusb error -3 / LIBUSB_ERROR_BUSY). A persistent
    /// holder (e.g. the ChatGPT/Codex desktop app or Chrome) can’t be retried away.
    private static func isBusy(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("claim_interface")
            || l.contains("unable to initialize device")
            || l.contains("unable to open raw device")
            || l.contains("libmtp panic")
    }

    /// Superset of isBusy plus the "nothing on the bus" signatures — exactly the
    /// cases where the *next* attempt might succeed (transient plug-in race or a
    /// momentary contention that releases between tries).
    private static func isTransientFailure(_ s: String) -> Bool {
        let l = s.lowercased()
        return isBusy(s) || l.contains("no raw devices") || l.contains("no devices")
    }

    /// Run an mtp-* command, retrying briefly while the result looks transient.
    /// Bounded: `attempts` tries ~1s apart, so a persistent lock fails fast and a
    /// clean success returns on try 1.
    private func runMTPWithRetry(_ command: String, arguments: [String],
                                 attempts: Int = 4) async -> String {
        // Try once without touching ptpcamerad, so an idle launch with no phone —
        // or an uncontended phone — never kills the camera daemon. If that comes
        // back BUSY we free the daemon and retry; NODEVICE just retries.
        var output = await runCommand(command, arguments: arguments)
        if !Self.isTransientFailure(output) { return output }
        for _ in 1..<attempts {
            if Self.isBusy(output) { await reclaimPtpcamerad() }
            await Self.pause(0.7)
            output = await runCommand(command, arguments: arguments)
            if !Self.isTransientFailure(output) { return output }
        }
        return output
    }

    /// Deprecation-free, availability-free async sleep.
    private static func pause(_ seconds: Double) async {
        await withCheckedContinuation { cont in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { cont.resume() }
        }
    }

    /// Stop macOS’s ptpcamerad, which grabs the Lumia’s USB interface exclusively
    /// and causes libusb_claim_interface() = -3. It runs as the current user (no
    /// sudo) and launchd respawns it afterwards, so this is safe and reversible.
    /// Done via /bin/bash so we don’t depend on pkill being on PATH.
    private func reclaimPtpcamerad() async {
        _ = await runCommand("/bin/bash", arguments: [
            "-c", "pkill -9 -x ptpcamerad 2>/dev/null || true"
        ])
    }

    /// Pairing key: basename minus extension, with a trailing "_*highres" removed
    /// so "WP_<ts>_Raw__highres" (DNG) and "WP_<ts>_Raw" (JPEG) both key to
    /// "WP_<ts>_Raw".
    private static func pairKey(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        if let r = base.range(of: "_+highres$", options: .regularExpression) {
            return String(base[base.startIndex..<r.lowerBound])
        }
        return base
    }

    private static func nonEmptyFile(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }

    private static let busyMessage: String =
        "Your Mac sees the Lumia 1020, but its USB interface is locked, so libmtp "
        + "can’t read files (libusb error -3 / LIBUSB_ERROR_BUSY).\n\n"
        + "This app already tries to release the usual culprit — macOS’s camera "
        + "daemon (ptpcamerad, behind Photos / Image Capture) — automatically. If "
        + "you’re still seeing this, the interface is held by something else, most "
        + "often Google Chrome or the ChatGPT / Codex desktop app (both probe USB).\n\n"
        + "To free it:\n"
        + "1) Quit Google Chrome (and any USB-using tab/extension).\n"
        + "2) Quit the ChatGPT / Codex desktop app — that ends this Codex session, "
        + "so run the transfer from Terminal with ./lumia-transfer.sh (it releases "
        + "ptpcamerad itself and needs nothing quit), then relaunch Codex.\n"
        + "3) Unplug → wait 5s → replug into a direct port, unlock the phone, set "
        + "MTP, then press Refresh.\n\n"
        + "The libmtp output below shows the exact libusb_claim_interface() = -3 line."

    /// libmtp’s "Friendly name" for the 1020 is the generic "Nokia Lumia WP8"; map the
    /// known VID/PID (and the kernel-reported RM-877) to the real marketing name.
    private static func friendlyName(from output: String) -> String {
        let map: [String: String] = [
            "0421:0661": "Nokia Lumia 1020",
            "0421:0662": "Nokia Lumia 1020",
            "0421:0663": "Nokia Lumia 1020",
            "0421:06fc": "Nokia Lumia 1020",
        ]
        if let re = try? NSRegularExpression(pattern: "VID=([0-9A-Fa-f]+)\\s+and\\s+PID=([0-9A-Fa-f]+)"),
           let m = re.firstMatch(in: output, range: NSRange(location: 0, length: (output as NSString).length)),
           m.numberOfRanges >= 3 {
            let ns = output as NSString
            let vid = pad(ns.substring(with: m.range(at: 1)).lowercased(), to: 4)
            let pid = pad(ns.substring(with: m.range(at: 2)).lowercased(), to: 4)
            if let nice = map["\(vid):\(pid)"] { return nice }
        }
        if let f = field(output, "Friendly name:"), !f.isEmpty, f != "Nokia Lumia WP8" { return f }
        if output.contains("Nokia Lumia WP8") { return "Nokia Lumia 1020" }
        return "MTP Device"
    }

    private static func pad(_ s: String, to n: Int) -> String {
        s.count >= n ? s : String(repeating: "0", count: n - s.count) + s
    }

    private static func field(_ text: String, _ name: String) -> String? {
        for line in text.components(separatedBy: .newlines) where line.contains(name) {
            let parts = line.components(separatedBy: name)
            if parts.count > 1 { return parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private func extractField(_ text: String, field: String) -> String? {
        for line in text.components(separatedBy: .newlines) where line.contains(field) {
            let parts = line.components(separatedBy: field)
            if parts.count > 1 { return parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    /// Build a PATH that includes Homebrew so a GUI-launched app can find mtp-*.
    nonisolated private static func environmentWithHomebrewPath() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var merged: [String] = []
        for p in homebrewBins + existing where !merged.contains(p) { merged.append(p) }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    private func runCommand(_ command: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command] + arguments
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = Self.environmentWithHomebrewPath()
                do {
                    try process.run()
                    // Drain the pipe BEFORE waiting for exit. stdout+stderr share
                    // one pipe with a ~64 KB kernel buffer; mtp-filetree on a full
                    // phone easily exceeds that. If we waitUntilExit() first, the
                    // child blocks writing into a full pipe while we block waiting
                    // for it to exit → deadlock. Reading to EOF unblocks the child;
                    // EOF arrives when it closes the pipe (on exit).
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "Error running \(command): \(error.localizedDescription)")
                }
            }
        }
    }
}
