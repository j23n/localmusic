import CryptoKit
import Foundation

/// Per-track lyrics payload (unsynced + synced). Stored on disk so the
/// in-memory `Track` doesn't carry potentially many KB of text per item.
struct TrackLyrics: Codable, Hashable, Sendable {
    var unsynced: String?
    var synced: [SyncedLyricLine]?

    var isEmpty: Bool {
        (unsynced?.isEmpty ?? true) && (synced?.isEmpty ?? true)
    }
}

enum LyricsCache {

    private static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        return cache
    }()

    private static let ioQueue = DispatchQueue(label: "com.localmusic.lyricsCache",
                                               qos: .userInitiated)

    #if DEBUG
    /// Test-only override. When non-nil, all cache files are written here
    /// instead of `Documents/Lyrics/`. Set sequentially in `setUp` /
    /// `tearDown`; not safe for parallel test plans.
    ///
    /// `nonisolated(unsafe)` because this is a DEBUG-only test seam that
    /// tests serialize themselves; production code never writes it.
    nonisolated(unsafe) static var directoryOverride: URL?
    #endif

    private static var directory: URL {
        let url: URL = {
            #if DEBUG
            if let override = directoryOverride { return override }
            #endif
            return FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lyrics", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func key(for trackURL: URL) -> String {
        let path = trackURL.standardized.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(for trackURL: URL) -> URL {
        directory.appendingPathComponent(key(for: trackURL) + ".json")
    }

    static func hasLyrics(for trackURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: trackURL).path)
    }

    static func storeSync(_ lyrics: TrackLyrics, for trackURL: URL) {
        let target = fileURL(for: trackURL)
        if lyrics.isEmpty {
            try? FileManager.default.removeItem(at: target)
            return
        }
        if let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: target, options: .atomic)
        }
    }

    static func remove(for trackURL: URL) {
        let target = fileURL(for: trackURL)
        memoryCache.removeObject(forKey: key(for: trackURL) as NSString)
        ioQueue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Loads lyrics off the main actor. Returns `nil` if no cache entry.
    static func load(for trackURL: URL) async -> TrackLyrics? {
        let keyString = key(for: trackURL)
        if let cached = memoryCache.object(forKey: keyString as NSString) as Data?,
           let lyrics = try? JSONDecoder().decode(TrackLyrics.self, from: cached) {
            return lyrics
        }
        let path = fileURL(for: trackURL)
        let data: Data? = await withCheckedContinuation { cont in
            ioQueue.async {
                cont.resume(returning: try? Data(contentsOf: path))
            }
        }
        guard let data else { return nil }
        memoryCache.setObject(data as NSData, forKey: keyString as NSString)
        return try? JSONDecoder().decode(TrackLyrics.self, from: data)
    }

    static func purgeMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
