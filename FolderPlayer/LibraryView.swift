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
            .refreshable {
                if let url = folderURL {
                    await rescan(url)
                }
            }
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
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(Color.accentColor)
            }
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
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(Color.accentColor)
            }
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
        List {
            Section {
                ForEach(filteredTracks) { track in
                    Button {
                        let list = filteredTracks
                        if let idx = list.firstIndex(where: { $0.id == track.id }) {
                            player.play(track: track, queue: list, startIndex: idx)
                        }
                    } label: {
                        TrackRow(track: track,
                                 isPlaying: player.currentTrack?.url == track.url)
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
                    .listRowSeparator(.hidden)
                }
            } header: {
                if !filteredTracks.isEmpty {
                    Text("\(filteredTracks.count) track\(filteredTracks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
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
            tracks = cached
        }
        if let url = PersistenceManager.shared.loadFolderBookmark() {
            folderURL = url
            playlists = MetadataLoader.scanPlaylists(in: url)
            scanFolder(url)
        }
    }

    private func scanFolder(_ url: URL) {
        isLoading = tracks.isEmpty
        Task {
            await rescan(url)
        }
    }

    private func rescan(_ url: URL) async {
        player.startAccessingFolder(url)
        let scanned = await MetadataLoader.scanFolder(at: url)
        await MainActor.run {
            if !scanned.isEmpty {
                tracks = scanned
                PersistenceManager.shared.saveLibrary(scanned)
            } else {
                print("[FolderPlayer] Rescan returned 0 tracks, keeping cached data")
            }
            playlists = MetadataLoader.scanPlaylists(in: url)
            isLoading = false
        }
    }

}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    var isPlaying: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                artworkView
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isPlaying {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(0.4))
                        .frame(width: 52, height: 52)
                    NowPlayingBars()
                        .frame(width: 16, height: 14)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(isPlaying ? Color.accentColor : .primary)
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
        .padding(.vertical, 4)
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
                Color(white: 0.85).opacity(0.5)
                Image(systemName: "music.note")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.55))
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

// MARK: - Now Playing Bars Animation

struct NowPlayingBars: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            bar(delay: 0.0)
            bar(delay: 0.2)
            bar(delay: 0.4)
        }
        .onAppear { animating = true }
    }

    private func bar(delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white)
            .frame(width: 3)
            .scaleEffect(y: animating ? 1.0 : 0.3, anchor: .bottom)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: animating
            )
    }
}
