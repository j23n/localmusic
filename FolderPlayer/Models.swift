import Foundation

// MARK: - RepeatMode

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
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

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Playlist

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
}
