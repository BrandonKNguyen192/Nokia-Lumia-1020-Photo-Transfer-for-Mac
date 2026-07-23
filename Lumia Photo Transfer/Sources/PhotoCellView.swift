import SwiftUI
import AppKit

// MARK: - Photo Cell View

struct PhotoCellView: View {
    let photo: PhotoItem
    let isSelected: Bool
    let thumbnailURL: URL?
    let onToggle: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail
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
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .gray.opacity(0.5))
                    .background(Circle().fill(.white).frame(width: 18, height: 18))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                // File type badge
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

            // Filename
            Text(photo.filename)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .onLoad {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard let url = thumbnailURL else {
            isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    self.thumbnail = image
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - View Extension for onLoad

extension View {
    func onLoad(perform action: @escaping () -> Void) -> some View {
        self.onAppear(perform: action)
    }
}
