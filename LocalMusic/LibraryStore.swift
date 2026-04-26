import Foundation
import SwiftUI

/// Central store for the user's music library. Owns the slim `Track` array,
/// a URL → Track lookup, debounced/filtered display state, and folder scan
/// orchestration.
@MainActor
final class LibraryStore: ObservableObject {

    enum SortOption: String, CaseIterable, Identifiable, Sendable {
        case title, artist, album, duration

        var id: String { rawValue }

        var label: String {
            switch self {
            case .title:    return "Title"
            case .artist:   return "Artist"
            case .album:    return "Album"
            case .duration: return "Duration"
            }
        }

        var icon: String {
            switch self {
            case .title:    return "textformat"
            case .artist:   return "person"
            case .album:    return "square.stack"
            case .duration: return "clock"
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var displayTracks: [Track] = []
    @Published private(set) var sections: [LibrarySection] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isFiltering: Bool = false
    @Published private(set) var scanProgress: ScanProgress?

    @Published var searchText: String = "" {
        didSet { scheduleApply() }
    }

    @Published var sortOption: SortOption = .title {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortDefaultsKey)
            scheduleApply(immediate: true)
        }
    }

    // MARK: - Internal Indexes

    private var tracksByURL: [URL: Track] = [:]
    private var searchKeys: [String] = []
    private var applyTask: Task<Void, Never>?
    private var scanAccessURL: URL?

    private static let sortDefaultsKey = "librarySort"

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.sortDefaultsKey),
           let opt = SortOption(rawValue: raw) {
            self.sortOption = opt
        }
        self.lastSynced = PersistenceManager.shared.loadLastSynced()
        self.folderURL = PersistenceManager.shared.loadFolderBookmark()
    }

    // MARK: - Lookup

    func track(forURL url: URL) -> Track? {
        tracksByURL[url.standardized]
    }

    func resolved(from urls: [URL]) -> [Track] {
        urls.compactMap { tracksByURL[$0.standardized] }
    }

    // MARK: - Bootstrap & Rescan

    /// Loads cached tracks (if any) and the playlist list, then triggers an
    /// incremental rescan when the folder mtime indicates changes.
    func bootstrap() async {
        let cached = await PersistenceManager.shared.loadLibraryAsync()
        await ingest(tracks: cached, persist: false)

        if let url = folderURL {
            startScanAccess(url)
            playlists = MetadataLoader.scanPlaylists(in: url)
            await rescanIfNeeded()
        }
    }

    /// Performs a full rescan only when nothing is in memory or the folder
    /// has been modified since the last successful sync.
    func rescanIfNeeded() async {
        guard let folderURL else { return }
        startScanAccess(folderURL)

        let needsRescan: Bool
        if tracks.isEmpty {
            needsRescan = true
        } else if let last = lastSynced,
                  let mtime = PersistenceManager.shared.folderContentModificationDate(at: folderURL) {
            needsRescan = mtime > last
        } else {
            needsRescan = true
        }

        if needsRescan {
            await rescan()
        } else {
            playlists = MetadataLoader.scanPlaylists(in: folderURL)
        }
    }

    /// Forces a full rescan regardless of mtime. No-op if a scan is already
    /// running so concurrent triggers (Reload + pull-to-refresh) don't race.
    func rescan() async {
        guard let folderURL else { return }
        guard !isScanning else { return }
        startScanAccess(folderURL)
        isScanning = true
        scanProgress = nil

        let scanned = await MetadataLoader.scanFolder(at: folderURL) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.scanProgress = progress
            }
        }

        if !scanned.isEmpty {
            await ingest(tracks: scanned, persist: true)
            let now = Date()
            PersistenceManager.shared.saveLastSynced(now)
            lastSynced = now
        } else {
            print("[LocalMusic] Rescan returned 0 tracks, keeping cached data")
        }

        playlists = MetadataLoader.scanPlaylists(in: folderURL)
        isScanning = false
        scanProgress = nil
    }

    /// Picks up a freshly-saved folder bookmark (after the picker has done
    /// the synchronous `startAccessingSecurityScopedResource` dance) and
    /// kicks off a full rescan against the resolved URL.
    func adoptSavedFolder() async {
        guard let resolved = PersistenceManager.shared.loadFolderBookmark() else { return }
        folderURL = resolved
        startScanAccess(resolved)
        await rescan()
    }

    /// Independent security-scoped access for scanning. The audio player
    /// retains its own scope for playback so the two systems don't depend
    /// on each other's lifetimes.
    private func startScanAccess(_ url: URL) {
        if let current = scanAccessURL {
            if current == url { return }
            current.stopAccessingSecurityScopedResource()
        }
        _ = url.startAccessingSecurityScopedResource()
        scanAccessURL = url
    }

    // MARK: - Playlists

    func refreshPlaylistsFromDisk() {
        guard let folderURL else { return }
        playlists = MetadataLoader.scanPlaylists(in: folderURL)
    }

    func savePlaylist(_ playlist: Playlist) {
        if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[idx] = playlist
        }
        MetadataLoader.writePlaylist(playlist)
    }

    func deletePlaylists(at offsets: IndexSet) {
        for idx in offsets {
            try? FileManager.default.removeItem(at: playlists[idx].fileURL)
        }
        playlists.remove(atOffsets: offsets)
    }

    func createPlaylist(name: String) -> Playlist? {
        guard let folderURL else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = MetadataLoader.createPlaylist(name: trimmed, in: folderURL)
        playlists.append(playlist)
        playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return playlist
    }

    // MARK: - Indexing

    private func ingest(tracks: [Track], persist: Bool) async {
        var byURL: [URL: Track] = [:]
        var keys: [String] = []
        byURL.reserveCapacity(tracks.count)
        keys.reserveCapacity(tracks.count)
        for t in tracks {
            byURL[t.url.standardized] = t
            keys.append((t.title + " " + t.artist + " " + t.album).lowercased())
        }
        self.tracks = tracks
        self.tracksByURL = byURL
        self.searchKeys = keys
        if persist {
            await PersistenceManager.shared.saveLibraryAsync(tracks)
        }
        scheduleApply(immediate: true)
    }

    private func scheduleApply(immediate: Bool = false) {
        applyTask?.cancel()
        let captureSearch = searchText
        let captureSort = sortOption
        let tracks = self.tracks
        let keys = self.searchKeys
        isFiltering = !immediate && !captureSearch.isEmpty
        applyTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
            }
            let (result, sections) = await Self.filterSortSection(
                tracks: tracks,
                keys: keys,
                query: captureSearch,
                sort: captureSort
            )
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                self.displayTracks = result
                self.sections = sections
                self.isFiltering = false
            }
        }
    }

    /// Filters, sorts, and pre-computes sections in a single detached task so
    /// large libraries don't block the main thread.
    private static func filterSortSection(tracks: [Track],
                                          keys: [String],
                                          query: String,
                                          sort: SortOption) async -> ([Track], [LibrarySection]) {
        await Task.detached(priority: .userInitiated) {
            var indices: [Int]
            let q = query.lowercased()
            if q.isEmpty {
                indices = Array(tracks.indices)
            } else {
                indices = []
                indices.reserveCapacity(tracks.count)
                for i in 0..<tracks.count {
                    if i < keys.count, keys[i].contains(q) { indices.append(i) }
                }
            }
            indices.sort { l, r in
                let a = tracks[l]
                let b = tracks[r]
                switch sort {
                case .title:
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case .artist:
                    let cmp = a.artist.localizedCaseInsensitiveCompare(b.artist)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case .album:
                    let cmp = a.album.localizedCaseInsensitiveCompare(b.album)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case .duration:
                    return a.duration < b.duration
                }
            }
            let result = indices.map { tracks[$0] }
            let sections = makeSections(result, sort: sort)
            return (result, sections)
        }.value
    }
}

// MARK: - Sectioning

struct LibrarySection: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let tracks: [Track]
}

extension LibraryStore {
    fileprivate nonisolated static func makeSections(_ tracks: [Track],
                                                     sort: SortOption) -> [LibrarySection] {
        guard !tracks.isEmpty else { return [] }
        switch sort {
        case .title:    return bucketByFirstLetter(tracks, key: \.title)
        case .artist:   return bucketByFirstLetter(tracks, key: \.artist)
        case .album:    return bucketByFirstLetter(tracks, key: \.album)
        case .duration: return bucketByDuration(tracks)
        }
    }

    nonisolated private static func bucketByFirstLetter(_ tracks: [Track],
                                                       key: KeyPath<Track, String>) -> [LibrarySection] {
        var sections: [LibrarySection] = []
        var currentTitle: String?
        var currentTracks: [Track] = []
        for t in tracks {
            let letter = sectionLetter(for: t[keyPath: key])
            if letter != currentTitle {
                if let ct = currentTitle, !currentTracks.isEmpty {
                    sections.append(LibrarySection(title: ct, tracks: currentTracks))
                }
                currentTitle = letter
                currentTracks = []
            }
            currentTracks.append(t)
        }
        if let ct = currentTitle, !currentTracks.isEmpty {
            sections.append(LibrarySection(title: ct, tracks: currentTracks))
        }
        return sections
    }

    nonisolated private static func sectionLetter(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        if first.isLetter {
            return String(first).uppercased()
        }
        return "#"
    }

    nonisolated private static func bucketByDuration(_ tracks: [Track]) -> [LibrarySection] {
        let buckets: [(String, ClosedRange<Double>)] = [
            ("Under 1 min", 0...59.999),
            ("1–3 min",     60...179.999),
            ("3–5 min",     180...299.999),
            ("5–10 min",    300...599.999),
            ("10+ min",     600...Double.greatestFiniteMagnitude)
        ]
        var grouped: [String: [Track]] = [:]
        var order: [String] = []
        for (name, _) in buckets { order.append(name); grouped[name] = [] }
        for t in tracks {
            for (name, range) in buckets where range.contains(t.duration) {
                grouped[name, default: []].append(t)
                break
            }
        }
        return order.compactMap { name in
            let entries = grouped[name] ?? []
            return entries.isEmpty ? nil : LibrarySection(title: name, tracks: entries)
        }
    }
}
