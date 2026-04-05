import AVFoundation
import UIKit

struct MetadataLoader {

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "opus"
    ]

    static let playlistExtensions: Set<String> = [
        "m3u", "m3u8", "pls"
    ]

    // MARK: - Folder Scanning

    /// Caller must ensure security-scoped access is already active on `url`.
    static func scanFolder(at url: URL) async -> [Track] {
        print("[FolderPlayer] scanFolder at: \(url.path)")
        let audioURLs = collectAudioFiles(in: url)
        print("[FolderPlayer] found \(audioURLs.count) audio files")
        if let first = audioURLs.first {
            print("[FolderPlayer] first file URL: \(first.path)")
        }

        var tracks: [Track] = []
        for fileURL in audioURLs {
            let track = await loadTrack(from: fileURL)
            tracks.append(track)
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

        return Track(
            id: UUID(),
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkData: artworkData
        )
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

        let trackURLs: [URL]
        if ext == "pls" {
            trackURLs = parsePLS(content, baseDir: baseDir)
        } else {
            trackURLs = parseM3U(content, baseDir: baseDir)
        }

        return Playlist(fileURL: url, name: name, trackURLs: trackURLs)
    }

    private static func parseM3U(_ content: String, baseDir: URL) -> [URL] {
        let lines = content.components(separatedBy: .newlines)
        var urls: [URL] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let resolved = resolveTrackPath(trimmed, baseDir: baseDir)
            if let resolved { urls.append(resolved) }
        }
        return urls
    }

    private static func parsePLS(_ content: String, baseDir: URL) -> [URL] {
        let lines = content.components(separatedBy: .newlines)
        var urls: [URL] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match File1=..., File2=..., etc.
            guard trimmed.lowercased().hasPrefix("file") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let path = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            let resolved = resolveTrackPath(path, baseDir: baseDir)
            if let resolved { urls.append(resolved) }
        }
        return urls
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
        let playlist = Playlist(fileURL: fileURL, name: name, trackURLs: [])
        let content = "#EXTM3U\n"
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        return playlist
    }

    private static func relativePath(for trackURL: URL, relativeTo baseDir: URL) -> String {
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
