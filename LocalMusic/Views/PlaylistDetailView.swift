import SwiftUI

// MARK: - Playlist Item (resolved track or missing file)

private enum PlaylistItem: Identifiable {
    case resolved(index: Int, track: Track)
    case missing(index: Int, rawPath: String)

    var id: String {
        switch self {
        case .resolved(let index, _): return "r-\(index)"
        case .missing(let index, _):  return "m-\(index)"
        }
    }
}

struct PlaylistDetailView: View {
    @Binding var playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @State private var showAddTracks = false

    /// Resolves URLs to tracks via the store's O(1) lookup. Memoizing this
    /// across body re-renders happens via the `@State` cache below.
    @State private var cachedItems: [PlaylistItem] = []
    @State private var cachedResolvedTracks: [Track] = []

    var body: some View {
        Group {
            if playlist.trackURLs.isEmpty {
                emptyState
            } else {
                listBody
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTracks = true
                } label: {
                    Label("Add Tracks", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddTracks) {
            AddTracksSheet(playlist: $playlist)
        }
        .onAppear { rebuildCaches() }
        .onChange(of: playlist.trackURLs) { _, _ in rebuildCaches() }
        .onChange(of: library.tracks.count) { _, _ in rebuildCaches() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(Color.accentColor)
            }
            Text("Empty Playlist")
                .font(.title3)
                .fontWeight(.medium)
            Text("Tap + to add tracks from your library.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var listBody: some View {
        let resolved = cachedResolvedTracks
        let items = cachedItems
        let missingCount = items.reduce(0) { acc, item in
            if case .missing = item { return acc + 1 }
            return acc
        }

        List {
            if !resolved.isEmpty {
                Section {
                    Button {
                        if let first = resolved.first {
                            player.play(track: first, queue: resolved, startIndex: 0)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Play All", systemImage: "play.fill")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                }
            }

            Section {
                ForEach(items) { item in
                    switch item {
                    case .resolved(_, let track):
                        Button {
                            if let playIdx = resolved.firstIndex(where: { $0.id == track.id }) {
                                player.play(track: track, queue: resolved, startIndex: playIdx)
                            }
                        } label: {
                            TrackRow(track: track,
                                     isPlaying: player.currentTrack?.id == track.id)
                        }
                        .listRowSeparator(.hidden)
                    case .missing(_, let rawPath):
                        MissingTrackRow(rawPath: rawPath)
                            .listRowSeparator(.hidden)
                    }
                }
                .onMove { from, to in
                    playlist.trackURLs.move(fromOffsets: from, toOffset: to)
                    playlist.rawPaths.move(fromOffsets: from, toOffset: to)
                    library.savePlaylist(playlist)
                }
                .onDelete { offsets in
                    playlist.trackURLs.remove(atOffsets: offsets)
                    playlist.rawPaths.remove(atOffsets: offsets)
                    library.savePlaylist(playlist)
                }
            } header: {
                if missingCount > 0 {
                    Text("\(resolved.count) track\(resolved.count == 1 ? "" : "s"), \(missingCount) missing")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                } else if !resolved.isEmpty {
                    Text("\(resolved.count) track\(resolved.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    // MARK: - Caching

    private func rebuildCaches() {
        var items: [PlaylistItem] = []
        var resolved: [Track] = []
        items.reserveCapacity(playlist.trackURLs.count)
        for (index, url) in playlist.trackURLs.enumerated() {
            if let track = library.track(forURL: url) {
                items.append(.resolved(index: index, track: track))
                resolved.append(track)
            } else {
                let raw = index < playlist.rawPaths.count ? playlist.rawPaths[index] : url.path
                items.append(.missing(index: index, rawPath: raw))
            }
        }
        self.cachedItems = items
        self.cachedResolvedTracks = resolved
    }
}

// MARK: - Missing Track Row

struct MissingTrackRow: View {
    let rawPath: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rawPath)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("File not found")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Tracks Sheet

struct AddTracksSheet: View {
    @Binding var playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var searchDraft = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    /// Local mutable snapshot. Toggles edit this copy only; we call
    /// `library.savePlaylist` once on dismiss so adding a hundred tracks
    /// no longer rewrites the .m3u file a hundred times.
    @State private var workingPlaylist: Playlist?
    @State private var includedURLs: Set<URL> = []
    @State private var dirty = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLibrary, id: \.id) { track in
                    let key = track.url.standardized
                    let included = includedURLs.contains(key)
                    Button {
                        toggle(track)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(included ? Color.accentColor : .secondary)

                            TrackRow(track: track)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchDraft, prompt: "Search library")
            .onChange(of: searchDraft) { _, newValue in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        debouncedQuery = newValue
                    }
                }
            }
            .navigationTitle("Add Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        commitIfNeeded()
                        dismiss()
                    }
                }
            }
            .onAppear {
                workingPlaylist = playlist
                includedURLs = Set(playlist.trackURLs.map { $0.standardized })
            }
            .onDisappear {
                commitIfNeeded()
            }
        }
    }

    private var filteredLibrary: [Track] {
        // Ceiling on rendered rows so the sheet stays responsive even for
        // 10k-track libraries when the user hasn't typed anything yet. The
        // store's pre-lowercased index does the actual matching.
        library.searchTracks(query: debouncedQuery,
                             limit: debouncedQuery.isEmpty ? 500 : nil)
    }

    private func toggle(_ track: Track) {
        guard var working = workingPlaylist else { return }
        let key = track.url.standardized
        if includedURLs.contains(key) {
            includedURLs.remove(key)
            let indices = working.trackURLs.enumerated()
                .filter { $0.element.standardized == key }
                .map(\.offset)
            for index in indices.reversed() {
                working.trackURLs.remove(at: index)
                working.rawPaths.remove(at: index)
            }
        } else {
            includedURLs.insert(key)
            working.trackURLs.append(track.url)
            let baseDir = working.fileURL.deletingLastPathComponent()
            working.rawPaths.append(
                MetadataLoader.relativePath(for: track.url, relativeTo: baseDir)
            )
        }
        workingPlaylist = working
        dirty = true
    }

    private func commitIfNeeded() {
        guard dirty, let working = workingPlaylist else { return }
        // `library.savePlaylist` is the single source of truth: it updates
        // the shared `playlists` array and writes the file once. The parent
        // binding reads through that array, so it'll observe the change on
        // its next render. No second write via `playlist = working`.
        library.savePlaylist(working)
        dirty = false
    }
}
