import CryptoKit
import Foundation

// MARK: - RepeatMode

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}

// MARK: - Synced Lyric Line

struct SyncedLyricLine: Identifiable, Codable, Hashable {
    var id: Double { timestamp }
    let timestamp: Double // seconds
    let text: String
}

// MARK: - Track

/// Slim representation of a single audio file. Heavy payloads (artwork bytes,
/// lyrics) are stored out-of-band in `ArtworkCache` / `LyricsCache` and looked
/// up on demand. The `id` is derived from the file URL so it stays stable
/// across rescans, which lets SwiftUI Lists preserve identity (no flicker /
/// scroll jump) when the library is re-loaded.
struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var hasArtwork: Bool
    var hasLyrics: Bool

    /// Stable UUID derived from the file path: a SHA-256 truncated to 16
    /// bytes with RFC 4122 variant + version-5 nibbles set so the value is
    /// a syntactically valid UUID. (It is not a strict v5 UUID — there's no
    /// namespace input — but Foundation only cares about the layout.)
    static func stableID(for url: URL) -> UUID {
        let path = url.standardized.path
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0],  bytes[1],  bytes[2],  bytes[3],
                           bytes[4],  bytes[5],  bytes[6],  bytes[7],
                           bytes[8],  bytes[9],  bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Playlist (discovered from .m3u / .m3u8 / .pls files)

struct Playlist: Identifiable {
    var id: URL { fileURL }
    let fileURL: URL
    let name: String
    var trackURLs: [URL]
    var rawPaths: [String]
}
