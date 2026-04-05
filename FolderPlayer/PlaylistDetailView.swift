import SwiftUI

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

    var body: some View {
        Group {
            if resolvedTracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Matching Tracks")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("None of the paths in this playlist could be resolved to tracks in your library.")
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
                            if let first = resolvedTracks.first {
                                player.play(track: first, queue: resolvedTracks, startIndex: 0)
                            }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                        }
                    }

                    Section {
                        ForEach(Array(resolvedTracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                player.play(track: track, queue: resolvedTracks, startIndex: index)
                            } label: {
                                TrackRow(track: track)
                            }
                        }
                        .onMove { from, to in
                            playlist.trackURLs.move(fromOffsets: from, toOffset: to)
                            MetadataLoader.writePlaylist(playlist)
                        }
                        .onDelete { offsets in
                            playlist.trackURLs.remove(atOffsets: offsets)
                            MetadataLoader.writePlaylist(playlist)
                        }
                    }
                }
                .listStyle(.plain)
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
                            playlist.trackURLs.removeAll { $0.standardized == track.url.standardized }
                        } else {
                            playlist.trackURLs.append(track.url)
                        }
                        MetadataLoader.writePlaylist(playlist)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(included ? .accentColor : .secondary)

                            TrackRow(track: track)
                        }
                    }
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
