import Foundation

@Observable
final class LogStore: @unchecked Sendable {
    static let shared = LogStore()

    struct Entry: Identifiable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        /// Pre-lowercased at insert so LogsView can filter without
        /// allocating on every render.
        let messageLowercased: String
        let categoryLowercased: String

        init(timestamp: Date, level: Level, category: String, message: String) {
            self.id = UUID()
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.messageLowercased = message.lowercased()
            self.categoryLowercased = category.lowercased()
        }

        enum Level: String, CaseIterable {
            case debug, info, warning, error

            var displayName: String { rawValue.uppercased() }
        }
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 5000

    /// Shared by `asText`. Callers (`LogPersistence.flushNow`, LogsView)
    /// run on the main actor; DateFormatter is not thread-safe.
    private static let asTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

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
        // insert is only called on the main thread (see `append`); hop into
        // the MainActor isolation domain so we can call into the @MainActor
        // LogPersistence singleton without an extra task hop.
        MainActor.assumeIsolated {
            LogPersistence.shared.scheduleFlush()
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
        let formatter = Self.asTextFormatter
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
