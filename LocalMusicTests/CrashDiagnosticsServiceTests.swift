import Foundation
import Testing
@testable import LocalMusic

/// Disk-touching tests for `CrashDiagnosticsService`. Each test creates a
/// fresh instance pointed at an isolated temp directory via
/// `directoryOverride`, so files don't leak into the simulator's
/// `Application Support/`.
///
/// `@MainActor` because the service is `@MainActor`-isolated.
/// `.serialized` because `directoryOverride` is a shared static.
@MainActor
@Suite(.serialized)
final class CrashDiagnosticsServiceTests {

    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashDiagnosticsTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CrashDiagnosticsService.directoryOverride = tempDir
    }

    deinit {
        CrashDiagnosticsService.directoryOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func setEnabledTrue_createsCrashesAndLogsDirectories() {
        let service = CrashDiagnosticsService()
        let crashesDir = tempDir.appendingPathComponent("crashes", isDirectory: true)
        let logsDir = tempDir.appendingPathComponent("logs", isDirectory: true)

        #expect(!FileManager.default.fileExists(atPath: crashesDir.path))
        #expect(!FileManager.default.fileExists(atPath: logsDir.path))

        service.setEnabled(true)

        #expect(FileManager.default.fileExists(atPath: crashesDir.path))
        #expect(FileManager.default.fileExists(atPath: logsDir.path))
        #expect(service.isEnabled)
    }

    @Test func setEnabledFalse_removesDirectoriesAndResetsPendingFlag() throws {
        let service = CrashDiagnosticsService()
        service.setEnabled(true)

        // Simulate a captured crash payload + log tail.
        let payload = Data("{\"crash\":true}".utf8)
        try payload.write(to: service.crashFileURL)
        try Data("logs".utf8).write(to: service.logTailURL)
        service.refreshPendingCrash()
        #expect(service.hasPendingCrash)

        service.setEnabled(false)

        #expect(!service.isEnabled)
        #expect(!service.hasPendingCrash)
        let crashesDir = tempDir.appendingPathComponent("crashes", isDirectory: true)
        let logsDir = tempDir.appendingPathComponent("logs", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: crashesDir.path))
        #expect(!FileManager.default.fileExists(atPath: logsDir.path))
    }

    @Test func pendingCrashReport_returnsWrittenJSON() throws {
        let service = CrashDiagnosticsService()
        service.setEnabled(true)

        let payload = Data("{\"call\":\"stack\"}".utf8)
        try payload.write(to: service.crashFileURL)

        #expect(service.pendingCrashReport() == payload)
    }

    @Test func recentLogTail_returnsWrittenText() throws {
        let service = CrashDiagnosticsService()
        service.setEnabled(true)

        let logs = Data("hello logs".utf8)
        try logs.write(to: service.logTailURL)

        #expect(service.recentLogTail() == logs)
    }

    @Test func clearPendingCrash_removesBothFilesAndFlag() throws {
        let service = CrashDiagnosticsService()
        service.setEnabled(true)

        try Data("{}".utf8).write(to: service.crashFileURL)
        try Data("logs".utf8).write(to: service.logTailURL)
        service.refreshPendingCrash()
        #expect(service.hasPendingCrash)

        service.clearPendingCrash()

        #expect(!service.hasPendingCrash)
        #expect(service.pendingCrashReport() == nil)
        #expect(service.recentLogTail() == nil)
    }

    @Test func refreshPendingCrash_picksUpFileFromDisk() throws {
        let service = CrashDiagnosticsService()
        service.setEnabled(true)

        #expect(!service.hasPendingCrash)
        try Data("{}".utf8).write(to: service.crashFileURL)
        service.refreshPendingCrash()
        #expect(service.hasPendingCrash)
    }
}
