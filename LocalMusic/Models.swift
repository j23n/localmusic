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

    init(id: UUID,
         url: URL,
         title: String,
         artist: String,
         album: String,
         duration: Double,
         hasArtwork: Bool,
         hasLyrics: Bool) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasArtwork = hasArtwork
        self.hasLyrics = hasLyrics
    }

    /// Stable UUID derived from the file path; identical inputs always
    /// produce the same `id`.
    static func stableID(for url: URL) -> UUID {
        let path = url.standardized.path
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122 version 5 / variant bits.
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

// MARK: - Codable migration

extension Track {
    /// Backwards-compatible decoder: legacy library.json embedded `artworkData`
    /// and `lyrics` directly on each Track. We accept either shape and let the
    /// caller migrate to the slim format on save.
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, duration
        case hasArtwork, hasLyrics
        // Legacy keys
        case artworkData, lyrics, syncedLyrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let url = try c.decode(URL.self, forKey: .url)
        let id = (try? c.decode(UUID.self, forKey: .id)) ?? Track.stableID(for: url)
        let title = try c.decode(String.self, forKey: .title)
        let artist = try c.decode(String.self, forKey: .artist)
        let album = try c.decode(String.self, forKey: .album)
        let duration = try c.decode(Double.self, forKey: .duration)

        let legacyArtwork = try c.decodeIfPresent(Data.self, forKey: .artworkData)
        let legacyLyrics = try c.decodeIfPresent(String.self, forKey: .lyrics)
        let legacySynced = try c.decodeIfPresent([SyncedLyricLine].self, forKey: .syncedLyrics)

        // Migrate legacy blobs to disk caches the first time they're seen.
        if let artworkData = legacyArtwork, !artworkData.isEmpty {
            ArtworkCache.storeSync(artworkData, for: url)
        }
        if legacyLyrics != nil || legacySynced != nil {
            let lyrics = TrackLyrics(unsynced: legacyLyrics, synced: legacySynced)
            if !lyrics.isEmpty {
                LyricsCache.storeSync(lyrics, for: url)
            }
        }

        let hasArtwork = (try? c.decode(Bool.self, forKey: .hasArtwork))
            ?? ArtworkCache.hasArtwork(for: url)
        let hasLyrics = (try? c.decode(Bool.self, forKey: .hasLyrics))
            ?? LyricsCache.hasLyrics(for: url)

        self.init(id: id, url: url, title: title, artist: artist, album: album,
                  duration: duration, hasArtwork: hasArtwork, hasLyrics: hasLyrics)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(album, forKey: .album)
        try c.encode(duration, forKey: .duration)
        try c.encode(hasArtwork, forKey: .hasArtwork)
        try c.encode(hasLyrics, forKey: .hasLyrics)
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
