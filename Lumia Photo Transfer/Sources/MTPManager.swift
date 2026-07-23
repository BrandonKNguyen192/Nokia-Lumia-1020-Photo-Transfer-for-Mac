import Foundation

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

    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumiaPhotoTransfer", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    // MARK: - Device Detection

    func detectDevice() async {
        state = .detecting
        let output = await runCommand("mtp-detect", arguments: [])
        rawDiagnostic = Self.trimDiagnostic(output)

        if output.contains("No raw devices found") || output.contains("No devices") {
            deviceInfo = nil
            state = .error("No MTP device found.\n\n"
                + "1) Connect the Lumia 1020 with a USB *data* cable (not charge-only).\n"
                + "2) Unlock the phone and keep the screen awake.\n"
                + "3) Pull down the notification shade → USB → “Media device (MTP)”.\n"
                + "4) Wait ~3s, then press Detect again.\n\n"
                + diagnosticBlock())
            return
        }

        let name = extractField(output, field: "Friendly name:")
            ?? (output.contains("Nokia Lumia WP8") ? "Nokia Lumia WP8" : "MTP Device")
        let model = extractField(output, field: "Model:") ?? "Lumia 1020"
        let serial = extractField(output, field: "Serial number:") ?? ""

        deviceInfo = MTPDeviceInfo(name: name, model: model, serial: serial, isConnected: true)
    }

    // MARK: - File Scanning

    func scanFiles() async {
        state = .scanning
        let output = await runCommand("mtp-filetree", arguments: [])
        rawDiagnostic = Self.trimDiagnostic(output)

        if output.contains("No raw devices") || output.contains("No devices") {
            deviceInfo = nil
            state = .error("Lost connection to device. Reconnect, unlock, and Detect again.\n\n"
                + diagnosticBlock())
            return
        }

        let lines = output.components(separatedBy: .newlines)
        var dngFiles: [PhotoItem] = []
        var jpegFiles: [String: PhotoItem] = [:]
        var allFiles: [(path: String, id: String, name: String, size: UInt64)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let idRange = trimmed.range(of: " [", options: .backwards) else { continue }
            let pathPart = String(trimmed[trimmed.startIndex..<idRange.lowerBound])
            let idPart = String(trimmed[idRange.upperBound...])
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard UInt32(idPart) != nil else { continue }
            let filename = (pathPart as NSString).lastPathComponent
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ["dng", "jpg", "jpeg"].contains(ext) else { continue }
            allFiles.append((path: pathPart, id: idPart, name: filename, size: 0))
        }

        for file in allFiles {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" {
                let baseName = (file.name as NSString).deletingPathExtension
                jpegFiles[baseName] = PhotoItem(
                    id: file.id, filename: file.name, filepath: file.path,
                    fileSize: file.size, isDNG: false, isJPEG: true,
                    dngFileID: nil, jpegFileID: nil, jpegFilename: nil)
            }
        }

        for file in allFiles {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ext == "dng" {
                let baseName = (file.name as NSString).deletingPathExtension
                    .replacingOccurrences(of: "_Raw_highres", with: "")
                let pairedJPEG = jpegFiles[baseName]
                dngFiles.append(PhotoItem(
                    id: file.id, filename: file.name, filepath: file.path,
                    fileSize: file.size, isDNG: true, isJPEG: false,
                    dngFileID: nil, jpegFileID: pairedJPEG?.id,
                    jpegFilename: pairedJPEG?.filename))
            }
        }

        if dngFiles.isEmpty {
            photos = Array(jpegFiles.values).sorted { $0.filename < $1.filename }
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
                + "• A flaky USB link (libusb claim_interface error) — unplug, wait 5s, "
                + "replug firmly into a direct port (no hub), unlock, then Detect.\n\n"
                + "Tip: also try opening OpenMTP (/Applications) as a cross-check — "
                + "if it sees files where this app doesn’t, tell me and I’ll swap the backend.\n\n"
                + diagnosticBlock())
            return
        }

        state = .ready
    }

    // MARK: - Thumbnail Generation

    func downloadThumbnail(for photo: PhotoItem) async -> URL? {
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
        _ = await runCommand("mtp-getfile", arguments: [targetID, destPath.path])

        if FileManager.default.fileExists(atPath: destPath.path) {
            _ = await runCommand("sips", arguments: ["-Z", "400", destPath.path, "--out", thumbPath.path])
            try? FileManager.default.removeItem(at: destPath)
            if FileManager.default.fileExists(atPath: thumbPath.path) { return thumbPath }
            return destPath
        }
        return nil
    }

    // MARK: - File Download

    func downloadFile(_ photo: PhotoItem, to destination: URL) async -> Bool {
        let destPath = destination.appendingPathComponent(photo.filename)
        _ = await runCommand("mtp-getfile", arguments: [photo.id, destPath.path])
        return FileManager.default.fileExists(atPath: destPath.path)
    }

    func downloadFiles(_ photos: [PhotoItem], to destination: URL,
                       progressHandler: @escaping (Double, String) -> Void) async -> Int {
        var successCount = 0
        let total = Double(max(photos.count, 1))
        for (index, photo) in photos.enumerated() {
            progressHandler(Double(index) / total, photo.filename)
            if await downloadFile(photo, to: destination) { successCount += 1 }
        }
        progressHandler(1.0, "Done")
        return successCount
    }

    // MARK: - Helpers

    private func diagnosticBlock() -> String {
        rawDiagnostic.isEmpty ? "(no diagnostic output captured)"
                              : "— libmtp output —\n" + rawDiagnostic
    }

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
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "Error running \(command): \(error.localizedDescription)")
                }
            }
        }
    }
}
