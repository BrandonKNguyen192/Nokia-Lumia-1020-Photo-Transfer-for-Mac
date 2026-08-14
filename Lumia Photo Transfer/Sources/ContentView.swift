import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var mtp = MTPManager()
    @State private var selectedIDs: Set<String> = []
    @State private var destinationURL: URL?
    @State private var showFilePicker = false
    @State private var sortOrder: SortOption = .nameDesc
    @State private var showOnlyDNG = true
    @State private var isDragging = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            headerView

            Divider()

            // Main content
            switch mtp.state {
            case .idle:
                idleView
            case .detecting:
                progressView("Detecting device\u{2026}")
            case .scanning:
                progressView("Scanning phone storage\u{2026}")
            case .downloadingThumbnails:
                progressView("Loading thumbnails\u{2026}")
            case .ready:
                photoGrid
            case .transferring(let progress, let currentFile):
                transferView(progress: progress, currentFile: currentFile)
            case .completed(let count):
                completedView(count: count)
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                destinationURL = url
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDevice)) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Device status
            HStack(spacing: 6) {
                Circle()
                    .fill(mtp.deviceInfo?.isConnected == true ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(mtp.deviceInfo?.name ?? "No Device")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Filter toggle
            Toggle("DNG only", isOn: $showOnlyDNG)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(mtp.photos.isEmpty)

            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .frame(width: 100)
            .disabled(mtp.photos.isEmpty)

            Divider().frame(height: 20)

            // Selection count
            Text("\(selectedIDs.count) selected")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Select All / Deselect
            Button(selectedIDs.count == filteredPhotos.count ? "Deselect All" : "Select All") {
                if selectedIDs.count == filteredPhotos.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(filteredPhotos.map(\.id))
                }
            }
            .disabled(mtp.photos.isEmpty)

            Divider().frame(height: 20)

            // Import button
            Button {
                importSelected()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedIDs.isEmpty)
            .buttonStyle(.borderedProminent)

            // Import to Lightroom
            Button {
                importToLightroom()
            } label: {
                Label("Lightroom", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(selectedIDs.isEmpty)

            // Destination picker
            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "folder")
            }
            .help(destinationURL?.path ?? "Choose destination folder")

            // Refresh
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filtered & Sorted Photos

    private var filteredPhotos: [PhotoItem] {
        var result = mtp.photos
        if showOnlyDNG {
            result = result.filter { $0.isDNG }
        }
        switch sortOrder {
        case .nameAsc:  result.sort { $0.filename < $1.filename }
        case .nameDesc: result.sort { $0.filename > $1.filename }
        case .sizeAsc:  result.sort { $0.fileSize < $1.fileSize }
        case .sizeDesc: result.sort { $0.fileSize > $1.fileSize }
        }
        return result
    }

    // MARK: - Views

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cable.connector")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Connect your phone via USB")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Unlock the phone, then set USB mode to \u{201C}Media device (MTP)\u{201D}")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))

            Button("Detect Device") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)

            diagnosticPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoGrid: some View {
        VStack(spacing: 0) {
            if filteredPhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    if showOnlyDNG && !mtp.photos.isEmpty {
                        Text("No DNG files found. Toggle \u{201C}DNG only\u{201D} off to see JPEGs.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No photos found on device.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredPhotos) { photo in
                            PhotoCellView(
                                photo: photo,
                                isSelected: selectedIDs.contains(photo.id),
                                thumbnailURL: mtp.thumbnailURLs[photo.id],
                                onToggle: { toggleSelection(photo.id) },
                                onRequest: { await mtp.requestThumbnail(for: photo) }
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Status bar
            HStack {
                Text("\(filteredPhotos.count) photo\(filteredPhotos.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                if let dest = destinationURL {
                    Text("Saving to: \(dest.lastPathComponent)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Default: \(defaultDestinationPath)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            diagnosticPanel
        }
    }

    private func transferView(progress: Double, currentFile: String) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .frame(width: 300)

            Text(currentFile)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text("\(Int(progress * 100))%")
                .font(.title2)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completedView(count: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Imported \(count) photo\(count == 1 ? "" : "s")")
                .font(.title3)

            if let dest = destinationURL {
                Text("Saved to \(dest.path)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Import More") {
                    selectedIDs.removeAll()
                    Task { await refresh() }
                }
                .buttonStyle(.borderedProminent)

                if let dest = destinationURL {
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(dest)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diagnostic panel

    /// Collapsible, copyable view of the trimmed libmtp output captured
    /// during the last detect/scan. Only renders when non-empty, so it
    /// stays out of the way on a clean first launch.
    @ViewBuilder
    private var diagnosticPanel: some View {
        if !mtp.rawDiagnostic.isEmpty {
            DisclosureGroup("libmtp output") {
                ScrollView {
                    Text(mtp.rawDiagnostic)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)

                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mtp.rawDiagnostic, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: 480)
            .padding(.top, 4)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Try Again") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)

            diagnosticPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Re-run detect \u{2192} scan, guarding scan on a successful detect. Single source
    /// of truth for the toolbar Refresh button, the idle/error CTAs, the \u{2318}R /
    /// Device menu (via .refreshDevice), and the one-shot launch detect in `.task`.
    /// Thumbnails are NOT loaded here \u{2014} the grid fetches them lazily per cell, so
    /// the UI reaches .ready (interactive) as soon as the file list is parsed.
    private func refresh() async {
        await mtp.detectDevice()
        if mtp.deviceInfo?.isConnected == true {
            await mtp.scanFiles()
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Default destination folder, named after whatever device is connected
    /// (e.g. ~/Pictures/Nokia Lumia). Falls back to a generic "Lumia Photos".
    private var defaultDestination: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let name = mtp.deviceInfo?.name
            .flatMap(Self.sanitizeFolderComponent(_:))
            ?? "Lumia Photos"
        return pictures.appendingPathComponent(name, isDirectory: true)
    }

    private var defaultDestinationPath: String {
        let url = destinationURL ?? defaultDestination
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Fold a device-reported name into a safe single path component.
    private static func sanitizeFolderComponent(_ name: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let cleaned = String(name.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : Character(" ")
        })
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func importSelected() {
        // If no destination set, default to ~/Pictures/<Device Name>
        let dest = destinationURL ?? defaultDestination

        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        destinationURL = dest

        let selectedPhotos = filteredPhotos.filter { selectedIDs.contains($0.id) }

        Task {
            let count = await mtp.downloadFiles(selectedPhotos, to: dest) { progress, file in
                mtp.state = .transferring(progress: progress, currentFile: file)
            }
            mtp.state = .completed(count: count)
        }
    }

    private func importToLightroom() {
        let dest = defaultDestination
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        destinationURL = dest

        let selectedPhotos = filteredPhotos.filter { selectedIDs.contains($0.id) }

        Task {
            let count = await mtp.downloadFiles(selectedPhotos, to: dest) { progress, file in
                mtp.state = .transferring(progress: progress, currentFile: file)
            }

            if count > 0 {
                // Open in Lightroom Classic
                let lightroomPath = "/Applications/Adobe Lightroom Classic.app"
                if FileManager.default.fileExists(atPath: lightroomPath) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-a", "Adobe Lightroom Classic", dest.path]
                    try? task.run()
                } else {
                    // Fallback: open the folder in Finder
                    NSWorkspace.shared.open(dest)
                }
            }

            mtp.state = .completed(count: count)
        }
    }

}
