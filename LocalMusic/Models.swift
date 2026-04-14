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

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkData: Data?
    var lyrics: String?
    var syncedLyrics: [SyncedLyricLine]?

    var hasLyrics: Bool {
        lyrics != nil || syncedLyrics != nil
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
