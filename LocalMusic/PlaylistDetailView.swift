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
            if resolvedTracks.isEmpty && playlist.trackURLs.isEmpty {
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
                        ForEach(Array(resolvedTracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                player.play(track: track, queue: resolvedTracks, startIndex: index)
                            } label: {
                                TrackRow(track: track,
                                         isPlaying: player.currentTrack?.url == track.url)
                            }
                            .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            playlist.trackURLs.move(fromOffsets: from, toOffset: to)
                            MetadataLoader.writePlaylist(playlist)
                        }
                        .onDelete { offsets in
                            playlist.trackURLs.remove(atOffsets: offsets)
                            MetadataLoader.writePlaylist(playlist)
                        }
                    } header: {
                        if !resolvedTracks.isEmpty {
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
