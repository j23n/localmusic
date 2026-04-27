import os

enum Log {
    private static let subsystem = "localmusic"

    static let library     = Logger(subsystem: subsystem, category: "library")
    static let scan        = Logger(subsystem: subsystem, category: "scan")
    static let player      = Logger(subsystem: subsystem, category: "player")
    static let queue       = Logger(subsystem: subsystem, category: "queue")
    static let cache       = Logger(subsystem: subsystem, category: "cache")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let ui          = Logger(subsystem: subsystem, category: "ui")
}
