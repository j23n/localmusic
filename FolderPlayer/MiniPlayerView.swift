import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "")
                    .font(.body)
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
                    .animation(.spring(), value: player.isPlaying)
            }
            .padding(.horizontal, 4)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                Color.gray.opacity(0.3)
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
