import Foundation
import Testing
@testable import LocalMusic

/// Disk-touching tests for `PersistenceManager`. Each test gets a private
/// temp `Documents/` and `UserDefaults` suite so state never leaks between
/// runs (or to the device under test). `.serialized` because the migration
/// path writes through the shared `ArtworkCache` / `LyricsCache` overrides.
@MainActor
@Suite(.serialized)
final class PersistenceManagerTests {

    private let tempDir: URL
    private let defaultsName: String
    private let defaults: UserDefaults
    private let artworkOverride: URL
    private let lyricsOverride: URL

    init() throws {
        CacheTestLock.acquire()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Isolated UserDefaults so tests can't pollute the real device state.
        defaultsName = "com.localmusic.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: defaultsName))

        // Migration writes into the on-disk caches; isolate those too.
        artworkOverride = tempDir.appendingPathComponent("Artwork", isDirectory: true)
        lyricsOverride = tempDir.appendingPathComponent("Lyrics", isDirectory: true)
        ArtworkCache.directoryOverride = artworkOverride
        LyricsCache.directoryOverride = lyricsOverride
    }

    deinit {
        ArtworkCache.directoryOverride = nil
        LyricsCache.directoryOverride = nil
        defaults.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: tempDir)
        CacheTestLock.release()
    }

    // MARK: - lastSynced

    @Test func lastSynced_returnsNilWhenUnset() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(pm.loadLastSynced() == nil)
    }

    @Test func lastSynced_roundTrip() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        pm.saveLastSynced(when)
        #expect(pm.loadLastSynced() == when)
    }

    // MARK: - folderBookmark

    @Test func folderBookmark_returnsNilWhenUnset() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(pm.loadFolderBookmark() == nil)
    }

    @Test func folderBookmark_roundTrip() throws {
        let folder = tempDir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        pm.saveFolderBookmark(folder)
        let resolved = try #require(pm.loadFolderBookmark())
        #expect(resolved.standardized.path == folder.standardized.path)
    }

    // MARK: - library round-trip (slim format)

    @Test func library_roundTripSlimFormat() async {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let tracks = [
            Fixtures.track(title: "One",   path: "/x/one.mp3"),
            Fixtures.track(title: "Two",   path: "/x/two.mp3"),
            Fixtures.track(title: "Three", path: "/x/three.mp3")
        ]

        await pm.saveLibraryAsync(tracks)
        let loaded = await pm.loadLibraryAsync()

        #expect(loaded.map(\.id) == tracks.map(\.id))
        #expect(loaded.map(\.title) == ["One", "Two", "Three"])
        #expect(loaded.map(\.url) == tracks.map(\.url))
    }

    @Test func library_loadAsyncReturnsEmptyWhenFileMissing() async {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(await pm.loadLibraryAsync().isEmpty)
    }

    @Test func library_loadSyncReturnsEmptyWhenFileMissing() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(pm.loadLibrary().isEmpty)
    }

    // MARK: - decodeAndMigrate (legacy → slim)

    @Test func migrate_legacyArtworkInlinePopulatesArtworkCache() async throws {
        let url = URL(fileURLWithPath: "/legacy/song.mp3")
        let artworkBytes = Data(repeating: 0xAB, count: 64)
        let json = """
        [{
          "url": "\(url.absoluteString)",
          "title": "Legacy",
          "artist": "X",
          "album": "Y",
          "duration": 42,
          "artworkData": "\(artworkBytes.base64EncodedString())"
        }]
        """
        try writeLibraryJSON(json)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let loaded = await pm.loadLibraryAsync()

        #expect(loaded.count == 1)
        let track = try #require(loaded.first)
        #expect(track.hasArtwork)
        #expect(ArtworkCache.hasArtwork(for: url))
        let storedURL = ArtworkCache.fileURL(for: url)
        #expect(try Data(contentsOf: storedURL) == artworkBytes)
    }

    @Test func migrate_legacyLyricsInlinePopulatesLyricsCache() async throws {
        let url = URL(fileURLWithPath: "/legacy/lyrical.mp3")
        let json = """
        [{
          "url": "\(url.absoluteString)",
          "title": "Lyrical",
          "artist": "X",
          "album": "Y",
          "duration": 60,
          "lyrics": "verse one\\nverse two",
          "syncedLyrics": [
            {"timestamp": 1.0, "text": "first"},
            {"timestamp": 2.0, "text": "second"}
          ]
        }]
        """
        try writeLibraryJSON(json)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let loaded = await pm.loadLibraryAsync()

        let track = try #require(loaded.first)
        #expect(track.hasLyrics)
        #expect(LyricsCache.hasLyrics(for: url))

        let lyrics = await LyricsCache.load(for: url)
        #expect(lyrics?.unsynced == "verse one\nverse two")
        #expect(lyrics?.synced?.map(\.text) == ["first", "second"])
    }

    @Test func migrate_missingIDDerivesStableID() async throws {
        let url = URL(fileURLWithPath: "/legacy/no-id.mp3")
        let json = """
        [{
          "url": "\(url.absoluteString)",
          "title": "NoID",
          "artist": "X",
          "album": "Y",
          "duration": 1
        }]
        """
        try writeLibraryJSON(json)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let loaded = await pm.loadLibraryAsync()

        let track = try #require(loaded.first)
        #expect(track.id == Track.stableID(for: url))
    }

    @Test func migrate_emptyArtworkDataDoesNotCreateCacheFile() async throws {
        let url = URL(fileURLWithPath: "/legacy/empty-art.mp3")
        let json = """
        [{
          "url": "\(url.absoluteString)",
          "title": "Empty",
          "artist": "X",
          "album": "Y",
          "duration": 1,
          "artworkData": ""
        }]
        """
        try writeLibraryJSON(json)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let loaded = await pm.loadLibraryAsync()

        let track = try #require(loaded.first)
        #expect(!track.hasArtwork)
        #expect(!ArtworkCache.hasArtwork(for: url))
    }

    @Test func migrate_explicitHasFlagsPreservedWhenCacheMissing() async throws {
        // The migration falls back to cache presence when hasArtwork/hasLyrics
        // are nil, but should respect explicit values when present.
        let url = URL(fileURLWithPath: "/legacy/explicit.mp3")
        let json = """
        [{
          "url": "\(url.absoluteString)",
          "title": "Explicit",
          "artist": "X",
          "album": "Y",
          "duration": 1,
          "hasArtwork": false,
          "hasLyrics": false
        }]
        """
        try writeLibraryJSON(json)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let loaded = await pm.loadLibraryAsync()
        let track = try #require(loaded.first)
        #expect(!track.hasArtwork)
        #expect(!track.hasLyrics)
    }

    @Test func migrate_corruptJSONReturnsEmpty() async throws {
        try writeLibraryJSON("{not valid json")
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(await pm.loadLibraryAsync().isEmpty)
    }

    // MARK: - folderContentModificationDate

    @Test func folderModification_emptyFolderReturnsRootMtime() throws {
        let folder = tempDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let mtime = pm.folderContentModificationDate(at: folder)
        #expect(mtime != nil)
    }

    @Test func folderModification_picksLatestNestedMtime() throws {
        let folder = tempDir.appendingPathComponent("nested", isDirectory: true)
        let nested = folder.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let oldFile = folder.appendingPathComponent("old.txt")
        let newFile = nested.appendingPathComponent("new.txt")
        FileManager.default.createFile(atPath: oldFile.path, contents: Data())
        FileManager.default.createFile(atPath: newFile.path, contents: Data())

        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate],
                                              ofItemAtPath: oldFile.path)
        try FileManager.default.setAttributes([.modificationDate: newDate],
                                              ofItemAtPath: newFile.path)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let mtime = try #require(pm.folderContentModificationDate(at: folder))
        #expect(abs(mtime.timeIntervalSince1970 - newDate.timeIntervalSince1970) < 1.5)
    }

    @Test func folderModification_nonExistentReturnsNil() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        #expect(pm.folderContentModificationDate(at: missing) == nil)
    }

    // MARK: - Helpers

    private func writeLibraryJSON(_ contents: String) throws {
        let url = tempDir.appendingPathComponent("library.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
