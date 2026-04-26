import XCTest
@testable import LocalMusic

final class LyricsCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsCacheTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        LyricsCache.directoryOverride = tempDir
        LyricsCache.purgeMemoryCache()
    }

    override func tearDownWithError() throws {
        LyricsCache.directoryOverride = nil
        LyricsCache.purgeMemoryCache()
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - storeSync / hasLyrics / load

    func testStoreSync_writesAndReadsBack() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(
            unsynced: "verse",
            synced: [SyncedLyricLine(timestamp: 1.0, text: "hi")]
        )

        XCTAssertFalse(LyricsCache.hasLyrics(for: url))
        LyricsCache.storeSync(lyrics, for: url)
        XCTAssertTrue(LyricsCache.hasLyrics(for: url))

        let loaded = await LyricsCache.load(for: url)
        XCTAssertEqual(loaded, lyrics)
    }

    func testStoreSync_emptyLyricsRemovesAnyExistingFile() {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let nonEmpty = TrackLyrics(unsynced: "verse", synced: nil)
        LyricsCache.storeSync(nonEmpty, for: url)
        XCTAssertTrue(LyricsCache.hasLyrics(for: url))

        let empty = TrackLyrics(unsynced: nil, synced: nil)
        LyricsCache.storeSync(empty, for: url)
        XCTAssertFalse(LyricsCache.hasLyrics(for: url))
    }

    func testLoad_returnsNilWhenMissing() async {
        let url = URL(fileURLWithPath: "/x/never-stored.mp3")
        let loaded = await LyricsCache.load(for: url)
        XCTAssertNil(loaded)
    }

    // MARK: - remove

    func testRemove_deletesDiskFile() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(unsynced: "v", synced: nil)
        LyricsCache.storeSync(lyrics, for: url)
        XCTAssertTrue(LyricsCache.hasLyrics(for: url))

        LyricsCache.remove(for: url)

        // remove() schedules disk I/O on a background queue.
        for _ in 0..<20 {
            if !LyricsCache.hasLyrics(for: url) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("lyrics file was not removed within 1s")
    }

    // MARK: - URL standardization

    func testStandardizedURLsShareCacheEntry() async {
        let raw = URL(fileURLWithPath: "/x/./song.mp3")
        let dotted = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(unsynced: "via raw", synced: nil)

        LyricsCache.storeSync(lyrics, for: raw)
        XCTAssertTrue(LyricsCache.hasLyrics(for: dotted))
        XCTAssertEqual(await LyricsCache.load(for: dotted), lyrics)
    }
}
