import XCTest
@testable import LocalMusic

final class MetadataLoaderTests: XCTestCase {

    // MARK: - Temp dir lifecycle

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataLoaderTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - resolveTrackPath

    func testResolveTrackPath_emptyReturnsNil() {
        XCTAssertNil(MetadataLoader.resolveTrackPath("", baseDir: tempDir))
    }

    func testResolveTrackPath_httpReturnsNil() {
        XCTAssertNil(MetadataLoader.resolveTrackPath("http://example.com/a.mp3", baseDir: tempDir))
        XCTAssertNil(MetadataLoader.resolveTrackPath("https://example.com/a.mp3", baseDir: tempDir))
        XCTAssertNil(MetadataLoader.resolveTrackPath("HTTPS://EXAMPLE.com/a.mp3", baseDir: tempDir))
    }

    func testResolveTrackPath_unsupportedExtensionReturnsNil() {
        XCTAssertNil(MetadataLoader.resolveTrackPath("readme.txt", baseDir: tempDir))
        XCTAssertNil(MetadataLoader.resolveTrackPath("/abs/song.ogg", baseDir: tempDir))
    }

    func testResolveTrackPath_relativeJoinsBaseDir() {
        let resolved = MetadataLoader.resolveTrackPath("subdir/song.mp3", baseDir: tempDir)
        XCTAssertEqual(
            resolved?.standardized.path,
            tempDir.appendingPathComponent("subdir/song.mp3").standardized.path
        )
    }

    func testResolveTrackPath_absolutePathPreserved() {
        let resolved = MetadataLoader.resolveTrackPath("/var/music/song.mp3", baseDir: tempDir)
        XCTAssertEqual(resolved?.path, "/var/music/song.mp3")
    }

    func testResolveTrackPath_caseInsensitiveExtension() {
        let resolved = MetadataLoader.resolveTrackPath("song.MP3", baseDir: tempDir)
        XCTAssertNotNil(resolved)
    }

    // MARK: - relativePath

    func testRelativePath_insideBaseDir() {
        let base = URL(fileURLWithPath: "/music")
        let track = URL(fileURLWithPath: "/music/Artist/Album/song.mp3")
        XCTAssertEqual(
            MetadataLoader.relativePath(for: track, relativeTo: base),
            "Artist/Album/song.mp3"
        )
    }

    func testRelativePath_baseDirWithTrailingSlashEqualsWithout() {
        let track = URL(fileURLWithPath: "/music/song.mp3")
        let baseA = URL(fileURLWithPath: "/music")
        let baseB = URL(fileURLWithPath: "/music/")
        XCTAssertEqual(
            MetadataLoader.relativePath(for: track, relativeTo: baseA),
            MetadataLoader.relativePath(for: track, relativeTo: baseB)
        )
    }

    func testRelativePath_outsideBaseDirReturnsAbsolute() {
        let base = URL(fileURLWithPath: "/music")
        let track = URL(fileURLWithPath: "/elsewhere/song.mp3")
        XCTAssertEqual(
            MetadataLoader.relativePath(for: track, relativeTo: base),
            "/elsewhere/song.mp3"
        )
    }

    // MARK: - parsePlaylist (.m3u)

    func testParseM3U_skipsCommentsAndBlankLines() throws {
        // Use real audio files in the temp dir so resolveTrackPath finds them.
        try touch("a.mp3"); try touch("b.mp3")
        let m3u = """
        #EXTM3U
        # a comment

        a.mp3
            b.mp3
        # another comment
        """
        let url = try writePlaylist(m3u, name: "set.m3u")
        let playlist = try XCTUnwrap(MetadataLoader.parsePlaylist(at: url))

        XCTAssertEqual(playlist.trackURLs.count, 2)
        XCTAssertEqual(playlist.rawPaths, ["a.mp3", "b.mp3"])
    }

    func testParseM3U_skipsHttpUrls() throws {
        try touch("local.mp3")
        let m3u = """
        local.mp3
        http://example.com/stream.mp3
        """
        let url = try writePlaylist(m3u, name: "mix.m3u")
        let playlist = try XCTUnwrap(MetadataLoader.parsePlaylist(at: url))

        XCTAssertEqual(playlist.rawPaths, ["local.mp3"])
    }

    func testParseM3U_preservesRawPathAlongsideResolved() throws {
        try touch("nested/song.mp3", makeDirs: true)
        let url = try writePlaylist("nested/song.mp3\n", name: "p.m3u")
        let playlist = try XCTUnwrap(MetadataLoader.parsePlaylist(at: url))

        XCTAssertEqual(playlist.rawPaths, ["nested/song.mp3"])
        XCTAssertEqual(
            playlist.trackURLs.first?.standardized.path,
            tempDir.appendingPathComponent("nested/song.mp3").standardized.path
        )
    }

    // MARK: - parsePlaylist (.pls)

    func testParsePLS_extractsFileEntriesIgnoringMetadata() throws {
        try touch("a.mp3"); try touch("b.mp3")
        let pls = """
        [playlist]
        NumberOfEntries=2
        File1=a.mp3
        Title1=Song A
        File2=b.mp3
        Title2=Song B
        Version=2
        """
        let url = try writePlaylist(pls, name: "set.pls")
        let playlist = try XCTUnwrap(MetadataLoader.parsePlaylist(at: url))

        XCTAssertEqual(playlist.rawPaths, ["a.mp3", "b.mp3"])
    }

    func testParsePLS_caseInsensitiveFilePrefix() throws {
        try touch("a.mp3")
        let pls = "[playlist]\nfile1=a.mp3\n"
        let url = try writePlaylist(pls, name: "set.pls")
        let playlist = try XCTUnwrap(MetadataLoader.parsePlaylist(at: url))
        XCTAssertEqual(playlist.rawPaths, ["a.mp3"])
    }

    // MARK: - writePlaylist round-trip

    func testRoundTrip_m3u() throws {
        try touch("one.mp3"); try touch("two.mp3")
        let original = Playlist(
            fileURL: tempDir.appendingPathComponent("rt.m3u"),
            name: "rt",
            trackURLs: [
                tempDir.appendingPathComponent("one.mp3"),
                tempDir.appendingPathComponent("two.mp3")
            ],
            rawPaths: ["one.mp3", "two.mp3"]
        )
        MetadataLoader.writePlaylist(original)

        let parsed = try XCTUnwrap(MetadataLoader.parsePlaylist(at: original.fileURL))
        XCTAssertEqual(parsed.rawPaths, ["one.mp3", "two.mp3"])
        XCTAssertEqual(parsed.trackURLs.count, 2)

        let written = try String(contentsOf: original.fileURL, encoding: .utf8)
        XCTAssertTrue(written.hasPrefix("#EXTM3U"))
    }

    func testRoundTrip_pls() throws {
        try touch("one.mp3"); try touch("two.mp3")
        let original = Playlist(
            fileURL: tempDir.appendingPathComponent("rt.pls"),
            name: "rt",
            trackURLs: [
                tempDir.appendingPathComponent("one.mp3"),
                tempDir.appendingPathComponent("two.mp3")
            ],
            rawPaths: ["one.mp3", "two.mp3"]
        )
        MetadataLoader.writePlaylist(original)

        let written = try String(contentsOf: original.fileURL, encoding: .utf8)
        XCTAssertTrue(written.contains("[playlist]"))
        XCTAssertTrue(written.contains("File1=one.mp3"))
        XCTAssertTrue(written.contains("File2=two.mp3"))
        XCTAssertTrue(written.contains("NumberOfEntries=2"))
        XCTAssertTrue(written.contains("Version=2"))
    }

    // MARK: - createPlaylist

    func testCreatePlaylist_writesEmptyM3UFile() throws {
        let playlist = MetadataLoader.createPlaylist(name: "Mix", in: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playlist.fileURL.path))
        let contents = try String(contentsOf: playlist.fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("#EXTM3U"))
        XCTAssertEqual(playlist.trackURLs, [])
    }

    // MARK: - parseSYLT

    func testParseSYLT_utf8_basicLines() {
        var data = Data()
        data.append(0x03)                     // encoding = UTF-8
        data.append(contentsOf: [0x65, 0x6E, 0x67]) // "eng"
        data.append(0x02)                     // timestamp format = ms
        data.append(0x00)                     // content type
        data.append(0x00)                     // empty content descriptor

        appendUTF8Line(into: &data, "Hello", timestampMs: 1_000)
        appendUTF8Line(into: &data, "World", timestampMs: 2_500)

        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Hello")
        XCTAssertEqual(lines[0].timestamp, 1.0, accuracy: 0.0001)
        XCTAssertEqual(lines[1].text, "World")
        XCTAssertEqual(lines[1].timestamp, 2.5, accuracy: 0.0001)
    }

    func testParseSYLT_sortsByTimestamp() {
        var data = sylTHeaderUTF8()
        appendUTF8Line(into: &data, "Second", timestampMs: 5_000)
        appendUTF8Line(into: &data, "First",  timestampMs: 1_000)

        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.map(\.text), ["First", "Second"])
    }

    func testParseSYLT_filtersWhitespaceOnlyLines() {
        var data = sylTHeaderUTF8()
        appendUTF8Line(into: &data, "Real",   timestampMs: 1_000)
        appendUTF8Line(into: &data, "   \t",  timestampMs: 2_000)
        appendUTF8Line(into: &data, "",       timestampMs: 3_000)

        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.map(\.text), ["Real"])
    }

    func testParseSYLT_latin1() {
        var data = Data()
        data.append(0x00) // encoding = ISO-8859-1
        data.append(contentsOf: [0x65, 0x6E, 0x67])
        data.append(0x02)
        data.append(0x00)
        data.append(0x00) // empty content descriptor

        appendLatin1Line(into: &data, "Adieu", timestampMs: 500)
        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.first?.text, "Adieu")
        XCTAssertEqual(lines.first?.timestamp ?? 0, 0.5, accuracy: 0.0001)
    }

    func testParseSYLT_utf16BigEndian() {
        var data = Data()
        data.append(0x02) // encoding = UTF-16 BE
        data.append(contentsOf: [0x65, 0x6E, 0x67])
        data.append(0x02)
        data.append(0x00)
        // empty content descriptor: two null bytes for UTF-16
        data.append(contentsOf: [0x00, 0x00])

        appendUTF16BELine(into: &data, "Yo", timestampMs: 250)
        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.first?.text, "Yo")
    }

    func testParseSYLT_shortBufferReturnsNil() {
        XCTAssertNil(MetadataLoader.parseSYLT(data: Data([0x03, 0x65, 0x6E])))
        XCTAssertNil(MetadataLoader.parseSYLT(data: Data()))
    }

    func testParseSYLT_truncatedTimestampStopsCleanly() {
        var data = sylTHeaderUTF8()
        appendUTF8Line(into: &data, "Hello", timestampMs: 1_000)
        // Append a partial next line: text + only 2 bytes of timestamp
        data.append(contentsOf: Array("Cut".utf8))
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x01]) // only 2 of 4 timestamp bytes

        let lines = try XCTUnwrap(MetadataLoader.parseSYLT(data: data))
        XCTAssertEqual(lines.map(\.text), ["Hello"])
    }

    // MARK: - Helpers

    private func touch(_ relativePath: String, makeDirs: Bool = false) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        if makeDirs {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func writePlaylist(_ contents: String, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func sylTHeaderUTF8() -> Data {
        var data = Data()
        data.append(0x03)                                  // UTF-8
        data.append(contentsOf: [0x65, 0x6E, 0x67])        // "eng"
        data.append(0x02)                                  // ms
        data.append(0x00)                                  // content type
        data.append(0x00)                                  // empty descriptor
        return data
    }

    private func appendUTF8Line(into data: inout Data, _ text: String, timestampMs: UInt32) {
        data.append(contentsOf: Array(text.utf8))
        data.append(0x00)
        appendBigEndianUInt32(&data, timestampMs)
    }

    private func appendLatin1Line(into data: inout Data, _ text: String, timestampMs: UInt32) {
        if let encoded = text.data(using: .isoLatin1) {
            data.append(encoded)
        }
        data.append(0x00)
        appendBigEndianUInt32(&data, timestampMs)
    }

    private func appendUTF16BELine(into data: inout Data, _ text: String, timestampMs: UInt32) {
        if let encoded = text.data(using: .utf16BigEndian) {
            data.append(encoded)
        }
        data.append(contentsOf: [0x00, 0x00])
        appendBigEndianUInt32(&data, timestampMs)
    }

    private func appendBigEndianUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >>  8) & 0xFF))
        data.append(UInt8(value         & 0xFF))
    }
}
