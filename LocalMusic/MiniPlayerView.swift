import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    let onTap: () -> Void

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 2)
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .frame(height: 2)
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                artworkView
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 4)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let data = player.currentTrack?.artworkData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.85).opacity(0.5)
                Image(systemName: "music.note")
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }
}
