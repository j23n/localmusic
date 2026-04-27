import Foundation
import Testing
@testable import LocalMusic

@MainActor
final class LibraryStoreTests {

    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - searchTracks(query:limit:)

    @Test func searchTracks_emptyQueryReturnsAll() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Alpha"),
            Fixtures.track(title: "Beta")
        ])

        #expect(store.searchTracks(query: "").count == 2)
    }

    @Test func searchTracks_emptyQueryRespectsLimit() async {
        let store = LibraryStore()
        await store._testSeedTracks(Fixtures.tracks(10))

        #expect(store.searchTracks(query: "", limit: 3).count == 3)
    }

    @Test func searchTracks_matchesTitleArtistAlbumCaseInsensitively() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Hello World", artist: "Anyone", album: "X"),
            Fixtures.track(title: "Other",       artist: "WORLDLY", album: "X"),
            Fixtures.track(title: "Other",       artist: "Anyone", album: "Earth"),
            Fixtures.track(title: "Skip",        artist: "Skip",   album: "Skip")
        ])

        #expect(store.searchTracks(query: "world").count == 2)
        #expect(store.searchTracks(query: "EARTH").count == 1)
        #expect(store.searchTracks(query: "nope").count == 0)
    }

    @Test func searchTracks_limitHonoredOnMatches() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Match A"),
            Fixtures.track(title: "Match B"),
            Fixtures.track(title: "Match C")
        ])

        #expect(store.searchTracks(query: "match", limit: 2).count == 2)
    }

    // MARK: - Sort

    @Test func sort_byTitle() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Charlie"),
            Fixtures.track(title: "alpha"),
            Fixtures.track(title: "Bravo")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        #expect(store.displayTracks.map(\.title) == ["alpha", "Bravo", "Charlie"])
    }

    @Test func sort_byArtistFallsBackToTitle() async {
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
        #expect(titles == ["M", "A", "Z"])
    }

    @Test func sort_byDuration() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Long",   duration: 600),
            Fixtures.track(title: "Short",  duration: 30),
            Fixtures.track(title: "Medium", duration: 200)
        ])
        store.sortOption = .duration
        await store._testWaitForApply()

        #expect(store.displayTracks.map(\.title) == ["Short", "Medium", "Long"])
    }

    // MARK: - Sectioning

    @Test func sections_byFirstLetterUppercased() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "alpha"),
            Fixtures.track(title: "Apple"),
            Fixtures.track(title: "banana")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        #expect(store.sections.map(\.title) == ["A", "B"])
        #expect(store.sections[0].tracks.count == 2)
    }

    @Test func sections_nonLetterStartsBucketIntoHash() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "1999"),
            Fixtures.track(title: "!Bang"),
            Fixtures.track(title: "Apple")
        ])
        store.sortOption = .title
        await store._testWaitForApply()

        let titles = store.sections.map(\.title)
        #expect(titles.contains("#"))
        #expect(titles.contains("A"))
    }

    @Test func sections_byDuration_bucketsBoundaries() async {
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
        #expect(titles == ["Under 1 min", "1\u{2013}3 min", "3\u{2013}5 min", "10+ min"])
    }

    // MARK: - Search through the pipeline

    @Test func search_filtersDisplayTracks() async {
        let store = LibraryStore()
        await store._testSeedTracks([
            Fixtures.track(title: "Hello"),
            Fixtures.track(title: "Goodbye")
        ])
        store.searchText = "hello"
        await store._testWaitForApply()

        #expect(store.displayTracks.map(\.title) == ["Hello"])
    }

    // MARK: - Playlist CRUD

    @Test func createPlaylist_emptyNameReturnsNil() {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)

        #expect(store.createPlaylist(name: "") == nil)
        #expect(store.createPlaylist(name: "   ") == nil)
    }

    @Test func createPlaylist_appendsAndSortsCaseInsensitively() {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)

        _ = store.createPlaylist(name: "zeta")
        _ = store.createPlaylist(name: "Alpha")
        _ = store.createPlaylist(name: "beta")

        #expect(store.playlists.map(\.name) == ["Alpha", "beta", "zeta"])
        for p in store.playlists {
            #expect(FileManager.default.fileExists(atPath: p.fileURL.path))
        }
    }

    @Test func deletePlaylists_removesFromArrayAndDisk() {
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)
        _ = store.createPlaylist(name: "Mix1")
        _ = store.createPlaylist(name: "Mix2")
        let firstURL = store.playlists[0].fileURL

        store.deletePlaylists(at: IndexSet(integer: 0))

        #expect(store.playlists.count == 1)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
    }

    @Test func savePlaylist_writesToDiskAndUpdatesMemory() throws {
        try touch("song.mp3")
        let store = LibraryStore()
        store._testSetFolderURL(tempDir)
        var playlist = try #require(store.createPlaylist(name: "Mix"))

        playlist.trackURLs = [tempDir.appendingPathComponent("song.mp3")]
        playlist.rawPaths = ["song.mp3"]
        store.savePlaylist(playlist)

        #expect(store.playlists.first(where: { $0.id == playlist.id })?.trackURLs.count == 1)
        let parsed = try #require(MetadataLoader.parsePlaylist(at: playlist.fileURL))
        #expect(parsed.rawPaths == ["song.mp3"])
    }

    // MARK: - Lookup helpers

    @Test func trackForURL_normalizesViaStandardized() async {
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
        #expect(store.track(forURL: dotURL)?.id == track.id)
    }

    @Test func resolved_returnsOnlyKnownURLs() async {
        let known = Fixtures.track(title: "K", path: "/x/known.mp3")
        let unknown = URL(fileURLWithPath: "/x/missing.mp3")
        let store = LibraryStore()
        await store._testSeedTracks([known])

        let resolved = store.resolved(from: [known.url, unknown])
        #expect(resolved.count == 1)
        #expect(resolved.first?.id == known.id)
    }

    // MARK: - Helpers

    private func touch(_ relativePath: String) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
}
