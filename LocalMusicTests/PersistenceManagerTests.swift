import XCTest
@testable import LocalMusic

/// Disk-touching tests for `PersistenceManager`. Each test gets a private
/// temp `Documents/` and `UserDefaults` suite so state never leaks between
/// runs (or to the device under test).
final class PersistenceManagerTests: XCTestCase {

    private var tempDir: URL!
    private var defaultsName: String!
    private var defaults: UserDefaults!
    private var artworkOverride: URL!
    private var lyricsOverride: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Isolated UserDefaults so tests can't pollute the real device state.
        defaultsName = "com.folderplayer.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))

        // Migration writes into the on-disk caches; isolate those too.
        artworkOverride = tempDir.appendingPathComponent("Artwork", isDirectory: true)
        lyricsOverride = tempDir.appendingPathComponent("Lyrics", isDirectory: true)
        ArtworkCache.directoryOverride = artworkOverride
        LyricsCache.directoryOverride = lyricsOverride
    }

    override func tearDownWithError() throws {
        ArtworkCache.directoryOverride = nil
        LyricsCache.directoryOverride = nil
        defaults.removePersistentDomain(forName: defaultsName)
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - lastSynced

    func testLastSynced_returnsNilWhenUnset() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertNil(pm.loadLastSynced())
    }

    func testLastSynced_roundTrip() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        pm.saveLastSynced(when)
        XCTAssertEqual(pm.loadLastSynced(), when)
    }

    // MARK: - folderBookmark

    func testFolderBookmark_returnsNilWhenUnset() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertNil(pm.loadFolderBookmark())
    }

    func testFolderBookmark_roundTrip() throws {
        let folder = tempDir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        pm.saveFolderBookmark(folder)
        let resolved = try XCTUnwrap(pm.loadFolderBookmark())
        XCTAssertEqual(resolved.standardized.path, folder.standardized.path)
    }

    // MARK: - library round-trip (slim format)

    func testLibrary_roundTripSlimFormat() async {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let tracks = [
            Fixtures.track(title: "One",   path: "/x/one.mp3"),
            Fixtures.track(title: "Two",   path: "/x/two.mp3"),
            Fixtures.track(title: "Three", path: "/x/three.mp3")
        ]

        await pm.saveLibraryAsync(tracks)
        let loaded = await pm.loadLibraryAsync()

        XCTAssertEqual(loaded.map(\.id), tracks.map(\.id))
        XCTAssertEqual(loaded.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(loaded.map(\.url), tracks.map(\.url))
    }

    func testLibrary_loadAsyncReturnsEmptyWhenFileMissing() async {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertTrue(await pm.loadLibraryAsync().isEmpty)
    }

    func testLibrary_loadSyncReturnsEmptyWhenFileMissing() {
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertTrue(pm.loadLibrary().isEmpty)
    }

    // MARK: - decodeAndMigrate (legacy → slim)

    func testMigrate_legacyArtworkInlinePopulatesArtworkCache() async throws {
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

        XCTAssertEqual(loaded.count, 1)
        let track = try XCTUnwrap(loaded.first)
        XCTAssertTrue(track.hasArtwork)
        XCTAssertTrue(ArtworkCache.hasArtwork(for: url))
        let storedURL = ArtworkCache.fileURL(for: url)
        XCTAssertEqual(try Data(contentsOf: storedURL), artworkBytes)
    }

    func testMigrate_legacyLyricsInlinePopulatesLyricsCache() async throws {
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

        let track = try XCTUnwrap(loaded.first)
        XCTAssertTrue(track.hasLyrics)
        XCTAssertTrue(LyricsCache.hasLyrics(for: url))

        let lyrics = await LyricsCache.load(for: url)
        XCTAssertEqual(lyrics?.unsynced, "verse one\nverse two")
        XCTAssertEqual(lyrics?.synced?.map(\.text), ["first", "second"])
    }

    func testMigrate_missingIDDerivesStableID() async throws {
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

        let track = try XCTUnwrap(loaded.first)
        XCTAssertEqual(track.id, Track.stableID(for: url))
    }

    func testMigrate_emptyArtworkDataDoesNotCreateCacheFile() async throws {
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

        let track = try XCTUnwrap(loaded.first)
        XCTAssertFalse(track.hasArtwork)
        XCTAssertFalse(ArtworkCache.hasArtwork(for: url))
    }

    func testMigrate_explicitHasFlagsPreservedWhenCacheMissing() async throws {
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
        let track = try XCTUnwrap(loaded.first)
        XCTAssertFalse(track.hasArtwork)
        XCTAssertFalse(track.hasLyrics)
    }

    func testMigrate_corruptJSONReturnsEmpty() async throws {
        try writeLibraryJSON("{not valid json")
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertTrue(await pm.loadLibraryAsync().isEmpty)
    }

    // MARK: - folderContentModificationDate

    func testFolderModification_emptyFolderReturnsRootMtime() throws {
        let folder = tempDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        let mtime = pm.folderContentModificationDate(at: folder)
        XCTAssertNotNil(mtime)
    }

    func testFolderModification_picksLatestNestedMtime() throws {
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
        let mtime = try XCTUnwrap(pm.folderContentModificationDate(at: folder))
        XCTAssertEqual(mtime.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 1.5)
    }

    func testFolderModification_nonExistentReturnsNil() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let pm = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        XCTAssertNil(pm.folderContentModificationDate(at: missing))
    }

    // MARK: - Helpers

    private func writeLibraryJSON(_ contents: String) throws {
        let url = tempDir.appendingPathComponent("library.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
