import Foundation
@testable import LocalMusic

/// Process-wide lock taken by every test suite that mutates the shared
/// `ArtworkCache.directoryOverride` / `LyricsCache.directoryOverride`
/// globals. `@Suite(.serialized)` only serializes within a suite, but
/// these globals are read by all three of our cache-touching suites
/// (`ArtworkCacheTests`, `LyricsCacheTests`, `PersistenceManagerTests`),
/// so we serialize across suites via this lock.
enum CacheTestLock {
    nonisolated(unsafe) private static let lock = NSLock()

    static func acquire() { lock.lock() }
    static func release() { lock.unlock() }
}

/// Shared helpers for building lightweight `Track` values without touching
/// the filesystem. The URL is synthesized; tests that need real files build
/// their own.
enum Fixtures {

    static func track(
        title: String,
        artist: String = "Artist",
        album: String = "Album",
        duration: Double = 180,
        path: String? = nil
    ) -> Track {
        let url = URL(fileURLWithPath: path ?? "/fixtures/\(UUID().uuidString)/\(title).mp3")
        return Track(
            id: Track.stableID(for: url),
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            hasArtwork: false,
            hasLyrics: false
        )
    }

    /// Generates `count` tracks with deterministic titles "T0", "T1", ….
    /// The path is unique per index so `Track.stableID` produces distinct IDs.
    static func tracks(_ count: Int) -> [Track] {
        (0..<count).map { i in
            track(title: "T\(i)", path: "/fixtures/track-\(i).mp3")
        }
    }
}
