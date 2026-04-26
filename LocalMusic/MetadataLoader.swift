import AVFoundation
import UIKit

/// Progress payload published while a folder scan is in flight.
struct ScanProgress: Sendable, Equatable {
    var completed: Int
    var total: Int
}

struct MetadataLoader {

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "opus"
    ]

    static let playlistExtensions: Set<String> = [
        "m3u", "m3u8", "pls"
    ]

    /// Maximum number of concurrent metadata loads. AVFoundation hits the file
    /// system aggressively, so we cap concurrency to avoid descriptor pressure.
    private static let scanConcurrency = 8

    // MARK: - Folder Scanning

    /// Caller must ensure security-scoped access is already active on `url`.
    /// Reports progress periodically via `onProgress`. Tracks are returned
    /// sorted by title for legacy callers; `LibraryStore` re-sorts as needed.
    static func scanFolder(at url: URL,
                           onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> [Track] {
        print("[LocalMusic] scanFolder at: \(url.path)")
        let audioURLs = collectAudioFiles(in: url)
        let total = audioURLs.count
        print("[LocalMusic] found \(total) audio files")
        if let first = audioURLs.first {
            print("[LocalMusic] first file URL: \(first.path)")
        }
        guard total > 0 else {
            onProgress?(ScanProgress(completed: 0, total: 0))
            return []
        }

        var tracks: [Track] = []
        tracks.reserveCapacity(total)

        await withTaskGroup(of: Track.self) { group in
            var iterator = audioURLs.makeIterator()
            let seed = min(scanConcurrency, total)
            for _ in 0..<seed {
                guard let next = iterator.next() else { break }
                group.addTask { await loadTrack(from: next) }
            }
            var completed = 0
            for await track in group {
                tracks.append(track)
                completed += 1
                if completed % 25 == 0 || completed == total {
                    onProgress?(ScanProgress(completed: completed, total: total))
                }
                if let next = iterator.next() {
                    group.addTask { await loadTrack(from: next) }
                }
            }
        }

        return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Recursively collect audio files using `contentsOfDirectory(at:)`.
    /// This preserves the parent URL's path prefix (critical for security-scoped access),
    /// unlike `FileManager.enumerator` which resolves symlinks and can produce
    /// `/private/var/...` paths that fall outside the security scope.
    private static func collectAudioFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                results.append(contentsOf: collectAudioFiles(in: item))
            } else {
                let ext = item.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    results.append(item)
                }
            }
        }
        return results
    }

    // MARK: - Single Track Metadata

    static func loadTrack(from url: URL) async -> Track {
        let asset = AVAsset(url: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        var title = fallbackTitle
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration: Double = 0
        var artworkData: Data?

        do {
            let durationTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationTime)
            if duration.isNaN || duration.isInfinite { duration = 0 }
        } catch { }

        do {
            let metadata = try await asset.load(.commonMetadata)

            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        album = value
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        artworkData = data
                    }
                default:
                    break
                }
            }
        } catch { }

        // Persist artwork to disk cache instead of the in-memory Track.
        var hasArtwork = false
        if let data = artworkData, !data.isEmpty {
            ArtworkCache.storeSync(data, for: url)
            hasArtwork = true
        } else {
            // Clean up stale artwork from a prior scan.
            if ArtworkCache.hasArtwork(for: url) {
                ArtworkCache.remove(for: url)
            }
        }

        // Persist lyrics to disk cache; only `hasLyrics` lives on the Track.
        let unsynced = await extractUnsyncedLyrics(from: asset)
        let synced = await extractSyncedLyrics(from: asset)
        let lyrics = TrackLyrics(unsynced: unsynced, synced: synced)
        var hasLyrics = false
        if !lyrics.isEmpty {
            LyricsCache.storeSync(lyrics, for: url)
            hasLyrics = true
        } else if LyricsCache.hasLyrics(for: url) {
            LyricsCache.remove(for: url)
        }

        return Track(
            id: Track.stableID(for: url),
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            hasArtwork: hasArtwork,
            hasLyrics: hasLyrics
        )
    }

    // MARK: - Lyrics Extraction

    private static func extractUnsyncedLyrics(from asset: AVAsset) async -> String? {
        // Try iTunes metadata (©lyr)
        let iTunesFormats: [AVMetadataFormat] = [.iTunesMetadata]
        for format in iTunesFormats {
            if let items = try? await asset.loadMetadata(for: format) {
                for item in items {
                    if let key = item.identifier,
                       key == .iTunesMetadataLyrics,
                       let value = try? await item.load(.stringValue),
                       !value.isEmpty {
                        return value
                    }
                }
            }
        }

        // Try ID3 metadata (USLT)
        if let items = try? await asset.loadMetadata(for: .id3Metadata) {
            for item in items {
                if let key = item.identifier,
                   key == .id3MetadataUnsynchronizedLyric,
                   let value = try? await item.load(.stringValue),
                   !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    private static func extractSyncedLyrics(from asset: AVAsset) async -> [SyncedLyricLine]? {
        guard let items = try? await asset.loadMetadata(for: .id3Metadata) else { return nil }

        for item in items {
            if let key = item.identifier,
               key == .id3MetadataSynchronizedLyric,
               let data = try? await item.load(.dataValue) {
                return parseSYLT(data: data)
            }
        }
        return nil
    }

    /// Parse ID3v2 SYLT frame payload.
    /// Format: encoding(1) language(3) timestampFormat(1) contentType(1)
    ///         contentDescriptor(null-terminated) then repeated [text\0][4-byte ms timestamp]
    static func parseSYLT(data: Data) -> [SyncedLyricLine]? {
        guard data.count > 6 else { return nil }

        let encoding = data[0]
        // bytes 1-3: language (skip)
        let timestampFormat = data[4]
        // byte 5: content type (skip)

        // Skip past content descriptor (null-terminated string after the 6-byte header)
        var offset = 6
        offset = skipNullTerminatedString(in: data, from: offset, encoding: encoding)
        guard offset < data.count else { return nil }

        var lines: [SyncedLyricLine] = []

        while offset < data.count {
            // Read null-terminated text
            guard let (text, nextOffset) = readNullTerminatedString(in: data, from: offset, encoding: encoding) else {
                break
            }
            offset = nextOffset

            // Read 4-byte big-endian timestamp
            guard offset + 4 <= data.count else { break }
            let rawTimestamp = UInt32(data[offset]) << 24
                | UInt32(data[offset + 1]) << 16
                | UInt32(data[offset + 2]) << 8
                | UInt32(data[offset + 3])
            offset += 4

            let seconds: Double
            if timestampFormat == 2 {
                // Milliseconds
                seconds = Double(rawTimestamp) / 1000.0
            } else {
                // MPEG frames — treat as ms as a fallback
                seconds = Double(rawTimestamp) / 1000.0
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(SyncedLyricLine(timestamp: seconds, text: trimmed))
            }
        }

        guard !lines.isEmpty else { return nil }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private static func skipNullTerminatedString(in data: Data, from offset: Int, encoding: UInt8) -> Int {
        let isUTF16 = encoding == 1 || encoding == 2
        var i = offset
        if isUTF16 {
            while i + 1 < data.count {
                if data[i] == 0 && data[i + 1] == 0 { return i + 2 }
                i += 2
            }
        } else {
            while i < data.count {
                if data[i] == 0 { return i + 1 }
                i += 1
            }
        }
        return data.count
    }

    private static func readNullTerminatedString(in data: Data, from offset: Int, encoding: UInt8) -> (String, Int)? {
        let isUTF16 = encoding == 1 || encoding == 2
        var end = offset

        if isUTF16 {
            while end + 1 < data.count {
                if data[end] == 0 && data[end + 1] == 0 { break }
                end += 2
            }
            let strData = data[offset..<end]
            let swiftEncoding: String.Encoding = encoding == 2 ? .utf16BigEndian : .utf16
            let text = String(data: strData, encoding: swiftEncoding) ?? ""
            return (text, end + 2)
        } else {
            while end < data.count && data[end] != 0 {
                end += 1
            }
            let strData = data[offset..<end]
            let swiftEncoding: String.Encoding = encoding == 3 ? .utf8 : .isoLatin1
            let text = String(data: strData, encoding: swiftEncoding) ?? ""
            return (text, end + 1)
        }
    }

    // MARK: - Playlist Discovery

    static func scanPlaylists(in directory: URL) -> [Playlist] {
        let files = collectPlaylistFiles(in: directory)
        return files.compactMap { parsePlaylist(at: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collectPlaylistFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                results.append(contentsOf: collectPlaylistFiles(in: item))
            } else {
                let ext = item.pathExtension.lowercased()
                if playlistExtensions.contains(ext) {
                    results.append(item)
                }
            }
        }
        return results
    }

    static func parsePlaylist(at url: URL) -> Playlist? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Try Latin-1 as fallback
            guard let content = try? String(contentsOf: url, encoding: .isoLatin1) else {
                return nil
            }
            return parsePlaylistContent(content, url: url)
        }
        return parsePlaylistContent(content, url: url)
    }

    private static func parsePlaylistContent(_ content: String, url: URL) -> Playlist? {
        let ext = url.pathExtension.lowercased()
        let baseDir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent

        let entries: [(rawPath: String, url: URL)]
        if ext == "pls" {
            entries = parsePLS(content, baseDir: baseDir)
        } else {
            entries = parseM3U(content, baseDir: baseDir)
        }

        return Playlist(fileURL: url, name: name,
                        trackURLs: entries.map(\.url),
                        rawPaths: entries.map(\.rawPath))
    }

    private static func parseM3U(_ content: String, baseDir: URL) -> [(rawPath: String, url: URL)] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [(rawPath: String, url: URL)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let resolved = resolveTrackPath(trimmed, baseDir: baseDir) {
                entries.append((trimmed, resolved))
            }
        }
        return entries
    }

    private static func parsePLS(_ content: String, baseDir: URL) -> [(rawPath: String, url: URL)] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [(rawPath: String, url: URL)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match File1=..., File2=..., etc.
            guard trimmed.lowercased().hasPrefix("file") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let path = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if let resolved = resolveTrackPath(path, baseDir: baseDir) {
                entries.append((path, resolved))
            }
        }
        return entries
    }

    static func resolveTrackPath(_ path: String, baseDir: URL) -> URL? {
        guard !path.isEmpty else { return nil }
        // Skip URLs (http://, https://)
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return nil
        }
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = baseDir.appendingPathComponent(path).standardized
        }
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }
        return url
    }

    // MARK: - Playlist Writing

    static func writePlaylist(_ playlist: Playlist) {
        let ext = playlist.fileURL.pathExtension.lowercased()
        let baseDir = playlist.fileURL.deletingLastPathComponent()
        let content: String

        if ext == "pls" {
            content = buildPLS(trackURLs: playlist.trackURLs, baseDir: baseDir)
        } else {
            content = buildM3U(trackURLs: playlist.trackURLs, baseDir: baseDir)
        }

        try? content.write(to: playlist.fileURL, atomically: true, encoding: .utf8)
    }

    static func createPlaylist(name: String, in directory: URL) -> Playlist {
        let fileURL = directory.appendingPathComponent("\(name).m3u")
        let playlist = Playlist(fileURL: fileURL, name: name, trackURLs: [], rawPaths: [])
        let content = "#EXTM3U\n"
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        return playlist
    }

    static func relativePath(for trackURL: URL, relativeTo baseDir: URL) -> String {
        let trackPath = trackURL.standardized.path
        let basePath = baseDir.standardized.path.hasSuffix("/")
            ? baseDir.standardized.path
            : baseDir.standardized.path + "/"
        if trackPath.hasPrefix(basePath) {
            return String(trackPath.dropFirst(basePath.count))
        }
        return trackPath
    }

    private static func buildM3U(trackURLs: [URL], baseDir: URL) -> String {
        var lines = ["#EXTM3U"]
        for url in trackURLs {
            lines.append(relativePath(for: url, relativeTo: baseDir))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildPLS(trackURLs: [URL], baseDir: URL) -> String {
        var lines = ["[playlist]"]
        for (i, url) in trackURLs.enumerated() {
            let num = i + 1
            lines.append("File\(num)=\(relativePath(for: url, relativeTo: baseDir))")
        }
        lines.append("NumberOfEntries=\(trackURLs.count)")
        lines.append("Version=2")
        return lines.joined(separator: "\n") + "\n"
    }
}
