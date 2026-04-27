import Foundation

struct SyncedLyricLine: Identifiable, Codable, Hashable, Sendable {
    var id: Double { timestamp }
    let timestamp: Double // seconds
    let text: String
}
