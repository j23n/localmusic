import Foundation

final class PersistenceManager {

    static let shared = PersistenceManager()

    private let fileManager = FileManager.default

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

    func saveLibrary(_ tracks: [Track]) {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("Failed to save library: \(error)")
        }
    }

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

}
