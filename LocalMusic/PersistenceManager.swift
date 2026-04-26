import Foundation

final class PersistenceManager {

    static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.folderplayer.persistence",
                                        qos: .userInitiated)

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var libraryURL: URL {
        documentsDirectory.appendingPathComponent("library.json")
    }

    // MARK: - Folder Bookmark

    func saveFolderBookmark(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: "folderBookmark")
        } catch {
            print("Failed to save folder bookmark: \(error)")
        }
    }

    func loadFolderBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "folderBookmark") else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveFolderBookmark(url)
            }
            return url
        } catch {
            print("Failed to resolve folder bookmark: \(error)")
            return nil
        }
    }

    // MARK: - Last Synced

    func saveLastSynced(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "lastSynced")
    }

    func loadLastSynced() -> Date? {
        UserDefaults.standard.object(forKey: "lastSynced") as? Date
    }

    // MARK: - Library

    /// Synchronous load (for callers that explicitly want it). Prefer
    /// `loadLibraryAsync()` from view code.
    func loadLibrary() -> [Track] {
        guard fileManager.fileExists(atPath: libraryURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: libraryURL)
            return try JSONDecoder().decode([Track].self, from: data)
        } catch {
            print("Failed to load library: \(error)")
            return []
        }
    }

    func loadLibraryAsync() async -> [Track] {
        let url = libraryURL
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    cont.resume(returning: []); return
                }
                do {
                    let data = try Data(contentsOf: url)
                    let tracks = try JSONDecoder().decode([Track].self, from: data)
                    cont.resume(returning: tracks)
                } catch {
                    print("Failed to load library: \(error)")
                    cont.resume(returning: [])
                }
            }
        }
    }

    /// Encodes and writes asynchronously off the main thread.
    func saveLibraryAsync(_ tracks: [Track]) async {
        let url = libraryURL
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ioQueue.async {
                do {
                    let data = try JSONEncoder().encode(tracks)
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("Failed to save library: \(error)")
                }
                cont.resume()
            }
        }
    }

    // MARK: - Folder Modification

    /// Latest content modification time across the folder tree, used to skip
    /// redundant rescans when nothing on disk has changed.
    func folderContentModificationDate(at url: URL) -> Date? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        for case let item as URL in enumerator {
            if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate {
                if date > latest { latest = date }
            }
        }
        return latest == .distantPast ? nil : latest
    }
}
