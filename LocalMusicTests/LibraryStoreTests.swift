import XCTest
@testable import LocalMusic

@MainActor
final class LibraryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - searchTracks(query:limit:)

    func testSearchTracks_emptyQueryReturnsAll() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Alpha"),
            Fixtures.track(title: "Beta")
        ])

        XCTAssertEqual(store.searchTracks(query: "").count, 2)
    }

    func testSearchTracks_emptyQueryRespectsLimit() async {
        let store = LibraryStore()
        await store._testSeedTracks(Fixtures.tracks(10))

        XCTAssertEqual(store.searchTracks(query: "", limit: 3).count, 3)
    }

    func testSearchTracks_matchesTitleArtistAlbumCaseInsensitively() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Hello World", artist: "Anyone", album: "X"),
            Fixtures.track(title: "Other",       artist: "WORLDLY", album: "X"),
            Fixtures.track(title: "Other",       artist: "Anyone", album: "Earth"),
            Fixtures.track(title: "Skip",        artist: "Skip",   album: "Skip")
        ])

        XCTAssertEqual(store.searchTracks(query: "world").count, 2)
        XCTAssertEqual(store.searchTracks(query: "EARTH").count, 1)
        XCTAssertEqual(store.searchTracks(query: "nope").count, 0)
    }

    func testSearchTracks_limitHonoredOnMatches() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Match A"),
            Fixtures.track(title: "Match B"),
            Fixtures.track(title: "Match C")
        ])

        XCTAssertEqual(store.searchTracks(query: "match", limit: 2).count, 2)
    }

    // MARK: - Sort

    func testSort_byTitle() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Charlie"),
            Fixtures.track(title: "alpha"),
            Fixtures.track(title: "Bravo")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        XCTAssertEqual(store.displayTracks.map(\.title), ["alpha", "Bravo", "Charlie"])
    }

    func testSort_byArtistFallsBackToTitle() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Z", artist: "Same"),
            Fixtures.track(title: "A", artist: "Same"),
            Fixtures.track(title: "M", artist: "Other")
        ])
        store.sortOption = .artist
        await store._testWaitForApply()

        let titles = store.displayTracks.map(\.title)
        // "Other" comes before "Same" (case-insensitive); within "Same",
        // titles are A, Z.
        XCTAssertEqual(titles, ["M", "A", "Z"])
    }

    func testSort_byDuration() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Long",   duration: 600),
            Fixtures.track(title: "Short",  duration: 30),
            Fixtures.track(title: "Medium", duration: 200)
        ])
        store.sortOption = .duration
        await store._testWaitForApply()

        XCTAssertEqual(store.displayTracks.map(\.title), ["Short", "Medium", "Long"])
    }

    // MARK: - Sectioning

    func testSections_byFirstLetterUppercased() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "alpha"),
            Fixtures.track(title: "Apple"),
            Fixtures.track(title: "banana")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        XCTAssertEqual(store.sections.map(\.title), ["A", "B"])
        XCTAssertEqual(store.sections[0].tracks.count, 2)
    }

    func testSections_nonLetterStartsBucketIntoHash() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "1999"),
            Fixtures.track(title: "!Bang"),
            Fixtures.track(title: "Apple")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        let titles = store.sections.map(\.title)
        XCTAssertTrue(titles.contains("#"))
        XCTAssertTrue(titles.contains("A"))
    }

    func testSections_byDuration_bucketsBoundaries() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "tiny",   duration: 30),
            Fixtures.track(title: "edge1",  duration: 60),       // 1–3 min
            Fixtures.track(title: "edge2",  duration: 179.999),  // 1–3 min
            Fixtures.track(title: "edge3",  duration: 180),      // 3–5 min
            Fixtures.track(title: "huge",   duration: 700)
        ])
        store.sortOption = .duration
        await store._testWaitForApply()

        let titles = store.sections.map(\.title)
        XCTAssertEqual(titles, ["Under 1 min", "1\u{2013}3 min", "3\u{2013}5 min", "10+ min"])
    }

    // MARK: - Search through the pipeline

    func testSearch_filtersDisplayTracks() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Hello"),
            Fixtures.track(title: "Goodbye")
        ])
        store.searchText = "hello"
        await store._testWaitForApply()

        XCTAssertEqual(store.displayTracks.map(\.title), ["Hello"])
    }

    // MARK: - Playlist CRUD

    func testCreatePlaylist_emptyNameReturnsNil() async {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)

        XCTAssertNil(store.createPlaylist(name: ""))
        XCTAssertNil(store.createPlaylist(name: "   "))
    }

    func testCreatePlaylist_appendsAndSortsCaseInsensitively() async {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)

        _ = store.createPlaylist(name: "zeta")
        _ = store.createPlaylist(name: "Alpha")
        _ = store.createPlaylist(name: "beta")

        XCTAssertEqual(store.playlists.map(\.name), ["Alpha", "beta", "zeta"])
        for p in store.playlists {
            XCTAssertTrue(FileManager.default.fileExists(atPath: p.fileURL.path))
        }
    }

    func testDeletePlaylists_removesFromArrayAndDisk() async {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)
        _ = store.createPlaylist(name: "Mix1")
        _ = store.createPlaylist(name: "Mix2")
        let firstURL = store.playlists[0].fileURL

        store.deletePlaylists(at: IndexSet(integer: 0))

        XCTAssertEqual(store.playlists.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testSavePlaylist_writesToDiskAndUpdatesMemory() async throws {
        try touch("song.mp3")
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)
        guard var playlist = store.createPlaylist(name: "Mix") else {
            return XCTFail("createPlaylist returned nil")
        }

        playlist.trackURLs = [tempDir.appendingPathComponent("song.mp3")]
        playlist.rawPaths = ["song.mp3"]
        store.savePlaylist(playlist)

        XCTAssertEqual(store.playlists.first(where: { $0.id == playlist.id })?.trackURLs.count, 1)
        let parsed = try XCTUnwrap(MetadataLoader.parsePlaylist(at: playlist.fileURL))
        XCTAssertEqual(parsed.rawPaths, ["song.mp3"])
    }

    // MARK: - Lookup helpers

    func testTrackForURL_normalizesViaStandardized() async {
        let url = URL(fileURLWithPath: "/library/song.mp3")
        let track = Track(
            id: Track.stableID(for: url),
            url: url,
            title: "song",
            artist: "x",
            album: "y",
            duration: 1,
            hasArtwork: false,
            hasLyrics: false
        )
        let store = LibraryStore()
        await store._testSeedTracks([track])

        let dotURL = URL(fileURLWithPath: "/library/./song.mp3")
        XCTAssertEqual(store.track(forURL: dotURL)?.id, track.id)
    }

    func testResolved_returnsOnlyKnownURLs() async {
        let known = Fixtures.track(title: "K", path: "/x/known.mp3")
        let unknown = URL(fileURLWithPath: "/x/missing.mp3")
        let store = LibraryStore()
        await store._testSeedTracks([known])

        let resolved = store.resolved(from: [known.url, unknown])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.id, known.id)
    }

    // MARK: - Helpers

    private func touch(_ relativePath: String) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
}
