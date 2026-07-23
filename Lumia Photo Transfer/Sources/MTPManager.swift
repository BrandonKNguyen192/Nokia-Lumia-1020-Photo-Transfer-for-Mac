import Foundation

// MARK: - MTP Manager (wraps libmtp CLI tools)

@MainActor
class MTPManager: ObservableObject {

    @Published var deviceInfo: MTPDeviceInfo?
    @Published var photos: [PhotoItem] = []
    @Published var state: TransferState = .idle
    @Published var errorMessage: String = ""

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

        if output.contains("No raw devices found") || output.contains("No devices") {
            state = .error("No MTP device found. Connect your Lumia 1020 via USB, unlock it, and set USB mode to 'Media device (MTP)'.")
            return
        }

        let name = extractField(output, field: "Friendly name:") ?? "Unknown Device"
        let model = extractField(output, field: "Model:") ?? "Unknown"
        let serial = extractField(output, field: "Serial number:") ?? ""

        deviceInfo = MTPDeviceInfo(name: name, model: model, serial: serial, isConnected: true)
    }

    // MARK: - File Scanning

    func scanFiles() async {
        state = .scanning
        let output = await runCommand("mtp-filetree", arguments: [])

        if output.contains("No raw devices") || output.contains("No devices") {
            state = .error("Lost connection to device. Please reconnect.")
            return
        }

        let lines = output.components(separatedBy: .newlines)
        var dngFiles: [PhotoItem] = []
        var jpegFiles: [String: PhotoItem] = [:]  // baseName -> PhotoItem

        // First pass: collect all files
        var allFiles: [(path: String, id: String, name: String, size: UInt64)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse: /path/to/file.ext [fileid]
            guard let idRange = trimmed.range(of: " [", options: .backwards) else { continue }
            let pathPart = String(trimmed[trimmed.startIndex..<idRange.lowerBound])
            let idPart = String(trimmed[idRange.upperBound...]).replacingOccurrences(of: "]", with: "")

            guard let fileID = UInt32(idPart) else { continue }
            let filename = (pathPart as NSString).lastPathComponent
            let ext = (filename as NSString).pathExtension.lowercased()

            // Only care about image files
            guard ["dng", "jpg", "jpeg"].contains(ext) else { continue }

            // Estimate size (we don't get it from filetree, so use 0 for now)
            allFiles.append((path: pathPart, id: String(fileID), name: filename, size: 0))
        }

        // Second pass: pair DNGs with JPEGs
        // Build a lookup of JPEGs by base name
        for file in allFiles {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" {
                let baseName = (file.name as NSString).deletingPathExtension
                jpegFiles[baseName] = PhotoItem(
                    id: file.id,
                    filename: file.name,
                    filepath: file.path,
                    fileSize: file.size,
                    isDNG: false,
                    isJPEG: true,
                    dngFileID: nil,
                    jpegFileID: nil,
                    jpegFilename: nil
                )
            }
        }

        // Build DNG items with JPEG pairing
        for file in allFiles {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ext == "dng" {
                let baseName = (file.name as NSString).deletingPathExtension
                    .replacingOccurrences(of: "_Raw_highres", with: "")

                let pairedJPEG = jpegFiles[baseName]

                let item = PhotoItem(
                    id: file.id,
                    filename: file.name,
                    filepath: file.path,
                    fileSize: file.size,
                    isDNG: true,
                    isJPEG: false,
                    dngFileID: nil,
                    jpegFileID: pairedJPEG?.id,
                    jpegFilename: pairedJPEG?.filename
                )
                dngFiles.append(item)
            }
        }

        // If no DNGs found, show JPEGs
        if dngFiles.isEmpty {
            photos = Array(jpegFiles.values).sorted { $0.filename < $1.filename }
        } else {
            photos = dngFiles.sorted { $0.filename < $1.filename }
        }

        state = .ready
    }

    // MARK: - Thumbnail Generation

    func downloadThumbnail(for photo: PhotoItem) async -> URL? {
        // For DNG files, download the paired JPEG (much smaller) for the thumbnail
        // For JPEG files, download the JPEG itself
        let targetID: String
        let targetName: String

        if photo.isDNG, let jpegID = photo.jpegFileID, let jpegName = photo.jpegFilename {
            targetID = jpegID
            targetName = jpegName
        } else {
            targetID = photo.id
            targetName = photo.filename
        }

        let thumbDir = tempDir.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        let thumbPath = thumbDir.appendingPathComponent("thumb_\(targetID).jpg")

        // Check if thumbnail already cached
        if FileManager.default.fileExists(atPath: thumbPath.path) {
            return thumbPath
        }

        // Download the JPEG for thumbnail
        let destPath = thumbDir.appendingPathComponent(targetName)
        _ = await runCommand("mtp-getfile", arguments: [targetID, destPath.path])

        if FileManager.default.fileExists(atPath: destPath.path) {
            // Generate a smaller thumbnail using sips
            let _ = await runCommand("sips", arguments: [
                "-Z", "400",
                destPath.path,
                "--out", thumbPath.path
            ])

            // Clean up the full-size download
            try? FileManager.default.removeItem(at: destPath)

            if FileManager.default.fileExists(atPath: thumbPath.path) {
                return thumbPath
            }
            // If sips failed, use the full download as thumbnail
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
        let total = Double(photos.count)

        for (index, photo) in photos.enumerated() {
            let progress = Double(index) / total
            progressHandler(progress, photo.filename)

            if await downloadFile(photo, to: destination) {
                successCount += 1
            }
        }

        progressHandler(1.0, "Done")
        return successCount
    }

    // MARK: - Helpers

    private func extractField(_ text: String, field: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            if line.contains(field) {
                let parts = line.components(separatedBy: field)
                if parts.count > 1 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
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

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
