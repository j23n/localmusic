import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        NavigationStack {
            if let track = player.currentTrack {
                nowPlayingContent(track: track)
                    .navigationTitle("Now Playing")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
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
        VStack(spacing: 0) {
            Spacer()

            // Artwork
            artworkView(track: track)
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                .animation(.spring(), value: track.id)

            Spacer().frame(height: 32)

            // Track info
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.title2)
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
                        .animation(.spring(), value: player.isPlaying)
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

    @ViewBuilder
    private func artworkView(track: Track) -> some View {
        if let data = track.artworkData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
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
