import Foundation
import Testing
@testable import LocalMusic

/// Disk-touching tests for `MetadataLoader`. Each test gets its own temp
/// directory; `init()` creates it, `deinit` cleans it up.
final class MetadataLoaderTests {

    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataLoaderTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - resolveTrackPath

    @Test func resolveTrackPath_emptyReturnsNil() {
        #expect(MetadataLoader.resolveTrackPath("", baseDir: tempDir) == nil)
    }

    @Test func resolveTrackPath_httpReturnsNil() {
        #expect(MetadataLoader.resolveTrackPath("http://example.com/a.mp3", baseDir: tempDir) == nil)
        #expect(MetadataLoader.resolveTrackPath("https://example.com/a.mp3", baseDir: tempDir) == nil)
        #expect(MetadataLoader.resolveTrackPath("HTTPS://EXAMPLE.com/a.mp3", baseDir: tempDir) == nil)
    }

    @Test func resolveTrackPath_unsupportedExtensionReturnsNil() {
        #expect(MetadataLoader.resolveTrackPath("readme.txt", baseDir: tempDir) == nil)
        #expect(MetadataLoader.resolveTrackPath("/abs/song.ogg", baseDir: tempDir) == nil)
    }

    @Test func resolveTrackPath_relativeJoinsBaseDir() {
        let resolved = MetadataLoader.resolveTrackPath("subdir/song.mp3", baseDir: tempDir)
        #expect(
            resolved?.standardized.path ==
            tempDir.appendingPathComponent("subdir/song.mp3").standardized.path
        )
    }

    @Test func resolveTrackPath_absolutePathPreserved() {
        let resolved = MetadataLoader.resolveTrackPath("/var/music/song.mp3", baseDir: tempDir)
        #expect(resolved?.path == "/var/music/song.mp3")
    }

    @Test func resolveTrackPath_caseInsensitiveExtension() {
        let resolved = MetadataLoader.resolveTrackPath("song.MP3", baseDir: tempDir)
        #expect(resolved != nil)
    }

    // MARK: - relativePath

    @Test func relativePath_insideBaseDir() {
        let base = URL(fileURLWithPath: "/music")
        let track = URL(fileURLWithPath: "/music/Artist/Album/song.mp3")
        #expect(
            MetadataLoader.relativePath(for: track, relativeTo: base) ==
            "Artist/Album/song.mp3"
        )
    }

    @Test func relativePath_baseDirWithTrailingSlashEqualsWithout() {
        let track = URL(fileURLWithPath: "/music/song.mp3")
        let baseA = URL(fileURLWithPath: "/music")
        let baseB = URL(fileURLWithPath: "/music/")
        #expect(
            MetadataLoader.relativePath(for: track, relativeTo: baseA) ==
            MetadataLoader.relativePath(for: track, relativeTo: baseB)
        )
    }

    @Test func relativePath_outsideBaseDirReturnsAbsolute() {
        let base = URL(fileURLWithPath: "/music")
        let track = URL(fileURLWithPath: "/elsewhere/song.mp3")
        #expect(
            MetadataLoader.relativePath(for: track, relativeTo: base) ==
            "/elsewhere/song.mp3"
        )
    }

    // MARK: - parsePlaylist (.m3u)

    @Test func parseM3U_skipsCommentsAndBlankLines() throws {
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
        let playlist = try #require(MetadataLoader.parsePlaylist(at: url))

        #expect(playlist.trackURLs.count == 2)
        #expect(playlist.rawPaths == ["a.mp3", "b.mp3"])
    }

    @Test func parseM3U_skipsHttpUrls() throws {
        try touch("local.mp3")
        let m3u = """
        local.mp3
        http://example.com/stream.mp3
        """
        let url = try writePlaylist(m3u, name: "mix.m3u")
        let playlist = try #require(MetadataLoader.parsePlaylist(at: url))

        #expect(playlist.rawPaths == ["local.mp3"])
    }

    @Test func parseM3U_preservesRawPathAlongsideResolved() throws {
        try touch("nested/song.mp3", makeDirs: true)
        let url = try writePlaylist("nested/song.mp3\n", name: "p.m3u")
        let playlist = try #require(MetadataLoader.parsePlaylist(at: url))

        #expect(playlist.rawPaths == ["nested/song.mp3"])
        #expect(
            playlist.trackURLs.first?.standardized.path ==
            tempDir.appendingPathComponent("nested/song.mp3").standardized.path
        )
    }

    // MARK: - parsePlaylist (.pls)

    @Test func parsePLS_extractsFileEntriesIgnoringMetadata() throws {
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
        let playlist = try #require(MetadataLoader.parsePlaylist(at: url))

        #expect(playlist.rawPaths == ["a.mp3", "b.mp3"])
    }

    @Test func parsePLS_caseInsensitiveFilePrefix() throws {
        try touch("a.mp3")
        let pls = "[playlist]\nfile1=a.mp3\n"
        let url = try writePlaylist(pls, name: "set.pls")
        let playlist = try #require(MetadataLoader.parsePlaylist(at: url))
        #expect(playlist.rawPaths == ["a.mp3"])
    }

    // MARK: - writePlaylist round-trip

    @Test func roundTrip_m3u() throws {
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

        let parsed = try #require(MetadataLoader.parsePlaylist(at: original.fileURL))
        #expect(parsed.rawPaths == ["one.mp3", "two.mp3"])
        #expect(parsed.trackURLs.count == 2)

        let written = try String(contentsOf: original.fileURL, encoding: .utf8)
        #expect(written.hasPrefix("#EXTM3U"))
    }

    @Test func roundTrip_pls() throws {
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
        #expect(written.contains("[playlist]"))
        #expect(written.contains("File1=one.mp3"))
        #expect(written.contains("File2=two.mp3"))
        #expect(written.contains("NumberOfEntries=2"))
        #expect(written.contains("Version=2"))
    }

    // MARK: - createPlaylist

    @Test func createPlaylist_writesEmptyM3UFile() throws {
        let playlist = MetadataLoader.createPlaylist(name: "Mix", in: tempDir)
        #expect(FileManager.default.fileExists(atPath: playlist.fileURL.path))
        let contents = try String(contentsOf: playlist.fileURL, encoding: .utf8)
        #expect(contents.contains("#EXTM3U"))
        #expect(playlist.trackURLs == [])
    }

    // MARK: - parseSYLT

    @Test func parseSYLT_utf8_basicLines() throws {
        var data = Data()
        data.append(0x03)                     // encoding = UTF-8
        data.append(contentsOf: [0x65, 0x6E, 0x67]) // "eng"
        data.append(0x02)                     // timestamp format = ms
        data.append(0x00)                     // content type
        data.append(0x00)                     // empty content descriptor

        Self.appendUTF8Line(into: &data, "Hello", timestampMs: 1_000)
        Self.appendUTF8Line(into: &data, "World", timestampMs: 2_500)

        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.count == 2)
        #expect(lines[0].text == "Hello")
        #expect(abs(lines[0].timestamp - 1.0) < 0.0001)
        #expect(lines[1].text == "World")
        #expect(abs(lines[1].timestamp - 2.5) < 0.0001)
    }

    @Test func parseSYLT_sortsByTimestamp() throws {
        var data = Self.sylTHeaderUTF8()
        Self.appendUTF8Line(into: &data, "Second", timestampMs: 5_000)
        Self.appendUTF8Line(into: &data, "First",  timestampMs: 1_000)

        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.map(\.text) == ["First", "Second"])
    }

    @Test func parseSYLT_filtersWhitespaceOnlyLines() throws {
        var data = Self.sylTHeaderUTF8()
        Self.appendUTF8Line(into: &data, "Real",   timestampMs: 1_000)
        Self.appendUTF8Line(into: &data, "   \t",  timestampMs: 2_000)
        Self.appendUTF8Line(into: &data, "",       timestampMs: 3_000)

        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.map(\.text) == ["Real"])
    }

    @Test func parseSYLT_latin1() throws {
        var data = Data()
        data.append(0x00) // encoding = ISO-8859-1
        data.append(contentsOf: [0x65, 0x6E, 0x67])
        data.append(0x02)
        data.append(0x00)
        data.append(0x00) // empty content descriptor

        Self.appendLatin1Line(into: &data, "Adieu", timestampMs: 500)
        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.first?.text == "Adieu")
        #expect(abs((lines.first?.timestamp ?? 0) - 0.5) < 0.0001)
    }

    @Test func parseSYLT_utf16BigEndian() throws {
        var data = Data()
        data.append(0x02) // encoding = UTF-16 BE
        data.append(contentsOf: [0x65, 0x6E, 0x67])
        data.append(0x02)
        data.append(0x00)
        // empty content descriptor: two null bytes for UTF-16
        data.append(contentsOf: [0x00, 0x00])

        Self.appendUTF16BELine(into: &data, "Yo", timestampMs: 250)
        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.first?.text == "Yo")
    }

    @Test func parseSYLT_shortBufferReturnsNil() {
        #expect(MetadataLoader.parseSYLT(data: Data([0x03, 0x65, 0x6E])) == nil)
        #expect(MetadataLoader.parseSYLT(data: Data()) == nil)
    }

    @Test func parseSYLT_truncatedTimestampStopsCleanly() throws {
        var data = Self.sylTHeaderUTF8()
        Self.appendUTF8Line(into: &data, "Hello", timestampMs: 1_000)
        // Append a partial next line: text + only 2 bytes of timestamp
        data.append(contentsOf: Array("Cut".utf8))
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x01]) // only 2 of 4 timestamp bytes

        let lines = try #require(MetadataLoader.parseSYLT(data: data))
        #expect(lines.map(\.text) == ["Hello"])
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

    private static func sylTHeaderUTF8() -> Data {
        var data = Data()
        data.append(0x03)                                  // UTF-8
        data.append(contentsOf: [0x65, 0x6E, 0x67])        // "eng"
        data.append(0x02)                                  // ms
        data.append(0x00)                                  // content type
        data.append(0x00)                                  // empty descriptor
        return data
    }

    private static func appendUTF8Line(into data: inout Data, _ text: String, timestampMs: UInt32) {
        data.append(contentsOf: Array(text.utf8))
        data.append(0x00)
        appendBigEndianUInt32(&data, timestampMs)
    }

    private static func appendLatin1Line(into data: inout Data, _ text: String, timestampMs: UInt32) {
        if let encoded = text.data(using: .isoLatin1) {
            data.append(encoded)
        }
        data.append(0x00)
        appendBigEndianUInt32(&data, timestampMs)
    }

    private static func appendUTF16BELine(into data: inout Data, _ text: String, timestampMs: UInt32) {
        if let encoded = text.data(using: .utf16BigEndian) {
            data.append(encoded)
        }
        data.append(contentsOf: [0x00, 0x00])
        appendBigEndianUInt32(&data, timestampMs)
    }

    private static func appendBigEndianUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >>  8) & 0xFF))
        data.append(UInt8(value         & 0xFF))
    }
}
