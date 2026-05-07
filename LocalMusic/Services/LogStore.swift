import Foundation

@Observable
final class LogStore: @unchecked Sendable {
    static let shared = LogStore()

    struct Entry: Identifiable {
        let id: UUID = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String, CaseIterable {
            case debug, info, warning, error

            var displayName: String { rawValue.uppercased() }
        }
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 5000

    private init() {}

    func append(level: Entry.Level, category: String, message: String) {
        let entry = Entry(timestamp: Date(), level: level, category: category, message: message)
        if Thread.isMainThread {
            insert(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.insert(entry) }
        }
    }

    private func insert(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        if Thread.isMainThread {
            entries = []
        } else {
            DispatchQueue.main.async { [weak self] in self?.entries = [] }
        }
    }

    var asText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
