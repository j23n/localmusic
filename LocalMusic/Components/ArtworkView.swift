import SwiftUI

/// Shows artwork for a track URL, loading from `ArtworkCache` asynchronously.
/// Avoids the synchronous `UIImage(data:)` decode in row rendering paths.
struct ArtworkView: View {
    let trackURL: URL?
    let hasArtwork: Bool
    let pointSize: CGFloat
    var fullResolution: Bool = false
    var placeholderIcon: String = "music.note"

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.85).opacity(0.5)
                    Image(systemName: placeholderIcon)
                        .font(.body)
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
        .task(id: identityKey) {
            await load()
        }
    }

    private var identityKey: String {
        let path = trackURL?.absoluteString ?? "_"
        return "\(path)|\(Int(pointSize))|\(fullResolution ? 1 : 0)|\(hasArtwork ? 1 : 0)"
    }

    private func load() async {
        guard let url = trackURL, hasArtwork else {
            image = nil
            return
        }
        let scale = displayScale > 0 ? displayScale : 2.0
        if fullResolution {
            if let cached = ArtworkCache.cachedFullImage(for: url) {
                image = cached
                return
            }
            image = await ArtworkCache.fullImage(for: url, pointSize: pointSize, scale: scale)
        } else {
            if let cached = ArtworkCache.cachedThumbnail(for: url) {
                image = cached
                return
            }
            image = await ArtworkCache.thumbnail(for: url, pointSize: pointSize, scale: scale)
        }
    }
}
