import Foundation
import Testing
@testable import LocalMusic

/// Tests for the static file-IO helpers on `LogPersistence`. The singleton
/// instance methods are integration-shaped and skipped here — `flush` and
/// `truncateIfNeeded` carry the load-bearing logic and are reachable as
/// pure functions of `(text, url)`.
@MainActor
@Suite(.serialized)
final class LogPersistenceTests {

    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogPersistenceTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func flush_writesTextAtomically() throws {
        let url = tempDir.appendingPathComponent("recent.txt")
        LogPersistence.flush(text: "hello", to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents == "hello")
    }

    @Test func flush_createsParentDirectory() throws {
        let url = tempDir
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("recent.txt")

        LogPersistence.flush(text: "x", to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func truncateIfNeeded_truncatesOversizedFileToTail() throws {
        let url = tempDir.appendingPathComponent("recent.txt")
        // Write maxBytes + 100 distinct bytes — last 100 are 'B', rest 'A'.
        var data = Data(repeating: 0x41, count: LogPersistence.maxBytes)
        data.append(contentsOf: Array(repeating: UInt8(0x42), count: 100))
        try data.write(to: url)

        LogPersistence.truncateIfNeeded(at: url)

        let truncated = try Data(contentsOf: url)
        #expect(truncated.count == LogPersistence.maxBytes)
        // The last 100 bytes ('B's) should survive — we keep the tail.
        #expect(truncated.suffix(100).allSatisfy { $0 == 0x42 })
    }

    @Test func truncateIfNeeded_leavesUndersizedFileAlone() throws {
        let url = tempDir.appendingPathComponent("recent.txt")
        let data = Data(repeating: 0x41, count: 1024)
        try data.write(to: url)

        LogPersistence.truncateIfNeeded(at: url)

        let after = try Data(contentsOf: url)
        #expect(after == data)
    }
}
