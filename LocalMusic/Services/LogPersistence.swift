import Foundation

/// Debounced write of `LogStore.shared.asText` to disk so the crash banner
/// can include a recent log tail. No-op when crash reporting is disabled.
@MainActor
final class LogPersistence {

    static let shared = LogPersistence()

    /// Maximum on-disk size of the log tail. After every flush, the file is
    /// truncated from the front to this byte count if it exceeds it.
    static let maxBytes = 500 * 1024

    /// Debounce window for coalescing burst writes (e.g. during a folder scan).
    static let debounceSeconds: UInt64 = 2

    private var pendingFlush: Task<Void, Never>?
    private var lastFlushedCount = 0
    private var lastFlushedID: UUID?

    private init() {}

    var isEnabled: Bool { CrashDiagnosticsService.shared.isEnabled }

    func scheduleFlush() {
        guard isEnabled else { return }
        pendingFlush?.cancel()
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flushNow()
        }
    }

    func flushNow() {
        guard isEnabled else { return }
        let entries = LogStore.shared.entries
        let lastID = entries.last?.id
        // Debounce already coalesces bursts; skip the 5k-line format +
        // disk write when the ring buffer hasn't changed since last flush.
        if entries.count == lastFlushedCount, lastID == lastFlushedID {
            return
        }
        lastFlushedCount = entries.count
        lastFlushedID = lastID
        let url = CrashDiagnosticsService.shared.logTailURL
        Self.flush(text: LogStore.shared.asText, to: url)
    }

    /// Atomically writes `text` to `url`, then truncates the file's leading
    /// bytes if it exceeds `maxBytes`. Exposed for tests.
    static func flush(text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        truncateIfNeeded(at: url)
    }

    static func truncateIfNeeded(at url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        let tail = data.suffix(maxBytes)
        try? tail.write(to: url, options: .atomic)
    }
}
