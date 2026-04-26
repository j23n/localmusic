import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var showLyrics = false
    @State private var lyrics: TrackLyrics?
    @State private var lyricsTrackID: UUID?
    @State private var artworkColor: UIColor = .systemGray
    @State private var artworkColorTrackID: UUID?

    var body: some View {
        NavigationStack {
            if let track = player.currentTrack {
                nowPlayingContent(track: track)
                    .navigationTitle("Now Playing")
                    .navigationBarTitleDisplayMode(.inline)
                    .task(id: track.id) {
                        await loadAuxiliary(for: track)
                    }
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Image(systemName: "play.circle")
                            .font(.system(size: 40))
                            .foregroundColor(Color.accentColor)
                    }
                    Text("Nothing Playing")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Select a track from the Library to start playing.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("Now Playing")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func nowPlayingContent(track: Track) -> some View {
        let artworkSize = UIScreen.main.bounds.width - 48
        let color = Color(artworkColor)
        // Only show the flip affordance once the lyrics payload is loaded
        // and confirmed non-empty, so we don't promise content the disk
        // load might fail to deliver.
        let hasLoadedLyrics = lyrics?.isEmpty == false

        return ZStack {
            // Ambient background
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.5),
                            color.opacity(0.12),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: track.id)

            VStack(spacing: 0) {
                Spacer()

                // Artwork / Lyrics flip
                ZStack {
                    artworkView(track: track)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        .opacity(showLyrics ? 0 : 1)
                        .rotation3DEffect(.degrees(showLyrics ? 180 : 0), axis: (x: 0, y: 1, z: 0))

                    lyricsView(track: track, size: artworkSize)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(showLyrics ? 1 : 0)
                        .rotation3DEffect(.degrees(showLyrics ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                }
                .shadow(color: color.opacity(0.45), radius: 28, x: 0, y: 12)
                .animation(.spring(response: 0.5), value: track.id)
                .onTapGesture {
                    if hasLoadedLyrics {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showLyrics.toggle()
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hasLoadedLyrics && !showLyrics {
                        Image(systemName: "quote.opening")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            .padding(10)
                    }
                }
                .onChange(of: track.id) { _, _ in
                    showLyrics = false
                }

                Spacer().frame(height: 28)

                // Track info
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(track.album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                // Seek slider
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    .tint(.primary)

                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text("-\(formatTime(max(0, player.duration - player.currentTime)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                // Transport controls
                HStack(spacing: 44) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 28))
                    }

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44))
                            .contentTransition(.symbolEffect(.replace))
                    }

                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 28))
                    }
                }
                .foregroundStyle(.primary)

                Spacer().frame(height: 20)

                // Shuffle & Repeat
                HStack(spacing: 48) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.body)
                            .foregroundStyle(player.shuffleEnabled ? Color.accentColor : .secondary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(player.shuffleEnabled ? Color.accentColor.opacity(0.15) : .clear)
                            )
                            .contentShape(Circle())
                    }

                    Button { player.cycleRepeatMode() } label: {
                        Image(systemName: repeatIcon)
                            .font(.body)
                            .foregroundStyle(player.repeatMode != .off ? Color.accentColor : .secondary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(player.repeatMode != .off ? Color.accentColor.opacity(0.15) : .clear)
                            )
                            .contentShape(Circle())
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(track: Track) -> some View {
        ArtworkView(
            trackURL: track.url,
            hasArtwork: track.hasArtwork,
            pointSize: UIScreen.main.bounds.width - 48,
            fullResolution: true,
            placeholderIcon: "music.note"
        )
    }

    // MARK: - Lyrics

    @ViewBuilder
    private func lyricsView(track: Track, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            if let synced = lyrics?.synced, !synced.isEmpty {
                SyncedLyricsView(lines: synced, currentTime: player.currentTime)
                    .padding(20)
            } else if let unsynced = lyrics?.unsynced, !unsynced.isEmpty {
                ScrollView {
                    Text(unsynced)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            } else if track.hasLyrics {
                ProgressView()
            }
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Auxiliary loads (lyrics + dominant color)

    private func loadAuxiliary(for track: Track) async {
        // Lyrics
        if lyricsTrackID != track.id {
            lyrics = nil
            lyricsTrackID = track.id
            if track.hasLyrics {
                let loaded = await LyricsCache.load(for: track.url)
                if lyricsTrackID == track.id {
                    lyrics = loaded
                }
            }
        }

        // Dominant color — compute once per track and cache.
        if artworkColorTrackID != track.id {
            artworkColorTrackID = track.id
            if track.hasArtwork,
               let cached = ArtworkColorCache.color(for: track.url) {
                artworkColor = cached
            } else if track.hasArtwork {
                let scale = UIScreen.main.scale
                let image = await ArtworkCache.thumbnail(for: track.url,
                                                          pointSize: 80,
                                                          scale: scale)
                if let image, let color = image.dominantColor {
                    ArtworkColorCache.set(color, for: track.url)
                    if artworkColorTrackID == track.id {
                        artworkColor = color
                    }
                } else if artworkColorTrackID == track.id {
                    artworkColor = .systemGray
                }
            } else {
                artworkColor = .systemGray
            }
        }
    }
}

// MARK: - Synced Lyrics View

struct SyncedLyricsView: View {
    let lines: [SyncedLyricLine]
    let currentTime: Double

    /// Binary-searches for the largest index whose timestamp is `<= currentTime`.
    /// Replaces a per-tick linear scan over potentially hundreds of lines.
    private var activeIndex: Int {
        guard !lines.isEmpty else { return 0 }
        var lo = 0
        var hi = lines.count - 1
        var best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].timestamp <= currentTime {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(.body)
                            .fontWeight(index == activeIndex ? .semibold : .regular)
                            .foregroundStyle(index == activeIndex ? .primary : .secondary)
                            .opacity(index == activeIndex ? 1.0 : 0.5)
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onChange(of: activeIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Dominant Color Cache

/// Caches the result of `UIImage.dominantColor` per track URL so we don't
/// re-run the (50–150 ms) CIAreaAverage filter on every Now Playing render.
enum ArtworkColorCache {
    private static let storage: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        cache.countLimit = 64
        return cache
    }()

    static func color(for trackURL: URL) -> UIColor? {
        storage.object(forKey: ArtworkCache.key(for: trackURL) as NSString)
    }

    static func set(_ color: UIColor, for trackURL: URL) {
        storage.setObject(color, forKey: ArtworkCache.key(for: trackURL) as NSString)
    }
}

// MARK: - Dominant Color Extraction

extension UIImage {
    var dominantColor: UIColor? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let extent = ciImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y,
                                     z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: extentVector]),
              let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255,
                       green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255,
                       alpha: 1)
    }
}
