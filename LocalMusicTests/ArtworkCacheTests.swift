import Foundation
import Testing
import UIKit
@testable import LocalMusic

/// Disk-touching tests for `ArtworkCache`. Each test redirects the cache
/// directory at a temp folder via `directoryOverride` so files don't leak
/// into the simulator's `Documents/Artwork/`.
///
/// `@MainActor` because `writePNG` uses `UIGraphicsImageRenderer`, which is
/// `@MainActor`-isolated in the iOS 18 SDK. `.serialized` because the
/// `directoryOverride` test seam is shared global state.
@MainActor
@Suite(.serialized)
final class ArtworkCacheTests {

    private let tempDir: URL

    init() throws {
        CacheTestLock.acquire()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkCacheTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        ArtworkCache.directoryOverride = tempDir
        ArtworkCache.purgeMemoryCaches()
    }

    deinit {
        ArtworkCache.directoryOverride = nil
        ArtworkCache.purgeMemoryCaches()
        try? FileManager.default.removeItem(at: tempDir)
        CacheTestLock.release()
    }

    // MARK: - key + fileURL

    @Test func key_isDeterministicAndPathDependent() {
        let a = URL(fileURLWithPath: "/x/song.mp3")
        let b = URL(fileURLWithPath: "/x/other.mp3")
        #expect(ArtworkCache.key(for: a) == ArtworkCache.key(for: a))
        #expect(ArtworkCache.key(for: a) != ArtworkCache.key(for: b))
    }

    @Test func key_collapsesDotSegments() {
        let a = URL(fileURLWithPath: "/x/song.mp3")
        let b = URL(fileURLWithPath: "/x/./song.mp3")
        #expect(ArtworkCache.key(for: a) == ArtworkCache.key(for: b))
    }

    @Test func fileURL_livesUnderConfiguredDirectory() {
        let track = URL(fileURLWithPath: "/x/song.mp3")
        let cacheURL = ArtworkCache.fileURL(for: track)
        #expect(
            cacheURL.standardized.path.hasPrefix(tempDir.standardized.path),
            "cache file \(cacheURL.path) should live under override \(tempDir.path)"
        )
    }

    // MARK: - storeSync / hasArtwork / remove

    @Test func storeSync_writesFileAndExposesHasArtwork() {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let bytes = Data(repeating: 0xCD, count: 32)

        #expect(!ArtworkCache.hasArtwork(for: url))
        ArtworkCache.storeSync(bytes, for: url)
        #expect(ArtworkCache.hasArtwork(for: url))

        let onDisk = try? Data(contentsOf: ArtworkCache.fileURL(for: url))
        #expect(onDisk == bytes)
    }

    @Test func remove_deletesFileAndClearsMemoryCache() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 4, height: 4, to: ArtworkCache.fileURL(for: url))

        // Populate the in-memory cache.
        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        #expect(ArtworkCache.cachedThumbnail(for: url) != nil)

        ArtworkCache.remove(for: url)

        // remove() schedules disk I/O on a background queue; assert eventually.
        #expect(ArtworkCache.cachedThumbnail(for: url) == nil)
        try await waitForFileToDisappear(at: ArtworkCache.fileURL(for: url))
        #expect(!ArtworkCache.hasArtwork(for: url))
    }

    // MARK: - thumbnail / fullImage

    @Test func thumbnail_returnsImageForValidArtwork() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 64, height: 64, to: ArtworkCache.fileURL(for: url))

        let thumb = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        let image = try #require(thumb)
        // ImageIO downsamples to <= maxPixel (pointSize * scale = 64).
        #expect(image.size.width <= 64)
        #expect(image.size.height <= 64)
    }

    @Test func thumbnail_returnsNilForMissingArtwork() async {
        let url = URL(fileURLWithPath: "/x/missing.mp3")
        let thumb = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        #expect(thumb == nil)
    }

    @Test func thumbnail_secondCallHitsMemoryCache() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 64, height: 64, to: ArtworkCache.fileURL(for: url))

        #expect(ArtworkCache.cachedThumbnail(for: url) == nil)
        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        #expect(ArtworkCache.cachedThumbnail(for: url) != nil)
    }

    @Test func fullImage_independentMemoryCacheFromThumbnail() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 128, height: 128, to: ArtworkCache.fileURL(for: url))

        #expect(ArtworkCache.cachedFullImage(for: url) == nil)
        _ = await ArtworkCache.fullImage(for: url, pointSize: 100, scale: 2)
        #expect(ArtworkCache.cachedFullImage(for: url) != nil)
        // The thumbnail cache shouldn't be populated as a side effect.
        #expect(ArtworkCache.cachedThumbnail(for: url) == nil)
    }

    @Test func purgeMemoryCaches_clearsBothCachesButLeavesDisk() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 32, height: 32, to: ArtworkCache.fileURL(for: url))

        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        _ = await ArtworkCache.fullImage(for: url, pointSize: 32, scale: 2)
        #expect(ArtworkCache.cachedThumbnail(for: url) != nil)
        #expect(ArtworkCache.cachedFullImage(for: url) != nil)

        ArtworkCache.purgeMemoryCaches()
        #expect(ArtworkCache.cachedThumbnail(for: url) == nil)
        #expect(ArtworkCache.cachedFullImage(for: url) == nil)
        #expect(ArtworkCache.hasArtwork(for: url), "disk cache should survive purge")
    }

    // MARK: - Helpers

    /// Writes a solid-color PNG to `url`. Uses UIGraphicsImageRenderer so the
    /// output is a real PNG that ImageIO can decode.
    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = try #require(image.pngData())
        try data.write(to: url, options: .atomic)
    }

    /// Polls for up to ~1s waiting for the cache file to be removed by the
    /// background I/O queue.
    private func waitForFileToDisappear(at url: URL) async throws {
        for _ in 0..<20 {
            if !FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("file at \(url.path) was not removed within 1s")
    }
}
