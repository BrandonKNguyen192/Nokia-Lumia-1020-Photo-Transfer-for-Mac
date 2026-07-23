import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var mtp = MTPManager()
    @State private var selectedIDs: Set<String> = []
    @State private var thumbnails: [String: URL] = [:]
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
                progressView("Detecting device…")
            case .scanning:
                progressView("Scanning phone storage…")
            case .downloadingThumbnails:
                progressView("Loading thumbnails…")
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
            .controlSize(.small)

            // Lightroom button
            Button {
                importToLightroom()
            } label: {
                Label("Lightroom", systemImage: "camera.aperture")
            }
            .disabled(selectedIDs.isEmpty)
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Refresh
            Button {
                Task {
                    await mtp.detectDevice()
                    await mtp.scanFiles()
                    await loadAllThumbnails()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Photo Grid

    private var filteredPhotos: [PhotoItem] {
        var items = mtp.photos
        if showOnlyDNG {
            items = items.filter(\.isDNG)
        }
        switch sortOrder {
        case .nameAsc: items.sort { $0.filename < $1.filename }
        case .nameDesc: items.sort { $0.filename > $1.filename }
        case .sizeAsc: items.sort { $0.fileSize < $1.fileSize }
        case .sizeDesc: items.sort { $0.fileSize > $1.fileSize }
        }
        return items
    }

    private var photoGrid: some View {
        ScrollView {
            if filteredPhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.4))
                    Text(showOnlyDNG ? "No DNG files found on the phone" : "No photos found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    if showOnlyDNG {
                        Text("Make sure you're shooting in RAW mode in Nokia Camera:\nSettings → Capture mode → RAW + JPEG")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredPhotos) { photo in
                        PhotoCellView(
                            photo: photo,
                            isSelected: selectedIDs.contains(photo.id),
                            thumbnailURL: thumbnails[photo.id]
                        ) {
                            toggleSelection(photo.id)
                        }
                        .contextMenu {
                            Button("Select") { selectedIDs.insert(photo.id) }
                            Button("Deselect") { selectedIDs.remove(photo.id) }
                            Divider()
                            Button("Download to Desktop") {
                                Task {
                                    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                                    _ = await mtp.downloadFile(photo, to: desktop)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.3))

            Text("No Device Connected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Connect your Nokia Lumia 1020 via USB cable,\nunlock the screen, and set USB mode to \"Media device (MTP)\".")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await mtp.detectDevice()
                    if mtp.deviceInfo?.isConnected == true {
                        await mtp.scanFiles()
                        await loadAllThumbnails()
                    }
                }
            } label: {
                Label("Detect Device", systemImage: "magnifyingglass")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

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

    private func transferView(progress: Double, currentFile: String) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress) {
                Text("Transferring…")
                    .font(.headline)
            } currentValueLabel: {
                Text(currentFile)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 300)

            Text("\(Int(progress * 100))%")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completedView(count: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Imported \(count) file\(count == 1 ? "" : "s")")
                .font(.title2)
                .fontWeight(.medium)

            if let dest = destinationURL {
                Text("Saved to: \(dest.path)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Open Folder") {
                    if let dest = destinationURL {
                        NSWorkspace.shared.open(dest)
                    }
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    mtp.state = .ready
                }
                .buttonStyle(.borderedProminent)
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
                Task {
                    await mtp.detectDevice()
                    if mtp.deviceInfo?.isConnected == true {
                        await mtp.scanFiles()
                        await loadAllThumbnails()
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            diagnosticPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func importSelected() {
        // If no destination set, default to ~/Pictures/Lumia 1020
        let dest = destinationURL ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumia 1020", isDirectory: true)

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
        let dest = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumia 1020", isDirectory: true)
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

    private func loadAllThumbnails() async {
        mtp.state = .downloadingThumbnails

        for photo in filteredPhotos {
            if let thumbURL = await mtp.downloadThumbnail(for: photo) {
                thumbnails[photo.id] = thumbURL
            }
        }

        mtp.state = .ready
    }
}
