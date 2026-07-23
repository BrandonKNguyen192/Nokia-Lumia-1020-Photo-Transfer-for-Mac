import SwiftUI
import AppKit

// MARK: - Photo Cell View

struct PhotoCellView: View {
    let photo: PhotoItem
    let isSelected: Bool
    let thumbnailURL: URL?
    let onToggle: () -> Void
    /// Fires once when the cell scrolls into view. The manager downloads the
    /// thumbnail lazily and serially, then publishes it via thumbnailURLs.
    /// Returns true iff a thumbnail is now available.
    let onRequest: @Sendable () async -> Bool

    @State private var thumbnail: NSImage?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if loadFailed {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : Color.gray.opacity(0.5))
                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                Text(photo.isDNG ? "DNG" : "JPG")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(photo.isDNG ? Color.orange.opacity(0.9) : Color.blue.opacity(0.9))
                    )
                    .foregroundColor(.white)
                    .padding(6)
            }

            Text(photo.filename)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        // Lazy: only the cells that scroll into view kick off a (serial, cached)
        // download, so the grid never blocks on a whole-device thumbnail pass.
        .task {
            let ok = await onRequest()
            if !ok { loadFailed = true }
        }
        // Decode the (local, tiny) preview whenever the published URL appears.
        .task(id: thumbnailURL) {
            thumbnail = thumbnailURL.flatMap { NSImage(contentsOf: $0) }
        }
    }
}
