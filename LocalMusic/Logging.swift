import Foundation
import os

enum Log {
    private static let subsystem = "localmusic"

    static let library     = LogCategory(subsystem: subsystem, category: "library")
    static let scan        = LogCategory(subsystem: subsystem, category: "scan")
    static let player      = LogCategory(subsystem: subsystem, category: "player")
    static let queue       = LogCategory(subsystem: subsystem, category: "queue")
    static let cache       = LogCategory(subsystem: subsystem, category: "cache")
    static let persistence = LogCategory(subsystem: subsystem, category: "persistence")
    static let ui          = LogCategory(subsystem: subsystem, category: "ui")
}

/// Thin wrapper over `os.Logger` that also mirrors entries into `LogStore`
/// for the in-app log viewer. All messages are emitted as `.public` to the
/// unified log; if you log something sensitive, hash or redact it at the
/// call site.
struct LogCategory: Sendable {
    private let logger: Logger
    let category: String

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        LogStore.shared.append(level: .debug, category: category, message: message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        LogStore.shared.append(level: .info, category: category, message: message)
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        LogStore.shared.append(level: .warning, category: category, message: message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        LogStore.shared.append(level: .error, category: category, message: message)
    }
}
