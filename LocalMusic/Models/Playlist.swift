import Foundation

/// User-editable playlist discovered from .m3u / .m3u8 / .pls files. We keep
/// `trackURLs` and `rawPaths` parallel so missing tracks still surface in the
/// detail view by their original on-disk path.
struct Playlist: Identifiable, Sendable {
    var id: URL { fileURL }
    let fileURL: URL
    let name: String
    var trackURLs: [URL]
    var rawPaths: [String]
}
