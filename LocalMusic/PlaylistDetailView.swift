import SwiftUI

// MARK: - Playlist Item (resolved track or missing file)

private enum PlaylistItem: Identifiable {
    case resolved(index: Int, track: Track)
    case missing(index: Int, rawPath: String)

    var id: String {
        switch self {
        case .resolved(let index, _): return "r-\(index)"
        case .missing(let index, _): return "m-\(index)"
        }
    }
}

struct PlaylistDetailView: View {
    @Binding var playlist: Playlist
    let library: [Track]
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var showAddTracks = false

    private var resolvedTracks: [Track] {
        playlist.trackURLs.compactMap { url in
            library.first { $0.url.standardized == url.standardized }
        }
    }

    private var playlistItems: [PlaylistItem] {
        playlist.trackURLs.enumerated().map { index, url in
            if let track = library.first(where: { $0.url.standardized == url.standardized }) {
                return .resolved(index: index, track: track)
            } else {
                let rawPath = index < playlist.rawPaths.count
                    ? playlist.rawPaths[index]
                    : url.path
                return .missing(index: index, rawPath: rawPath)
            }
        }
    }

    var body: some View {
        Group {
            if playlist.trackURLs.isEmpty {
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
            } else {
                List {
                    // Play button
                    if !resolvedTracks.isEmpty {
                        Section {
                            Button {
                                if let first = resolvedTracks.first {
                                    player.play(track: first, queue: resolvedTracks, startIndex: 0)
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

                    // Track list
                    Section {
                        ForEach(playlistItems) { item in
                            switch item {
                            case .resolved(_, let track):
                                Button {
                                    let queue = resolvedTracks
                                    if let playIndex = queue.firstIndex(where: { $0.url.standardized == track.url.standardized }) {
                                        player.play(track: track, queue: queue, startIndex: playIndex)
                                    }
                                } label: {
                                    TrackRow(track: track,
                                             isPlaying: player.currentTrack?.url == track.url)
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
                            MetadataLoader.writePlaylist(playlist)
                        }
                        .onDelete { offsets in
                            playlist.trackURLs.remove(atOffsets: offsets)
                            playlist.rawPaths.remove(atOffsets: offsets)
                            MetadataLoader.writePlaylist(playlist)
                        }
                    } header: {
                        if !playlistItems.isEmpty {
                            let missing = playlistItems.filter {
                                if case .missing = $0 { return true }; return false
                            }.count
                            if missing > 0 {
                                Text("\(resolvedTracks.count) track\(resolvedTracks.count == 1 ? "" : "s"), \(missing) missing")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                    .foregroundStyle(.primary)
                                    .padding(.top, 8)
                            } else if !resolvedTracks.isEmpty {
                                Text("\(resolvedTracks.count) track\(resolvedTracks.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                    .foregroundStyle(.primary)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 80, for: .scrollContent)
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
            AddTracksSheet(playlist: $playlist, library: library)
        }
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
    let library: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLibrary: [Track] {
        if searchText.isEmpty { return library }
        let query = searchText.lowercased()
        return library.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query) ||
            $0.album.lowercased().contains(query)
        }
    }

    private func isInPlaylist(_ track: Track) -> Bool {
        playlist.trackURLs.contains { $0.standardized == track.url.standardized }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLibrary, id: \.id) { track in
                    let included = isInPlaylist(track)
                    Button {
                        if included {
                            let indices = playlist.trackURLs.enumerated()
                                .filter { $0.element.standardized == track.url.standardized }
                                .map(\.offset)
                            for index in indices.reversed() {
                                playlist.trackURLs.remove(at: index)
                                playlist.rawPaths.remove(at: index)
                            }
                        } else {
                            playlist.trackURLs.append(track.url)
                            let baseDir = playlist.fileURL.deletingLastPathComponent()
                            playlist.rawPaths.append(
                                MetadataLoader.relativePath(for: track.url, relativeTo: baseDir)
                            )
                        }
                        MetadataLoader.writePlaylist(playlist)
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
            .searchable(text: $searchText, prompt: "Search library")
            .navigationTitle("Add Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
