import Foundation
import Testing
@testable import LocalMusic

struct TrackTests {

    // MARK: - Track.stableID

    @Test func stableID_isDeterministic() {
        let url = URL(fileURLWithPath: "/Users/me/Music/song.mp3")
        #expect(Track.stableID(for: url) == Track.stableID(for: url))
    }

    @Test func stableID_differsForDifferentPaths() {
        let a = Track.stableID(for: URL(fileURLWithPath: "/a/song.mp3"))
        let b = Track.stableID(for: URL(fileURLWithPath: "/b/song.mp3"))
        #expect(a != b)
    }

    @Test func stableID_collapsesDotSegments() {
        // `.standardized` removes the `./` so both URLs hash the same path.
        let a = Track.stableID(for: URL(fileURLWithPath: "/Music/Album/song.mp3"))
        let b = Track.stableID(for: URL(fileURLWithPath: "/Music/Album/./song.mp3"))
        #expect(a == b)
    }

    @Test func stableID_setsRFC4122Bits() {
        let id = Track.stableID(for: URL(fileURLWithPath: "/x.mp3"))
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        // Variant: top two bits of byte 8 must be 0b10
        #expect(bytes[8] & 0xC0 == 0x80)
        // Version: top four bits of byte 6 must be 0b0101 (we set version 5)
        #expect(bytes[6] & 0xF0 == 0x50)
    }

    // MARK: - RepeatMode

    @Test func repeatMode_rawValueRoundTrip() {
        for mode in RepeatMode.allCases {
            #expect(RepeatMode(rawValue: mode.rawValue) == mode)
        }
    }

    // MARK: - TrackLyrics

    @Test func trackLyrics_isEmpty() {
        #expect(TrackLyrics(unsynced: nil, synced: nil).isEmpty)
        #expect(TrackLyrics(unsynced: "", synced: []).isEmpty)
        #expect(!TrackLyrics(unsynced: "lyrics", synced: nil).isEmpty)
        #expect(!TrackLyrics(
            unsynced: nil,
            synced: [SyncedLyricLine(timestamp: 0, text: "hi")]
        ).isEmpty)
    }

    @Test func trackLyrics_codableRoundTrip() throws {
        let original = TrackLyrics(
            unsynced: "verse one\nverse two",
            synced: [
                SyncedLyricLine(timestamp: 1.0, text: "first"),
                SyncedLyricLine(timestamp: 2.0, text: "second")
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackLyrics.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - SyncedLyricLine

    @Test func syncedLyricLine_idMatchesTimestamp() {
        let line = SyncedLyricLine(timestamp: 12.5, text: "test")
        #expect(line.id == 12.5)
    }
}
