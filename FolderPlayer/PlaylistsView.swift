import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var playlists: [Playlist] = []
    @State private var library: [Track] = []
    @State private var isLoading = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Scanning for playlists…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Playlists Found")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Add .m3u or .pls files to your music folder, or tap + to create one.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: $playlists[index], library: library)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.body)
                                    Text("\(playlist.trackURLs.count) track\(playlist.trackURLs.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                        Label("New Playlist", systemImage: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    createPlaylist()
                }
            } message: {
                Text("Enter a name for the new playlist.")
            }
        }
        .onAppear {
            loadPlaylists()
        }
    }

    private func loadPlaylists() {
        library = PersistenceManager.shared.loadLibrary()
        guard let url = PersistenceManager.shared.loadFolderBookmark() else { return }
        isLoading = playlists.isEmpty
        Task {
            let found = MetadataLoader.scanPlaylists(in: url)
            await MainActor.run {
                playlists = found
                isLoading = false
            }
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let folderURL = PersistenceManager.shared.loadFolderBookmark() else { return }
        let playlist = MetadataLoader.createPlaylist(name: name, in: folderURL)
        playlists.append(playlist)
        playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets {
            let playlist = playlists[index]
            try? FileManager.default.removeItem(at: playlist.fileURL)
        }
        playlists.remove(atOffsets: offsets)
    }
}
