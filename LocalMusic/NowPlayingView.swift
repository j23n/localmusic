import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var showLyrics = false

    var body: some View {
        NavigationStack {
            if let track = player.currentTrack {
                nowPlayingContent(track: track)
                    .navigationTitle("Now Playing")
                    .navigationBarTitleDisplayMode(.inline)
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
        let artworkColor = track.artworkData
            .flatMap { UIImage(data: $0) }
            .flatMap { $0.dominantColor } ?? UIColor.systemGray

        let artworkSize = UIScreen.main.bounds.width - 48

        return ZStack {
            // Ambient background
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(artworkColor).opacity(0.5),
                            Color(artworkColor).opacity(0.12),
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
                    // Front: artwork
                    artworkView(track: track)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        .opacity(showLyrics ? 0 : 1)
                        .rotation3DEffect(.degrees(showLyrics ? 180 : 0), axis: (x: 0, y: 1, z: 0))

                    // Back: lyrics
                    lyricsView(track: track, size: artworkSize)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(showLyrics ? 1 : 0)
                        .rotation3DEffect(.degrees(showLyrics ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                }
                .shadow(color: Color(artworkColor).opacity(0.45), radius: 28, x: 0, y: 12)
                .animation(.spring(response: 0.5), value: track.id)
                .onTapGesture {
                    if track.hasLyrics {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showLyrics.toggle()
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if track.hasLyrics && !showLyrics {
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
                            .foregroundStyle(player.shuffleEnabled ? .primary : .secondary)
                    }

                    Button { player.cycleRepeatMode() } label: {
                        Image(systemName: repeatIcon)
                            .font(.body)
                            .foregroundStyle(player.repeatMode != .off ? .primary : .secondary)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(track: Track) -> some View {
        if let data = track.artworkData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.85).opacity(0.3)
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    // MARK: - Lyrics

    @ViewBuilder
    private func lyricsView(track: Track, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            if let syncedLines = track.syncedLyrics {
                SyncedLyricsView(lines: syncedLines, currentTime: player.currentTime)
                    .padding(20)
            } else if let lyrics = track.lyrics {
                ScrollView {
                    Text(lyrics)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
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
}

// MARK: - Synced Lyrics View

struct SyncedLyricsView: View {
    let lines: [SyncedLyricLine]
    let currentTime: Double

    private var activeIndex: Int {
        var best = 0
        for (i, line) in lines.enumerated() {
            if currentTime >= line.timestamp {
                best = i
            } else {
                break
            }
        }
        return best
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
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
