import CryptoKit
import Foundation

/// Per-track lyrics payload (unsynced + synced). Stored on disk so the
/// in-memory `Track` doesn't carry potentially many KB of text per item.
struct TrackLyrics: Codable, Hashable {
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

    private static let ioQueue = DispatchQueue(label: "com.folderplayer.lyricsCache",
                                               qos: .userInitiated)

    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Lyrics", isDirectory: true)
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
        let cacheKey = key(for: trackURL) as NSString
        if let cached = memoryCache.object(forKey: cacheKey) as Data?,
           let lyrics = try? JSONDecoder().decode(TrackLyrics.self, from: cached) {
            return lyrics
        }
        let path = fileURL(for: trackURL)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: path) else {
                    cont.resume(returning: nil); return
                }
                memoryCache.setObject(data as NSData, forKey: cacheKey)
                cont.resume(returning: try? JSONDecoder().decode(TrackLyrics.self, from: data))
            }
        }
    }

    static func purgeMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
