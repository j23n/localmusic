import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var playlists: [Playlist] = []
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var library: [Track] = []

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Playlists")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Tap + to create your first playlist.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlist: binding(for: playlist),
                                    library: library,
                                    onSave: savePlaylists
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.body)
                                        Text("\(playlist.trackIDs.count) track\(playlist.trackIDs.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deletePlaylists)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    createPlaylist()
                }
            } message: {
                Text("Enter a name for the new playlist.")
            }
        }
        .onAppear {
            playlists = PersistenceManager.shared.loadPlaylists()
            library = PersistenceManager.shared.loadLibrary()
        }
    }

    private func binding(for playlist: Playlist) -> Binding<Playlist> {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            return .constant(playlist)
        }
        return $playlists[idx]
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let playlist = Playlist(id: UUID(), name: name, trackIDs: [])
        playlists.append(playlist)
        savePlaylists()
    }

    private func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }

    private func savePlaylists() {
        PersistenceManager.shared.savePlaylists(playlists)
    }
}
