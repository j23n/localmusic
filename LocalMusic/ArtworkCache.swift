import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Stores audio file artwork outside of `Track` so the in-memory library
/// stays slim. Originals live on disk under `Documents/Artwork/`; thumbnails
/// and full-size decodes are kept in bounded `NSCache`s.
enum ArtworkCache {

    private static let thumbnailMemoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private static let fullImageMemoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        return cache
    }()

    private static let ioQueue = DispatchQueue(label: "com.folderplayer.artworkCache",
                                               qos: .userInitiated)

    #if DEBUG
    /// Test-only override. When non-nil, all cache files are written here
    /// instead of `Documents/Artwork/`. Set sequentially in `setUp` /
    /// `tearDown`; not safe for parallel test plans.
    static var directoryOverride: URL?
    #endif

    private static var directory: URL {
        let url: URL = {
            #if DEBUG
            if let override = directoryOverride { return override }
            #endif
            return FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Artwork", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func key(for trackURL: URL) -> String {
        let path = trackURL.standardized.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
        let target = fileURL(for: trackURL)
        ioQueue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    /// Synchronous variant for hot paths during scanning where we want the
    /// file to be readable before returning the Track to the caller.
    static func storeSync(_ data: Data, for trackURL: URL) {
        let target = fileURL(for: trackURL)
        try? data.write(to: target, options: .atomic)
    }

    static func remove(for trackURL: URL) {
        let target = fileURL(for: trackURL)
        let cacheKey = key(for: trackURL) as NSString
        thumbnailMemoryCache.removeObject(forKey: cacheKey)
        fullImageMemoryCache.removeObject(forKey: cacheKey)
        ioQueue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }

    static func cachedThumbnail(for trackURL: URL) -> UIImage? {
        thumbnailMemoryCache.object(forKey: key(for: trackURL) as NSString)
    }

    static func cachedFullImage(for trackURL: URL) -> UIImage? {
        fullImageMemoryCache.object(forKey: key(for: trackURL) as NSString)
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
    /// the I/O queue, and writes successful results back into the cache.
    private static func loadDownsampled(trackURL: URL,
                                        pointSize: CGFloat,
                                        scale: CGFloat,
                                        cache: NSCache<NSString, UIImage>) async -> UIImage? {
        let keyString = key(for: trackURL)
        if let cached = cache.object(forKey: keyString as NSString) {
            return cached
        }
        let path = fileURL(for: trackURL)
        let maxPixel = max(pointSize * scale, 1)
        let image: UIImage? = await withCheckedContinuation { cont in
            ioQueue.async {
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
        if let image {
            cache.setObject(image, forKey: keyString as NSString)
        }
        return image
    }

    static func purgeMemoryCaches() {
        thumbnailMemoryCache.removeAllObjects()
        fullImageMemoryCache.removeAllObjects()
    }
}
