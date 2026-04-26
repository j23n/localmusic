import XCTest
import UIKit
@testable import LocalMusic

/// Disk-touching tests for `ArtworkCache`. Each test redirects the cache
/// directory at a temp folder via `directoryOverride` so files don't leak
/// into the simulator's `Documents/Artwork/`.
final class ArtworkCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkCacheTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        ArtworkCache.directoryOverride = tempDir
        ArtworkCache.purgeMemoryCaches()
    }

    override func tearDownWithError() throws {
        ArtworkCache.directoryOverride = nil
        ArtworkCache.purgeMemoryCaches()
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - key + fileURL

    func testKey_isDeterministicAndPathDependent() {
        let a = URL(fileURLWithPath: "/x/song.mp3")
        let b = URL(fileURLWithPath: "/x/other.mp3")
        XCTAssertEqual(ArtworkCache.key(for: a), ArtworkCache.key(for: a))
        XCTAssertNotEqual(ArtworkCache.key(for: a), ArtworkCache.key(for: b))
    }

    func testKey_collapsesDotSegments() {
        let a = URL(fileURLWithPath: "/x/song.mp3")
        let b = URL(fileURLWithPath: "/x/./song.mp3")
        XCTAssertEqual(ArtworkCache.key(for: a), ArtworkCache.key(for: b))
    }

    func testFileURL_livesUnderConfiguredDirectory() {
        let track = URL(fileURLWithPath: "/x/song.mp3")
        let cacheURL = ArtworkCache.fileURL(for: track)
        XCTAssertTrue(
            cacheURL.standardized.path.hasPrefix(tempDir.standardized.path),
            "cache file \(cacheURL.path) should live under override \(tempDir.path)"
        )
    }

    // MARK: - storeSync / hasArtwork / remove

    func testStoreSync_writesFileAndExposesHasArtwork() {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let bytes = Data(repeating: 0xCD, count: 32)

        XCTAssertFalse(ArtworkCache.hasArtwork(for: url))
        ArtworkCache.storeSync(bytes, for: url)
        XCTAssertTrue(ArtworkCache.hasArtwork(for: url))

        let onDisk = try? Data(contentsOf: ArtworkCache.fileURL(for: url))
        XCTAssertEqual(onDisk, bytes)
    }

    func testRemove_deletesFileAndClearsMemoryCache() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 4, height: 4, to: ArtworkCache.fileURL(for: url))

        // Populate the in-memory cache.
        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        XCTAssertNotNil(ArtworkCache.cachedThumbnail(for: url))

        ArtworkCache.remove(for: url)

        // remove() schedules disk I/O on a background queue; assert eventually.
        XCTAssertNil(ArtworkCache.cachedThumbnail(for: url))
        try await waitForFileToDisappear(at: ArtworkCache.fileURL(for: url))
        XCTAssertFalse(ArtworkCache.hasArtwork(for: url))
    }

    // MARK: - thumbnail / fullImage

    func testThumbnail_returnsImageForValidArtwork() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 64, height: 64, to: ArtworkCache.fileURL(for: url))

        let thumb = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        let image = try XCTUnwrap(thumb)
        // ImageIO downsamples to <= maxPixel (pointSize * scale = 64).
        XCTAssertLessThanOrEqual(image.size.width, 64)
        XCTAssertLessThanOrEqual(image.size.height, 64)
    }

    func testThumbnail_returnsNilForMissingArtwork() async {
        let url = URL(fileURLWithPath: "/x/missing.mp3")
        let thumb = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        XCTAssertNil(thumb)
    }

    func testThumbnail_secondCallHitsMemoryCache() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 64, height: 64, to: ArtworkCache.fileURL(for: url))

        XCTAssertNil(ArtworkCache.cachedThumbnail(for: url))
        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        XCTAssertNotNil(ArtworkCache.cachedThumbnail(for: url))
    }

    func testFullImage_independentMemoryCacheFromThumbnail() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 128, height: 128, to: ArtworkCache.fileURL(for: url))

        XCTAssertNil(ArtworkCache.cachedFullImage(for: url))
        _ = await ArtworkCache.fullImage(for: url, pointSize: 100, scale: 2)
        XCTAssertNotNil(ArtworkCache.cachedFullImage(for: url))
        // The thumbnail cache shouldn't be populated as a side effect.
        XCTAssertNil(ArtworkCache.cachedThumbnail(for: url))
    }

    func testPurgeMemoryCaches_clearsBothCachesButLeavesDisk() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        try writePNG(width: 32, height: 32, to: ArtworkCache.fileURL(for: url))

        _ = await ArtworkCache.thumbnail(for: url, pointSize: 32, scale: 2)
        _ = await ArtworkCache.fullImage(for: url, pointSize: 32, scale: 2)
        XCTAssertNotNil(ArtworkCache.cachedThumbnail(for: url))
        XCTAssertNotNil(ArtworkCache.cachedFullImage(for: url))

        ArtworkCache.purgeMemoryCaches()
        XCTAssertNil(ArtworkCache.cachedThumbnail(for: url))
        XCTAssertNil(ArtworkCache.cachedFullImage(for: url))
        XCTAssertTrue(ArtworkCache.hasArtwork(for: url), "disk cache should survive purge")
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
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: url, options: .atomic)
    }

    /// Polls for up to ~1s waiting for the cache file to be removed by the
    /// background I/O queue.
    private func waitForFileToDisappear(at url: URL) async throws {
        for _ in 0..<20 {
            if !FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("file at \(url.path) was not removed within 1s")
    }
}
