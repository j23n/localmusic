import SwiftUI

struct LibraryView: View {
    // Intentionally does NOT observe `AudioPlayerManager`: that would force
    // a body re-render on every 0.5 s playback tick. Per-row playback state
    // is read inside `TrackRowButton`, where the cost is bounded.
    @Environment(LibraryStore.self) private var library
    @State private var showSettings = false
    @State private var showFolderPicker = false
    @State private var searchDraft = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.folderURL == nil && library.tracks.isEmpty {
                    onboardingView
                } else if library.isScanning && library.tracks.isEmpty {
                    scanningView
                } else if library.tracks.isEmpty {
                    emptyStateView
                } else {
                    trackListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .searchable(text: $searchDraft, prompt: "Search by title, artist, or album")
            .onChange(of: searchDraft) { _, newValue in
                library.searchText = newValue
            }
            .refreshable {
                await library.rescan()
            }
        }
    }

    // MARK: - Subviews

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { library.sortOption },
                set: { library.sortOption = $0 }
            )) {
                ForEach(LibraryStore.SortOption.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var onboardingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to LocalMusic")
                .font(.title2.bold())

            Text("Select a folder containing your audio files to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button {
                showFolderPicker = true
            } label: {
                Label("Choose Folder", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 48)

            Spacer()
        }
        .sheet(isPresented: $showFolderPicker) {
            DocumentPicker { pickerURL in
                _ = pickerURL.startAccessingSecurityScopedResource()
                PersistenceManager.shared.saveFolderBookmark(pickerURL)
                pickerURL.stopAccessingSecurityScopedResource()
                Task {
                    await library.adoptSavedFolder()
                }
            }
        }
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

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Group {
                if let progress = library.scanProgress, progress.total > 0 {
                    Text("Scanning \(progress.completed) of \(progress.total)…")
                        .monospacedDigit()
                } else {
                    Text("Scanning folder…")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var trackListView: some View {
        let sections = library.sections
        let total = library.displayTracks.count
        List {
            if let progress = library.scanProgress, library.isScanning, progress.total > 0 {
                Section {
                    HStack {
                        ProgressView(value: Double(progress.completed),
                                     total: Double(max(progress.total, 1)))
                        Text("\(progress.completed)/\(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .listRowSeparator(.hidden)
            }

            if total == 0 {
                Section {
                    Text(library.searchText.isEmpty
                         ? "No tracks."
                         : "No matches for “\(library.searchText)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                }
                .listRowSeparator(.hidden)
            } else {
                Section {
                    Text("\(total) track\(total == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .listRowSeparator(.hidden)

                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.tracks) { track in
                            TrackRowButton(track: track)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(section.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }
}

// MARK: - Row helpers

/// Wraps a `TrackRow` with the play action and Add-to-Playlist context menu.
/// Pulled out so SwiftUI doesn't re-evaluate the entire `LibraryView` body
/// each time `player.currentTrack` ticks.
private struct TrackRowButton: View {
    let track: Track
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        Button {
            let queue = library.displayTracks
            if let idx = queue.firstIndex(where: { $0.id == track.id }) {
                player.play(track: track, queue: queue, startIndex: idx)
            }
        } label: {
            TrackRow(track: track,
                     isPlaying: player.currentTrack?.id == track.id)
        }
        .contextMenu {
            if !library.playlists.isEmpty {
                Menu("Add to Playlist") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) {
                            addTrack(track, to: playlist)
                        }
                    }
                }
            }
        }
    }

    private func addTrack(_ track: Track, to playlist: Playlist) {
        guard let idx = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var updated = library.playlists[idx]
        updated.trackURLs.append(track.url)
        let baseDir = updated.fileURL.deletingLastPathComponent()
        updated.rawPaths.append(MetadataLoader.relativePath(for: track.url, relativeTo: baseDir))
        library.savePlaylist(updated)
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    var isPlaying: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ArtworkView(trackURL: track.url,
                            hasArtwork: track.hasArtwork,
                            pointSize: 52)
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
