import SwiftUI

struct PlaylistDetailView: View {
    @Binding var playlist: Playlist
    let library: [Track]
    let onSave: () -> Void
    @EnvironmentObject private var player: AudioPlayerManager

    private var tracks: [Track] {
        playlist.trackIDs.compactMap { id in
            library.first { $0.id == id }
        }
    }

    var body: some View {
        Group {
            if tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Empty Playlist")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Long-press tracks in the Library to add them here.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Button {
                            playPlaylist()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                        }
                    }

                    Section {
                        ForEach(tracks) { track in
                            Button {
                                let list = tracks
                                if let idx = list.firstIndex(where: { $0.id == track.id }) {
                                    player.play(track: track, queue: list, startIndex: idx)
                                }
                            } label: {
                                TrackRow(track: track)
                            }
                        }
                        .onDelete(perform: deleteTrack)
                        .onMove(perform: moveTrack)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            if !tracks.isEmpty {
                EditButton()
            }
        }
    }

    private func playPlaylist() {
        let list = tracks
        guard let first = list.first else { return }
        player.play(track: first, queue: list, startIndex: 0)
    }

    private func deleteTrack(at offsets: IndexSet) {
        playlist.trackIDs.remove(atOffsets: offsets)
        onSave()
    }

    private func moveTrack(from source: IndexSet, to destination: Int) {
        playlist.trackIDs.move(fromOffsets: source, toOffset: destination)
        onSave()
    }
}
