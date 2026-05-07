import Foundation
import MetricKit

/// Captures crash diagnostics from MetricKit and exposes a pending-crash flag
/// to the UI. Subscriber registration is gated by `setEnabled(_:)`, mirroring
/// the user-facing `crashReportingEnabled` `@AppStorage` toggle.
@Observable
@MainActor
final class CrashDiagnosticsService: NSObject, MXMetricManagerSubscriber {

    static let shared = CrashDiagnosticsService()

    /// Override the directory used for crashes/ and logs/ in tests. Read once
    /// per instance during init; tests should set this before constructing.
    nonisolated(unsafe) static var directoryOverride: URL?

    let crashFileURL: URL
    let logTailURL: URL

    private(set) var isEnabled: Bool = false
    private(set) var hasPendingCrash: Bool = false

    private let crashesDir: URL
    private let logsDir: URL

    override init() {
        let baseDir: URL = Self.directoryOverride
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
        self.crashesDir = baseDir.appendingPathComponent("crashes", isDirectory: true)
        self.logsDir = baseDir.appendingPathComponent("logs", isDirectory: true)
        self.crashFileURL = crashesDir.appendingPathComponent("last-crash.json")
        self.logTailURL = logsDir.appendingPathComponent("recent.txt")
        super.init()
    }

    // MARK: - Toggle

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            // First-call sync: still refresh hasPendingCrash from disk so a
            // payload from a previous on-state surfaces even if state already
            // matches the requested value.
            if enabled {
                refreshPendingCrash()
            }
            return
        }
        isEnabled = enabled
        if enabled {
            try? FileManager.default.createDirectory(at: crashesDir,
                                                     withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: logsDir,
                                                     withIntermediateDirectories: true)
            MXMetricManager.shared.add(self)
            refreshPendingCrash()
        } else {
            MXMetricManager.shared.remove(self)
            hasPendingCrash = false
            try? FileManager.default.removeItem(at: crashesDir)
            try? FileManager.default.removeItem(at: logsDir)
        }
    }

    // MARK: - Pending crash payload

    func pendingCrashReport() -> Data? {
        try? Data(contentsOf: crashFileURL)
    }

    func recentLogTail() -> Data? {
        try? Data(contentsOf: logTailURL)
    }

    func clearPendingCrash() {
        try? FileManager.default.removeItem(at: crashFileURL)
        try? FileManager.default.removeItem(at: logTailURL)
        hasPendingCrash = false
    }

    /// Re-checks whether `last-crash.json` is on disk. Called on enable and
    /// after `scenePhase` returns to active so payloads delivered mid-session
    /// surface without an app restart.
    func refreshPendingCrash() {
        hasPendingCrash = FileManager.default.fileExists(atPath: crashFileURL.path)
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let candidate = payloads.last { ($0.crashDiagnostics?.isEmpty == false) }
        guard let payload = candidate else { return }
        let data = payload.jsonRepresentation()
        Task { @MainActor in
            self.handleCrashPayload(data)
        }
    }

    private func handleCrashPayload(_ data: Data) {
        guard isEnabled else { return }
        try? FileManager.default.createDirectory(at: crashesDir,
                                                 withIntermediateDirectories: true)
        do {
            try data.write(to: crashFileURL, options: .atomic)
            hasPendingCrash = true
        } catch {
            Log.ui.error("Failed to write crash payload: \(error.localizedDescription)")
        }
    }
}
