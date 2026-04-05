import AVFoundation
import UIKit

struct MetadataLoader {

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "opus"
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
}
