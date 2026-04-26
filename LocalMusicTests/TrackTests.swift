import XCTest
@testable import LocalMusic

final class TrackTests: XCTestCase {

    // MARK: - Track.stableID

    func testStableID_isDeterministic() {
        let url = URL(fileURLWithPath: "/Users/me/Music/song.mp3")
        XCTAssertEqual(Track.stableID(for: url), Track.stableID(for: url))
    }

    func testStableID_differsForDifferentPaths() {
        let a = Track.stableID(for: URL(fileURLWithPath: "/a/song.mp3"))
        let b = Track.stableID(for: URL(fileURLWithPath: "/b/song.mp3"))
        XCTAssertNotEqual(a, b)
    }

    func testStableID_collapsesDotSegments() {
        // `.standardized` removes the `./` so both URLs hash the same path.
        let a = Track.stableID(for: URL(fileURLWithPath: "/Music/Album/song.mp3"))
        let b = Track.stableID(for: URL(fileURLWithPath: "/Music/Album/./song.mp3"))
        XCTAssertEqual(a, b)
    }

    func testStableID_setsRFC4122Bits() {
        let id = Track.stableID(for: URL(fileURLWithPath: "/x.mp3"))
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        // Variant: top two bits of byte 8 must be 0b10
        XCTAssertEqual(bytes[8] & 0xC0, 0x80)
        // Version: top four bits of byte 6 must be 0b0101 (we set version 5)
        XCTAssertEqual(bytes[6] & 0xF0, 0x50)
    }

    // MARK: - RepeatMode

    func testRepeatMode_rawValueRoundTrip() {
        for mode in RepeatMode.allCases {
            XCTAssertEqual(RepeatMode(rawValue: mode.rawValue), mode)
        }
    }

    // MARK: - TrackLyrics

    func testTrackLyrics_isEmpty() {
        XCTAssertTrue(TrackLyrics(unsynced: nil, synced: nil).isEmpty)
        XCTAssertTrue(TrackLyrics(unsynced: "", synced: []).isEmpty)
        XCTAssertFalse(TrackLyrics(unsynced: "lyrics", synced: nil).isEmpty)
        XCTAssertFalse(TrackLyrics(
            unsynced: nil,
            synced: [SyncedLyricLine(timestamp: 0, text: "hi")]
        ).isEmpty)
    }

    func testTrackLyrics_codableRoundTrip() throws {
        let original = TrackLyrics(
            unsynced: "verse one\nverse two",
            synced: [
                SyncedLyricLine(timestamp: 1.0, text: "first"),
                SyncedLyricLine(timestamp: 2.0, text: "second")
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackLyrics.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - SyncedLyricLine

    func testSyncedLyricLine_idMatchesTimestamp() {
        let line = SyncedLyricLine(timestamp: 12.5, text: "test")
        XCTAssertEqual(line.id, 12.5)
    }
}
