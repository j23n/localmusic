import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var showPicker = false
    @State private var folderURL: URL?
    @State private var searchText = ""
    @State private var didLoadInitialData = false
    @State private var playlists: [Playlist] = []

    private var filteredTracks: [Track] {
        if searchText.isEmpty { return tracks }
        let query = searchText.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query) ||
            $0.album.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if folderURL == nil && tracks.isEmpty {
                    onboardingView
                } else if isLoading {
                    ProgressView("Scanning folder…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tracks.isEmpty {
                    emptyStateView
                } else {
                    trackListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { pickerURL in
                    // Start security-scoped access BEFORE creating bookmark —
                    // the scope token must be active for it to be embedded in the bookmark data.
                    _ = pickerURL.startAccessingSecurityScopedResource()
                    PersistenceManager.shared.saveFolderBookmark(pickerURL)
                    pickerURL.stopAccessingSecurityScopedResource()

                    if let resolvedURL = PersistenceManager.shared.loadFolderBookmark() {
                        folderURL = resolvedURL
                        scanFolder(resolvedURL)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by title, artist, or album")
        }
        .onAppear {
            guard !didLoadInitialData else { return }
            didLoadInitialData = true
            loadCachedData()
        }
    }

    // MARK: - Subviews

    private var onboardingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Music Folder Selected")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Choose a folder containing your audio files to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showPicker = true
            } label: {
                Label("Choose Folder", systemImage: "folder")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Audio Files Found")
                .font(.title3)
                .fontWeight(.medium)
            Text("The selected folder contains no supported audio files.\nTry choosing a different folder.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackListView: some View {
        List(filteredTracks) { track in
            Button {
                let list = filteredTracks
                if let idx = list.firstIndex(where: { $0.id == track.id }) {
                    player.play(track: track, queue: list, startIndex: idx)
                }
            } label: {
                TrackRow(track: track)
            }
            .contextMenu {
                if !playlists.isEmpty {
                    Menu("Add to Playlist") {
                        ForEach(playlists) { playlist in
                            Button(playlist.name) {
                                addTrack(track, to: playlist)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func addTrack(_ track: Track, to playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].trackURLs.append(track.url)
        MetadataLoader.writePlaylist(playlists[idx])
    }

    // MARK: - Actions

    private func loadCachedData() {
        let cached = PersistenceManager.shared.loadLibrary()
        if !cached.isEmpty {
            // Show cached tracks immediately while rescan happens
            tracks = cached
        }
        if let url = PersistenceManager.shared.loadFolderBookmark() {
            folderURL = url
            playlists = MetadataLoader.scanPlaylists(in: url)
            // Always rescan — cached track URLs are from a previous session
            // and their security scope won't be valid. Rescanning produces
            // fresh URLs under the current session's security-scoped access.
            scanFolder(url)
        }
    }

    private func scanFolder(_ url: URL) {
        isLoading = tracks.isEmpty
        Task {
            // Start security-scoped access — keep it open for the lifetime
            // of this folder so playback can access the files.
            player.startAccessingFolder(url)
            let scanned = await MetadataLoader.scanFolder(at: url)
            await MainActor.run {
                if !scanned.isEmpty {
                    tracks = scanned
                    PersistenceManager.shared.saveLibrary(scanned)
                } else {
                    print("[FolderPlayer] Rescan returned 0 tracks, keeping cached data")
                }
                isLoading = false
            }
        }
    }

}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(track.duration))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let data = track.artworkData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
