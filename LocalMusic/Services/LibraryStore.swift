import Foundation
import Observation
import SwiftUI

/// Central store for the user's music library. Owns the slim `Track` array,
/// a URL → Track lookup, debounced/filtered display state, and folder scan
/// orchestration.
@Observable
@MainActor
final class LibraryStore {

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

    // MARK: - Observed State

    private(set) var tracks: [Track] = []
    private(set) var displayTracks: [Track] = []
    private(set) var sections: [LibrarySection] = []
    private(set) var playlists: [Playlist] = []
    private(set) var folderURL: URL?
    private(set) var lastSynced: Date?
    private(set) var isScanning: Bool = false
    private(set) var isFiltering: Bool = false
    private(set) var scanProgress: ScanProgress?

    var searchText: String = "" {
        didSet { scheduleApply() }
    }

    var sortOption: SortOption = .title {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortDefaultsKey)
            scheduleApply(immediate: true)
        }
    }

    // MARK: - Internal Indexes

    @ObservationIgnored private var tracksByURL: [URL: Track] = [:]
    @ObservationIgnored private var searchKeys: [String] = []
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var scanAccessURL: URL?

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

    /// Synchronous filter that reuses the pre-lowercased search index built
    /// during ingest. Avoids the per-track `.lowercased()` allocations the
    /// naive `tracks.filter { ... }` would incur — useful for sheets that
    /// need their own filtered view without going through the debounced
    /// `displayTracks` pipeline.
    func searchTracks(query: String, limit: Int? = nil) -> [Track] {
        let q = query.lowercased()
        if q.isEmpty {
            if let limit { return Array(tracks.prefix(limit)) }
            return tracks
        }
        var result: [Track] = []
        result.reserveCapacity(min(tracks.count, limit ?? .max))
        for i in 0..<tracks.count {
            if i < searchKeys.count, searchKeys[i].contains(q) {
                result.append(tracks[i])
                if let limit, result.count >= limit { break }
            }
        }
        return result
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

    /// Cheap resume hook: short-circuits when the folder mtime hasn't moved
    /// past the last successful sync. Called from the app's `scenePhase`
    /// listener so files added while we were backgrounded show up without a
    /// manual reload.
    func checkForExternalChanges() async {
        await rescanIfNeeded()
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
        }
        // If `scanned` is empty (likely a transient access failure) we
        // intentionally keep the cached library rather than blowing it away.

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
            guard let output = await Self.filterSortSection(
                tracks: tracks,
                keys: keys,
                query: captureSearch,
                sort: captureSort
            ), !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.displayTracks = output.0
                self.sections = output.1
                self.isFiltering = false
            }
        }
    }

    #if DEBUG
    /// Test-only: replaces the in-memory library and waits for the display
    /// pipeline to settle. Skips disk I/O so tests stay fast and isolated.
    func _testSeedTracks(_ tracks: [Track]) async {
        await ingest(tracks: tracks, persist: false)
        await applyTask?.value
    }

    /// Test-only: awaits the most recent filter/sort/section task. Useful
    /// after mutating `searchText` or `sortOption` to assert on
    /// `displayTracks` / `sections` without sleeping.
    func _testWaitForApply() async {
        await applyTask?.value
    }

    /// Test-only: assigns `folderURL` directly so playlist CRUD tests can
    /// run against a temp directory.
    func _testSetFolderURL(_ url: URL?) {
        folderURL = url
    }
    #endif

    /// Filters, sorts, and pre-computes sections in a single detached task so
    /// large libraries don't block the main thread.
    ///
    /// `Task.checkCancellation` is consulted between each phase, and the
    /// outer `withTaskCancellationHandler` forwards the parent task's
    /// cancellation into the detached worker — without it, cancelling
    /// `applyTask` would only abandon the await and leave the worker
    /// running to completion.
    private static func filterSortSection(tracks: [Track],
                                          keys: [String],
                                          query: String,
                                          sort: SortOption) async -> ([Track], [LibrarySection])? {
        let task = Task.detached(priority: .userInitiated) { () throws -> ([Track], [LibrarySection]) in
            var indices: [Int]
            let q = query.lowercased()
            if q.isEmpty {
                indices = Array(tracks.indices)
            } else {
                indices = []
                indices.reserveCapacity(tracks.count)
                for i in 0..<tracks.count {
                    if i % 1024 == 0 { try Task.checkCancellation() }
                    if i < keys.count, keys[i].contains(q) { indices.append(i) }
                }
            }
            try Task.checkCancellation()
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
            try Task.checkCancellation()
            let result = indices.map { tracks[$0] }
            let sections = makeSections(result, sort: sort)
            return (result, sections)
        }
        return await withTaskCancellationHandler {
            try? await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

// MARK: - Sectioning

struct LibrarySection: Identifiable, Equatable, Sendable {
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
            ("1\u{2013}3 min",     60...179.999),
            ("3\u{2013}5 min",     180...299.999),
            ("5\u{2013}10 min",    300...599.999),
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
