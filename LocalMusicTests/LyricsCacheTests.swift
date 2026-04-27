import Foundation
import Testing
@testable import LocalMusic

/// `.serialized` because the `directoryOverride` test seam is shared global
/// state.
@Suite(.serialized)
final class LyricsCacheTests {

    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsCacheTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        LyricsCache.directoryOverride = tempDir
        LyricsCache.purgeMemoryCache()
    }

    deinit {
        LyricsCache.directoryOverride = nil
        LyricsCache.purgeMemoryCache()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - storeSync / hasLyrics / load

    @Test func storeSync_writesAndReadsBack() async {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(
            unsynced: "verse",
            synced: [SyncedLyricLine(timestamp: 1.0, text: "hi")]
        )

        #expect(!LyricsCache.hasLyrics(for: url))
        LyricsCache.storeSync(lyrics, for: url)
        #expect(LyricsCache.hasLyrics(for: url))

        let loaded = await LyricsCache.load(for: url)
        #expect(loaded == lyrics)
    }

    @Test func storeSync_emptyLyricsRemovesAnyExistingFile() {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let nonEmpty = TrackLyrics(unsynced: "verse", synced: nil)
        LyricsCache.storeSync(nonEmpty, for: url)
        #expect(LyricsCache.hasLyrics(for: url))

        let empty = TrackLyrics(unsynced: nil, synced: nil)
        LyricsCache.storeSync(empty, for: url)
        #expect(!LyricsCache.hasLyrics(for: url))
    }

    @Test func load_returnsNilWhenMissing() async {
        let url = URL(fileURLWithPath: "/x/never-stored.mp3")
        let loaded = await LyricsCache.load(for: url)
        #expect(loaded == nil)
    }

    // MARK: - remove

    @Test func remove_deletesDiskFile() async throws {
        let url = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(unsynced: "v", synced: nil)
        LyricsCache.storeSync(lyrics, for: url)
        #expect(LyricsCache.hasLyrics(for: url))

        LyricsCache.remove(for: url)

        // remove() schedules disk I/O on a background queue.
        for _ in 0..<20 {
            if !LyricsCache.hasLyrics(for: url) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("lyrics file was not removed within 1s")
    }

    // MARK: - URL standardization

    @Test func standardizedURLsShareCacheEntry() async {
        let raw = URL(fileURLWithPath: "/x/./song.mp3")
        let dotted = URL(fileURLWithPath: "/x/song.mp3")
        let lyrics = TrackLyrics(unsynced: "via raw", synced: nil)

        LyricsCache.storeSync(lyrics, for: raw)
        #expect(LyricsCache.hasLyrics(for: dotted))
        #expect(await LyricsCache.load(for: dotted) == lyrics)
    }
}
