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
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 100, height: 100)
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 40))
                                .foregroundColor(Color.accentColor)
                        }
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
                                HStack(spacing: 14) {
                                    PlaylistMosaicView(
                                        trackURLs: playlist.trackURLs,
                                        library: library
                                    )
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        Text("\(playlist.trackURLs.count) track\(playlist.trackURLs.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deletePlaylists)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Playlists")
            .refreshable {
                await refreshPlaylists()
            }
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

    private func refreshPlaylists() async {
        library = PersistenceManager.shared.loadLibrary()
        guard let url = PersistenceManager.shared.loadFolderBookmark() else { return }
        let found = MetadataLoader.scanPlaylists(in: url)
        playlists = found
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

// MARK: - Playlist Mosaic Thumbnail

struct PlaylistMosaicView: View {
    let trackURLs: [URL]
    let library: [Track]

    private var artworkImages: [Data] {
        var images: [Data] = []
        for url in trackURLs {
            if images.count >= 4 { break }
            if let track = library.first(where: { $0.url.standardized == url.standardized }),
               let data = track.artworkData {
                images.append(data)
            }
        }
        return images
    }

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            if artworkImages.isEmpty {
                ZStack {
                    Color(white: 0.85).opacity(0.5)
                    Image(systemName: "music.note.list")
                        .font(.body)
                        .foregroundStyle(Color(white: 0.55))
                }
            } else if artworkImages.count == 1 {
                artworkImage(artworkImages[0])
            } else {
                let grid = padded(artworkImages, to: 4)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        artworkImage(grid[0]).frame(width: half, height: half)
                        artworkImage(grid[1]).frame(width: half, height: half)
                    }
                    HStack(spacing: 0) {
                        artworkImage(grid[2]).frame(width: half, height: half)
                        artworkImage(grid[3]).frame(width: half, height: half)
                    }
                }
            }
        }
    }

    private func artworkImage(_ data: Data?) -> some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.85).opacity(0.5)
            }
        }
        .clipped()
    }

    private func padded(_ images: [Data], to count: Int) -> [Data?] {
        var result: [Data?] = images.map { $0 }
        while result.count < count {
            result.append(nil)
        }
        return result
    }
}
