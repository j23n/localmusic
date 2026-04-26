import Foundation

final class PersistenceManager {

    static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.folderplayer.persistence",
                                        qos: .userInitiated)
    private let documentsURL: URL
    private let defaults: UserDefaults

    /// Default initializer points at the real `Documents/` and
    /// `UserDefaults.standard`. Tests inject a temp directory and a private
    /// suite to keep state isolated.
    init(documentsURL: URL? = nil, userDefaults: UserDefaults = .standard) {
        if let documentsURL {
            self.documentsURL = documentsURL
        } else {
            self.documentsURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        self.defaults = userDefaults
    }

    private var libraryURL: URL {
        documentsURL.appendingPathComponent("library.json")
    }

    // MARK: - Folder Bookmark

    func saveFolderBookmark(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmarkData, forKey: "folderBookmark")
        } catch {
            print("Failed to save folder bookmark: \(error)")
        }
    }

    func loadFolderBookmark() -> URL? {
        guard let data = defaults.data(forKey: "folderBookmark") else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveFolderBookmark(url)
            }
            return url
        } catch {
            print("Failed to resolve folder bookmark: \(error)")
            return nil
        }
    }

    // MARK: - Last Synced

    func saveLastSynced(_ date: Date) {
        defaults.set(date, forKey: "lastSynced")
    }

    func loadLastSynced() -> Date? {
        defaults.object(forKey: "lastSynced") as? Date
    }

    // MARK: - Library

    /// Synchronous load. Prefer `loadLibraryAsync()` from view code.
    func loadLibrary() -> [Track] {
        guard fileManager.fileExists(atPath: libraryURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: libraryURL)
            return Self.decodeAndMigrate(data)
        } catch {
            print("Failed to load library: \(error)")
            return []
        }
    }

    func loadLibraryAsync() async -> [Track] {
        let url = libraryURL
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    cont.resume(returning: []); return
                }
                do {
                    let data = try Data(contentsOf: url)
                    cont.resume(returning: Self.decodeAndMigrate(data))
                } catch {
                    print("Failed to load library: \(error)")
                    cont.resume(returning: [])
                }
            }
        }
    }

    /// Encodes and writes asynchronously off the main thread.
    func saveLibraryAsync(_ tracks: [Track]) async {
        let url = libraryURL
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ioQueue.async {
                do {
                    let data = try JSONEncoder().encode(tracks)
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("Failed to save library: \(error)")
                }
                cont.resume()
            }
        }
    }

    // MARK: - Decode + Migrate

    /// Tolerant decoder: accepts both the slim format (current) and the
    /// legacy format that embedded `artworkData` / `lyrics` / `syncedLyrics`
    /// inline. Legacy blobs are migrated to the on-disk caches as a side
    /// effect of loading. Pure functions on `Track` itself stay free of I/O.
    private static func decodeAndMigrate(_ data: Data) -> [Track] {
        guard let entries = try? JSONDecoder().decode([LibraryEntry].self, from: data) else {
            return []
        }
        return entries.map(migrate(_:))
    }

    private static func migrate(_ entry: LibraryEntry) -> Track {
        if let bytes = entry.artworkData, !bytes.isEmpty {
            ArtworkCache.storeSync(bytes, for: entry.url)
        }
        if entry.lyrics != nil || entry.syncedLyrics != nil {
            let lyrics = TrackLyrics(unsynced: entry.lyrics, synced: entry.syncedLyrics)
            if !lyrics.isEmpty {
                LyricsCache.storeSync(lyrics, for: entry.url)
            }
        }
        let hasArtwork = entry.hasArtwork ?? ArtworkCache.hasArtwork(for: entry.url)
        let hasLyrics = entry.hasLyrics ?? LyricsCache.hasLyrics(for: entry.url)
        return Track(
            id: entry.id ?? Track.stableID(for: entry.url),
            url: entry.url,
            title: entry.title,
            artist: entry.artist,
            album: entry.album,
            duration: entry.duration,
            hasArtwork: hasArtwork,
            hasLyrics: hasLyrics
        )
    }

    /// Wire shape that accepts both legacy and slim track JSON.
    private struct LibraryEntry: Decodable {
        let id: UUID?
        let url: URL
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let hasArtwork: Bool?
        let hasLyrics: Bool?
        let artworkData: Data?
        let lyrics: String?
        let syncedLyrics: [SyncedLyricLine]?
    }

    // MARK: - Folder Modification

    /// Latest content modification time across the folder tree, used to skip
    /// redundant rescans when nothing on disk has changed.
    ///
    /// Walks via `contentsOfDirectory(at:)` rather than `enumerator(at:)`
    /// because the latter resolves symlinks to `/private/var/...` paths,
    /// which fall outside the security-scoped grant and silently fail to
    /// produce resource values — making the returned date stale and
    /// suppressing legitimate rescans.
    func folderContentModificationDate(at url: URL) -> Date? {
        let rootDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        let latest = max(rootDate, latestMTime(under: url))
        return latest == .distantPast ? nil : latest
    }

    private func latestMTime(under directory: URL) -> Date {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .distantPast
        }

        var latest: Date = .distantPast
        for item in contents {
            let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if let date = values?.contentModificationDate, date > latest {
                latest = date
            }
            if values?.isDirectory == true {
                let nested = latestMTime(under: item)
                if nested > latest { latest = nested }
            }
        }
        return latest
    }
}
