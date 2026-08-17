import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Stores audio file artwork outside of `Track` so the in-memory library
/// stays slim. Originals live on disk under `Documents/Artwork/`; thumbnails
/// and full-size decodes are kept in bounded `NSCache`s.
enum ArtworkCache {

    /// `nonisolated(unsafe)` because `NSCache` is internally thread-safe but
    /// not `Sendable`-marked in the iOS SDK, and we serve it from arbitrary
    /// threads (downsample worker, MainActor view code).
    nonisolated(unsafe) private static let thumbnailMemoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    nonisolated(unsafe) private static let fullImageMemoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        return cache
    }()

    /// Side maps from disk SHA → in-memory keys (`"\(sha)|\(Int(maxPixel))"`)
    /// so we can invalidate every size for a track and still answer
    /// size-agnostic lookups used by now-playing / lock-screen code.
    nonisolated(unsafe) private static var thumbnailMemoryKeys: [String: Set<String>] = [:]
    nonisolated(unsafe) private static var fullImageMemoryKeys: [String: Set<String>] = [:]

    /// Guards the side maps. `NSCache` itself is thread-safe; these
    /// dictionaries are not.
    private static let memoryLock = NSLock()

    /// Serial writes / deletes so store and remove don't race on disk.
    private static let writeQueue = DispatchQueue(label: "com.localmusic.artworkCache",
                                                  qos: .userInitiated)

    /// Concurrent ImageIO decode with a small cap so fast scrolling doesn't
    /// serialize every row, and a cancelled `.task(id:)` can abandon work
    /// without blocking later rows.
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.localmusic.artworkCache.decode"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    #if DEBUG
    /// Test-only override. When non-nil, all cache files are written here
    /// instead of `Documents/Artwork/`. Set sequentially in `setUp` /
    /// `tearDown`; not safe for parallel test plans.
    ///
    /// `nonisolated(unsafe)` because this is a DEBUG-only test seam that
    /// tests serialize themselves; production code never writes it.
    nonisolated(unsafe) static var directoryOverride: URL?
    #endif

    /// Last directory we ensured exists, so `createDirectory` isn't a
    /// syscall on every `fileURL` / `hasArtwork` access. Re-checked when
    /// the DEBUG override changes between tests.
    nonisolated(unsafe) private static var preparedDirectory: URL?

    private static var directory: URL {
        let url: URL = {
            #if DEBUG
            if let override = directoryOverride { return override }
            #endif
            return FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Artwork", isDirectory: true)
        }()
        if preparedDirectory != url {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            preparedDirectory = url
        }
        return url
    }

    /// Disk filename key — path-only SHA. Must stay stable; changing the
    /// hex format would invalidate every cached artwork file.
    static func key(for trackURL: URL) -> String {
        let path = trackURL.standardized.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// In-memory cache key includes pixel size so 52pt rows, mosaic cells,
    /// and the mini player don't share one downsampled bitmap.
    private static func memoryKey(sha: String, maxPixel: CGFloat) -> String {
        "\(sha)|\(Int(maxPixel))"
    }

    static func fileURL(for trackURL: URL) -> URL {
        directory.appendingPathComponent(key(for: trackURL) + ".dat")
    }

    static func hasArtwork(for trackURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: trackURL).path)
    }

    /// Persists artwork bytes to disk. Safe to call from any thread; performs
    /// the actual I/O asynchronously on a background queue.
    static func store(_ data: Data, for trackURL: URL) {
        invalidateMemoryCaches(for: trackURL)
        let target = fileURL(for: trackURL)
        writeQueue.async {
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                Log.cache.warning("Failed to write artwork: \(error.localizedDescription)")
            }
        }
    }

    /// Synchronous variant for hot paths during scanning where we want the
    /// file to be readable before returning the Track to the caller.
    static func storeSync(_ data: Data, for trackURL: URL) {
        invalidateMemoryCaches(for: trackURL)
        let target = fileURL(for: trackURL)
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            Log.cache.warning("Failed to write artwork: \(error.localizedDescription)")
        }
    }

    static func remove(for trackURL: URL) {
        invalidateMemoryCaches(for: trackURL)
        let target = fileURL(for: trackURL)
        writeQueue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Any cached thumbnail size for this track. Used by now-playing /
    /// lock-screen code that doesn't know the view's pixel size.
    static func cachedThumbnail(for trackURL: URL) -> UIImage? {
        anyCachedImage(sha: key(for: trackURL), kind: .thumbnail)
    }

    /// Size-specific thumbnail lookup. `maxPixel` is `pointSize * scale`
    /// (same units as `thumbnail(for:pointSize:scale:)`).
    static func cachedThumbnail(for trackURL: URL, maxPixel: CGFloat) -> UIImage? {
        let key = memoryKey(sha: key(for: trackURL), maxPixel: maxPixel)
        return thumbnailMemoryCache.object(forKey: key as NSString)
    }

    /// Any cached full-size decode for this track.
    static func cachedFullImage(for trackURL: URL) -> UIImage? {
        anyCachedImage(sha: key(for: trackURL), kind: .full)
    }

    /// Size-specific full-image lookup. `maxPixel` is `pointSize * scale`.
    static func cachedFullImage(for trackURL: URL, maxPixel: CGFloat) -> UIImage? {
        let key = memoryKey(sha: key(for: trackURL), maxPixel: maxPixel)
        return fullImageMemoryCache.object(forKey: key as NSString)
    }

    /// Loads (and caches) a downsampled thumbnail. `pointSize` is in points;
    /// the underlying decode targets `pointSize * scale` pixels.
    static func thumbnail(for trackURL: URL,
                          pointSize: CGFloat,
                          scale: CGFloat) async -> UIImage? {
        await loadDownsampled(trackURL: trackURL,
                              pointSize: pointSize,
                              scale: scale,
                              cache: thumbnailMemoryCache)
    }

    /// Loads (and caches) a near-full-size image suitable for Now Playing.
    static func fullImage(for trackURL: URL,
                          pointSize: CGFloat,
                          scale: CGFloat) async -> UIImage? {
        await loadDownsampled(trackURL: trackURL,
                              pointSize: pointSize,
                              scale: scale,
                              cache: fullImageMemoryCache)
    }

    /// Shared decode pipeline for thumbnail / full-image variants: hits the
    /// supplied memory cache first, falls back to ImageIO downsampling on
    /// a bounded concurrent queue, and writes successful results back into
    /// the cache unless the calling task was cancelled.
    private static func loadDownsampled(trackURL: URL,
                                        pointSize: CGFloat,
                                        scale: CGFloat,
                                        cache: NSCache<NSString, UIImage>) async -> UIImage? {
        let sha = key(for: trackURL)
        let maxPixel = max(pointSize * scale, 1)
        let memoryKey = memoryKey(sha: sha, maxPixel: maxPixel)
        if let cached = cache.object(forKey: memoryKey as NSString) {
            return cached
        }
        if Task.isCancelled { return nil }

        let path = fileURL(for: trackURL)
        let image: UIImage? = await withCheckedContinuation { cont in
            decodeQueue.addOperation {
                guard let source = CGImageSourceCreateWithURL(path as CFURL, nil) else {
                    cont.resume(returning: nil); return
                }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: UIImage(cgImage: cg))
            }
        }

        // Fast-scroll cancellation: don't populate the cache for a row the
        // user has already left. Prefer nil over caching a late decode.
        if Task.isCancelled {
            return nil
        }
        if let image {
            cache.setObject(image, forKey: memoryKey as NSString)
            rememberMemoryKey(memoryKey, sha: sha, cache: cache)
        }
        return image
    }

    private enum MemoryKind {
        case thumbnail
        case full
    }

    private static func anyCachedImage(sha: String, kind: MemoryKind) -> UIImage? {
        memoryLock.lock()
        let keys: Set<String>?
        switch kind {
        case .thumbnail: keys = thumbnailMemoryKeys[sha]
        case .full: keys = fullImageMemoryKeys[sha]
        }
        memoryLock.unlock()
        let cache = kind == .thumbnail ? thumbnailMemoryCache : fullImageMemoryCache
        guard let keys else { return nil }
        for key in keys {
            if let image = cache.object(forKey: key as NSString) {
                return image
            }
        }
        return nil
    }

    private static func rememberMemoryKey(_ memoryKey: String,
                                          sha: String,
                                          cache: NSCache<NSString, UIImage>) {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        if cache === thumbnailMemoryCache {
            thumbnailMemoryKeys[sha, default: []].insert(memoryKey)
        } else {
            fullImageMemoryKeys[sha, default: []].insert(memoryKey)
        }
    }

    /// Drops every in-memory thumbnail and full-image entry for this track
    /// (all pixel sizes). Disk is left alone.
    private static func invalidateMemoryCaches(for trackURL: URL) {
        let sha = key(for: trackURL)
        memoryLock.lock()
        let thumbKeys = thumbnailMemoryKeys.removeValue(forKey: sha) ?? []
        let fullKeys = fullImageMemoryKeys.removeValue(forKey: sha) ?? []
        memoryLock.unlock()
        for key in thumbKeys {
            thumbnailMemoryCache.removeObject(forKey: key as NSString)
        }
        for key in fullKeys {
            fullImageMemoryCache.removeObject(forKey: key as NSString)
        }
    }

    static func purgeMemoryCaches() {
        thumbnailMemoryCache.removeAllObjects()
        fullImageMemoryCache.removeAllObjects()
        memoryLock.lock()
        thumbnailMemoryKeys.removeAll()
        fullImageMemoryKeys.removeAll()
        memoryLock.unlock()
    }
}
