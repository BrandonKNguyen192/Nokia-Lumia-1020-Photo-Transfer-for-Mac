import Foundation
import SwiftUI

// MARK: - Photo Item Model

struct PhotoItem: Identifiable, Hashable {
    let id: String            // MTP file ID
    let filename: String
    let filepath: String      // Full path on phone
    let fileSize: UInt64
    let isDNG: Bool
    let isJPEG: Bool
    let dngFileID: String?    // If this is a JPEG, the paired DNG file ID
    let jpegFileID: String?   // If this is a DNG, the paired JPEG file ID
    let jpegFilename: String? // Paired JPEG filename

    var displayName: String {
        filename
    }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    // Base name without extension for pairing
    var baseName: String {
        let name = (filename as NSString).deletingPathExtension
        // Remove _Raw_highres suffix for DNG files
        return name.replacingOccurrences(of: "_Raw_highres", with: "")
    }
}

// MARK: - Device Info

struct MTPDeviceInfo {
    let name: String
    let model: String
    let serial: String
    let isConnected: Bool
}

// MARK: - Transfer State

enum TransferState: Equatable {
    case idle
    case detecting
    case scanning
    case downloadingThumbnails
    case ready
    case transferring(progress: Double, currentFile: String)
    case completed(count: Int)
    case error(String)

    static func == (lhs: TransferState, rhs: TransferState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.detecting, .detecting),
             (.scanning, .scanning), (.downloadingThumbnails, .downloadingThumbnails),
             (.ready, .ready):
            return true
        case (.transferring(let p1, let f1), .transferring(let p2, let f2)):
            return p1 == p2 && f1 == f2
        case (.completed(let c1), .completed(let c2)):
            return c1 == c2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - Sort Options

enum SortOption: String, CaseIterable {
    case nameAsc = "Name ↑"
    case nameDesc = "Name ↓"
    case sizeAsc = "Size ↑"
    case sizeDesc = "Size ↓"
}

// MARK: - Look Apply Mode

/// How a selected colour profile ("Look") is applied on import.
///  - `.none`:    download originals only.
///  - `.sidecar`: also drop a `.xmp` next to each file for Lightroom to read.
///  - `.process`: render each file through the Look ourselves (CoreImage) and
///                write a graded JPEG to a `Processed/` subfolder — no Lightroom.
enum ApplyMode: String, CaseIterable, Identifiable {
    case none = "Off"
    case sidecar = "Sidecar (LR)"
    case process = "Process JPEG"
    var id: String { rawValue }
}
